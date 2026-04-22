# review_agent — 整体框架设计 v1（按你的反馈重写）

日期：2026-04-20

## 新的核心架构：IM + 异步子任务 session

不再是"下级 agent 本地调 slash command"。改成：
- Review agent 挂在 **IM 通道**（Lark / Telegram / WeChat 等）
- 下级通过 IM 把初稿/讨论点发给 review agent（不论美观与否）
- Review agent 启动**子任务 session**（独立 workspace，按 peer 隔离）
- 多轮**异步**对话：review agent 以**提问 / 不同视角 / 追问**为主
- 下级根据反馈修改并最终**自行定稿**
- 子任务结束后，review agent 产出一个 summary 给上级

## 借鉴 memoirist-skill 的双层结构

和 memoirist 同构——这是已经验证过的 openclaw 模式：

```
review-agent-manager (给用户/上级用的 skill)
  管理: 挂载 review agent 到 IM peer / 列表 / 卸载

review-agent (每个下级对应一个 narrator 风格的 per-peer agent)
  workspace template: references/template/AGENTS.md, SOUL.md, USER.md, HEARTBEAT.md
  每个下级有独立 workspace（对话历史、当前 session 文件都隔离）
```

## 流程 v1

```
T0  [一次性] 上级设置 boss_profile.md，定义审阅标准、偏好、pet peeves、决策风格
T1  [一次性] 上级用 /review-agent add <channel> <peer_id> 给某下级开通 review 通道
T2  下级通过 IM 发第一条消息（可以是草稿 / 语音 / 图片 / 一段想法）
T3  review-agent 启动该下级的子任务 session，读 boss_profile，吸收初稿
T4  review-agent 异步返回第一轮反馈：
     - 直接型 BLOCKER（ask 不清、完全没数据）——明确指出
     - Socratic 追问（"为什么选 A 不是 B？" "如果竞品先动怎么办？"）
     - 不同视角（客户 / 投资人 / 监管）
T5  下级 IM 回复 / 发新版本
T6  T4–T5 循环，每轮可 close 旧问题 / 开新问题 / 下级保留异议（dissent）
T7  下级说"结束" 或 review-agent 判定"无重大 gap 剩余" → 子任务归档
T8  产出：
     - (下级自行定稿的) 最终汇报材料
     - session archive: 完整对话 + dissent log
     - summary-for-boss.md：给上级的摘要（改了哪些、下级保留异议的点、剩余 open items）
```

## 上一版 vs 这一版关键差异

| 维度 | v0（作废）| v1（当前）|
|---|---|---|
| 触发 | 下级 CLI `/review-agent` | 下级 IM 发消息 |
| 对话模式 | 一次性 punch list 反馈 | 多轮异步 Socratic |
| 风格 | 打分型 critic | 提问型 coach（hybrid）|
| 定稿 | review-agent 输出 briefing.md | **下级自行定稿**（符合 CSW）|
| 异议处理 | 未设计 | 明确支持"下级不同意可保留"，但进 dissent log |
| 对上级 | open_items.md | summary-for-boss.md（改了什么 + 异议 + 剩余开放项）|
| 实现 | 单 skill | 管理层 skill + per-peer agent template（双层）|

## 沿用 v0 的要点

- 七轴（BLUF / Completeness / Evidence / Assumptions / Red Team / Stakeholder / Decision Readiness）—— 还是 review 的内容轴
- 借鉴 Completed Staff Work、BLUF、devil's advocate 的方法论基础
- Agent skill 标准 + hermes / openclaw 兼容
- 最终目标：让上级会议时只做"签字级"决策

## 风格 hybrid 规则（新增）

对话风格不能纯 Socratic 也不能纯 punch list。经验法则：

| 类型 | 处理方式 |
|---|---|
| Ask 不清 / 没 recommendation / 明显数据空白 | 直接指出（"前 3 行没看到你要什么，改成 X"）|
| 选项论证薄弱 / counterarg 缺失 | Socratic 追问（"如果 A 选项失败，fallback 是什么？"）|
| 利益相关方视角遗漏 | 不同视角注入（"站在投资人立场，这一页会先问 …"）|
| 低优先级润色 | 不提（避免噪音）|

## 按你答复更新的决策

