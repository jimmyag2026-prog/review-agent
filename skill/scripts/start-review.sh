#!/bin/bash
# start-review.sh — atomic "start a new review session from this message"
#
# Called by the Orchestrator when it detects review-new intent (a registered
# Requester sent a message with a review trigger and no active session).
#
# Does ALL the steps in sequence:
#   1. Create session folder (new-session.sh)
#   2. Save inbound message + any material to input/
#   3. Run ingest (multi-modal normalize)
#   4. Run confirm-topic --send (sends first message to Requester via Lark)
#
# Usage:
#   start-review.sh <requester_open_id> "<inferred subject>" "<message text>"
#
# The orchestrator still has to capture the Requester's confirmation reply and
# then run scan.py — that happens on next inbound turn via qa-step or an
# explicit "confirmed" signal.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${REVIEW_AGENT_ROOT:-$HOME/.review-agent}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'

usage() {
  echo "Usage: $(basename "$0") <requester_open_id> \"<subject>\" \"<message text>\" [--no-send]" >&2
  exit 1
}

if [ $# -lt 3 ]; then usage; fi

REQ_OID="$1"
SUBJECT="$2"
MSG_TEXT="$3"
shift 3
SEND=1
while [ $# -gt 0 ]; do
  case "$1" in
    --no-send) SEND=0; shift ;;
    *) usage ;;
  esac
done

# Verify requester exists
if [ ! -d "$ROOT/users/$REQ_OID" ]; then
  echo "error: requester $REQ_OID not enrolled" >&2
  exit 2
fi

# Refuse if already has active session (the orchestrator should have routed elsewhere)
if [ -f "$ROOT/users/$REQ_OID/active_session.json" ]; then
  EXISTING=$(python3 -c "import json,sys; print(json.load(open('$ROOT/users/$REQ_OID/active_session.json'))['session_id'])" 2>/dev/null || true)
  if [ -n "${EXISTING:-}" ] && [ -d "$ROOT/users/$REQ_OID/sessions/$EXISTING" ]; then
    echo -e "${YELLOW}warn: already active session $EXISTING — orchestrator should have routed to qa-step${NC}" >&2
    echo "$EXISTING"
    exit 0
  fi
fi

# Step 1: create session
SID=$(bash "$SKILL_DIR/scripts/new-session.sh" "$REQ_OID" "$SUBJECT" 2>&1 | tail -1)
SDIR="$ROOT/users/$REQ_OID/sessions/$SID"
if [ ! -d "$SDIR" ]; then
  echo "[start-review] error: new-session failed" >&2
  exit 3
fi
# stderr: minimal lifecycle markers only — NO session content
echo "[start-review] session_created sid=$SID" >&2

# Step 2: save inbound message as initial input (no stderr echo of message body)
TS=$(date +%Y%m%d-%H%M%S)
MSG_FILE="$SDIR/input/${TS}_initial_message.md"
cat > "$MSG_FILE" <<EOF
# Requester's initial message

**Sent**: $(date -Iseconds)
**From**: $REQ_OID

$MSG_TEXT
EOF
echo "[start-review] inbound_saved" >&2

# Also log the inbound message to conversation.jsonl
python3 <<PYEOF
import json
from datetime import datetime
entry = {
    "ts": datetime.now().astimezone().isoformat(timespec="seconds"),
    "role": "requester",
    "source": "lark_dm",
    "text": """$MSG_TEXT""",
    "stage": "review_new_trigger",
}
with open("$SDIR/conversation.jsonl", "a") as f:
    f.write(json.dumps(entry, ensure_ascii=False) + "\n")
PYEOF

# Step 3: run ingest. Three outcomes:
#   exit 0 → everything extracted cleanly, proceed to confirm-topic.
#   exit 3 → HARD FAIL: attachment needed a tool we don't have, and no
#            usable text was salvaged. ingest.py wrote ingest_failed.json
#            with a Requester-facing message and also printed it to stdout.
#            We relay that to Lark and STOP (don't run scan on garbage).
#   other  → unexpected ingest failure. Keep legacy fallback (confirm-topic
#            will still prompt the Requester to paste text).
set +e
INGEST_OUTPUT=$(python3 "$SKILL_DIR/scripts/ingest.py" "$SDIR" --force 2>/dev/null)
INGEST_RC=$?
set -e

if [ $INGEST_RC -eq 3 ]; then
  echo "[start-review] ingest_hard_fail_missing_tool" >&2
  # Relay the user-facing message to Requester if we're sending to Lark.
  if [ $SEND -eq 1 ]; then
    bash "$SKILL_DIR/scripts/send-lark.sh" --open-id "$REQ_OID" --text "$INGEST_OUTPUT" >/dev/null 2>&1 \
      && echo "[start-review] hard_fail_message_sent" >&2 \
      || echo "[start-review] hard_fail_message_send_failed" >&2
  else
    echo "$INGEST_OUTPUT"
  fi
  # Mark session as failed rather than active — the Requester needs to retry
  # with pasted text or after Admin installs the missing tool.
  python3 <<PYEOF
import json
m = json.load(open("$SDIR/meta.json"))
m["status"] = "ingest_failed"
m["termination"] = "ingest_tool_missing"
json.dump(m, open("$SDIR/meta.json", "w"), indent=2, ensure_ascii=False)
PYEOF
  # Clear the active-session pointer so the Requester can retry immediately.
  rm -f "$ROOT/users/$REQ_OID/active_session.json"
  echo "$SID"
  exit 3
elif [ $INGEST_RC -eq 0 ]; then
  echo "[start-review] ingest_ok" >&2
else
  echo "[start-review] ingest_failed_fallback_to_text_paste" >&2
fi

# Step 4: run confirm-topic
if [ $SEND -eq 1 ]; then
  python3 "$SKILL_DIR/scripts/confirm-topic.py" "$SDIR" --send >/dev/null 2>&1 \
    && echo "[start-review] confirmation_sent_to_requester" >&2 \
    || echo "[start-review] confirmation_send_failed" >&2
else
  # Dry-run: print confirm message to stdout (for orchestrator/tester to inspect)
  python3 "$SKILL_DIR/scripts/confirm-topic.py" "$SDIR"
fi

# Mark session state
python3 <<PYEOF
import json
m = json.load(open("$SDIR/meta.json"))
m["status"] = "awaiting_subject_confirmation"
json.dump(m, open("$SDIR/meta.json", "w"), indent=2, ensure_ascii=False)
PYEOF

# stdout = session_id so orchestrator can pass it to next step
echo "$SID"
