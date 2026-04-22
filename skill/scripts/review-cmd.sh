#!/bin/bash
# review-cmd.sh — handle explicit /review commands sent by a Requester via IM
# Called by the Orchestrator (hermes main agent) when it detects a /review ... prefix.
#
# Usage:
#   review-cmd.sh <sender_open_id> start [subject]
#   review-cmd.sh <sender_open_id> end   [reason]
#   review-cmd.sh <sender_open_id> status
#   review-cmd.sh <sender_open_id> help
#
# Emits a short status line to stdout — the orchestrator uses it to compose
# the IM reply to the sender.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${REVIEW_AGENT_ROOT:-$HOME/.review-agent}"

usage() {
  cat <<EOF >&2
Usage: $(basename "$0") <sender_open_id> <start|end|status|help> [args...]
EOF
  exit 1
}

if [ $# -lt 2 ]; then usage; fi

SENDER="$1"; shift
CMD="$1"; shift

UDIR="$ROOT/users/$SENDER"
if [ ! -d "$UDIR" ]; then
  echo "error: user $SENDER not enrolled" >&2
  exit 2
fi

# Verify Requester role
ROLE_OK=$(python3 -c "
import json
m = json.load(open('$UDIR/meta.json'))
print('yes' if 'Requester' in m.get('roles',[]) else 'no')
" 2>/dev/null || echo "no")
if [ "$ROLE_OK" != "yes" ]; then
  echo "error: sender is not a Requester" >&2
  exit 2
fi

POINTER="$UDIR/active_session.json"

case "$CMD" in
  start)
    SUBJECT="${1:-untitled}"
    # Check active session via python helper (avoids bash nounset + quoting hazards)
    set +u
    ACTIVE_CHECK=$(POINTER="$POINTER" UDIR="$UDIR" python3 -c '
import json, os, sys
p = os.environ["POINTER"]
u = os.environ["UDIR"]
if os.path.exists(p):
    try:
        sid = json.load(open(p)).get("session_id") or ""
    except Exception:
        sid = ""
    if sid and os.path.isdir(os.path.join(u,"sessions",sid)):
        print(f"ACTIVE:{sid}")
        sys.exit(0)
# no active → remove any stale pointer
if os.path.exists(p):
    os.remove(p)
print("NONE")
')
    set -u
    case "$ACTIVE_CHECK" in
      ACTIVE:*)
        echo "你已有一个活跃 session：${ACTIVE_CHECK#ACTIVE:}。v0 支持一次一个——先 /review end，或切换到新话题前手动 close。"
        exit 0
        ;;
    esac
    SID=$(bash "$SKILL_DIR/scripts/new-session.sh" "$SENDER" "$SUBJECT" | tail -1)
    echo "已开启 review session：$SID"
    echo "主题：$SUBJECT"
    echo "接下来把你要 review 的材料（文本 / 链接 / 文件）发过来。"
    ;;

  end)
    REASON="${1:-}"
    if [ ! -f "$POINTER" ]; then
      echo "你当前没有活跃 review session。"
      exit 0
    fi
    SID=$(POINTER="$POINTER" python3 -c 'import json,os; print(json.load(open(os.environ["POINTER"]))["session_id"])')
    if [ -z "$REASON" ]; then
      echo "结束前请给一句理由（便于写进 summary），例：'/review end 材料不齐我改好再来 / 这次不做了'"
      exit 0
    fi
    bash "$SKILL_DIR/scripts/close-session.sh" "$SID" --termination forced_by_briefer --reason "$REASON" 2>&1 | tail -3
    echo "session $SID 已结束，summary 已送达。"
    ;;

  status)
    UDIR="$UDIR" POINTER="$POINTER" python3 <<'PYEOF'
import json, os
udir = os.environ["UDIR"]
pointer = os.environ["POINTER"]
if os.path.exists(pointer):
    p = json.load(open(pointer))
    sid = p.get("session_id")
    sd = os.path.join(udir, "sessions", sid)
    meta = json.load(open(os.path.join(sd,"meta.json"))) if os.path.isdir(sd) else {}
    print(f"活跃 session: {sid}")
    print(f"  主题: {meta.get('subject','?')}")
    print(f"  轮次: {meta.get('round',0)}")
    print(f"  状态: {meta.get('status','?')}")
    print(f"  创建: {meta.get('created_at','?')}")
else:
    print("当前没有活跃 review session。")
sdir = os.path.join(udir,"sessions")
if os.path.isdir(sdir):
    closed = []
    for s in sorted(os.listdir(sdir), reverse=True):
        mp = os.path.join(sdir, s, "meta.json")
        if os.path.exists(mp):
            try:
                m = json.load(open(mp))
                if m.get("status") == "closed":
                    closed.append((m.get("session_id"), m.get("subject",""), m.get("closed_at","")))
            except: pass
    if closed:
        print()
        print("最近关闭的 session:")
        for sid, subj, ts in closed[:5]:
            print(f"  {sid}  {subj[:40]}  closed {ts}")
PYEOF
    ;;

  help|*)
    cat <<EOF
可用命令：
  /review start <主题>     开始新的 review 对话
  /review end <理由>       结束当前 review（理由会记入 summary）
  /review status           查看当前 session 状态
  /review help             看这个说明
普通聊天直接说话即可，不用命令。如果你发的内容看起来是要 review，agent 会询问确认。
EOF
    ;;
esac
