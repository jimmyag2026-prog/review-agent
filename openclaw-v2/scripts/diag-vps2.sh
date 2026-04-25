#!/bin/bash
# review-agent v2.1.2 — discovery for new openclaw versions where ANCHOR_RE no longer matches.
# Finds which monitor-*.js has the dynamic-agent creator + dumps function shape.

echo "─── [1] which monitor-*.js has the dynamic-agent function ───"
for f in /usr/lib/node_modules/openclaw/dist/monitor-*.js \
         /usr/local/lib/node_modules/openclaw/dist/monitor-*.js \
         /opt/homebrew/lib/node_modules/openclaw/dist/monitor-*.js; do
  [ -f "$f" ] || continue
  H=$(grep -c 'maybeCreateDynamicAgent\|feishu: creating dynamic agent\|dynamicAgentCreation' "$f" 2>/dev/null)
  [ "$H" -gt 0 ] && echo "  ★ $f  hits=$H"
done

echo
echo "─── [2] function body around the creator ───"
for f in /usr/lib/node_modules/openclaw/dist/monitor-*.js \
         /usr/local/lib/node_modules/openclaw/dist/monitor-*.js \
         /opt/homebrew/lib/node_modules/openclaw/dist/monitor-*.js; do
  [ -f "$f" ] || continue
  if grep -q 'maybeCreateDynamicAgent\|feishu: creating dynamic agent' "$f" 2>/dev/null; then
    echo "▼ $(basename "$f")"
    grep -n -B 2 -A 30 'creating dynamic agent\|maybeCreateDynamicAgent' "$f" 2>/dev/null | head -45
    echo
  fi
done

echo "─── [3] what mkdir-style call does it use ───"
for f in /usr/lib/node_modules/openclaw/dist/monitor-*.js \
         /usr/local/lib/node_modules/openclaw/dist/monitor-*.js \
         /opt/homebrew/lib/node_modules/openclaw/dist/monitor-*.js; do
  [ -f "$f" ] || continue
  grep -nE 'mkdir|makedirs|fsSync|fs\.cp|fs\.copy|copyFile|copyRecursive' "$f" 2>/dev/null | head -10 | sed "s|^|  $(basename $f):|"
done | sort -u | head -20

echo
echo "─── [4] openclaw version ───"
npm list -g openclaw 2>/dev/null | head -3

echo
echo "─── [5] log location ───"
find /tmp/openclaw "$HOME/.openclaw" -name "*.log" 2>/dev/null | head -5
journalctl --user -u openclaw-gateway --no-pager 2>&1 | tail -3
