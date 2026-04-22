#!/bin/bash
# install/bootstrap.sh — one-command system setup for bare-metal / fresh VPS.
#
# Auto-detects OS (Ubuntu/Debian, RHEL/Fedora, Arch, Alpine, macOS) and
# installs the system-level packages review-agent needs. Does NOT install
# hermes itself (that's a separate project). Does NOT configure Lark or
# OpenRouter credentials (you do that interactively after bootstrap).
#
# Safe to re-run. Skips packages that are already installed.
#
# Usage:
#   bash install/bootstrap.sh                # installs everything below
#   bash install/bootstrap.sh --no-optional  # skip whisper/tesseract/pdftotext
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'

OS=""
if [ "$(uname)" = "Darwin" ]; then OS="macos"
elif [ -f /etc/os-release ]; then
  . /etc/os-release
  case "${ID:-}" in
    ubuntu|debian) OS="debian" ;;
    fedora|rhel|centos|rocky|alma) OS="rhel" ;;
    arch|manjaro) OS="arch" ;;
    alpine) OS="alpine" ;;
    *) OS="linux" ;;
  esac
fi

SKIP_OPTIONAL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --no-optional) SKIP_OPTIONAL=1; shift ;;
    -h|--help) echo "Usage: $0 [--no-optional]"; exit 0 ;;
    *) echo "unknown flag: $1"; exit 1 ;;
  esac
done

echo -e "${BLUE}══════════════════════════════════════════${NC}"
echo -e "${BLUE}  review-agent · system bootstrap ($OS)${NC}"
echo -e "${BLUE}══════════════════════════════════════════${NC}"
echo

# ─── Required packages per OS ───
case "$OS" in
  debian)
    REQUIRED_PKGS="git python3 python3-pip python3-yaml rsync curl"
    OPTIONAL_PKGS="poppler-utils tesseract-ocr tesseract-ocr-chi-sim ffmpeg"
    INSTALLER="sudo apt-get install -y"
    UPDATE="sudo apt-get update"
    ;;
  rhel)
    REQUIRED_PKGS="git python3 python3-pip python3-pyyaml rsync curl"
    OPTIONAL_PKGS="poppler-utils tesseract tesseract-langpack-chi_sim ffmpeg"
    INSTALLER="sudo dnf install -y"
    UPDATE=""
    ;;
  arch)
    REQUIRED_PKGS="git python python-pip python-yaml rsync curl"
    OPTIONAL_PKGS="poppler tesseract tesseract-data-chi_sim ffmpeg"
    INSTALLER="sudo pacman -S --needed --noconfirm"
    UPDATE="sudo pacman -Sy"
    ;;
  alpine)
    REQUIRED_PKGS="git python3 py3-pip py3-yaml rsync curl bash"
    OPTIONAL_PKGS="poppler-utils tesseract-ocr ffmpeg"
    INSTALLER="sudo apk add --no-cache"
    UPDATE="sudo apk update"
    ;;
  macos)
    if ! command -v brew >/dev/null 2>&1; then
      echo -e "${YELLOW}! Homebrew not installed.${NC} Installing now…"
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    REQUIRED_PKGS="git python@3.11 rsync curl"
    OPTIONAL_PKGS="poppler tesseract tesseract-lang ffmpeg openai-whisper"
    INSTALLER="brew install"
    UPDATE="brew update"
    ;;
  *)
    echo -e "${RED}error:${NC} unsupported OS: $OS"
    echo "Install manually: git, python3 (≥3.9), python3-yaml, rsync, curl"
    exit 2
    ;;
esac

# ─── Update package index ───
if [ -n "$UPDATE" ]; then
  echo -e "${BLUE}Updating package index…${NC}"
  $UPDATE
  echo
fi

# ─── Install required packages ───
echo -e "${BLUE}Installing required packages…${NC}"
echo -e "  ${GREEN}$INSTALLER $REQUIRED_PKGS${NC}"
$INSTALLER $REQUIRED_PKGS
echo

# ─── Install optional packages (for multi-modal ingest) ───
if [ $SKIP_OPTIONAL -eq 0 ]; then
  echo -e "${BLUE}Installing optional packages (for PDF/image/audio ingest)…${NC}"
  echo -e "  ${GREEN}$INSTALLER $OPTIONAL_PKGS${NC}"
  $INSTALLER $OPTIONAL_PKGS || echo -e "  ${YELLOW}!${NC} some optional packages failed — degraded ingest OK"
  # whisper on non-macOS: via pip
  if [ "$OS" != "macos" ]; then
    if ! command -v whisper >/dev/null 2>&1; then
      echo -e "  installing whisper via pip…"
      pip3 install --user openai-whisper 2>/dev/null \
        || echo -e "  ${YELLOW}!${NC} whisper install failed — audio ingest degraded"
    fi
  fi
  echo
else
  echo -e "${YELLOW}!${NC} skipped optional packages (--no-optional)"
  echo
fi

# ─── Final guidance ───
echo -e "${GREEN}✓ System bootstrap complete.${NC}"
echo
echo -e "${BLUE}Next steps:${NC}"
cat <<'NEXT'

1. Install hermes (not part of this bootstrap):
     https://github.com/hermes-agent/hermes

2. Configure hermes credentials:
     Create ~/.hermes/.env with at minimum:
       FEISHU_APP_ID=cli_xxxxxxxx
       FEISHU_APP_SECRET=xxxxxxxx
       FEISHU_DOMAIN=lark
       FEISHU_CONNECTION_MODE=websocket
       OPENROUTER_API_KEY=sk-or-v1-xxx
     Lark app credentials: https://open.larksuite.com/app
     OpenRouter key: https://openrouter.ai/keys

3. (Private repo) Ensure you can clone the repo:
     - If you have `gh`: gh auth login && gh repo clone jimmyag2026-prog/review-agent
     - Or add an SSH key to github.com/settings/keys, then:
         git clone git@github.com:jimmyag2026-prog/review-agent.git
     - Or use a Personal Access Token:
         git clone https://<TOKEN>@github.com/jimmyag2026-prog/review-agent.git

4. Run the skill installer from the repo root:
     bash install.sh
NEXT