| 项 | 决策 |
|---|---|
| Skill 命名 | `review-agent`（manager）+ template 叫 `reviewer`，对齐 memoirist 双层 |
| 触发 | IM 消息触发（subtask 模式），非 CLI slash；所以 `disable-model-invocation: true` 在 manager；narrator 端通过 openclaw peer routing 自动启动 |
| 模型 | narrator 默认继承主 agent model；workspace 配置里可显式覆盖（用户自定义位）|
| open_items | 不再由 review-agent 写最终文档；只在 `summary-for-boss.md` 列出"未闭合 / 下级保留异议"的点，由下级定稿时自决 |

---

# 我看到的不完善处（请你逐条裁定）

### G1. "后台子任务" + "多轮对话" 表面张力
你说的"后台跑子任务，子任务结束才返回信息给上级"——我理解为：
- 下级和 review-agent 之间是**异步** IM 对话（不抢主线程）
- **上级**在子任务结束前看不到任何东西
- 子任务结束后，上级才拿到 summary

如果正确，就没问题。如果你想的是"上级过程中可随时看进度"——需要额外做个上级侧 dashboard。建议 v0 按我理解做，上级不参与中间过程。

### G2. "下级不同意可保留"——需要 dissent log
这条我觉得是对的（避免 review-agent 变审查机），但如果下级默默跳过反馈不告诉上级，上级开会时会被打脸。建议强制："任何下级拒绝的反馈必须回一句理由，进 dissent log，写入 summary-for-boss。" review-agent 不 veto，但透明。

### G3. review-agent 什么时候判断"子任务可以结束"？
三选一：
- (a) 下级显式说"结束/ok 了"
- (b) review-agent 判定"无重大 gap"主动宣布
- (c) hybrid：review-agent 标 "ready" 但等下级确认
建议 (c)。

### G4. 下级定稿产物的位置 / 交付
最终汇报材料是下级自己在别处写（Lark 文档 / 本地 markdown）还是在 review-agent 的 workspace 里产生？建议：workspace 里留一个 `final-brief.md` 路径，下级说"这是最终版"就存进去、归档里可回溯。

### G5. Boss 偏好文件何时读、怎么更新
`boss_profile.md` 每次 session 开始重新读（支持上级更新标准）。建议再加 `review_criteria.md` override——特定会议可能有特殊门槛（如"这次融资汇报不能有 > 6 个月的数据"）。

### G6. 多个下级互相隔离
继承 memoirist 模式：每个 peer 一个 workspace，memory/对话/dissent 都独立。Review-agent 不能把 A 下级的 brief 信息泄露给 B 下级。

### G7. IM 通道先上哪个
你 memory 里 Lark 最常用（有 lark open API 脚本），但 openclaw 原生不支持 feishu。建议 **本地测试先用 Telegram**（openclaw 已验证 + memoirist 跑过），生产上再走 Lark（走 lark_send.md 那套）。或者干脆本地测试先跑 CLI mock（不接 IM），省去 gateway 配置干扰。

### G8. summary-for-boss 什么时候生成 / 如何送达
子任务结束即生成。送达方式：
- (a) 写到本地文件让上级自己看
- (b) review-agent 通过 IM 主动发给上级
- (c) 生成 Lark 文档（走 gdrive_cli 或 lark_send）
建议 v0: (a)，v1 加 (b)/(c) 集成。

### G9. 测试路径：本地 hermes 上怎么跑
`本地 hermes` 目前没跑 openclaw gateway / IM 通道（从 ~/.hermes 结构看）。两个选项：
- (A) 在你本地起 openclaw + telegram binding（比较重）
- (B) **先做 CLI mock 模式**：一个命令 `/review-agent start <peer>` 进入交互 REPL，模拟 IM 异步对话；验证七轴/Socratic 风格/dissent log/summary 逻辑正确后，再把同一套 workspace template 挂到 openclaw IM
建议 (B)。代码可复用 —— workspace template 同一份，manager 层做双驱动（CLI mock / openclaw binding）。

### G10. 上级的角色细化
现在"上级"和"boss_profile"绑死，意味着 review-agent 只能为一个上级服务。如果用户自己既是老板又要扮上级审不同人，OK。但如果要扩展到"多个上级、多个下级"矩阵——需要 `boss_id` 维度。建议 v0 单 boss，v1 多 boss。
