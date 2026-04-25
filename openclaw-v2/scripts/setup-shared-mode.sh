#!/bin/bash
# setup-shared-mode.sh — review-agent v2 in single-agent mode (no per-peer subagent).
#
# When to use this: you're running 1-3 Requesters and don't need per-peer context
# isolation. Simpler than the watcher/patcher path; works on any openclaw version
# without root, sudo, systemd, or inotify.
#
# What it does:
#   1. Disable channels.feishu.dynamicAgentCreation (so openclaw doesn't create
#      empty per-peer workspaces).
#   2. Inject review-agent's SOUL.md / AGENTS.md / BOOTSTRAP.md as the MAIN
#      agent's persona files (so the main agent itself becomes a review-coach).
#   3. Ensure the review-agent skill is loadable by the main agent.
#   4. Restart openclaw gateway.
#
# After this, every Lark DM lands in the main agent (already configured as
# review-coach), and the skill provides the four-pillar / Q&A scripts.
#
# Trade-off: all Requesters share the main agent's context (no per-peer
# isolation). For ≤3 active Requesters this is usually fine.
#
# Usage:
#   bash setup-shared-mode.sh
#   bash setup-shared-mode.sh --revert   (re-enable dynamicAgentCreation,
#                                          remove main-agent persona overrides)
set -e

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'

OPENCLAW_JSON="$HOME/.openclaw/openclaw.json"
TEMPLATE_DIR="$HOME/.openclaw/workspace/templates/review-agent"
MAIN_AGENT_DIR="$HOME/.openclaw/agents/main/agent"
MAIN_WORKSPACE="$HOME/.openclaw/agents/main/workspace"

if [ "${1:-}" = "--revert" ]; then
  echo "─── reverting shared-mode setup ───"
  python3 - <<PY
import json, shutil
from pathlib import Path
p = Path("$OPENCLAW_JSON")
if p.exists():
    d = json.loads(p.read_text())
    f = d.get('channels', {}).get('feishu', {})
    if 'dynamicAgentCreation' in f:
        f['dynamicAgentCreation']['enabled'] = True
        p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
        print("  re-enabled feishu.dynamicAgentCreation")
PY
  for f in SOUL.md AGENTS.md BOOTSTRAP.md HEARTBEAT.md IDENTITY.md responder-profile.md; do
    [ -f "$MAIN_AGENT_DIR/$f.shared-mode-bak" ] && mv "$MAIN_AGENT_DIR/$f.shared-mode-bak" "$MAIN_AGENT_DIR/$f" 2>/dev/null
    [ -f "$MAIN_WORKSPACE/$f.shared-mode-bak" ] && mv "$MAIN_WORKSPACE/$f.shared-mode-bak" "$MAIN_WORKSPACE/$f" 2>/dev/null
  done
  echo -e "${GREEN}✓${NC} reverted. restart gateway: openclaw gateway restart"
  exit 0
fi

echo "─── review-agent v2 shared-mode setup ───"
echo

# ── 1. sanity ──
if [ ! -f "$OPENCLAW_JSON" ]; then
  echo -e "${RED}✗${NC} $OPENCLAW_JSON not found — run 'openclaw setup' first"
  exit 2
fi
if [ ! -d "$TEMPLATE_DIR" ]; then
  echo -e "${RED}✗${NC} template dir $TEMPLATE_DIR not found"
  echo "  run install.sh first to install the workspace template"
  exit 2
fi
echo -e "${GREEN}✓${NC} prereqs OK (running as $(whoami), HOME=$HOME)"

# ── 2. disable dynamicAgentCreation ──
echo
echo "─── 1/4: disable feishu.dynamicAgentCreation ───"
python3 - <<PY
import json, shutil
from pathlib import Path
from datetime import datetime
p = Path("$OPENCLAW_JSON")
d = json.loads(p.read_text())
f = d.setdefault('channels', {}).setdefault('feishu', {})
dac = f.setdefault('dynamicAgentCreation', {})
prev = dac.get('enabled', False)
if prev is not False:
    bak = p.with_suffix(f".json.bak.shared-mode-{datetime.now().strftime('%Y%m%d_%H%M%S')}")
    shutil.copy2(p, bak)
    dac['enabled'] = False
    p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
    print(f"  ✓ disabled (was {prev}). backup: {bak.name}")
