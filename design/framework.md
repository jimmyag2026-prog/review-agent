# review_agent — 整体框架设计（v0，待确认）

日期：2026-04-20

## 一句话定位

> **上级的审阅代理**。替上级按其标准审下级会前汇报材料，循环推到"签字即用"状态；不能 close 的项整理成 open items 留给会议讨论。

差异化：市面上的 pre-meeting AI 基本都是 "给 receiver 做 pre-read"。review_agent 反向——**替 receiver 把 briefer 训练到位**。理论原型是 1942 年美军的 Completed Staff Work (CSW) 原则，目前没人把它 AI 化。

## 三角色模型

```
┌──────────────┐  review_criteria   ┌──────────────────┐
│  上级 (Boss) │ ─────────────────> │  review_agent    │
│  定义标准    │                    │  (独立 context)   │
└──────────────┘                    └─────────┬────────┘
                                              │ structured feedback
                                              v
┌──────────────┐   draft   ┌──────────────────────────┐
│ 下级(Briefer)│ ────────> │  迭代循环 ≤N 轮           │
│ hermes agent │ <──────── │  直到 gate pass 或升级    │
└──────────────┘  revised  └──────────────────────────┘
                                              │
                                              v
                                    briefing.md + open_items.md
```

### 角色职责

| 角色 | 本次由谁扮 | 做什么 |
|---|---|---|
| 上级 (Boss) | 用户本人 | 一次性写 `boss_profile.md`；每次会议前写 `meeting_context.md` |
| 下级 (Briefer) | hermes 主 agent | 起草 `draft.md`；invoke `/review-agent`；按反馈迭代 |
| 审阅代理 (Reviewer) | `review-agent` skill，在 fork 的 subagent context 中运行 | 按七轴检查 + 红队 + 出结构化反馈 + 判定 gate |

**关键**：reviewer 独立 context，不看主会话历史。这是 devil's advocate 架构的必要条件——防止顺着下级之前的话说。

## 输入（下级 invoke 时传）

必需：
- `$0` = draft 文件路径
- `$1` = boss_profile 文件路径

可选（通过 skill 内部寻址或 `$2+`）：
- `meeting_context.md` — 本次会议主题、参会人、期望决策
- `review_criteria.md` — 本次 brief 的特殊门槛（覆盖或扩展 boss_profile）
- `prior_briefings/` — 此前同主题的 brief，用于一致性检查
- `external_refs/` — 外部信息锚（行业报告、竞品、数据）

## 七轴 Review Checklist

合成 CSW + BLUF + Staff Study + Policy Memo + Red Team：

| 轴 | 通过标准 | 失败处理 |
|---|---|---|
| **1. Ask Clarity (BLUF)** | 前 3 行能读出：要什么决策 / 批准 / 资源 / 行动 | BLOCKER：重写开头 |
| **2. Completeness** | 列出至少 2 个 alternatives + 推荐 + 推荐理由 | BLOCKER：补 alternatives |
| **3. Evidence Freshness** | 数据有来源+时间；内部数据 + 外部锚点都有 | IMPROVEMENT：标记陈旧 |
| **4. Explicit Assumptions** | 显式列出 3–5 条关键假设；每条注明"如不成立会怎样" | BLOCKER：补假设段 |
| **5. Red Team / Counterargs** | 最强反方立场 + fallback position 被写出 | BLOCKER：补红队段 |
| **6. Stakeholder Reality** | 关联方（团队、客户、投资方、监管）的真实立场，不是想象 | IMPROVEMENT：点明缺失视角 |
| **7. Decision Readiness (CSW gate)** | 上级只需 yes/no；不留后续给上级做的功课 | BLOCKER：重拟 ask |

每条 finding 必须：
- 标 tag：`BLOCKER` / `IMPROVEMENT` / `NICE-TO-HAVE`
- 给**具体修改建议**（不是"需要更完整"这种废话）
- 引用 draft 原文 line / 段落

## 迭代协议

- 默认最多 N=3 轮。
- 每轮只能 close 已有 finding 或新增 BLOCKER（如果新改动带来新问题）。
- **不能无限要求加内容**——reviewer 若提出新 IMPROVEMENT 但已满足 gate 上限，自动降级为 NICE-TO-HAVE 不阻塞发布。
- 若 N 轮后仍有 BLOCKER，且是"确实没信息可补"型——自动升级为 **open item**，进 `open_items.md`。

