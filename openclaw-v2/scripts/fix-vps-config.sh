#!/bin/bash
# fix-vps-config.sh — fix the bad workspaceTemplate value left by old patcher.
# Run as root: sudo bash fix-vps-config.sh
# Or as openclaw user: bash fix-vps-config.sh
set -e

# Detect: are we root or openclaw user
if [ "$(whoami)" = "root" ]; then
  SUDO_OC="sudo -u openclaw"
  HOME_OC="/home/openclaw"
elif [ "$(whoami)" = "openclaw" ]; then
  SUDO_OC=""
  HOME_OC="$HOME"
else
  echo "run as root or openclaw user"; exit 1
fi

CONF="$HOME_OC/.openclaw/openclaw.json"

echo "─── 1/4: backup config ───"
$SUDO_OC cp "$CONF" "$CONF.bak.fix-wt-$(date +%Y%m%d_%H%M%S)"

echo "─── 2/4: rewrite dynamicAgentCreation with correct {agentId} placeholder ───"
$SUDO_OC python3 - <<PY
import json
from pathlib import Path
p = Path("$CONF")
d = json.loads(p.read_text())
f = d.setdefault('channels', {}).setdefault('feishu', {})
f['dynamicAgentCreation'] = {
    'enabled': True,
    'workspaceTemplate': '$HOME_OC/.openclaw/workspace-{agentId}',
    'agentDirTemplate':  '$HOME_OC/.openclaw/agents/{agentId}/agent',
    'maxAgents': 100,
}
# Clear stale feishu bindings + agent entries — let openclaw recreate properly
d['bindings'] = [b for b in d.get('bindings',[])
                 if not (b.get('match',{}).get('channel')=='feishu')]
agents = d.setdefault('agents', {}).setdefault('list', [])
d['agents']['list'] = [a for a in agents if not a.get('id','').startswith('feishu-')]
p.write_text(json.dumps(d, indent=2, ensure_ascii=False)+'\n')
print("  ✓ dynamicAgentCreation fixed; cleared stale feishu bindings + agents")
PY

echo "─── 3/4: clean stale workspace-feishu-* + agents/feishu-* dirs ───"
$SUDO_OC rm -rf "$HOME_OC/.openclaw/agents/feishu-"* "$HOME_OC/.openclaw/workspace-feishu-"* 2>/dev/null || true
echo "  ✓ cleaned"

echo "─── 4/4: restart openclaw gateway ───"
$SUDO_OC openclaw gateway restart 2>&1 | tail -5 || echo "  ! restart had issues; try: sudo systemctl restart openclaw-gateway"

echo
echo "═══ DONE ═══"
echo "Now have Evie DM the bot — openclaw will create:"
echo "  $HOME_OC/.openclaw/workspace-feishu-ou_xxx/"
echo "watcher will seed review-coach template into it. Verify with:"
echo "  $SUDO_OC tail -3 $HOME_OC/.openclaw/seeder.log"
