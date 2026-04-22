#!/bin/bash
# set-role.sh — Admin: add/remove a role on a user
set -euo pipefail

ROOT="${REVIEW_AGENT_ROOT:-$HOME/.review-agent}"

usage() {
  echo "Usage: $(basename "$0") <open_id> <add|remove> <Admin|Responder|Requester>" >&2
  exit 1
}

if [ $# -ne 3 ]; then usage; fi

OID="$1"
ACTION="$2"
ROLE="$3"

case "$ACTION" in add|remove) ;; *) usage ;; esac
case "$ROLE" in Admin|Responder|Requester) ;; *) usage ;; esac

UDIR="$ROOT/users/$OID"
if [ ! -d "$UDIR" ]; then
  echo "error: user $OID not found at $UDIR" >&2
  exit 2
fi

python3 - "$UDIR/meta.json" "$ACTION" "$ROLE" <<'PYEOF'
import json, sys
mp, action, role = sys.argv[1:4]
m = json.load(open(mp))
roles = set(m.get("roles", []))
if action == "add":
    roles.add(role)
else:
    roles.discard(role)
m["roles"] = sorted(roles)
json.dump(m, open(mp, "w"), indent=2, ensure_ascii=False)
print(f"roles now: {m['roles']}")
PYEOF
