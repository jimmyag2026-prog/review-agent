#!/bin/bash
# setup-watcher.sh — install the review-agent template seeder as a user-mode
# systemd service. Replaces feishu_seed_workspace_patch.py (no longer needed).
#
# Why: the monitor.js patch approach was fragile across openclaw versions.
# This watcher works in pure userspace: when openclaw creates a new peer
# workspace dir, this daemon copies our review-agent template into it within
# milliseconds, so the subagent loads review-coach persona instead of
# openclaw's default memorist.
#
# Requirements:
#   - inotify-tools (we'll try to install via sudo apt / yum if missing)
#   - systemd user instance (default on Ubuntu/Debian/Fedora)
#
# Usage:
#   curl -fsSL <raw-url>/setup-watcher.sh | bash
#   bash setup-watcher.sh
#   bash setup-watcher.sh --uninstall
set -e

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'

UNIT_NAME=review-agent-seeder
UNIT_FILE="$HOME/.config/systemd/user/$UNIT_NAME.service"
TPL="$HOME/.openclaw/workspace/templates/review-agent"
LOG="$HOME/.openclaw/seeder.log"

if [ "${1:-}" = "--uninstall" ]; then
  systemctl --user disable --now $UNIT_NAME 2>/dev/null
  rm -f "$UNIT_FILE"
  systemctl --user daemon-reload
  echo -e "${GREEN}✓${NC} uninstalled $UNIT_NAME"
  exit 0
fi

echo "─── review-agent watcher installer ───"

# ── 1. inotify-tools ──
if ! command -v inotifywait >/dev/null 2>&1; then
  echo "installing inotify-tools (sudo prompt)..."
  if command -v apt >/dev/null 2>&1; then
    sudo apt update -qq && sudo apt install -y inotify-tools
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y inotify-tools
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y inotify-tools
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --noconfirm inotify-tools
  else
    echo -e "${RED}✗${NC} no apt/dnf/yum/pacman found — install inotify-tools manually then re-run"
    exit 1
  fi
fi
echo -e "${GREEN}✓${NC} inotifywait: $(command -v inotifywait)"

# ── 2. template must exist ──
if [ ! -d "$TPL" ]; then
  echo -e "${RED}✗${NC} template not found at $TPL"
  echo "  run install.sh first to install the workspace template, then re-run this"
  exit 2
fi
echo -e "${GREEN}✓${NC} template at $TPL ($(ls "$TPL" | wc -l | tr -d ' ') files)"

# ── 3. write the systemd unit ──
mkdir -p "$(dirname "$UNIT_FILE")"
cat > "$UNIT_FILE" <<UNITEOF
[Unit]
Description=review-agent peer-workspace template seeder
After=default.target

[Service]
Type=simple
ExecStart=/usr/bin/env bash -c 'inotifywait -m -e create --format %%w%%f $HOME/.openclaw 2>/dev/null | while read NEW; do case "\$NEW" in *workspace-feishu-*|*workspace-wecom-*) [ -d "\$NEW" ] && sleep 1 && cp -R $TPL/. "\$NEW/" 2>/dev/null && rm -f $HOME/.openclaw/agents/\$(basename \$NEW | sed s/workspace-//)/sessions/*.jsonl 2>/dev/null && echo "\$(date -Iseconds) seeded \$NEW" >> $LOG ;; esac; done'
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
UNITEOF
echo -e "${GREEN}✓${NC} unit written to $UNIT_FILE"

# ── 4. enable + start ──
systemctl --user daemon-reload
systemctl --user enable --now $UNIT_NAME
echo -e "${GREEN}✓${NC} enabled + started"

# ── 5. linger so it survives ssh disconnect ──
if command -v loginctl >/dev/null 2>&1; then
  if ! loginctl show-user "$(whoami)" 2>/dev/null | grep -q Linger=yes; then
    if sudo -n true 2>/dev/null; then
      sudo loginctl enable-linger "$(whoami)" && \
        echo -e "${GREEN}✓${NC} loginctl linger enabled (survives ssh disconnect)"
    else
      echo -e "${YELLOW}!${NC} couldn't auto-enable linger (no sudo). To make watcher survive ssh disconnect, run later:"
      echo "    sudo loginctl enable-linger $(whoami)"
    fi
  fi
fi

# ── 6. verify ──
echo
echo "─── status ───"
systemctl --user status $UNIT_NAME --no-pager 2>&1 | head -6
echo
echo "─── log will appear at: $LOG ───"
echo
echo -e "${GREEN}✓ done.${NC} watcher will seed review-coach persona into every new peer workspace."
echo
echo "Test: have a new feishu user DM your bot. Then:"
echo "    tail -3 $LOG"
echo "should show: <timestamp> seeded ~/.openclaw/workspace-feishu-ou_xxx"
echo
echo "Uninstall later: bash $0 --uninstall"