## 最终交付物

### briefing.md（签字即用的 brief）
标准结构（遵循 Staff Study + BLUF）：
1. BLUF（3 行以内）
2. Background（≤1 段）
3. Key Assumptions（显式列表）
4. Options（≥2 个 + 比较）
5. Recommendation + Rationale
6. Risks & Counterarguments
7. Fallback
8. Ask（上级需要做的具体动作）

### open_items.md（会议真正要讨论的）
每条 open item：
- 事项陈述
- 为什么不能在会前定（没信息 / 需要上级判断 / 需要 alignment）
- 推荐讨论框架（"如果上级倾向 A，则…；倾向 B，则…"）

### review_trail.jsonl（可选审计日志）
每轮：findings、改动 diff 摘要、gate 结果。

## 与市面 agent 的兼容

- **Claude Code**：`~/.claude/skills/review-agent/`
- **Hermes**：`~/.hermes/skills/productivity/review-agent/`
- **Cursor / Cline**：把 SKILL.md 正文 + checklist 当 system prompt 注入
- **OpenAI Custom GPT / Agents SDK**：把 SKILL.md 正文粘到 instructions，references/ 挂 File Search
- **通用兼容约束**：
  - 只依赖 Read / Write / Bash 三种通用工具
  - 不绑定特定 MCP / tool
  - 所有路径用 `${CLAUDE_SKILL_DIR}` 或相对传参
  - 无外部 API 调用（纯 prompt + 本地文件）

## 退出条件（gate 判定）

```
GATE PASS ⇔ 七轴全部通过 OR
            (BLOCKER 已全 close) AND
            (剩余 unresolvable 项已全部进 open_items.md)
```

## UX 流程（hermes 本地）

**一次性设置**（用户本人）：
```bash
# 在 hermes 里首次运行
/review-agent init
# 交互生成 ~/.hermes/workspace/review/boss_profile.md
```

**每次汇报前**（用户 / hermes）：
```
用户: memoirist 发布方案草稿在 ~/draft.md，帮我 review 一下
hermes: /review-agent ~/draft.md ~/.hermes/workspace/review/boss_profile.md

[review-agent 在 fork 的 context 里]
→ 读 draft + profile
→ 七轴检查
→ 生成 findings list
→ 返回主会话

hermes: [把 findings 展示给用户]

用户: 好，按建议改
hermes: [改 draft] → /review-agent 再来一轮

...直到 gate pass...

最终输出:
  ~/draft.reviewed.md      (= briefing.md)
  ~/draft.open-items.md
```

## 开放设计决策（需用户确认）

1. **触发方式**：自动 invoke（hermes 看到"汇报/brief/review"就建议调用）还是**只接受显式 `/review-agent`**？
   - 建议显式：不希望顺手的对话都被 review 打断。对应 `disable-model-invocation: true`。

2. **reviewer 的模型**：跟 hermes 主 model 一样，还是**指定更便宜的 aux 模型**（省成本）/ **指定 Opus**（最强批判）？
   - 建议 Opus/Sonnet 4.7 等顶级批判模型——review 质量是这个 skill 的全部价值。

3. **iteration 轮数**：硬上限 3 轮？还是"直到 gate pass 或用户喊停"？
   - 建议硬上限 3，否则容易陷入"再改一点更好"的 loop。

4. **是否需要 boss_profile 的交互式向导**？
   - 建议 v0 提供模板文件，用户手填——交互向导放 v1。

5. **open_items 的粒度**：列出即可，还是 review_agent 再给**推荐的会议讨论框架**（"如 A 则…，如 B 则…"）？
   - 建议后者——这是减少上级开会负担的关键杠杆。

6. **审计日志**：默认开还是默认关？
   - 建议默认关（噪音大）；`--audit` flag 或 `AUDIT=1` env 打开。

7. **Skill 名字**：`review-agent` / `review` / `csw` / `pre-meeting-review` / 其他？
   - 建议 `review-agent`（和你现在用的术语一致）。注意 Claude Code 已有 built-in `/review`（PR review），所以不能叫 `review` 会冲突。
