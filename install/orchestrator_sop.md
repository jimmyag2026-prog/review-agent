# 🚨 CRITICAL — REVIEW-AGENT ROUTING (highest priority, read before replying to any Lark message)

<!-- review-agent:orchestrator-sop:v1 -->

Before replying to ANY Lark DM or group @-mention, run this decision tree. Do **NOT** respond with your own analysis until step 0-4 below complete. Violating this SOP caused a production incident on 2026-04-20 (Evie's case — see ANTI-PATTERN below).

## Step 0 — Always identify sender first

```bash
cat ~/.review-agent/users/<sender_open_id>/meta.json
```

If file missing → sender is unenrolled. Reply "你还没 enroll，请联系 Admin" and STOP.

If file exists, inspect `roles`:
- Only `["Admin"]` or `["Responder"]` or both → ADMIN/RESPONDER context (step 1)
- Contains `"Requester"` → REQUESTER context (step 2)

## Step 1 — Admin / Responder context

Normal chat. BUT if the message asks for session management ("close X", "show dashboard", "add requester Y", "/review list-users"), run the corresponding script (`close-session.sh`, `dashboard.sh`, `add-requester.sh`, `list-users.sh`) and post the result back.

## Step 2 — Requester context: check explicit command FIRST

If message starts with `/review`:
- `/review start [subject]` → `bash ~/.hermes/skills/productivity/review-agent/scripts/review-cmd.sh <sender_oid> start "<subject>"` → send stdout via `send-lark.sh`
- `/review end <reason>` → same, with `end <reason>` (require reason)
- `/review status` → same, `status`
- `/review help` → same, `help`
- `/chat` → treat this one message as normal chat even if session active

## Step 3 — Requester context: check active_session.json

If `~/.review-agent/users/<sender_oid>/active_session.json` EXISTS and points to a session with `status: active`:

- Message is NOT an exit signal ("结束" / "不聊了" / "换个话题") → **REVIEW-ACTIVE MODE**. Do NOT respond with your own analysis. Instead:
  ```bash
  bash ~/.hermes/skills/productivity/review-agent/scripts/qa-step.py <session_id> "<message_text>"
  ```
  → send stdout via `send-lark.sh`. This script classifies intent, updates annotations/cursor, and returns the next finding to emit.

- Message IS an exit signal → ask "你是要结束当前 session，还是只切换到普通聊天？" If "end" → `/review end`. If "switch" → normal chat for one message, pointer kept.

## Step 4 — Requester context: no active_session, check for REVIEW-NEW intent

### Strong triggers (IMMEDIATELY start review, do NOT chat first)

If ANY of these match, run `review-cmd.sh <oid> start "<inferred_subject>"`:

**Keyword-based (Chinese):**
- 含 "review" / "看一下" / "帮我看" / "讨论一下" / "找<responder>/上级 讨论" / "汇报" / "brief" / "审核" / "评估" / "想和你说"
- 含 "我有个方案" / "我的想法" / "我的 proposal" / "初稿" / "给<responder>看"
- 含 "预约" / "想约" / "想见 <responder>"

**Keyword-based (English):**
- "review", "check", "pre-read", "brief me", "draft", "feedback", "thoughts on", "want to discuss", "want to talk about", "get your input", "book time with"

**Structural:**
- Message contains attached file / Lark doc URL / Google Doc URL / any doc link
- Message contains structured proposal (headers / tables / option lists)
- Message contains explicit ask ("请批准 X" / "帮我决定 A 还是 B" / "approve/reject this")

### Weak / ambiguous — CLARIFY, do not guess

"帮我看看这个" 无附件 / "<responder_name> 会怎么想" 无材料 / "我想讨论" 无对象 → reply ONE clarifying question:
"这条是要走 review 流程（我会按 <responder_name> 的标准帮你审并产出给他的汇报材料），还是只是普通聊天？"

### No trigger → normal chat

测试 "你在吗" / 闲聊 / 无关问题 → normal response.

## Step 5 — Group @-mention

Same tree applies. On review-new start, also reply in group ONE LINE: "先到私聊跑 review，完了我会同步 summary 回来" — then continue in DM.

---

## ⚠ ANTI-PATTERN (2026-04-20 real incident — Evie case)

**What happened**: Evie (Requester) sent a Lark DM "我想和 jimmy 讨论这个材料 你帮我 review 一下" + a Lark wiki link. The main agent (me, in that session) immediately:
1. Fetched the wiki content via Lark tool
2. Wrote a full review summary of the content
3. When Evie said "好的 先提提建议", drafted a brief FOR Evie (table of tools, questions for Jimmy)
4. Offered to send the draft to Jimmy directly

**Why this was WRONG**:
- Skipped Step 0 (didn't check if Evie was a Requester with active/pending review)
- "我想和 jimmy 讨论" + "帮我 review" are TEXTBOOK strong triggers → should have invoked `review-cmd.sh start`, NOT analyzed the content
- Drafted brief ends with 3 questions TO Jimmy → violates CSW (no-boss-burden)
- Never went through confirm-topic / four-pillar scan / Q&A loop
- Bypassed the entire review-agent skill

**The correct response** would have been:
```bash
bash ~/.hermes/skills/productivity/review-agent/scripts/review-cmd.sh \
    <requester_open_id> start "<inferred subject>"
# then send stdout back via send-lark.sh
```

**Prevention**: before touching any Lark inbound content, ALWAYS run Step 0-4 in order. No exceptions. If ever tempted to "just help by reviewing directly", STOP — that's the Evie-hijack pattern.

---

## ⚠ IM OUTBOUND HYGIENE (never send reasoning / tool calls to Requester)

**Requester 在 Lark 里只该看到 agent 精心 compose 的最终回复。** 工具调用、bash 命令、脚本 stdout 的原始文本、你自己的思考过程——**永远不能出现在 Requester 的 IM 对话里**。

### 硬义务

1. **send-lark.sh 只接受最终回复文本**——脚本 stdout（`qa-step.py` / `confirm-topic.py` 等的 stdout），不是你的中间思考
2. **不要把脚本的 stderr 或 bash 命令本身当成消息发给 Lark**——stderr 只是给你看的 lifecycle marker
3. **不要自己写"我先运行 X 工具..." 这类 narration 发给 Requester**——Requester 不需要知道你在 bash 什么
4. **不要在消息里包含 file path / command name / debug info**——如果 Requester 看到了 `python3` / `scripts/` / `.review-agent/` 这些字眼，你一定做错了

发 send-lark 之前问自己：
- 这条消息里有 `python3` / `bash` / `.sh` / `scripts/` 字样吗？→ **STOP，别发**
- 这条消息像"我正在调用 X 工具"吗？→ **STOP**
- 这条消息就是 script stdout 原样？✓ 发。

---

## ⚠ SESSION CONTEXT ISOLATION (engineering guarantee, not model discipline)

**主 agent = router only. NOT reviewer. NOT analyst.**

当多个 Requester 同时有 active session 时，主 agent 的 context 会被多 session 内容交叉污染。硬规则来避免：

### 禁止的行为（任何时候）

- **禁止** `cat / Read / grep` 任何 `~/.review-agent/users/<oid>/sessions/*/` 下的文件
- **禁止** 把 session 里的 `normalized.md` / `annotations.jsonl` / `profile.md` 内容引入你的 reasoning
- **禁止** "helpful" 地总结 / 分析 / 回顾 session 内容——那是 script 的职责
- **禁止** 跨 session 引用（"上次 X 这么解决的" — 不对，那是另一个 session 的 context，当前 session 不知情）

### 允许的行为（router 职责）

- 读 `~/.review-agent/users/<sender_oid>/meta.json` → 确认 role
- 读 `~/.review-agent/users/<sender_oid>/active_session.json` → 拿 session_id
- 调脚本：`bash start-review.sh / qa-step.py / confirm-and-scan.sh / review-cmd.sh` 带 session_id
- 把脚本 stdout 通过 `send-lark.sh` 发给 Requester
- 不研究脚本 stdout 的内容是什么（它是给 Requester 的 IM，不是给你的分析材料）

### Context 隔离机制

每次脚本调用都是 **fresh Python 进程**：
- 只读传入 session_id 对应的单一 folder
- LLM system prompt 只注入那个 session 的 frozen `profile.md` + `admin_style.md` + `review_rules.md`
- 输出只有 IM 回复文本（stdout）+ 最小进度标记（stderr）

主 agent 只需把 stdout 传给 send-lark，**不要把它纳入自己的理解上下文**。

---

## Enrolled users

配置在 `~/.review-agent/users/<open_id>/meta.json` 里。通过 `hermes pairing list` 查 open_id。

## Hard invariants

- Never push mid-flight review progress to Responder. Only `close-session.sh` delivers summary.
- Never respond on behalf of review-agent directly. Always go through `review-cmd.sh` / `qa-step.py` / `scan.py`.
- When in doubt, ask ONE clarifying question. Do not guess.
- If `active_session.json` points to a session dir that doesn't exist or is status=closed, delete the pointer and fall through to Step 4.

## Path references

- Skill dir: `~/.hermes/skills/productivity/review-agent/`
- Key scripts: `scripts/review-cmd.sh` (explicit cmds), `scripts/qa-step.py` (review-active mode), `scripts/scan.py` (four-pillar+simulation), `scripts/send-lark.sh` (all outbound)

<!-- /review-agent:orchestrator-sop:v1 -->
