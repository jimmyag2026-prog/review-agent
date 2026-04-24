# Review Agent v2.1 · 测试清单

> 给测试用户（扮演 Requester 角色）+ Admin（观察 log 和 workspace 的人）共用。测试用户照第 2-6 节一步步跑；Admin 在第 7 节盯 gateway.log 对照"预期看到的事件"验收。

## 用法

- **测试用户**：跟着"测试步骤"栏逐条做，记录"实际结果"（截图 Lark + 一两句评价）
- **Admin**：开 `tail -F ~/.openclaw/logs/gateway.log`，每步对照"Admin 侧应看到的 log" 一栏。任何一栏对不上即视为失败 → 记录下来我一起 debug
- **通关标准**: 1-5 节全绿（或只有已知降级项），再进第 6 节边缘 case

---

## 0. 测前 Admin 侧自检

在把测试账号交给用户前，Admin 先跑一遍:

```bash
# 1. openclaw gateway 活着
pgrep -f openclaw-gateway | head -1 && echo GATEWAY_UP

# 2. feishu.dynamicAgentCreation 开着
python3 -c "
import json
d = json.load(open('$HOME/.openclaw/openclaw.json'))
dac = d['channels']['feishu'].get('dynamicAgentCreation', {})
print('enabled:', dac.get('enabled'), ' maxAgents:', dac.get('maxAgents'))
"
# 预期: enabled: True   maxAgents: 100

# 3. 模板 + responder profile 都在
ls ~/.openclaw/workspace/templates/review-agent/ | head -5
cat ~/.openclaw/review-agent/responder-profile.md | head -3

# 4. openclaw source patch 落盘
grep -c "review-agent local patch" /opt/homebrew/lib/node_modules/openclaw/dist/monitor-D9C3Olkl.js
# 预期: 2（opening + closing marker）

# 5. skill version 对得上
cat ~/.openclaw/skills/review-agent/VERSION
cat ~/.openclaw/workspace/skills/review-agent/VERSION 2>/dev/null
# 预期: 2.1.0 两处都是

# 6. 测试用户的 open_id 在 allowFrom 里（如果 dmPolicy=allowlist）
python3 -c "
import json
d = json.load(open('$HOME/.openclaw/openclaw.json'))
f = d['channels']['feishu']
print('dmPolicy:', f.get('dmPolicy'), 'allowFrom:', f.get('allowFrom', []))
"
```

6 项全绿才把测试账号交出去。

---

## 1. 首次对话 · Persona 正确性 (5 min)

| # | 测试步骤 | 预期看到（Lark 里）| Admin 侧 log 该出现 | 实际结果 |
|---|---|---|---|---|
| 1.1 | 测试用户用新 Lark 账号向 bot 发一句闲聊: `你好` | 简短礼貌回复，内容不长；语气是 Review Agent（直接、务实），**不是** 默认的"Hey I just came online, who am I?"、也**不**问 "我该叫你什么？" | `creating dynamic agent "feishu-ou_xxxx"` → `review-agent: seeded ...` → `dispatch complete (... replies=1)` | |
| 1.2 | 发 `/review help` | 显示 `/review start/end/status/help` 命令表 + 一句"普通聊天直接说话即可" | 同上 3 步 log，replies=1 | |
| 1.3 | 发一句纯无关文字: `今天天气不错` | 简短回应，**不**启动 review 流程；不要出现 "I need to figure out..."、"Thinking Process:" 等内心独白字样 | replies=1 | |

**一定不该出现的信号**:
- ❌ `Thinking Process:` / `Analyze the Request:` / `Drafting Response:` / `Output Generation:`
- ❌ `Hey I just came online` / `Who am I?` / "你要怎么称呼我"
- ❌ `BOOTSTRAP.md` / `SOUL.md` 等文件名字面出现在聊天里
- ❌ `bash $`、`python3 -c`、`pip install` 等命令字样

看到任意一条上面的 → 记截图，**停止测试**，反馈给 Admin。

---

## 2. 无材料开启 review · Attachment-first flow (5 min)

