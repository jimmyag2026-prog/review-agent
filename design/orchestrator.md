# Orchestrator Design — Mode-aware routing

## Core insight

同一个 Requester 可能在不同**场景**里和 bot 交互：
- 提交汇报走 review 流程
- 随便聊天 / 问连接状态 / 测试 bot
- 临时请教个非决策问题

不能按"身份"一刀切说"Requester 发的所有消息都强制走 review"。要按**本次对话在哪个 scene** 来路由。

## 三种 scene

| Scene | 触发条件 | 路由到 | Example |
|---|---|---|---|
| **review-active** | Requester 有 `active_session.json` 指向一个 active 状态 session，且本条消息不是 exit 命令 | `review-agent` skill（接续当前 session）| 回 finding、发修订草稿 |
| **review-new** | 无 active session，但本条消息是 review intent（见下方信号）| `review-agent` skill（启新 session）| "想找 Jimmy 讨论 X"、附 brief 文件 |
| **normal** | 非 Requester；或是 Requester 但无 active session 且无 review intent | hermes main agent 常规回复 | "bot 你连着吗"、"帮我查个天气" |

## Orchestrator 决策树（hermes main agent 每条 Lark DM/群 @ 执行）

```
收到 Lark 消息
├── sender 是 Admin/Responder-only（无 Requester role）？
│   └── 执行管理命令 / 常规对话 → 结束
├── sender 是 Requester？
│   ├── 消息是显式 /review 命令？
│   │   ├── /review start [subject]  → 启 review_agent skill + new-session
│   │   ├── /review end [reason]     → 启 review_agent skill + close
│   │   ├── /review status           → 列 sessions（只这个 Requester 的）
│   │   ├── /chat                    → 本条按 normal
│   │   └── /review help             → 打印命令列表
│   ├── 有 active session？（读 users/<oid>/active_session.json）
│   │   ├── 本条消息是"exit 信号"（见下）？
│   │   │   └── 确认 → close session → 退出 review mode
│   │   └── 否则 → review-active：把消息喂给 review-agent skill
│   └── 无 active session
│       ├── 本条消息含 review intent 信号？
│       │   ├── 强信号 → review-new：启动 session
│       │   └── 弱信号/歧义 → 反问："这条是要走 review 流程，还是普通聊天？"
│       └── 无 review 信号 → normal
└── sender 未注册 → 礼貌告知 "你还没 enroll，请联系 Admin"
```

## Review intent 信号（强/弱）

**强信号**（直接进 review-new）：
- 附件 / 文档链接 + 任一关键词: "review", "讨论", "汇报", "brief", "让 Jimmy 看", "找上级", "批准"
- 显式 "/review start"
- "我想把 X 给 Jimmy 过一下"
- 明确的 ask 结构（"请 Jimmy 批准 ...", "我建议 X，需要 Jimmy 定"）

**弱信号 → 要反问**：
- "帮我看看这个" 无附件
- "jimmy 会怎么想" 无材料
- "这个方案" 无上下文

**非信号 → normal chat**：
- 测试类："bot 在吗"、"连接好了"
- 元问题："你能做什么"
- 完全无关的问题（天气、时间等）

## Exit 信号（review-active → normal 或 close）

- "结束"、"不聊这个了"、"换个话题"、"/review end"
- "我先不 review 了"
- 主动发不相关内容（agent 需判断；可先反问确认）

## 状态文件 `users/<oid>/active_session.json`

存在且指向 active session → Requester 处于 review-active mode。

```json
{
  "session_id": "20260420-213020-Tavily-API",
  "opened_at": "2026-04-20T21:30:00-07:00",
  "pointer_updated_at": "2026-04-20T21:35:03-07:00"
}
```

不存在或为 `null` → 无 active session。

**约束**：v0 一个 Requester 最多一个 active session。真要多个并发，先 close 前一个或 `/review switch` 明示切换（v1）。

## 为什么 Orchestrator = 主 agent，不是独立 sub-agent

mental model 上 Orchestrator 看起来像独立 agent，但在 hermes 架构里，最简实现就是**主 agent 加载一份路由 SOP**（通过 `~/.hermes/memories/MEMORY.md` 持久化）。

理由：
- 主 agent 本来就是 Lark DM 第一个接住消息的人，加一层独立 agent 多一次跳转
- 路由逻辑是几十行 markdown，不是重度 LLM 任务
- hermes skill `review-agent` 已经独立 context 处理 review 流；主 agent 只管"是不是把球传给它"
- 独立 sub-agent 方案（`context: fork` 的 orchestrator skill）留给 v1，如果 v0 证明主 agent 路由不稳再做

## 实现步骤

1. `new-session.sh`：创建 session 成功后，写 `users/<oid>/active_session.json`
2. `close-session.sh`：成功关闭后，删除或清空 `active_session.json`
3. 新增 `scripts/review-cmd.sh` 处理 `/review start/end/status/help` 四个显式命令
4. 在 `~/.hermes/memories/MEMORY.md` 加一条"Lark DM 路由规则"，把上面的决策树写成给 main agent 看的 SOP
5. `SKILL.md` 加一段说明主 agent 可以直接 invoke 本 skill，也可以通过显式命令触发
6. 测试：
   - Requester A 发"bot 在吗" → normal 回复
   - Requester A 发"/review start Tavily 选型" → 启 new session
   - Requester A 在 active session 里发"好的 按你说的改" → review-agent 接
   - Requester A 发"结束" → close 确认流程
   - Requester A 在 session 里突然发"顺便问今天天气" → 主 agent 反问"是 review 内容还是切回普通聊天"

## 和 context B'（群 @ 触发）的兼容

群里 @bot 时 Orchestrator 同样跑决策树：
- 无 active session + 有 review intent → 启 new session，回一句"先去 DM 跑 review"
- 有 active session → 一般不期望在群里继续 review；主 agent 反问"是要继续 DM 里那个 session 还是新的？"
- 无意图 → 群里短 ack（admin_style 允许的话）或沉默

## 风险与 fallback

- **风险**：模型误判 intent（把 review 当 chat 或反之）
  - Mitigation：ambiguous 就反问，不要自己决定
- **风险**：active_session pointer 和实际 session 状态漂移（比如文件手动删了）
  - Mitigation：orchestrator 每次先验证 session dir 还在 + status == active；否则清 pointer
- **风险**：Admin/Responder 也是 Requester（自己给自己 review）时矩阵冲突
  - v0 假设三角色独立；冲突时走 ambiguous 反问
