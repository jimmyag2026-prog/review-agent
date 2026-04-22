#!/bin/bash
# lark-fetch.sh — fetch Lark wiki / docx content via Open API
# Uses hermes feishu creds (~/.hermes/.env)
set -euo pipefail

HERMES_ENV="$HOME/.hermes/.env"

if [ $# -ne 1 ]; then
  echo "Usage: $(basename "$0") <lark_url>" >&2
  exit 1
fi

URL="$1"

APP_ID=$(grep -E '^FEISHU_APP_ID=' "$HERMES_ENV" | head -1 | cut -d= -f2-)
APP_SECRET=$(grep -E '^FEISHU_APP_SECRET=' "$HERMES_ENV" | head -1 | cut -d= -f2-)
DOMAIN_RAW=$(grep -E '^FEISHU_DOMAIN=' "$HERMES_ENV" | head -1 | cut -d= -f2-)

case "$DOMAIN_RAW" in
  lark|larksuite) DOMAIN="https://open.larksuite.com" ;;
  feishu) DOMAIN="https://open.feishu.cn" ;;
  *) DOMAIN="https://open.larksuite.com" ;;
esac

# Get token
AUTH_BODY=$(APP_ID="$APP_ID" APP_SECRET="$APP_SECRET" python3 -c '
import json, os
print(json.dumps({"app_id": os.environ["APP_ID"], "app_secret": os.environ["APP_SECRET"]}))
')
TOKEN_RESP=$(curl -sS -X POST "$DOMAIN/open-apis/auth/v3/tenant_access_token/internal" \
  -H 'Content-Type: application/json' -d "$AUTH_BODY")
TOKEN=$(printf '%s' "$TOKEN_RESP" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tenant_access_token",""))')
if [ -z "$TOKEN" ]; then
  echo "error: token fetch failed: $TOKEN_RESP" >&2
  exit 2
fi

# Parse URL → identify wiki vs docx and extract token
URL_TYPE=""
RES_TOKEN=""
if [[ "$URL" =~ /wiki/([A-Za-z0-9]+) ]]; then
  URL_TYPE="wiki"
  RES_TOKEN="${BASH_REMATCH[1]}"
elif [[ "$URL" =~ /docx/([A-Za-z0-9]+) ]]; then
  URL_TYPE="docx"
  RES_TOKEN="${BASH_REMATCH[1]}"
elif [[ "$URL" =~ /docs/([A-Za-z0-9]+) ]]; then
  URL_TYPE="docs"
  RES_TOKEN="${BASH_REMATCH[1]}"
fi

if [ -z "$URL_TYPE" ] || [ -z "$RES_TOKEN" ]; then
  echo "error: could not parse Lark URL type/token from: $URL" >&2
  exit 3
fi

# For wiki: first resolve node_token → obj_token; then fetch docx blocks
if [ "$URL_TYPE" = "wiki" ]; then
  NODE_RESP=$(curl -sS "$DOMAIN/open-apis/wiki/v2/spaces/get_node?token=$RES_TOKEN" \
    -H "Authorization: Bearer $TOKEN")
  OBJ_TOKEN=$(printf '%s' "$NODE_RESP" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("data",{}).get("node",{}).get("obj_token",""))')
  if [ -z "$OBJ_TOKEN" ]; then
    echo "error: wiki node resolve failed: $NODE_RESP" >&2
    exit 4
  fi
  RES_TOKEN="$OBJ_TOKEN"
fi

# Fetch docx raw content (block-based API). Use the /raw_content endpoint for plain text.
CONTENT_RESP=$(curl -sS "$DOMAIN/open-apis/docx/v1/documents/$RES_TOKEN/raw_content" \
  -H "Authorization: Bearer $TOKEN")
CODE=$(printf '%s' "$CONTENT_RESP" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("code","?"))')
if [ "$CODE" != "0" ]; then
  echo "error: raw_content fetch failed (code=$CODE): $CONTENT_RESP" >&2
  exit 5
fi

printf '%s' "$CONTENT_RESP" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("data",{}).get("content",""))'