| # | 测试步骤 | 预期 Lark 看到 | Admin 侧 | 实际结果 |
|---|---|---|---|---|
| 2.1 | 发 `我想和 Jimmy 讨论 Q2 产品路线图` （review 意图，**无**附件） | Agent 回一句大致: "好。你有材料要一起看吗？附件 / Lark 链接 / 一段文字都行。没有的话我也可以先听你口头讲思路再问问题。" **不应**直接启动 review 流程 | replies=1，session dir **未创建** | |
| 2.2 | 紧接发 `/review start` （无 subject 也无材料） | 类似回复：请发材料或讲思路 | replies=1 | |
| 2.3 | 发 `算了` 或 `先不聊了` | 简短应一句"好" | replies=1 | |

---

## 3. 有材料开启 review · 文本 / URL / 附件 (15 min)

### 3A · 长文本作为材料

| # | 步骤 | 预期 Lark | Admin | 实际 |
|---|---|---|---|---|
| 3A.1 | 粘贴一段 300+ 字的 proposal（比如某产品立项报告，你准备一段），结尾说 `帮我看看` | Agent 回一条 **主题确认** 消息，列 2-4 个候选主题供选（a/b/c/custom），**不应**直接跳到 findings | `sessions/<timestamp-xxx>/` 目录被创建，里面有 `input/initial.md`、`normalized.md`、`subject_confirm_draft.md` | |
| 3A.2 | 回一个字母（比如 `a` 或 `b`）确认主题 | Agent 回 **开场白 + 第一条 finding**：开场白是 "我扫到 N 条问题。先带你过最关键的 5 条……"（N 通常 8-12），后面跟 Finding #1 带 `[Intent · BLOCKER]` / `[Materials · IMPROVEMENT]` 等 pillar 标签，结尾有 `(a) accept / (b) reject / (c) modify / (p) pass / (custom)` 选项 | `annotations.jsonl` 写入，5-12 行 JSON；`cursor.json` 显示 `total_found`=N, `top_n`=5, `pending` 长度≤4 | |

### 3B · Lark wiki / docx URL

| # | 步骤 | 预期 Lark | Admin | 实际 |
|---|---|---|---|---|
| 3B.1 | 发一个 Lark wiki 链接 + `帮我看看这个` （链接要是你有权限的 doc）| **预期 A (有 wiki scope)**: Agent 正常进入主题确认流程（如 3A.1）。**预期 B (缺 wiki scope)**: Agent 回 "我这边 app 没有 `wiki:wiki:readonly` scope 读不到，你先帮我把正文贴在聊天里，或者让 Admin 去 Lark 开发者后台加这个 scope" | 预期 B 时 gateway.log 有 `Access denied ... wiki:wiki:readonly`，然后 replies=1（说明 Agent 优雅降级了） | |
| 3B.2 | 如果 3B.1 走的预期 B，复制 doc 内容粘贴进聊天 | Agent 走 3A 流程（进入主题确认）| session dir 创建 + input/initial.md | |

### 3C · PDF / 图片 / 语音附件

| # | 步骤 | 预期 Lark | Admin | 实际 |
|---|---|---|---|---|
| 3C.1 | 发一份小 PDF (< 5MB)，附言 `这是我们的方案` | Agent 启动 review，几秒后回主题确认消息 | `sessions/<id>/input/<filename>.pdf` 存在，`normalized.md` 里有提取出的文字 | |
| 3C.2 | 发一张截图（图片），附言 `这是界面方案` | 如 Admin 装了 tesseract：Agent OCR 后进 review。否则回 "image OCR unavailable — install tesseract; image saved as xxx" 建议粘贴文字 | 同上；或 `ingest_failed.json` 生成 | |
| 3C.3 | 发一个 **大** PDF (>20MB 或 >100 页) | Agent 直接回 "文件有点大（X MB / N 页），能发小一点的版本或拆成几段吗？" **不**尝试处理 | 无新 session 创建；gateway.log 无 ingest 错误（因为 ingest 没跑）| |

---

## 4. Q&A loop · a/b/c/p/custom/more/done (20 min)

接在 3A 或 3B 之后（有 session 在进行中）:

