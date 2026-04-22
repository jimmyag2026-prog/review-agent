#!/bin/bash
# setup.sh — initialize ~/.review-agent/ with three-role model
# Default: Admin == Responder (same Lark open_id). To split, pass both flags.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${REVIEW_AGENT_ROOT:-$HOME/.review-agent}"

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'

usage() {
  cat <<EOF
Usage: $(basename "$0") --admin-open-id <ou_xxx> [options]
Required:
  --admin-open-id <ou_>            Lark open_id of the Admin

Optional:
  --responder-open-id <ou_>        Lark open_id of the Responder (default: same as admin)
  --admin-name <text>              display name for the Admin
  --responder-name <text>          display name for the Responder (default: --admin-name)
  --root <path>                    override ~/.review-agent root
  --force                          overwrite existing users/profile

Creates:
  \$ROOT/users/<admin_open_id>/meta.json     (roles: Admin [+Responder if same person])
  \$ROOT/users/<admin_open_id>/profile.md     (only if also Responder)
  \$ROOT/users/<responder_open_id>/...        (if separate from admin)
  \$ROOT/rules/review_rules.md
  \$ROOT/delivery_targets.json
  \$ROOT/dashboard.md
  \$ROOT/logs/
EOF
  exit 1
}

ADMIN_OPEN_ID=""
RESPONDER_OPEN_ID=""
ADMIN_NAME=""
RESPONDER_NAME=""
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --admin-open-id) ADMIN_OPEN_ID="$2"; shift 2 ;;
    --responder-open-id) RESPONDER_OPEN_ID="$2"; shift 2 ;;
    --admin-name) ADMIN_NAME="$2"; shift 2 ;;
    --responder-name) RESPONDER_NAME="$2"; shift 2 ;;
    --root) ROOT="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown option: $1" >&2; usage ;;
  esac
done

[ -z "$ADMIN_OPEN_ID" ] && { echo -e "${RED}error:${NC} --admin-open-id required" >&2; usage; }
[ -z "$RESPONDER_OPEN_ID" ] && RESPONDER_OPEN_ID="$ADMIN_OPEN_ID"
[ -z "$ADMIN_NAME" ] && ADMIN_NAME="Admin"
[ -z "$RESPONDER_NAME" ] && RESPONDER_NAME="$ADMIN_NAME"

SAME_PERSON=0
[ "$ADMIN_OPEN_ID" = "$RESPONDER_OPEN_ID" ] && SAME_PERSON=1

echo -e "${GREEN}Initializing review-agent at:${NC} $ROOT"
echo "  Admin     : $ADMIN_OPEN_ID ($ADMIN_NAME)"
echo "  Responder : $RESPONDER_OPEN_ID ($RESPONDER_NAME) $([ $SAME_PERSON -eq 1 ] && echo '(= Admin)')"

mkdir -p "$ROOT"/{users,rules,logs}

# Admin style (agent-behavior config, distinct from per-Responder profile)
STYLE="$ROOT/admin_style.md"
if [ ! -f "$STYLE" ] || [ $FORCE -eq 1 ]; then
  cp "$SKILL_DIR/references/template/admin_style.md" "$STYLE"
  echo -e "${GREEN}  wrote${NC} $STYLE"
fi

# Shared review rules
RULES="$ROOT/rules/review_rules.md"
if [ ! -f "$RULES" ] || [ $FORCE -eq 1 ]; then
  cp "$SKILL_DIR/references/template/review_rules.md" "$RULES"
  echo -e "${GREEN}  wrote${NC} $RULES"
fi

# Default delivery_targets.json
DTARGETS="$ROOT/delivery_targets.json"
if [ ! -f "$DTARGETS" ] || [ $FORCE -eq 1 ]; then
  cat > "$DTARGETS" <<EOF
{
  "on_close": [
    {
      "name": "archive-local",
      "backend": "local_path",
      "path": "$ROOT/sessions/_closed/{{YYYY}}-{{MM}}/{{session_id}}/",
      "payload": ["summary","summary_audit","final","conversation","annotations","dissent"]
    },
    {
      "name": "responder-lark-dm",
      "backend": "lark_dm",
      "open_id": "{{RESPONDER_OPEN_ID}}",
      "payload": ["summary","final","dissent"],
      "role": "responder"
    },
    {
      "name": "requester-lark-dm",
      "backend": "lark_dm",
      "open_id": "{{REQUESTER_OPEN_ID}}",
      "payload": ["summary"],
      "role": "requester"
    }
  ]
}
EOF
  echo -e "${GREEN}  wrote${NC} $DTARGETS"
