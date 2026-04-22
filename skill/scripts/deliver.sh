#!/bin/bash
# deliver.sh — execute delivery_targets for a closed session
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${REVIEW_AGENT_ROOT:-$HOME/.review-agent}"

if [ $# -ne 1 ]; then echo "Usage: $(basename "$0") <session_id>" >&2; exit 1; fi

SESSION_ID="$1"

# Locate session and resolve requester / responder
SESSION_DIR=""
REQ_OID=""
for p in "$ROOT/users"/*/sessions/"$SESSION_ID"; do
  if [ -d "$p" ]; then
    SESSION_DIR="$p"
    REQ_OID=$(basename "$(dirname "$(dirname "$p")")")
    break
  fi
done
if [ -z "$SESSION_DIR" ]; then echo "error: session $SESSION_ID not found" >&2; exit 2; fi

RESP_OID=$(python3 -c "
import json
m = json.load(open('$SESSION_DIR/meta.json'))
print(m.get('responder_open_id',''))
")

# Resolve delivery_targets: per-Responder override > shared default
DT_PATH=""
[ -f "$ROOT/users/$RESP_OID/delivery_override.json" ] && DT_PATH="$ROOT/users/$RESP_OID/delivery_override.json"
[ -z "$DT_PATH" ] && [ -f "$ROOT/delivery_targets.json" ] && DT_PATH="$ROOT/delivery_targets.json"
[ -z "$DT_PATH" ] && [ -f "$ROOT/profile/delivery_targets.json" ] && DT_PATH="$ROOT/profile/delivery_targets.json"

if [ -z "$DT_PATH" ]; then
  echo "warning: no delivery_targets.json found; skipping" >&2
  exit 0
fi

python3 "$SKILL_DIR/scripts/_deliver.py" "$SESSION_DIR" "$REQ_OID" "$RESP_OID" "$DT_PATH"
