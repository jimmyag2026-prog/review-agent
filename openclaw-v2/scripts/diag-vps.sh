#!/bin/bash
# review-agent v2.1.2 VPS 一键诊断 — 输出 5 行，发回给 dev 排查
# 用同一个跑 install.sh 的用户登录 VPS 然后 bash 这个脚本

echo "─── review-agent VPS diag ───"

# [1] 哪个 monitor-*.js 被 patch 了
echo "[1] patcher marker:"
for f in /usr/lib/node_modules/openclaw/dist/monitor-*.js \
         /usr/local/lib/node_modules/openclaw/dist/monitor-*.js \
         /opt/homebrew/lib/node_modules/openclaw/dist/monitor-*.js \
         "$(npm root -g 2>/dev/null)/openclaw/dist/monitor-*.js"; do
  for ff in $f; do
    [ -f "$ff" ] || continue
    M=$(grep -c 'review-agent local patch' "$ff" 2>/dev/null)
    A=$(grep -c 'mkdir(agentDir' "$ff" 2>/dev/null)
    echo "  $ff  marker=$M  anchor=$A"
  done
done

# [2] template 在 install user 的 HOME 里吗
echo "[2] template at \$HOME/.openclaw/workspace/templates/review-agent:"
if [ -d "$HOME/.openclaw/workspace/templates/review-agent" ]; then
  echo "  YES — has $(ls $HOME/.openclaw/workspace/templates/review-agent 2>/dev/null | wc -l | tr -d ' ') files"
else
  echo "  ✗ NOT FOUND under $HOME"
fi

# [3] install user vs gateway service user 是不是同一个
GW=$(pgrep -f openclaw-gateway 2>/dev/null | head -1)
GU=$(ps -p "$GW" -o user= 2>/dev/null | tr -d ' ')
echo "[3] users:  installer=$(whoami)   gateway=${GU:-NOT-RUNNING}"

# [4] gateway log 有 review-agent: seeded 吗
echo "[4] last 5 review-agent log entries:"
LOG="$HOME/.openclaw/logs/gateway.log"
if [ -f "$LOG" ]; then
  grep -E 'review-agent|creating dynamic agent' "$LOG" 2>/dev/null | tail -5 | sed 's/^/  /'
else
  echo "  ✗ no log at $LOG"
fi

# [5] 最新 peer workspace 里的 SOUL.md 是 review-coach 还是 memorist
WS=$(ls -td "$HOME"/.openclaw/workspace-feishu-* 2>/dev/null | head -1)
if [ -n "$WS" ]; then
  echo "[5] latest peer SOUL.md ($(basename $WS)):"
  head -3 "$WS/SOUL.md" 2>/dev/null | sed 's/^/  /'
  if grep -qE 'I just came online|just woke up|becoming someone' "$WS/SOUL.md" 2>/dev/null; then
    echo "  → MEMORIST default (patch 没生效或 template 没拷进去)"
  elif grep -qE 'Review Agent|review-coach|挑刺' "$WS/SOUL.md" 2>/dev/null; then
    echo "  → review-coach OK"
  fi
else
  echo "[5] no peer workspace yet (没人 DM 过 bot)"
fi

echo "─── done ───"
