#!/bin/bash
# new-session.sh — create a new subtask session under a Requester user
# Returns session_id on stdout.
set -euo pipefail

ROOT="${REVIEW_AGENT_ROOT:-$HOME/.review-agent}"

usage() {
  echo "Usage: $(basename "$0") <requester_open_id> \"<subject>\" [--criteria <path>] [--originating-chat <chat_id>:<chat_name>]" >&2
  exit 1
}

if [ $# -lt 2 ]; then usage; fi

REQ_OID="$1"
SUBJECT="$2"
CRITERIA_SRC=""
ORIG_CHAT=""
shift 2
while [ $# -gt 0 ]; do
  case "$1" in
    --criteria) CRITERIA_SRC="$2"; shift 2 ;;
    --originating-chat) ORIG_CHAT="$2"; shift 2 ;;
    *) usage ;;
  esac
done

REQ_DIR="$ROOT/users/$REQ_OID"
if [ ! -d "$REQ_DIR" ]; then
  echo "error: user dir not found: $REQ_DIR" >&2
  echo "run add-requester.sh first" >&2
  exit 2
fi

# Verify role
ROLE_OK=$(python3 -c "
import json
m = json.load(open('$REQ_DIR/meta.json'))
print('yes' if 'Requester' in m.get('roles',[]) else 'no')
")
if [ "$ROLE_OK" != "yes" ]; then
  echo "error: $REQ_OID is not a Requester" >&2
  exit 2
fi

# Resolve responder
RESPONDER_OID=$(python3 -c "
import json
m = json.load(open('$REQ_DIR/meta.json'))
print(m.get('responder',''))
")
if [ -z "$RESPONDER_OID" ] || [ ! -d "$ROOT/users/$RESPONDER_OID" ]; then
  echo "error: responder $RESPONDER_OID not registered" >&2
  exit 2
fi

# session id — slug from subject, keep ASCII for filesystem safety
SLUG=$(SUBJECT="$SUBJECT" python3 -c '
import os, re
s = os.environ["SUBJECT"]
# Transliterate Chinese → pinyin-less keep ASCII; keep alnum/hyphen
ascii_only = re.sub(r"[^a-zA-Z0-9]+", "-", s).strip("-")[:40]
print(ascii_only or "topic")
')
SESSION_ID="$(date +%Y%m%d-%H%M%S)-${SLUG}"
SESSION_DIR="$REQ_DIR/sessions/$SESSION_ID"

mkdir -p "$SESSION_DIR"/{input,final}

# Freeze copies: admin style, responder profile, shared rules
[ -f "$ROOT/admin_style.md" ] && cp "$ROOT/admin_style.md" "$SESSION_DIR/admin_style.md"
cp "$ROOT/users/$RESPONDER_OID/profile.md" "$SESSION_DIR/profile.md"
cp "$ROOT/rules/review_rules.md" "$SESSION_DIR/review_rules.md"
[ -n "$CRITERIA_SRC" ] && [ -f "$CRITERIA_SRC" ] && cp "$CRITERIA_SRC" "$SESSION_DIR/review_criteria.md"

ORIG_CHAT_JSON="null"
if [ -n "$ORIG_CHAT" ]; then
  ORIG_CHAT_JSON=$(python3 -c "
import json,sys
parts = sys.argv[1].split(':',1)
print(json.dumps({'chat_id': parts[0], 'chat_name': parts[1] if len(parts)>1 else ''}))
" "$ORIG_CHAT")
fi

TRIGGER_SURFACE="direct_message"
[ -n "$ORIG_CHAT" ] && TRIGGER_SURFACE="group_at_mention"

# Build meta.json entirely in python via env vars (avoid bash+python+{}+chinese escaping trap)
SESSION_ID="$SESSION_ID" \
REQ_OID="$REQ_OID" \
RESPONDER_OID="$RESPONDER_OID" \
SUBJECT="$SUBJECT" \
TRIGGER_SURFACE="$TRIGGER_SURFACE" \
ORIG_CHAT_JSON="$ORIG_CHAT_JSON" \
CREATED_AT="$(date -Iseconds)" \
META_OUT_PATH="$SESSION_DIR/meta.json" \
python3 -c '
import json, os
meta = {
    "session_id": os.environ["SESSION_ID"],
    "requester_open_id": os.environ["REQ_OID"],
    "responder_open_id": os.environ["RESPONDER_OID"],
    "subject": os.environ["SUBJECT"],
    "trigger_surface": os.environ["TRIGGER_SURFACE"],
    "originating_chat": json.loads(os.environ["ORIG_CHAT_JSON"]),
    "status": "active",
    "round": 0,
    "created_at": os.environ["CREATED_AT"],
    "last_activity_at": os.environ["CREATED_AT"],
    "termination": None,
    "forced_reason": None,
    "closed_at": None,
    "tags": []
}
with open(os.environ["META_OUT_PATH"], "w") as f:
    json.dump(meta, f, indent=2, ensure_ascii=False)
'

: > "$SESSION_DIR/conversation.jsonl"
: > "$SESSION_DIR/annotations.jsonl"
: > "$SESSION_DIR/dissent.md"
echo '{"current_id": null, "pending": [], "done": []}' > "$SESSION_DIR/cursor.json"

# Write active_session pointer (orchestrator reads this)
SESSION_ID="$SESSION_ID" \
POINTER_OUT="$REQ_DIR/active_session.json" \
CREATED_AT="$(date -Iseconds)" \
python3 -c '
import json, os
json.dump({
    "session_id": os.environ["SESSION_ID"],
    "opened_at": os.environ["CREATED_AT"],
    "pointer_updated_at": os.environ["CREATED_AT"]
}, open(os.environ["POINTER_OUT"], "w"), indent=2, ensure_ascii=False)
'

echo "$SESSION_ID"
