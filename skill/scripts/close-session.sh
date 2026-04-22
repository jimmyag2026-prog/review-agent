#!/bin/bash
# close-session.sh — close a session, generate summary, trigger delivery
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${REVIEW_AGENT_ROOT:-$HOME/.review-agent}"

usage() {
  echo "Usage: $(basename "$0") <session_id> [--force] [--reason \"text\"] [--termination mutual|forced_by_briefer]" >&2
  exit 1
}

if [ $# -lt 1 ]; then usage; fi

SESSION_ID="$1"; shift
FORCE=0; REASON=""; TERMINATION=""; NO_DELIVER=0
while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; TERMINATION="${TERMINATION:-forced_by_briefer}"; shift ;;
    --reason) REASON="$2"; shift 2 ;;
    --termination) TERMINATION="$2"; shift 2 ;;
    --no-deliver) NO_DELIVER=1; shift ;;
    *) usage ;;
  esac
done
TERMINATION="${TERMINATION:-mutual}"

# Locate session under users/*/sessions/<id>/
SESSION_DIR=""
for p in "$ROOT/users"/*/sessions/"$SESSION_ID"; do
  [ -d "$p" ] && SESSION_DIR="$p" && break
done
if [ -z "$SESSION_DIR" ]; then
  echo "error: session $SESSION_ID not found" >&2
  exit 2
fi

echo "Closing session: $SESSION_DIR"
echo "  termination: $TERMINATION"
[ -n "$REASON" ] && echo "  reason: $REASON"

# Final-gate verification (unless force)
if [ $FORCE -eq 0 ]; then
  GATE_OUT=$(python3 "$SKILL_DIR/scripts/final-gate.py" "$SESSION_DIR" 2>&1 || true)
  GATE_VERDICT=$(echo "$GATE_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('verdict','?'))" 2>/dev/null || echo "ERROR")
  echo "  final-gate: $GATE_VERDICT"
  if [ "$GATE_VERDICT" = "FAIL" ]; then
    echo "  ⚠ FAIL — unresolved BLOCKERs remain; session NOT closed. Continue Q&A or pass --force." >&2
    echo "$GATE_OUT" | tail -20 >&2
    exit 3
  fi
  # Record gate result in meta for summary/dashboard
  python3 - "$SESSION_DIR" <<PYEOF
import json, os, sys
sd = sys.argv[1]
gate = json.loads('''$GATE_OUT''')
mp = os.path.join(sd, "meta.json")
m = json.load(open(mp))
m["final_gate"] = gate
json.dump(m, open(mp, "w"), indent=2, ensure_ascii=False)
PYEOF
fi

python3 - "$SESSION_DIR" "$TERMINATION" "$REASON" <<'PYEOF'
import json, sys, os
from datetime import datetime
session_dir, termination, reason = sys.argv[1:4]
mp = os.path.join(session_dir, "meta.json")
m = json.load(open(mp))
m["status"] = "closed"
m["termination"] = termination
m["forced_reason"] = reason or None
m["closed_at"] = datetime.now().astimezone().isoformat(timespec="seconds")
json.dump(m, open(mp, "w"), indent=2, ensure_ascii=False)
PYEOF

python3 "$SKILL_DIR/scripts/_build_summary.py" "$SESSION_DIR"

# Clear active_session.json pointer for this Requester
# (only if pointer references this session; avoids clobbering concurrent sessions in v1+)
REQ_OID=$(python3 -c "import json; print(json.load(open('$SESSION_DIR/meta.json')).get('requester_open_id',''))")
POINTER="$ROOT/users/$REQ_OID/active_session.json"
if [ -f "$POINTER" ]; then
  POINTS_TO=$(python3 -c "import json; print(json.load(open('$POINTER')).get('session_id',''))" 2>/dev/null)
  if [ "$POINTS_TO" = "$SESSION_ID" ]; then
    rm -f "$POINTER" && echo "  cleared active_session pointer for $REQ_OID"
  fi
fi

if [ $NO_DELIVER -eq 1 ]; then
  echo "  --no-deliver → skipping delivery"
elif [ -f "$ROOT/delivery_targets.json" ] || [ -f "$ROOT/profile/delivery_targets.json" ]; then
  bash "$SKILL_DIR/scripts/deliver.sh" "$SESSION_ID" || echo "warning: delivery failed (see logs)" >&2
fi

bash "$SKILL_DIR/scripts/dashboard.sh" --refresh >/dev/null 2>&1 || true

echo "done. Summary: $SESSION_DIR/summary.md"