| # | 测试步骤 | 预期 Lark | Admin | 实际 |
|---|---|---|---|---|
| 4.1 | 回 `a` （接受 Finding #1 的建议）| "✓ 收到。" + 下一条 Finding (#2)，格式同 #1 | `cursor.json.done` 增加一个；`pending` 减一；`annotations.jsonl` 对应 id status=accepted | |
| 4.2 | 对 Finding #2 回 `b 我不同意，理由是 X` | "收到你的反对意见，记录了。" + Finding #3 | `dissent.md` 有新条目；`annotations.jsonl` 对应 id status=rejected | |
| 4.3 | 对 Finding #3 回 `c 我改成 Y` | "收到修改版。" + Finding #4 | `annotations.jsonl` 对应 id status=modified, reply="Y" | |
| 4.4 | 对 Finding #4 回 `p` (跳过) | "⊘ 跳过。" + Finding #5 | cursor 推进但 id 不进 done | |
| 4.5 | 对 Finding #5 回一句不是缩写的自然语言（比如 `这个我已经和运营对过了`）| Agent 理解并给 ✓/modified 中的一种反馈 + 下一步 | `annotations.jsonl` 对应 id 有合理的 status 转换 | |
| 4.6 | 所有 top-5 过完后 | Agent 回: "前 5 条已过完。还有 N-5 条 deferred 的问题（优先级较低），回 `more` 继续，或 `done` 结束进入 merge+final-gate。" | cursor.pending 为空，deferred 非空 | |
| 4.7 | 回 `done` | Agent 启动收尾：跑 merge-draft + final-gate，生成 6-section 决策简报 | `sessions/<id>/final/revised.md` 生成；`sessions/<id>/meta.json` status=closed | |

或者 4.7 替代版本:

| # | | | | |
|---|---|---|---|---|
| 4.7b | 回 `more` 继续看 deferred | Agent 继续弹 Finding #6、#7... | deferred 清空，pending 补上 | |

---

## 5. Session 关闭 + 交付 (5 min)

接在 4.7 之后:

| # | 步骤 | 预期 Lark | Admin | 实际 |
|---|---|---|---|---|
| 5.1 | 等 1-2 分钟让 merge + final-gate 跑完 | Agent 主动发一条：简短 "session 已关闭" + 附 6-section 决策简报摘要 | `meta.json.status` = "closed"；`final/revised.md`、`final/revised_changelog.md` 都在；`cursor.done` 是所有 id | |
| 5.2 | 再发 `/review status` | "当前没有活跃 review session。最近关闭的 session: ..." | `active_session.json` 不存在；meta.status=closed | |
| 5.3 | **Responder（你，Admin）** 自己的 Lark 账号该收到一条 summary DM | 收到 6-section 简报 + 议题 / 数据 / 决策建议 / 时间预算 / 风险 | `delivery.jsonl` （如果配了）有 record；feishu API 日志里有 Admin 的 open_id 收到消息 | |

---

## 6. 中断 + 异常 (10 min)

| # | 步骤 | 预期 Lark | Admin | 实际 |
|---|---|---|---|---|
| 6.1 | 在 Q&A 中途发 `/review end 算了` | Agent 接受终止 + session status=closed_by_briefer | `meta.json.termination=forced_by_briefer, forced_reason="算了"`；active_session 清空 | |
| 6.2 | 再开一个 session，在主题确认阶段发 `p` | Agent 回 "好，跳过 review。以后想继续重新发材料" + session 关闭 | meta.status=closed, termination=forced_by_briefer | |
| 6.3 | 开 session + 发 Finding #1 → 然后 24h 不理 | Admin 在 dashboard 看到 `stale` 标记（不是 active）| meta.last_activity_at 远于现在；cursor 未动 | _(如果想测等 24h；跳过也行)_ |
| 6.4 | 发一段纯 emoji 或乱码 `😂🫠🤡🪦` | Agent 礼貌应一句 "看不太懂——能直接打字说吗？" | replies=1 | |
| 6.5 | 发长篇（5000+字）外语文本当材料 | Agent 应该能处理；normalized.md 存全文；scan 正常 | 无 ingest error | |
| 6.6 | 同一个测试用户**同时**开 2 个 session（先 /review start 主题 A，再不 end 直接 /review start 主题 B） | Agent 回 "你已有一个活跃 session：X。v0 支持一次一个——先 /review end，或手动 close 后再开新的" | 原 session 不受影响 | |

