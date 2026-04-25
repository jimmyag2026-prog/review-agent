#!/bin/bash
# vps-doctor.sh — auto-diagnose + auto-fix every common review-agent VPS issue.
# Run as root or as openclaw user. Idempotent. No prompts.
#
# Fixes:
#   - missing/incorrect dynamicAgentCreation in openclaw.json
#   - {responder_name} placeholder unsubstituted in template/peer SOUL.md/AGENTS.md
#   - missing owner.json (still has owner.json.template)
#   - missing global responder-profile.md
#   - broken responder-profile.md symlink in peer workspaces
#   - cached subagent sessions causing prompt-cache stickiness
#   - re-seeds all existing peer workspaces from fresh template

set -e
GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'

# ── detect user ──
if [ "$(whoami)" = "root" ]; then
  RUN="sudo -u openclaw"
  HOME_OC="/home/openclaw"
else
  RUN=""
  HOME_OC="$HOME"
fi

OC=$HOME_OC/.openclaw
TEMPLATE=$OC/workspace/templates/review-agent
GLOBAL_PROFILE=$OC/review-agent/responder-profile.md

# ── decide responder name ──
ADMIN_NAME="${RESPONDER_NAME:-}"
if [ -z "$ADMIN_NAME" ]; then
  if [ -f "$OC/review-agent/enabled.json" ]; then
    ADMIN_NAME=$($RUN python3 -c "import json; d=json.load(open('$OC/review-agent/enabled.json')); print(d.get('admin_display_name',''))" 2>/dev/null)
  fi
fi
ADMIN_NAME="${ADMIN_NAME:-Boss}"

# ── decide admin open_id ──
ADMIN_OID=""
if [ -f "$OC/review-agent/enabled.json" ]; then
  ADMIN_OID=$($RUN python3 -c "import json; d=json.load(open('$OC/review-agent/enabled.json')); print(d.get('admin_open_id',''))" 2>/dev/null)
fi

echo "─── review-agent VPS doctor ───"
echo "  HOME=$HOME_OC  responder_name=$ADMIN_NAME  admin_oid=${ADMIN_OID:-<unknown>}"
echo

# ── 1. ensure global responder-profile.md ──
echo "─── 1. global responder-profile.md ───"
$RUN mkdir -p $OC/review-agent
if [ ! -f "$GLOBAL_PROFILE" ]; then
  for src in $TEMPLATE/responder-profile.md $TEMPLATE/../../skills/review-agent/references/template/boss_profile.md $HOME_OC/.openclaw/skills/review-agent/references/template/boss_profile.md $HOME_OC/.openclaw/workspace/skills/review-agent/references/template/boss_profile.md; do
    [ -f "$src" ] && [ ! -L "$src" ] && $RUN cp "$src" "$GLOBAL_PROFILE" && break
  done
  if [ -f "$GLOBAL_PROFILE" ]; then
    echo "  ✓ created from default boss_profile template"
  else
    $RUN bash -c "cat > $GLOBAL_PROFILE <<EOF
# Responder Profile
Name: $ADMIN_NAME
Decision style: data-first, fast yes/no
Pet peeves: vague asks, no numbers, recommendations creating follow-up work
Always ask: What's the smallest version testable in a week? Who disagrees?
EOF"
    echo "  ✓ created minimal default"
  fi
else
  echo "  ✓ exists"
fi

# ── 2. fix template files: substitute {responder_name} + materialize owner.json ──
echo "─── 2. template substitution ───"
if [ -d "$TEMPLATE" ]; then
  for f in SOUL.md AGENTS.md BOOTSTRAP.md HEARTBEAT.md IDENTITY.md USER.md; do
    [ -f "$TEMPLATE/$f" ] && $RUN sed -i "s|{responder_name}|$ADMIN_NAME|g" "$TEMPLATE/$f"
  done
  # materialize owner.json from .template if not present
  if [ -f "$TEMPLATE/owner.json.template" ] && [ ! -f "$TEMPLATE/owner.json" ]; then
    $RUN bash -c "cat > $TEMPLATE/owner.json <<EOF
{
  \"admin_open_id\": \"$ADMIN_OID\",
  \"admin_display_name\": \"$ADMIN_NAME\",
  \"responder_open_id\": \"$ADMIN_OID\",
  \"responder_name\": \"$ADMIN_NAME\"
}
EOF"
    $RUN rm -f $TEMPLATE/owner.json.template
  fi
  # remove the install marker if any
  $RUN rm -f $TEMPLATE/responder-profile.md.INSTALL_SHOULD_SYMLINK
  # responder-profile.md → symlink to global
  $RUN bash -c "[ -L $TEMPLATE/responder-profile.md ] || (rm -f $TEMPLATE/responder-profile.md && ln -s $GLOBAL_PROFILE $TEMPLATE/responder-profile.md)"
  echo "  ✓ template ready"
