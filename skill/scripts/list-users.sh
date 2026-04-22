#!/bin/bash
# list-users.sh — print all users with roles
set -euo pipefail
ROOT="${REVIEW_AGENT_ROOT:-$HOME/.review-agent}"

ROLE_FILTER=""
[ "${1:-}" = "--role" ] && ROLE_FILTER="${2:-}"

if [ ! -d "$ROOT/users" ]; then
  echo "(no users; run setup.sh first)"; exit 0
fi

printf "%-44s %-20s %-30s %-10s %-10s\n" "OPEN_ID" "NAME" "ROLES" "ACTIVE" "CLOSED"
printf "%-44s %-20s %-30s %-10s %-10s\n" "------" "----" "-----" "------" "------"
for u in "$ROOT/users"/*/; do
  [ -d "$u" ] || continue
  oid=$(basename "$u")
  python3 - "$u" "$ROLE_FILTER" <<'PYEOF'
import json, os, sys
udir, role_filter = sys.argv[1], sys.argv[2]
mp = os.path.join(udir, "meta.json")
if not os.path.exists(mp): sys.exit(0)
m = json.load(open(mp))
roles = m.get("roles", [])
if role_filter and role_filter not in roles:
    sys.exit(0)
sd = os.path.join(udir, "sessions")
active = closed = 0
if os.path.isdir(sd):
    for s in os.listdir(sd):
        smp = os.path.join(sd, s, "meta.json")
        if os.path.exists(smp):
            try:
                sm = json.load(open(smp))
                if sm.get("status") == "closed": closed += 1
                else: active += 1
            except: pass
oid = os.path.basename(udir.rstrip("/"))
print(f"{oid:<44} {(m.get('display_name') or '-')[:18]:<20} {','.join(roles)[:28]:<30} {active:<10} {closed:<10}")
PYEOF
done
