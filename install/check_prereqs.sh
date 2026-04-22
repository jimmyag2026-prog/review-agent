#!/bin/bash
# install/check_prereqs.sh — verify environment is ready for review-agent.
# Returns 0 if all prereqs met, non-zero with specific messages otherwise.
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
fails=0
warns=0

check_ok()    { echo -e "  ${GREEN}✓${NC} $1"; }
check_fail()  { echo -e "  ${RED}✗${NC} $1"; fails=$((fails+1)); }
check_warn()  { echo -e "  ${YELLOW}!${NC} $1"; warns=$((warns+1)); }

echo "Prerequisite checks:"

# hermes CLI
if command -v hermes >/dev/null 2>&1; then
  check_ok "hermes CLI available ($(command -v hermes))"
else
  check_fail "hermes CLI not found — install hermes first (https://github.com/hermes-agent/hermes)"
fi

# Python 3.9+
if command -v python3 >/dev/null 2>&1; then
  PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")')
  check_ok "python3 $PY_VER"
else
  check_fail "python3 not found"
fi

# hermes .env
HERMES_ENV="$HOME/.hermes/.env"
if [ -f "$HERMES_ENV" ]; then
  check_ok ".env at $HERMES_ENV"
  grep -q "^FEISHU_APP_ID=" "$HERMES_ENV" 2>/dev/null \
    && check_ok "FEISHU_APP_ID present" \
    || check_fail "FEISHU_APP_ID missing in $HERMES_ENV"
  grep -q "^FEISHU_APP_SECRET=" "$HERMES_ENV" 2>/dev/null \
    && check_ok "FEISHU_APP_SECRET present" \
    || check_fail "FEISHU_APP_SECRET missing in $HERMES_ENV"
  grep -q "^OPENROUTER_API_KEY=" "$HERMES_ENV" 2>/dev/null \
    && check_ok "OPENROUTER_API_KEY present" \
    || check_fail "OPENROUTER_API_KEY missing in $HERMES_ENV (needed for LLM calls)"
else
  check_fail ".env missing at $HERMES_ENV — run 'hermes setup' first"
fi

# hermes memories dir
if [ -d "$HOME/.hermes/memories" ]; then
  check_ok "~/.hermes/memories exists"
else
  check_warn "~/.hermes/memories missing — will be created by hermes on first chat"
fi

# hermes config.yaml
if [ -f "$HOME/.hermes/config.yaml" ]; then
  check_ok "~/.hermes/config.yaml exists"
else
  check_fail "~/.hermes/config.yaml missing — run 'hermes setup' first"
fi

# Gateway running (optional but recommended)
if hermes gateway status 2>/dev/null | grep -qi running; then
  check_ok "hermes gateway running"
else
  check_warn "hermes gateway not running — run 'hermes gateway install && hermes gateway start' to receive Lark inbound"
fi

# Lark open_id paired (user knows own open_id only after pairing the bot)
if hermes pairing list 2>&1 | grep -q "feishu" ; then
  check_ok "Lark pairing exists"
else
  check_warn "No Lark (feishu) pairing yet — DM your bot once, then 'hermes pairing approve <open_id>' to pair"
fi

# Optional tools
command -v whisper >/dev/null 2>&1 \
  && check_ok "whisper (audio ingest) available" \
  || check_warn "whisper not installed — audio message ingest will fall back to 'please paste text'"

command -v pdftotext >/dev/null 2>&1 \
  && check_ok "pdftotext available" \
  || check_warn "pdftotext not installed — PDF ingest will fall back. Install: brew install poppler"

echo
if [ $fails -gt 0 ]; then
  echo -e "${RED}✗ $fails blocking issues${NC}. Fix them before installing."
  exit 1
elif [ $warns -gt 0 ]; then
  echo -e "${YELLOW}! $warns warnings${NC}. Install can proceed; some features may be limited."
  exit 0
else
  echo -e "${GREEN}✓ all checks passed.${NC}"
  exit 0
fi