else
  echo -e "  ${RED}✗${NC} no template at $TEMPLATE — install.sh first"
  exit 2
fi

# ── 3. re-seed every existing peer workspace from fresh template ──
echo "─── 3. re-seed existing peer workspaces ───"
SEEDED=0
for ws in $OC/workspace-feishu-* $OC/workspace-wecom-*; do
  [ -d "$ws" ] || continue
  $RUN cp -R $TEMPLATE/. $ws/ 2>/dev/null
  $RUN sed -i "s|{responder_name}|$ADMIN_NAME|g" $ws/SOUL.md $ws/AGENTS.md $ws/BOOTSTRAP.md $ws/HEARTBEAT.md $ws/IDENTITY.md $ws/USER.md 2>/dev/null
  $RUN rm -f $ws/owner.json.template
  # symlink responder-profile to global
  $RUN bash -c "[ -L $ws/responder-profile.md ] || (rm -f $ws/responder-profile.md && ln -s $GLOBAL_PROFILE $ws/responder-profile.md)"
  echo "  ✓ $ws"
  SEEDED=$((SEEDED+1))
done
[ $SEEDED -eq 0 ] && echo "  (no peer workspaces yet — watcher will seed on next DM)"

# ── 4. clear cached subagent sessions ──
echo "─── 4. clear subagent prompt-cache ───"
CLEARED=0
for ad in $OC/agents/feishu-* $OC/agents/wecom-*; do
  [ -d "$ad/sessions" ] || continue
  $RUN rm -f $ad/sessions/*.jsonl $ad/sessions/sessions.json $ad/sessions/*.lock 2>/dev/null
  CLEARED=$((CLEARED+1))
done
echo "  ✓ cleared $CLEARED agent's session cache"

# ── 5. fix openclaw.json dynamicAgentCreation if needed ──
echo "─── 5. openclaw.json dynamicAgentCreation ───"
$RUN python3 - <<PY
import json, shutil
from pathlib import Path
from datetime import datetime
p = Path("$OC/openclaw.json")
if not p.exists():
    print("  ✗ openclaw.json not found"); raise SystemExit(2)
d = json.loads(p.read_text())
f = d.setdefault('channels', {}).setdefault('feishu', {})
correct = {
    'enabled': True,
    'workspaceTemplate': '$HOME_OC/.openclaw/workspace-{agentId}',
    'agentDirTemplate':  '$HOME_OC/.openclaw/agents/{agentId}/agent',
    'maxAgents': 100,
}
existing = f.get('dynamicAgentCreation') or {}
if existing != correct:
    bak = p.with_suffix(f".json.bak.doctor-{datetime.now().strftime('%Y%m%d_%H%M%S')}")
    shutil.copy2(p, bak)
    f['dynamicAgentCreation'] = correct
    # clean legacy bad keys at channels.feishu top level
    for k in ('dynamicAgents', 'dm', 'workspaceTemplate'):
        if k in f and k != 'dynamicAgentCreation': del f[k]
    p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
    print(f"  ✓ fixed dynamicAgentCreation. backup: {bak.name}")
else:
    print("  ✓ already correct")
PY

# ── 6. restart gateway ──
echo "─── 6. restart openclaw gateway ───"
if sudo systemctl restart openclaw-gateway 2>/dev/null; then
  echo "  ✓ restarted (system service)"
elif command -v openclaw >/dev/null 2>&1; then
  $RUN openclaw gateway restart 2>&1 | tail -3
else
  echo -e "  ${YELLOW}!${NC} restart manually"
fi

echo
echo -e "${GREEN}═══ DONE ═══${NC}"
echo
echo "Now:"
echo "  1. Have Evie send a NEW DM to the bot"
echo "  2. Wait 10 seconds"
echo "  3. Run: $RUN tail -3 $OC/seeder.log"
echo "  4. Watch the gateway log:"
echo "       sudo journalctl -u openclaw-gateway --no-pager -f"
echo "     OR"
echo "       $RUN tail -F $OC/logs/gateway.log"
echo
echo "If still 'Something went wrong', send back full output of:"
echo "  sudo journalctl -u openclaw-gateway --no-pager -n 40"
