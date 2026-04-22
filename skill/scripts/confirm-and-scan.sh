#!/bin/bash
# confirm-and-scan.sh — after Requester confirms subject, run the scan + emit first finding
#
# Orchestrator calls this when:
#   - session is in status "awaiting_subject_confirmation"
#   - Requester replied with (a/b/c/d) or specific subject description
#
# Steps:
#   1. Record the Requester's confirmation in conversation.jsonl + session meta
#   2. Run scan.py (four-pillar + responder simulation)
#   3. Update session status → "qa_active"
#   4. Compose first finding message and emit via Lark (or print for dry-run)
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${REVIEW_AGENT_ROOT:-$HOME/.review-agent}"

usage() {
  echo "Usage: $(basename "$0") <session_id> \"<requester confirmation text>\" [--no-send]" >&2
  exit 1
}

if [ $# -lt 2 ]; then usage; fi

SID="$1"
CONFIRM_TEXT="$2"
shift 2
SEND=1
while [ $# -gt 0 ]; do
  case "$1" in
    --no-send) SEND=0; shift ;;
    *) usage ;;
  esac
done

# Locate session
SDIR=""
REQ_OID=""
for p in "$ROOT/users"/*/sessions/"$SID"; do
  if [ -d "$p" ]; then
    SDIR="$p"
    REQ_OID=$(basename "$(dirname "$(dirname "$p")")")
    break
  fi
done
if [ -z "$SDIR" ]; then
  echo "error: session $SID not found" >&2
  exit 2
fi

# Record confirmation
python3 <<PYEOF
import json
from datetime import datetime
entry = {
    "ts": datetime.now().astimezone().isoformat(timespec="seconds"),
    "role": "requester",
    "source": "lark_dm",
    "text": """$CONFIRM_TEXT""",
    "stage": "subject_confirmation_reply",
}
with open("$SDIR/conversation.jsonl", "a") as f:
    f.write(json.dumps(entry, ensure_ascii=False) + "\n")
# Update meta
m = json.load(open("$SDIR/meta.json"))
m["confirmed_subject"] = """$CONFIRM_TEXT"""
m["status"] = "scanning"
json.dump(m, open("$SDIR/meta.json", "w"), indent=2, ensure_ascii=False)
PYEOF

# Run scan (suppress internals to prevent session content leaking to main agent)
python3 "$SKILL_DIR/scripts/scan.py" "$SDIR" >/dev/null 2>&1 \
  && echo "[confirm-and-scan] scan_completed" >&2 \
  || { echo "[confirm-and-scan] scan_failed" >&2; exit 3; }

# Auto-scope: pick top 3 (BLOCKER first, then IMPROVEMENT, then NICE), defer rest.
# Transition directly to qa_active and emit first finding.
python3 <<'PYEOF'
import json, os, sys
sd = "$SDIR"
# This is inside shell heredoc — ensure $SDIR is expanded; re-do via env var
sd = os.environ.get("SDIR_REAL", sd)
PYEOF

SDIR_REAL="$SDIR" python3 <<PYEOF
import json, os, sys
sd = os.environ["SDIR_REAL"]
anns_path = os.path.join(sd, "annotations.jsonl")
anns = [json.loads(l) for l in open(anns_path) if l.strip()]

if not anns:
    # No findings — skip Q&A entirely
    first_msg = "扫描完成但没挑出 finding — 材料已经相当 decision-ready。我直接产 summary 给你核对。"
    import json as _j
    m = _j.load(open(os.path.join(sd, "meta.json")))
    m["status"] = "ready_for_close"
    _j.dump(m, open(os.path.join(sd, "meta.json"), "w"), indent=2, ensure_ascii=False)
    with open(os.path.join(sd, "_first_msg.tmp"), "w") as f:
        f.write(first_msg)
    sys.exit(0)

total = len(anns)
blockers = [a for a in anns if a.get("severity") == "BLOCKER"]
improvements = [a for a in anns if a.get("severity") == "IMPROVEMENT"]
nice = [a for a in anns if a.get("severity") == "NICE-TO-HAVE"]
n_b = len(blockers); n_i = len(improvements); n_n = len(nice)
ordered = blockers + improvements + nice

# Auto-pick top 3 (severity priority)
K = min(3, total)
selected = ordered[:K]
selected_ids = [a["id"] for a in selected]
selected_set = set(selected_ids)

# Mark non-selected as deferred_by_scope
for a in anns:
    if a["id"] not in selected_set:
        a["status"] = "deferred_by_scope"
        a["scope_note"] = "below top-3 severity cutoff; can be covered later on request"

# Rewrite annotations
with open(anns_path, "w") as f:
    for a in anns:
        f.write(json.dumps(a, ensure_ascii=False) + "\n")

# Set cursor
cursor = {
    "current_id": selected_ids[0],
    "pending": selected_ids[1:],
    "done": [],
}
with open(os.path.join(sd, "cursor.json"), "w") as f:
    json.dump(cursor, f, indent=2, ensure_ascii=False)

# Transition meta
import datetime
m = json.load(open(os.path.join(sd, "meta.json")))
m["status"] = "qa_active"
m["scope_selected"] = selected_ids
m["last_activity_at"] = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
json.dump(m, open(os.path.join(sd, "meta.json"), "w"), indent=2, ensure_ascii=False)

# Compose first-finding message with preamble
first = selected[0]
pillar = first.get("pillar", "?")
sev = first.get("severity", "?")
issue_text = first.get("simulated_question") or first.get("issue", "")
suggest = first.get("suggest", "")
is_sim = first.get("source") == "responder_simulation"
remaining = total - K

options = """
(a) accept · 按建议改
(b) reject · 不同意（说一下理由）
(c) modify · 我要改成另外的版本 xxx
(p) pass · 跳过这条
(custom) 其他——直接打字"""

preamble = f"扫完了，共挑出 **{total} 条** 问题（🚩 {n_b} BLOCKER · ⚠ {n_i} IMPROVEMENT · • {n_n} NICE）。我先带你过最关键的 **{K} 条**" + (f"——剩下 {remaining} 条等这 {K} 条走完后，如果你还有时间，我们可以继续讨论。" if remaining > 0 else "。") + "\n\n一条条来：\n"

src_tag = "（Responder 视角模拟的追问）" if is_sim else ""

if is_sim:
    body = f"""{preamble}
**第 1 / {K} 条 · {pillar} · {sev}**{src_tag}

{issue_text}
{options}"""
else:
    body = f"""{preamble}
**第 1 / {K} 条 · {pillar} · {sev}**

{issue_text}

建议：{suggest}
{options}"""

with open(os.path.join(sd, "_first_msg.tmp"), "w") as f:
    f.write(body)
PYEOF

FIRST_MSG=$(cat "$SDIR/_first_msg.tmp")
rm -f "$SDIR/_first_msg.tmp"

# Log outbound + send
python3 <<PYEOF
import json
from datetime import datetime
cursor = json.load(open("$SDIR/cursor.json"))
entry = {
    "ts": datetime.now().astimezone().isoformat(timespec="seconds"),
    "role": "reviewer",
    "source": "lark_dm_out",
    "finding_id": cursor.get("current_id"),
    "stage": "first_finding_after_confirmation",
    "text": """$FIRST_MSG""",
}
with open("$SDIR/conversation.jsonl", "a") as f:
    f.write(json.dumps(entry, ensure_ascii=False) + "\n")
PYEOF

if [ $SEND -eq 1 ]; then
  bash "$SKILL_DIR/scripts/send-lark.sh" --open-id "$REQ_OID" --text "$FIRST_MSG" >/dev/null 2>&1 \
    && echo "[confirm-and-scan] first_finding_sent" >&2 \
    || echo "[confirm-and-scan] first_finding_send_failed" >&2
else
  # Dry-run: stdout the message (this is not session internal — it's what would be sent)
  echo "$FIRST_MSG"
fi

echo "$SID"
