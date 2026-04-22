#!/bin/bash
# install/check_prereqs.sh — verify environment is ready for review-agent.
# On failures, print OS-specific install hint. Returns non-zero on blockers.
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
fails=0; warns=0

# Detect OS
OS="unknown"
if [ "$(uname)" = "Darwin" ]; then OS="macos"
elif [ -f /etc/os-release ]; then
  . /etc/os-release
  case "${ID:-}" in
    ubuntu|debian) OS="debian" ;;
    fedora|rhel|centos|rocky|alma) OS="rhel" ;;
    arch|manjaro) OS="arch" ;;
    alpine) OS="alpine" ;;
    *) OS="${ID:-linux}" ;;
  esac
fi

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; fails=$((fails+1))
         [ -n "${2:-}" ] && echo -e "     ${CYAN}→ fix:${NC} $2"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; warns=$((warns+1))
         [ -n "${2:-}" ] && echo -e "     ${CYAN}→ fix:${NC} $2"; }

# per-OS install hints
hint_apt()   { echo "sudo apt update && sudo apt install -y $*"; }
hint_brew()  { echo "brew install $*"; }
hint_yum()   { echo "sudo dnf install -y $*"; }
hint_pacman(){ echo "sudo pacman -S --noconfirm $*"; }
hint_apk()   { echo "sudo apk add $*"; }

install_hint() {
  local pkg="$1"
  case "$OS" in
    debian)  hint_apt "$pkg" ;;
    macos)   hint_brew "$pkg" ;;
    rhel)    hint_yum "$pkg" ;;
    arch)    hint_pacman "$pkg" ;;
    alpine)  hint_apk "$pkg" ;;
    *)       echo "install '$pkg' using your package manager" ;;
  esac
}

echo "Prerequisite check (detected OS: ${OS})"
echo

# ─── Core system tools ───
command -v git >/dev/null 2>&1 \
  && ok "git $(git --version | awk '{print $3}')" \
  || fail "git not found" "$(install_hint git)"

if command -v python3 >/dev/null 2>&1; then
  PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")')
  PY_MAJ=$(python3 -c 'import sys; print(sys.version_info[0])')
  PY_MIN=$(python3 -c 'import sys; print(sys.version_info[1])')
  if [ "$PY_MAJ" -ge 3 ] && [ "$PY_MIN" -ge 9 ]; then
    ok "python3 $PY_VER"
  else
    fail "python3 $PY_VER too old (need ≥ 3.9)" "$(install_hint python3)"
  fi
else
  case "$OS" in
    debian) fix="$(install_hint 'python3 python3-pip')" ;;
    macos) fix="$(install_hint 'python@3.11')" ;;
    *) fix="$(install_hint python3)" ;;
  esac
  fail "python3 not found" "$fix"
fi

# Python yaml module — needed for config patch
if python3 -c "import yaml" 2>/dev/null; then
  ok "python3 yaml module"
else
  case "$OS" in
    debian) fix="sudo apt install -y python3-yaml   # or: pip3 install pyyaml" ;;
    macos) fix="pip3 install pyyaml" ;;
    rhel)  fix="sudo dnf install -y python3-pyyaml" ;;
    alpine) fix="sudo apk add py3-yaml" ;;
    *) fix="pip3 install pyyaml" ;;
  esac
  fail "python3 yaml module missing" "$fix"
fi

command -v rsync >/dev/null 2>&1 \
  && ok "rsync" \
  || warn "rsync not found — will fall back to 'cp -R' (OK but slightly slower)" "$(install_hint rsync)"

command -v curl >/dev/null 2>&1 \
  && ok "curl" \
  || fail "curl not found" "$(install_hint curl)"

# ─── hermes CLI ───
if command -v hermes >/dev/null 2>&1; then
  ok "hermes CLI ($(command -v hermes))"
else
  case "$OS" in
    debian|rhel|alpine|arch) h="# see https://github.com/hermes-agent/hermes for install" ;;
    macos) h="# see hermes docs: https://github.com/hermes-agent/hermes" ;;
    *) h="# install hermes first" ;;
  esac
  fail "hermes CLI not found" "$h"
fi

# ─── hermes .env & keys ───
HERMES_ENV="$HOME/.hermes/.env"
if [ -f "$HERMES_ENV" ]; then
  ok ".env at $HERMES_ENV"
  grep -q "^FEISHU_APP_ID=" "$HERMES_ENV" 2>/dev/null \
    && ok "FEISHU_APP_ID present" \
    || fail "FEISHU_APP_ID missing in $HERMES_ENV" "设置: echo 'FEISHU_APP_ID=cli_xxx' >> $HERMES_ENV  (在 Lark Open 开发者后台建 app 后拿)"
  grep -q "^FEISHU_APP_SECRET=" "$HERMES_ENV" 2>/dev/null \
    && ok "FEISHU_APP_SECRET present" \
    || fail "FEISHU_APP_SECRET missing in $HERMES_ENV" "设置: echo 'FEISHU_APP_SECRET=xxxxxx' >> $HERMES_ENV"
  grep -q "^OPENROUTER_API_KEY=" "$HERMES_ENV" 2>/dev/null \
    && ok "OPENROUTER_API_KEY present" \
    || fail "OPENROUTER_API_KEY missing" "设置: echo 'OPENROUTER_API_KEY=sk-or-v1-xxx' >> $HERMES_ENV  (https://openrouter.ai/keys)"
