# Hermes / Claude Skill 结构规范（实测版）

日期：2026-04-20

## SKILL.md 格式（agentskills.io 标准）

```yaml
---
name: skill-name                    # 小写字母+数字+连字符，≤64 字符；省略则用目录名
description: ...                    # 推荐填；和 when_to_use 合并后截至 1536 字符
when_to_use: ...                    # 可选，补 trigger phrase
argument-hint: "[draft] [profile]"  # autocomplete 提示
disable-model-invocation: false     # true = 只能用户手动 / 下级 agent 显式调
user-invocable: true                # false = 只 agent 可调（背景知识型）
allowed-tools: Read Write Bash(...) # 空格分隔或 YAML list
model: claude-sonnet-4-7            # 可选，本 skill 生效期间用此模型
effort: medium                      # low/medium/high/xhigh/max
context: fork                       # 跑在独立 subagent context（reviewer 必用）
agent: general-purpose              # fork 时选哪个 subagent type
paths: ["**/drafts/*.md"]           # 只在这些路径的文件被编辑时自动触发
---

# 正文 markdown（≤500 行；超长放 references/ 分块）
```

## 关键变量

| 占位符 | 作用 |
|---|---|
| `$ARGUMENTS` | 调用时全部参数字符串 |
| `$0 / $1 / ...` | 按位置取参数（多词用引号包起来算一个）|
| `${CLAUDE_SKILL_DIR}` | skill 目录绝对路径——引用内部脚本/模板用这个 |
| `${CLAUDE_SESSION_ID}` | 会话 ID，日志文件命名用 |

## 目录布局（推荐）

```
review-agent/
├── SKILL.md                 # 入口，≤500 行
├── references/              # 按需加载的长文档
│   ├── boss_profile_template.md
│   ├── review_criteria_template.md
│   ├── checklist.md         # 七轴检查详表
│   └── output_schema.md     # briefing.md / open_items.md 模板
├── scripts/                 # 可执行脚本（非上下文加载）
│   ├── init-profile.sh      # 初次使用：创建 boss_profile
│   └── run-review.sh        # 封装调用
└── README.md                # 面向发布的说明（不被 agent 载入）
```

## 三级渐进载入

1. **Frontmatter metadata**（永远在 context）：`name` + `description` + `when_to_use`，用于触发判断。
2. **SKILL.md 正文**（被 invoke 时注入一次，整个 session 都在）。
3. **references/ 和 scripts/**：正文用 markdown link 引用，agent 自行决定是否 Read / Bash。

## 发布路径（多 agent 兼容）

| Agent | 位置 |
|---|---|
| Claude Code（personal）| `~/.claude/skills/review-agent/` |
| Claude Code（project）| `.claude/skills/review-agent/` |
| Hermes | `~/.hermes/skills/productivity/review-agent/`（需放一个 category 下）|
| Plugin 分发 | `<plugin>/skills/review-agent/` |
| 其他 agentskills.io 兼容 | 同 SKILL.md 即可 |

## Hermes 特有点

- `~/.hermes/skills/` 下必须按 **category 目录** 组织（`productivity/`、`creative/` 等）；每个 category 根有 `DESCRIPTION.md` 做目录描述。
- Hermes frontmatter 可加 `metadata.hermes.tags` 做搜索标签。
- Hermes 的 `config.yaml` 里 `auxiliary.skills_hub` 可能影响 skill 列表展示——测试时如果不出现，检查这里。

## 绑定到 hermes 的测试方式

```bash
# 方案 A：直接软链
ln -sfn ~/review_agent_development/skill ~/.hermes/skills/productivity/review-agent

# 方案 B：拷贝
cp -r ~/review_agent_development/skill ~/.hermes/skills/productivity/review-agent

# 验证
hermes chat -- "/skills review-agent"
```

## 风险点 / 注意事项

- **SKILL.md 中描述字数过 1536 会截断**——把关键 trigger 放前面。
- **`context: fork` 是"reviewer 独立人格"的技术实现**，但 fork 后看不到主会话历史，需要把需要的信息显式写进 `$ARGUMENTS` 或 references。
- Skill 内容在整个 session 一旦 invoke 就常驻，所以**不要在正文里放"临时性"指令**（比如"这次请 …"），否则后续调用也会被污染。
- 跨 agent 分发时，所有 shell 脚本必须用 `${CLAUDE_SKILL_DIR}` 取路径，不能 hardcode `~/review_agent_development/skill/`。