else:
    print("  (already disabled)")
PY

# ── 3. inject persona into main agent's persona dirs ──
echo
echo "─── 2/4: install review-coach persona on the main agent ───"
mkdir -p "$MAIN_WORKSPACE" "$MAIN_AGENT_DIR"
COPIED=0
for f in SOUL.md AGENTS.md BOOTSTRAP.md HEARTBEAT.md IDENTITY.md USER.md review_rules.md; do
  src="$TEMPLATE_DIR/$f"
  [ -f "$src" ] || continue
  for dst_dir in "$MAIN_WORKSPACE" "$MAIN_AGENT_DIR"; do
    dst="$dst_dir/$f"
    if [ -f "$dst" ] && [ ! -f "$dst.shared-mode-bak" ]; then
      cp "$dst" "$dst.shared-mode-bak"
    fi
    cp "$src" "$dst"
    COPIED=$((COPIED+1))
  done
done
# Symlink responder-profile.md from global
GLOBAL_PROFILE="$HOME/.openclaw/review-agent/responder-profile.md"
if [ -f "$GLOBAL_PROFILE" ]; then
  for dst_dir in "$MAIN_WORKSPACE" "$MAIN_AGENT_DIR"; do
    rm -f "$dst_dir/responder-profile.md"
    ln -sf "$GLOBAL_PROFILE" "$dst_dir/responder-profile.md"
  done
  COPIED=$((COPIED+2))
fi
echo "  ✓ wrote $COPIED persona files into main-agent workspace + agentDir"

# ── 4. ensure skill is loadable ──
echo
echo "─── 3/4: verify review-agent skill ───"
SKILL_PATHS=(
  "$HOME/.openclaw/workspace/skills/review-agent"
  "$HOME/.openclaw/skills/review-agent"
)
FOUND_SKILL=""
for sp in "${SKILL_PATHS[@]}"; do
  if [ -f "$sp/SKILL.md" ]; then
    FOUND_SKILL="$sp"
    break
  fi
done
if [ -n "$FOUND_SKILL" ]; then
  echo "  ✓ skill loaded from $FOUND_SKILL"
else
  echo -e "  ${YELLOW}!${NC} skill not found at standard locations. Install it:"
  echo "    clawhub install review-agent --force"
  echo "  or: git clone https://github.com/jimmyag2026-prog/review-agent-skill ~/.openclaw/skills/review-agent"
fi

# ── 5. restart gateway ──
echo
echo "─── 4/4: restart openclaw gateway ───"
if command -v openclaw >/dev/null 2>&1; then
  openclaw gateway restart 2>&1 | tail -3 || echo -e "  ${YELLOW}!${NC} gateway restart had issues; run manually: openclaw gateway restart"
else
  echo -e "  ${YELLOW}!${NC} 'openclaw' not in PATH; restart manually:"
  echo "    openclaw gateway restart"
fi

echo
echo -e "${GREEN}═══ DONE ═══${NC}"
echo
cat <<EOF
Now:
  - feishu.dynamicAgentCreation is OFF (no per-peer subagent spawn)
  - main openclaw agent has review-coach SOUL.md + AGENTS.md
  - When a Lark user DMs your bot, the main agent acts as the review-coach
  - skill review-agent provides ingest/scan/qa-step scripts

Test:
  Have a Lark user (Evie or other) DM the bot a proposal or Lark doc URL.
  Watch the gateway log:
    journalctl --user -u openclaw-gateway --no-pager -f 2>/dev/null \\
      || tail -F \$HOME/.openclaw/logs/gateway.log

  Expect: 'dispatching to agent (session=agent:main:main)'
  followed by a review-coach style reply (NOT 'Hey I just came online').

Limitations:
  All Requesters share the main agent's context. If you scale past 3
  concurrent Requesters and want per-peer isolation, switch to either:
    - watcher mode: bash setup-watcher.sh
    - pre-enroll mode: TBD (v2.2)

Revert this setup:
  bash setup-shared-mode.sh --revert
EOF
