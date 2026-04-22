# review_agent — 详细工作流

日期：2026-04-20

## 一次完整 review session 的生命周期

```
T0  下级 invoke: /review-agent <draft> <profile> [meeting_context]
T1  reviewer 在 fork context 启动
T2  读入 artifacts（draft + profile + meeting_context + references/checklist.md）
T3  七轴扫描 → findings[]
T4  合并/去重 → 按 tag 排序
T5  产出反馈 report（见下方模板）→ 返回主 context
T6  下级 revise draft
T7  下级再次 invoke: /review-agent <draft> <profile> --round=2
T8  reviewer 对比上一轮 findings：
     - 哪些已 close？
     - 改动是否引入新问题？
     - 剩余 BLOCKER 是否可 close？不可的 → flag as "unresolvable"
T9  若所有 BLOCKER close 或 flag unresolvable → gate pass
    否则继续 T6–T8，直到 round == N
T10 最终产出：briefing.md + open_items.md (+ review_trail.jsonl if audit)
```

## 反馈 report 模板（主 context 看到的）

```markdown
# Review Round <n> — <gate_status>

## Gate Status: PASS / BLOCKED / ESCALATED-TO-OPEN-ITEMS

## Findings

### BLOCKER — Ask 不清（轴 1）
**Draft line 3–5**: "我们考虑下周上线..."
**Issue**: 没有明确 ask——是要资源？要 approval？要决策方向？
**Suggestion**: 改成具体一句，例如 "请批准 4-30 前端发布 v0.3，需 workspace 模板审批"
**Severity**: BLOCKER

### IMPROVEMENT — Evidence 陈旧（轴 3）
...

### NICE-TO-HAVE — ...

## Unresolvable (升级为 open_items)
- [ ] 竞品上月定价数据未公开——需要会议上让上级判断是否派 BD 去探

## Summary
- 2 BLOCKER / 1 IMPROVEMENT / 1 NICE-TO-HAVE / 1 Unresolvable
- Est. revision time: 30 min
- 下一步：close BLOCKER，IMPROVEMENT 可选
```

## Reviewer 的内部 prompt 结构（skill 正文核心）

```
你是 <BossName> 的审阅代理。你的唯一目标：让 <BossName> 在
<MeetingContext> 上只需签字即可，不需要做下级本应做的功课。

读入：
- <BossProfile>（上级的标准、偏好、pet peeves、决策风格）
- <Draft>（下级当前版本）
- <MeetingContext>（本次会议目的）
- 可选 <PriorBriefings>

按七轴扫描。每条 finding 必须：
1. 引用 draft 原文定位
2. 明确说哪一轴 fail
3. 给出**具体**修改建议（"改成 X"而不是"需要更清晰"）
4. tag 严重度：BLOCKER / IMPROVEMENT / NICE-TO-HAVE

禁止：
- 废话型反馈（"可以更完整"）
- 增加上级工作量的建议（"建议上级开会前也看一下…"）
- 一轮同时提出 >5 个 NICE-TO-HAVE（噪音）
- 顺着下级的话说（这是 reviewer，不是 cheerleader）
- 把本轮能定的 open item 推到下一轮

输出按上述 report 模板。
```

## 迭代收敛策略

### 条件 A：自然收敛
所有 BLOCKER → close, IMPROVEMENT 按情况 close or 降级 NICE-TO-HAVE → gate pass。

### 条件 B：真无法收敛
某 BLOCKER 属于"没有信息"类（竞品数据、监管判断、上级口味）→ flag unresolvable → 写 open_items → gate escalated。

### 条件 C：进入局部震荡
上一轮的改动引入新 BLOCKER，且修复会再引入新 BLOCKER。3 轮后自动 gate escalated，把震荡链条写进 open_items 让上级决定方向。

## 多 agent 协作场景（高级用法）

未来可扩展：
- 下级 agent A 起草
- **研究 subagent B** 补 evidence（轴 3）
- **stakeholder subagent C** 扮演客户/投资方给 counterarg（轴 5）
- review-agent 统一判 gate

v0 只做 review-agent 本身，B / C 作为 reference 写进 roadmap。

## 反滥用约束

- review-agent 不该被当普通编辑器。如果 draft 文本质量低到"根本没到 brief 形态"——应返回 `PREMATURE_INPUT`，要求先过最低结构门槛再送审。
- review-agent 不产出 briefing 本身，只给 findings。**下级必须自己改**——否则违反 CSW 原则（上级不替下级做功课，reviewer 也不替下级做）。
- 唯一例外：最终 `briefing.md` 是下级改好后的文件改名/copy，不是 reviewer 写的。

## 数据持久化

`~/.hermes/workspace/review/`（或项目 `.claude/workspace/review/`）：
```
review/
├── boss_profile.md          # 一次性配置
├── sessions/
│   └── 2026-04-20-memoirist-release/
│       ├── meeting_context.md
│       ├── draft.md           # 最新版
│       ├── draft.round1.md    # 历史版本
│       ├── draft.round2.md
│       ├── findings.round1.md
│       ├── findings.round2.md
│       ├── briefing.md        # gate pass 后产出
│       ├── open_items.md
│       └── review_trail.jsonl # 可选审计
```