else
  fail ".env missing at $HERMES_ENV" "run 'hermes setup' first"
fi

# ─── hermes dirs / config ───
[ -d "$HOME/.hermes/memories" ] && ok "~/.hermes/memories exists" \
  || warn "~/.hermes/memories missing — will be created on first hermes chat"

[ -f "$HOME/.hermes/config.yaml" ] && ok "~/.hermes/config.yaml exists" \
  || fail "~/.hermes/config.yaml missing" "run 'hermes setup' first"

# ─── hermes gateway ───
if hermes gateway status 2>/dev/null | grep -qi running; then
  ok "hermes gateway running"
else
  warn "hermes gateway not running" "hermes gateway install && hermes gateway start  (先装 launchd/systemd service)"
fi

# ─── Lark pairing ───
if hermes pairing list 2>&1 | grep -q "feishu"; then
  ok "Lark pairing exists"
else
  warn "No Lark (feishu) pairing yet" "让你自己 DM bot 一次，然后 'hermes pairing approve <open_id>'"
fi

# ─── Optional tools for ingest ───
# ─── Optional tools install hints (extracted for clean multi-line case) ───

hint_whisper() {
  case "$OS" in
    macos)  echo "brew install openai-whisper" ;;
    debian) echo "pip3 install openai-whisper && sudo apt install -y ffmpeg" ;;
    rhel)   echo "pip3 install openai-whisper && sudo dnf install -y ffmpeg" ;;
    *)      echo "pip3 install openai-whisper" ;;
  esac
}

hint_pdftotext() {
  case "$OS" in
    macos)  echo "brew install poppler" ;;
    debian) echo "sudo apt install -y poppler-utils" ;;
    rhel)   echo "sudo dnf install -y poppler-utils" ;;
    arch)   echo "sudo pacman -S poppler" ;;
    alpine) echo "sudo apk add poppler-utils" ;;
    *)      echo "install poppler / poppler-utils" ;;
  esac
}

hint_tesseract() {
  case "$OS" in
    macos)  echo "brew install tesseract tesseract-lang" ;;
    debian) echo "sudo apt install -y tesseract-ocr tesseract-ocr-chi-sim" ;;
    rhel)   echo "sudo dnf install -y tesseract tesseract-langpack-chi_sim" ;;
    arch)   echo "sudo pacman -S tesseract tesseract-data-chi_sim" ;;
    alpine) echo "sudo apk add tesseract-ocr" ;;
    *)      echo "install tesseract + 中文 language pack" ;;
  esac
}

hint_gh() {
  case "$OS" in
    macos)  echo "brew install gh" ;;
    debian) echo "sudo apt install -y gh   # or: https://github.com/cli/cli/blob/trunk/docs/install_linux.md" ;;
    rhel)   echo "sudo dnf install -y gh" ;;
    arch)   echo "sudo pacman -S github-cli" ;;
    alpine) echo "sudo apk add github-cli" ;;
    *)      echo "see https://github.com/cli/cli for your distro" ;;
  esac
}

command -v whisper >/dev/null 2>&1 \
  && ok "whisper (audio ingest)" \
  || warn "whisper not installed — audio messages fall back to 'paste text'" "$(hint_whisper)"

command -v pdftotext >/dev/null 2>&1 \
  && ok "pdftotext (PDF ingest)" \
  || warn "pdftotext not installed — PDF falls back to 'paste text'" "$(hint_pdftotext)"

command -v tesseract >/dev/null 2>&1 \
  && ok "tesseract (OCR for image ingest)" \
  || warn "tesseract not installed — image OCR unavailable" "$(hint_tesseract)"

# ─── gh (only needed if cloning via gh, not SSH/HTTPS) ───
if command -v gh >/dev/null 2>&1; then
  ok "gh CLI (optional for cloning private repo)"
else
  warn "gh CLI not found — use 'git clone' with SSH/HTTPS+token instead, or install gh" "$(hint_gh)"
fi

echo
if [ $fails -gt 0 ]; then
  echo -e "${RED}✗ $fails blocking issue(s)${NC}. Resolve the ${CYAN}→ fix${NC} lines above, then re-run."
  echo
  echo -e "Tip: to auto-install Linux system deps, run:"
  echo -e "  ${CYAN}bash $(cd "$(dirname "$0")"/.. && pwd)/install/bootstrap.sh${NC}"
  exit 1
elif [ $warns -gt 0 ]; then
  echo -e "${YELLOW}! $warns warning(s)${NC}. Install可继续; 某些可选特性会降级."
  exit 0
else
  echo -e "${GREEN}✓ all checks passed.${NC}"
  exit 0
fi