---

## 7. Admin 实时监控 (during all tests)

在测试进行时，开三个 terminal tab:

### Tab A · gateway log

```bash
tail -F ~/.openclaw/logs/gateway.log | grep -E "creating dynamic agent|review-agent: seeded|DM from|dispatching|dispatch complete|invalid|ERROR|denied"
```

每个测试步骤都应看到 `DM from` → `dispatching` → `dispatch complete (... replies=1)`。看到 `replies=0` **就是出问题**，立刻记下对应步骤号给 Admin。

### Tab B · 测试用户的 workspace

```bash
# 替换 OID 为测试用户的 open_id
OID=ou_xxxxxxxx
watch -n 3 "ls $HOME/.openclaw/workspace-feishu-$OID/sessions/ 2>/dev/null"
```

看 session 目录是否按步骤创建。

### Tab C · 当前 session 文件变化

```bash
# 步骤 3A.1 触发后找 session id
SID=$(ls -t ~/.openclaw/workspace-feishu-$OID/sessions/ | head -1)
watch -n 3 "ls -la ~/.openclaw/workspace-feishu-$OID/sessions/$SID/"
```

应该能看到 `normalized.md` → `subject_confirm_draft.md` → `annotations.jsonl` → `cursor.json` → `dissent.md` (if rejected) → `final/revised.md` 按流程出现。

### 如果任何一步 Lark replies=0 但 subagent 在 jsonl 里有 output

```bash
# 查 subagent 最近 message 工具调用的 target 格式
python3 <<PYEOF
import json
from pathlib import Path
f = Path.home() / '.openclaw' / 'agents' / 'feishu-$OID' / 'sessions'
for j in sorted(f.glob('*.jsonl'), key=lambda p: p.stat().st_mtime, reverse=True)[:1]:
    print("file:", j.name)
    for line in j.read_text().splitlines()[-20:]:
        try:
            d = json.loads(line)
            for c in d.get('message',{}).get('content',[]) or []:
                if isinstance(c, dict) and c.get('type') == 'toolCall' and c.get('name') == 'message':
                    a = c.get('arguments', {})
                    print(f"  target={a.get('target')!r}  action={a.get('action')!r}  msg[:60]={str(a.get('message',''))[:60]}")
        except: pass
PYEOF
```

**预期**: `target` 应是 `None` / 缺失 / 或 `user:ou_xxx` 格式。如果是 **bare `ou_xxx`** → SOUL.md 指令没被模型读到，需要 `rm -f ~/.openclaw/agents/feishu-$OID/sessions/*.jsonl` 清 prompt cache。

---

## 8. 已知降级 / 暂不测 (info only)

这些是 v2.1 已知但故意不修的，见到对应现象属正常:

- **每条 DM 都 `creating dynamic agent` 一次** — openclaw 内部一致性问题，我们的 cp -R seed 幂等不影响数据
- **`[contact:contact.base:readonly] Access denied`** 反复刷 — 测试用户 display name 解析不到，但不影响 DM 收发
- **第一次 response 比较慢 (5-15s)** — LLM 过 ingest → scan 需时间；第二条起应 <5s
- **Telegram / WhatsApp / 其他 channel 没有 per-peer subagent** — 架构限制，v2 只为 feishu + wecom 开发

---

## 9. 测试报告模板（给测试用户填）

```markdown
# review-agent v2.1 测试报告
- 测试日期: 2026-04-__
- 测试账号 (open_id 前 8 位): ou_ccaf7d__
- Admin: Jimmy

## 整体印象（一句话）
> "___"

## 每节通过率
- §1 首次对话 & persona: __/3
- §2 无材料: __/3
- §3 有材料: __/6
- §4 Q&A loop: __/7
- §5 关闭交付: __/3
- §6 异常: __/6

## 最差的 3 个体验点（截图）
1. __
2. __
3. __

## 最好的 3 个点
1. __
2. __
3. __

## 期望改进
1. __
2. __
```

把这份 markdown 填完给回 Admin，我会按优先级排入 v2.2 patch queue。

---

_生成于 v2.1.0 发布后（2026-04-24）。下一版会根据这轮测试反馈再精简 checklist。_