fi

create_user() {
  local oid="$1"
  local roles_json="$2"
  local name="$3"
  local extra_field="$4"   # e.g. for requester: ',"responder":"<ou_>"'
  local udir="$ROOT/users/$oid"
  if [ -d "$udir" ] && [ $FORCE -eq 0 ]; then
    echo -e "${YELLOW}  user $oid already exists; skipping (use --force to overwrite)${NC}"
    return
  fi
  mkdir -p "$udir"
  cat > "$udir/meta.json" <<EOF
{
  "open_id": "$oid",
  "display_name": "$name",
  "roles": $roles_json$extra_field,
  "channel": "feishu",
  "runtime": "hermes",
  "created_at": "$(date -Iseconds)"
}
EOF
  echo -e "${GREEN}  wrote${NC} $udir/meta.json (roles: $roles_json)"
}

if [ $SAME_PERSON -eq 1 ]; then
  create_user "$ADMIN_OPEN_ID" '["Admin","Responder"]' "$ADMIN_NAME" ""
  PROFILE="$ROOT/users/$ADMIN_OPEN_ID/profile.md"
  if [ ! -f "$PROFILE" ] || [ $FORCE -eq 1 ]; then
    cp "$SKILL_DIR/references/template/boss_profile.md" "$PROFILE"
    python3 -c "
import re
p = open('$PROFILE').read()
p = re.sub(r'\*\*Name\*\*:\s*<[^>]*>', '**Name**: $RESPONDER_NAME', p)
open('$PROFILE','w').write(p)
"
    echo -e "${GREEN}  wrote${NC} $PROFILE"
  fi
else
  create_user "$ADMIN_OPEN_ID" '["Admin"]' "$ADMIN_NAME" ""
  create_user "$RESPONDER_OPEN_ID" '["Responder"]' "$RESPONDER_NAME" ""
  PROFILE="$ROOT/users/$RESPONDER_OPEN_ID/profile.md"
  if [ ! -f "$PROFILE" ] || [ $FORCE -eq 1 ]; then
    cp "$SKILL_DIR/references/template/boss_profile.md" "$PROFILE"
    python3 -c "
import re
p = open('$PROFILE').read()
p = re.sub(r'\*\*Name\*\*:\s*<[^>]*>', '**Name**: $RESPONDER_NAME', p)
open('$PROFILE','w').write(p)
"
    echo -e "${GREEN}  wrote${NC} $PROFILE"
  fi
fi

DASHBOARD="$ROOT/dashboard.md"
if [ ! -f "$DASHBOARD" ] || [ $FORCE -eq 1 ]; then
  cat > "$DASHBOARD" <<EOF
# Review Agent Dashboard

_Last refreshed: $(date -Iseconds)_

## Users

| open_id | name | roles | sessions (active/closed) |
|---|---|---|---|
_(run dashboard.sh --refresh)_

## Active sessions

_(run dashboard.sh --refresh)_

## Closed sessions (last 10)

_(run dashboard.sh --refresh)_
EOF
  echo -e "${GREEN}  wrote${NC} $DASHBOARD"
fi

echo
echo -e "${GREEN}Done.${NC}"
echo "Next steps:"
[ -n "${PROFILE:-}" ] && echo "  1. Edit $PROFILE with the Responder's standards"
echo "  2. Edit $DTARGETS to add email or other delivery targets if desired"
echo "  3. Add a Requester:"
echo "     bash $SKILL_DIR/scripts/add-requester.sh <briefer_open_id> --name 'Name'"
echo "  (v0 supports a single Responder; multi-Responder is planned for v1.)"
