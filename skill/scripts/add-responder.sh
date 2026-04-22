#!/bin/bash
# add-responder.sh — Admin-only: register a Responder
# v0: single-Responder only. If a Responder already exists, this errors.
# Multi-Responder is planned for v1.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${REVIEW_AGENT_ROOT:-$HOME/.review-agent}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'

usage() {
  cat <<EOF >&2
Usage: $(basename "$0") <responder_open_id> [--name <text>] [--approve-pairing] [--force]
  --force   bypass the v0 single-Responder guard (use only for migration)

NOTE: v0 supports only ONE Responder. To replace an existing Responder, first run:
        bash remove-user.sh <existing_responder_open_id>
EOF
  exit 1
}

if [ $# -lt 1 ]; then usage; fi

OID="$1"; shift
NAME=""
AUTO_APPROVE=0
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --approve-pairing) AUTO_APPROVE=1; shift ;;
    --force) FORCE=1; shift ;;
    *) usage ;;
  esac
done
[ -z "$NAME" ] && NAME="Responder"

if [ ! -d "$ROOT/users" ]; then
  echo -e "${RED}error:${NC} run setup.sh first" >&2
  exit 2
fi

# v0 single-Responder guard
EXISTING=$(python3 - "$ROOT" "$OID" <<'PYEOF'
import json, os, sys
root, new_oid = sys.argv[1], sys.argv[2]
udir = os.path.join(root, "users")
others = []
for u in os.listdir(udir):
    if u == new_oid: continue
    mp = os.path.join(udir, u, "meta.json")
    if os.path.exists(mp):
        try:
            m = json.load(open(mp))
            if "Responder" in m.get("roles", []):
                others.append(u)
        except: pass
print(",".join(others))
PYEOF
)
if [ -n "$EXISTING" ] && [ $FORCE -eq 0 ]; then
  echo -e "${RED}error:${NC} a Responder already exists: $EXISTING" >&2
  echo "v0 supports only one Responder. Either:" >&2
  echo "  - remove the existing Responder: bash $SKILL_DIR/scripts/remove-user.sh $EXISTING" >&2
  echo "  - or pass --force (advanced; v1 will support multi-Responder properly)" >&2
  exit 3
fi

UDIR="$ROOT/users/$OID"
if [ -d "$UDIR" ]; then
  # already exists — add Responder role if missing
  python3 - "$UDIR" <<'PYEOF'
import json, sys
mp = sys.argv[1] + "/meta.json"
m = json.load(open(mp))
roles = set(m.get("roles", []))
if "Responder" not in roles:
    roles.add("Responder")
    m["roles"] = sorted(roles)
    json.dump(m, open(mp, "w"), indent=2, ensure_ascii=False)
    print("  added Responder role to existing user")
else:
    print("  already has Responder role")
PYEOF
else
  mkdir -p "$UDIR"
  cat > "$UDIR/meta.json" <<EOF
{
  "open_id": "$OID",
  "display_name": "$NAME",
  "roles": ["Responder"],
  "channel": "feishu",
  "runtime": "hermes",
  "created_at": "$(date -Iseconds)"
}
EOF
  echo -e "${GREEN}  created user with Responder role${NC}"
fi

# profile.md
PROFILE="$UDIR/profile.md"
if [ ! -f "$PROFILE" ]; then
  cp "$SKILL_DIR/references/template/boss_profile.md" "$PROFILE"
  python3 -c "
import re
p = open('$PROFILE').read()
p = re.sub(r'\*\*Name\*\*:\s*<[^>]*>', '**Name**: $NAME', p)
open('$PROFILE','w').write(p)
"
  echo -e "${GREEN}  wrote starter profile${NC} $PROFILE"
fi

if [ $AUTO_APPROVE -eq 1 ] && command -v hermes >/dev/null 2>&1; then
  hermes pairing approve "$OID" 2>&1 | head -3 || true
fi

echo
echo -e "${GREEN}Responder ready.${NC}"
echo "Edit profile: $PROFILE"
echo "Add Requesters under this Responder:"
echo "  bash $SKILL_DIR/scripts/add-requester.sh <ou_> --responder $OID --name 'Name'"
