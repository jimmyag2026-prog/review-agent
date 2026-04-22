#!/bin/bash
# send-lark.sh — Lark Open API text sender (DM via open_id, or group via chat_id)
# Reads feishu creds from ~/.hermes/.env (primary) or ~/.openclaw/openclaw.json (fallback)
set -euo pipefail

HERMES_ENV="$HOME/.hermes/.env"
OC_CFG="$HOME/.openclaw/openclaw.json"

usage() {
  cat <<EOF >&2
Usage:
  $(basename "$0") --open-id <ou_xxx> --text <text>
  $(basename "$0") --chat-id <oc_xxx> --text <text>       (group)
  $(basename "$0") (--open-id|--chat-id) <id> --file <path>
EOF
  exit 1
}

OPEN_ID=""; CHAT_ID=""; TEXT=""; FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --open-id) OPEN_ID="$2"; shift 2 ;;
    --chat-id) CHAT_ID="$2"; shift 2 ;;
    --text) TEXT="$2"; shift 2 ;;
    --file) FILE="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[ -z "$OPEN_ID" ] && [ -z "$CHAT_ID" ] && usage
[ -n "$OPEN_ID" ] && [ -n "$CHAT_ID" ] && { echo "error: pass only one of --open-id / --chat-id" >&2; exit 1; }
if [ -z "$TEXT" ] && [ -n "$FILE" ] && [ -f "$FILE" ]; then
  TEXT=$(cat "$FILE")
fi
[ -z "$TEXT" ] && usage

# Load creds — prefer hermes .env
APP_ID=""; APP_SECRET=""; DOMAIN_RAW=""
if [ -f "$HERMES_ENV" ]; then
  APP_ID=$(grep -E '^FEISHU_APP_ID=' "$HERMES_ENV" | head -1 | cut -d= -f2-)
  APP_SECRET=$(grep -E '^FEISHU_APP_SECRET=' "$HERMES_ENV" | head -1 | cut -d= -f2-)
  DOMAIN_RAW=$(grep -E '^FEISHU_DOMAIN=' "$HERMES_ENV" | head -1 | cut -d= -f2-)
fi
if [ -z "$APP_ID" ] && [ -f "$OC_CFG" ]; then
  APP_ID=$(python3 -c "import json; print(json.load(open('$OC_CFG'))['channels']['feishu']['appId'])" 2>/dev/null || echo "")
  APP_SECRET=$(python3 -c "import json; print(json.load(open('$OC_CFG'))['channels']['feishu']['appSecret'])" 2>/dev/null || echo "")
  DOMAIN_RAW=$(python3 -c "import json; print(json.load(open('$OC_CFG'))['channels']['feishu'].get('domain','lark'))" 2>/dev/null || echo "lark")
fi
if [ -z "$APP_ID" ] || [ -z "$APP_SECRET" ]; then
  echo "error: FEISHU_APP_ID / FEISHU_APP_SECRET not found" >&2
  exit 2
fi

DOMAIN_RAW=${DOMAIN_RAW:-lark}
case "$DOMAIN_RAW" in
  lark|larksuite) DOMAIN="https://open.larksuite.com" ;;
  feishu) DOMAIN="https://open.feishu.cn" ;;
  *) DOMAIN="https://open.larksuite.com" ;;
esac

# Build request bodies entirely in python (avoids bash brace/quote escaping hell)
# Token request
AUTH_BODY=$(APP_ID="$APP_ID" APP_SECRET="$APP_SECRET" python3 -c '
import json, os
print(json.dumps({"app_id": os.environ["APP_ID"], "app_secret": os.environ["APP_SECRET"]}))
')
TOKEN_RESP=$(curl -sS -X POST "$DOMAIN/open-apis/auth/v3/tenant_access_token/internal" \
  -H 'Content-Type: application/json' -d "$AUTH_BODY")
TOKEN=$(printf '%s' "$TOKEN_RESP" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tenant_access_token",""))' 2>/dev/null)
if [ -z "$TOKEN" ]; then
  echo "error: token acquisition failed: $TOKEN_RESP" >&2
  exit 3
fi

# Build message body via python (read text/open_id/chat_id from env to avoid escaping)
if [ -n "$CHAT_ID" ]; then
  RECEIVE_ID="$CHAT_ID"
  RECEIVE_ID_TYPE="chat_id"
else
  RECEIVE_ID="$OPEN_ID"
  RECEIVE_ID_TYPE="open_id"
fi
MSG_BODY=$(RECEIVE_ID="$RECEIVE_ID" MSG_TEXT="$TEXT" python3 -c '
import json, os
print(json.dumps({
    "receive_id": os.environ["RECEIVE_ID"],
    "msg_type": "text",
    "content": json.dumps({"text": os.environ["MSG_TEXT"]})
}))
')

RESP=$(curl -sS -X POST "$DOMAIN/open-apis/im/v1/messages?receive_id_type=$RECEIVE_ID_TYPE" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d "$MSG_BODY")
CODE=$(printf '%s' "$RESP" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("code","?"))' 2>/dev/null)
if [ "$CODE" = "0" ]; then
  exit 0
fi
echo "lark send failed (code=$CODE): $RESP" >&2
exit 1
