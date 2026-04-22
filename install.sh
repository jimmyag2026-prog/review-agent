#!/bin/bash
# install.sh — one-shot install of review-agent skill into a fresh hermes environment.
#
# What it does:
#   1. Prerequisite check (hermes, python, env vars, Lark creds)
#   2. Copy skill/ to ~/.hermes/skills/productivity/review-agent/
#   3. Patch ~/.hermes/config.yaml  (feishu display tier, no-interim)
#   4. Install orchestrator SOP at top of ~/.hermes/memories/MEMORY.md
#   5. Initialize ~/.review-agent/ with your Admin open_id (interactive if not provided)
#   6. Print next steps
#
# Safe to re-run: all steps are idempotent.
#
# Usage:
#   bash install.sh                          # interactive
#   bash install.sh --admin-open-id ou_xxx   # non-interactive
#   bash install.sh --skip-hermes-restart    # don't suggest gateway restart at end
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ADMIN_OID=""
ADMIN_NAME=""
RESPONDER_OID=""
RESPONDER_NAME=""
SKIP_RESTART=0

while [ $# -gt 0 ]; do
  case "$1" in
    --admin-open-id) ADMIN_OID="$2"; shift 2 ;;
    --admin-name) ADMIN_NAME="$2"; shift 2 ;;
    --responder-open-id) RESPONDER_OID="$2"; shift 2 ;;
    --responder-name) RESPONDER_NAME="$2"; shift 2 ;;
    --skip-hermes-restart) SKIP_RESTART=1; shift ;;
    -h|--help)
      cat <<'HELP'
Usage: install.sh [options]

Options:
  --admin-open-id <ou_xxx>         Admin's Lark open_id (skip interactive prompt)
  --admin-name <text>              display name for Admin
  --responder-open-id <ou_xxx>     separate Responder (default = Admin)
  --responder-name <text>
  --skip-hermes-restart            don't remind to restart gateway at end
  -h, --help                       show this help

Environment:
  REVIEW_AGENT_ROOT   override ~/.review-agent install root (default: ~/.review-agent)
HELP
      exit 0 ;;
    *) echo "unknown option: $1"; exit 1 ;;
  esac
done

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

banner() {
  echo
  echo -e "${BLUE}════════════════════════════════════════${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}════════════════════════════════════════${NC}"
}

banner "review-agent · install"

# ─── Step 1: prerequisites ───
banner "Step 1 / 5 · Prerequisite check"
if ! bash "$SCRIPT_DIR/install/check_prereqs.sh"; then
  echo -e "${RED}→ fix blocking issues above and re-run.${NC}"
  exit 2
fi

# ─── Step 2: copy skill into hermes skills dir ───
banner "Step 2 / 5 · Install skill files"
SKILL_DST="$HOME/.hermes/skills/productivity/review-agent"
mkdir -p "$(dirname "$SKILL_DST")"

if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete --exclude=".git" --exclude=".DS_Store" \
        "$SCRIPT_DIR/skill/" "$SKILL_DST/"
else
  rm -rf "$SKILL_DST"
  cp -R "$SCRIPT_DIR/skill" "$SKILL_DST"
fi

# Make all scripts executable
chmod +x "$SKILL_DST"/scripts/*.sh "$SKILL_DST"/scripts/*.py 2>/dev/null || true
echo -e "${GREEN}✓${NC} installed to $SKILL_DST"

# Verify hermes sees it
if hermes skills list --source local 2>&1 | grep -q "review-agent"; then
  echo -e "${GREEN}✓${NC} hermes skills list recognizes review-agent"
else
  echo -e "${YELLOW}!${NC} hermes skills list doesn't show review-agent yet — may need hermes restart"
fi

# ─── Step 3: patch hermes config.yaml ───
banner "Step 3 / 5 · Patch hermes config (feishu display tier)"
python3 "$SCRIPT_DIR/install/patch_hermes_config.py"

# ─── Step 4: install orchestrator SOP to MEMORY.md ───
banner "Step 4 / 5 · Install orchestrator SOP into MEMORY.md"
python3 "$SCRIPT_DIR/install/patch_memory_sop.py"

# ─── Step 5: initialize ~/.review-agent/ ───
banner "Step 5 / 5 · Initialize ~/.review-agent/"

if [ -z "$ADMIN_OID" ]; then
  echo
  echo "Now we need your Admin's Lark open_id."
  echo "Tip: run 'hermes pairing list' to see yours (the feishu row)."
  echo
  hermes pairing list 2>&1 | grep feishu || echo "  (no feishu pairings yet — DM your bot first)"
  echo
  read -rp "Admin Lark open_id (starts with 'ou_'): " ADMIN_OID
fi

if [ -z "$ADMIN_OID" ] || [[ ! "$ADMIN_OID" =~ ^ou_ ]]; then
  echo -e "${RED}error:${NC} Admin open_id required, must start with 'ou_'"
  exit 3
fi

[ -z "$ADMIN_NAME" ] && read -rp "Admin display name (leave blank for '$USER'): " ADMIN_NAME
[ -z "$ADMIN_NAME" ] && ADMIN_NAME="$USER"

SETUP_ARGS=(--admin-open-id "$ADMIN_OID" --admin-name "$ADMIN_NAME")
if [ -n "$RESPONDER_OID" ]; then
  SETUP_ARGS+=(--responder-open-id "$RESPONDER_OID")
fi
if [ -n "$RESPONDER_NAME" ]; then
  SETUP_ARGS+=(--responder-name "$RESPONDER_NAME")
fi

bash "$SKILL_DST/scripts/setup.sh" "${SETUP_ARGS[@]}"

# ─── Done ───
ROOT="${REVIEW_AGENT_ROOT:-$HOME/.review-agent}"
banner "Done!"

cat <<EOF

${GREEN}✓${NC} review-agent installed and initialized.

${YELLOW}Recommended next steps:${NC}

1. ${BLUE}Edit your Responder profile${NC} (your review standards, pet peeves, etc.):
     vim $ROOT/users/$ADMIN_OID/profile.md

2. ${BLUE}(Optional) Edit agent behavior style${NC}:
     vim $ROOT/admin_style.md

3. ${BLUE}Add your first Requester${NC} (subordinate whose briefings you'll review):
     bash $SKILL_DST/scripts/add-requester.sh <requester_ou_xxx> --name "Name"

4. ${BLUE}Open the local dashboard${NC} (watch session progress):
     bash $SKILL_DST/scripts/dashboard-web.sh --open

EOF

if [ $SKIP_RESTART -eq 0 ]; then
  cat <<EOF
${YELLOW}!${NC}  Restart hermes gateway to apply config changes:
     hermes gateway restart

EOF
fi

cat <<EOF
${BLUE}Reference${NC}: https://github.com/jimmyag2026-prog/review-agent
${BLUE}Uninstall${NC}: bash install.sh --uninstall   (coming soon; for now: rm -rf $SKILL_DST $ROOT)

EOF
