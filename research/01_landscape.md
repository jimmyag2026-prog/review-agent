# 调研：上级审阅下级汇报材料——方法论与工具

日期：2026-04-20

## 1. 先行方法论（非 AI 年代但对 agent 仍最有指导意义）

### 1.1 Completed Staff Work (CSW) — 1942, 美国陆军
"对一个问题的研究与解决方案的呈现，要达到首长只需要指示批准或不批准的程度。"

核心原则（翻译+改写）：
- 不要用长篇解释和备忘录去打扰首长；要递交已成形的方案。
- 不要为了自保把事情拆成一堆问题让首长定——那是在把决策负担推回去。
- 草稿可以粗糙，但**每一项**必须齐全。粗糙 ≠ 半成品。
- 最终文件只需一个动作：签字。
- 可以让首长不开心（因为推敲要下级下功夫），但不能让首长替你做决策。

**这是 review_agent 最直接的理论原型。**

### 1.2 Amazon 六页备忘录 (6-Pager) — 2004, Bezos
- 会前 20–30 分钟全场静读。
- 叙述式 memo，禁用 PPT。
- 强迫发起人先把话说清楚，会议时间全部用于决策不是讲解。
- **启示**：review_agent 的合格品是"能被静读 20 分钟就看懂并能讨论"的材料，不是一堆 bullet。

### 1.3 BLUF (Bottom Line Up Front) — 美军通信规范
- 头三句话：情况 + 冲突 + 建议方案。
- 其余内容是展开和支撑。
- **启示**：审阅第一关就是验 BLUF——前 3 行看不懂要什么的 brief，直接打回。

### 1.4 Policy Memo (Shorenstein / USC 公共政策教材标准结构)
Header → Executive Summary → Background → Analysis → Options → Recommendation → Counterarguments → Fallback positions → Conclusion

比 CSW 多两条可吸收的：
- **Counterarguments** 必须明确写出最强反对立场。
- **Fallback positions** 在首选方案不可得时的备选。

### 1.5 Staff Study 十段式（Army 现行版）
Problem → Recommendation → Background → Assumptions → Courses of Action → Comparison → Conclusion

比 policy memo 多的：**显式 Assumptions 段**——讨论哪些假设若不成立则结论崩。

## 2. AI 时代的同类工具

### 2.1 Pre-Meeting Briefing AI (read.ai, Fellow, Monday Briefing, Similarweb Meeting Prep)
- **方向**：多数是"帮参会者做 pre-read"——从 calendar、email、CRM 拉数据生成 brief 给 receiver。
- **缺口**：几乎没有工具在做"上级视角审阅下级材料"。当前市场的重心是 **给 receiver 喂信息**，不是**替 receiver 把 briefer 训练到位**。
- **review_agent 的差异化定位**：top-down 质量门，而不是 bottom-up 信息聚合。

### 2.2 Devil's Advocate / Red Team Prompt Pattern
- 模式："Now play devil's advocate and critique your own answer."
- 作用：打破模型的默认 agreeable 模式，逼它从反方重新扫一遍。
- 在 multi-agent 架构里通常作为独立 reviewer agent 出现（Microsoft AI Red Teaming Agent / promptfoo）。
- **启示**：review_agent 不能是同一个 agent 自评，必须作为独立人格 + 独立 context。

### 2.3 Anthropic Agent Skills (SKILL.md) — 2025-12 开源标准
- 一个目录 + SKILL.md + 可选 references/scripts。
- YAML frontmatter：name, description, allowed-tools, disable-model-invocation。
- `context: fork` 可以把 skill 跑在隔离 subagent 里，带独立 context——**正好是 reviewer 独立人格的技术实现**。
- 三级渐进载入：metadata（always）→ SKILL.md 正文（invoke 时）→ bundled files（按需）。
- 同一 SKILL.md 文件同时被 Claude Code / Hermes / 符合 agentskills.io 的其他 agent 支持。

## 3. 落地 review_agent 可借鉴的组合

| 来源 | 吸收成 |
|---|---|
| CSW 签字即用原则 | 验收 gate：boss 只需 yes/no |
| BLUF 前三行 | 第 1 个 review 轴 |
| Staff Study Assumptions | 第 4 个 review 轴（显式假设）|
| Policy memo Counterargs + Fallbacks | 第 5 个 review 轴（红队）|
| 6-Pager 静读标准 | 输出格式要求：narrative，可 20 分钟独立读懂 |
| Devil's advocate 独立 context | `context: fork` 跑 reviewer 子 agent |
| Agent Skills 标准 | 产物直接 `~/.claude/skills/`、`~/.hermes/skills/` 通用 |

## 4. 市场空白与机会

- 没有主流产品做 "boss's reviewer proxy"（替上级审下级）。
- 大部分 AI meeting tool 解决 receiver 的 attention 问题，不解决 briefer 的 quality 问题。
- CSW 是 1942 年的方法，至今被军队和咨询行业当 gold standard 但在 AI 产品里几乎没人实现——**值得把 CSW 做成 skill 并把它做对**。

## 来源

- [Completed Staff Work - Wikipedia](https://en.wikipedia.org/wiki/Completed_staff_work)
- [The Doctrine of Completed Staff Work - govleaders.org](https://govleaders.org/completed-staff-work.php)
- [Revisiting the Doctrine of Completed Staff Work - Technical Assent](https://www.technicalassent.com/insight/revisiting-the-doctrine-of-completed-staff-work)
- [Amazon 6-pager template](https://www.sixpagermemo.com/blog/amazon-six-pager-template)
- [BLUF Wikipedia](https://en.wikipedia.org/wiki/BLUF_(communication))
- [BLUF - The Persimmon Group](https://thepersimmongroup.com/bluf-how-these-4-letters-simplify-communication/)
- [Writing a Policy Memo - USC Libraries](https://libguides.usc.edu/writingguide/assignments/policymemo)
- [Devil's Advocate prompt](https://docsbot.ai/prompts/analysis/devils-advocate-agent)
- [Multi-agent Devil's Advocate Architecture - Medium](https://medium.com/@jsmith0475/the-devils-advocate-architecture-how-multi-agent-ai-systems-mirror-human-decision-making-9c9e6beb09da)
- [Microsoft AI Red Teaming Agent](https://learn.microsoft.com/en-us/azure/foundry/concepts/ai-red-teaming-agent)
- [Anthropic Skills spec](https://code.claude.com/docs/en/skills)
- [agentskills.io open standard](https://agentskills.io)
- [Fellow / read.ai / Monday Briefing 行业综述 - read.ai](https://www.read.ai/articles/best-ai-meeting-assistants)
