#!/bin/bash
# list-sessions.sh — list sessions across all Requesters, optional filter
set -euo pipefail
ROOT="${REVIEW_AGENT_ROOT:-$HOME/.review-agent}"

REQ_FILTER="${1:-}"

printf "%-30s %-25s %-20s %-30s %-8s %-10s\n" "SESSION_ID" "REQUESTER" "RESPONDER" "SUBJECT" "ROUND" "STATUS"
printf "%-30s %-25s %-20s %-30s %-8s %-10s\n" "----------" "---------" "---------" "-------" "-----" "------"

for u in "$ROOT/users"/*/; do
  [ -d "$u" ] || continue
  oid=$(basename "$u")
  [ -n "$REQ_FILTER" ] && [ "$oid" != "$REQ_FILTER" ] && continue
  uname=$(python3 -c "
import json,os
m=os.path.join('$u','meta.json')
print(json.load(open(m)).get('display_name') or '$oid' if os.path.exists(m) else '$oid')
" 2>/dev/null)
  [ -d "$u/sessions" ] || continue
  for s in "$u/sessions"/*/; do
    [ -d "$s" ] || continue
    python3 - "$s" "$uname" <<'PYEOF'
import json, os, sys
sd, briefer = sys.argv[1:3]
m = os.path.join(sd, 'meta.json')
if not os.path.exists(m): sys.exit(0)
try: meta = json.load(open(m))
except: sys.exit(0)
subj = (meta.get('subject') or '')[:28]
resp = (meta.get('responder_open_id','') or '')[:18]
print(f"{meta.get('session_id',''):<30} {briefer[:23]:<25} {resp:<20} {subj:<30} {meta.get('round',0):<8} {meta.get('status','?'):<10}")
PYEOF
  done
done
