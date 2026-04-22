# Open Issues — deferred problems with their context and future paths

> 记录已识别但 v0 不解决的架构 / 工程问题。每条写清**是什么 / 为什么没解**+ **未来要解时的方向**。

---

## I-001 · Session context isolation — 主 agent 层无工程保障

**发现**：2026-04-21
**影响**：当 hermes 主 agent 同时处理多个 Requester 的 review session，主 agent 自己的 context window 会累积多个 session 的材料、profile、findings、对话片段。跨 session 污染是**架构级风险**。

### v0 现状（3 层软保障）

1. **脚本层（唯一强保障）**：所有 session-level reasoning 都在 fresh Python 进程里跑（`qa-step.py`、`scan.py`、`confirm-topic.py`、`merge-draft.py`），每次只读指定 session_id 的 folder，LLM system prompt 只注入该 session 的 frozen `admin_style.md + profile.md + review_rules.md`。脚本之间完全隔离。

2. **脚本输出契约（弱保障）**：脚本 stdout 只给 IM 回复文本；stderr 只给 lifecycle markers（`[qa-step] intent=... cursor_advance=...`）。不回显 Requester 材料、profile、finding 内容。主 agent 读 stderr 拿不到 session 细节。

3. **文档硬规则（discipline）**：`MEMORY.md` 顶部的 "🚨 CRITICAL" block + "⚠ SESSION CONTEXT ISOLATION" 段 + `SKILL.md` 的 Session Context Isolation 硬规则 + hijack 反例——要求主 agent **永不 cat/Read session 文件**，**只查 meta.json + active_session.json** 做路由，**不做任何 session content reasoning**。

### 为什么 v0 不上硬约束

调研了 hermes 自身权限机制：

- `DANGEROUS_PATTERNS`（硬编码在 `~/.hermes/hermes-agent/tools/approval.py` 里的 regex 列表）+ `command_allowlist`（config 放行列表）——只拦 **shell 命令**，不拦 Read/Grep tool。没有 config 级别的 `command_blocklist` 或 `path_deny` 机制。
- 改 approval.py 加 custom pattern（option B1）只管 shell，且升级覆盖脆弱。
- TCC 保护目录（option B3）不可靠（见 `feedback_tcc_finder_bypass`）。
- Broker / sandbox 方案（option D/C）对 v0 过重。

### 剩余可接受风险的理由

- 路由决策用 `sender_oid → meta.json`，纯 deterministic，不受主 agent context 污染影响
- 脚本的 LLM 上下文独立，不继承主 agent 污染
- 唯一真实风险是**主 agent 违反文档规则主动 analyze session 内容**——用劫持反例 + 硬规则约束，接受软保障

### 未来要彻底解决时的路径

**方向 A · Broker 进程（最优雅）**

写 `session-broker.py`：
- 主 agent 禁止 Read/Grep/cat session 文件，只允许调 `session-broker.py <op> <args>`
- Broker 接受受限 op：`get_role <oid>` / `get_active_session <oid>` / `invoke <script> <args>` 等
- Broker 校验 `sender_oid == session.requester_oid`，阻止跨 session 访问
- 主 agent 看不到 session folder 结构

适合 hermes / 任何以 Python skill + Bash 为核心的 agent 平台。

**方向 B · OpenClaw / 自建 agent 架构的深度改造**

如果未来把 review-agent 重构到 openclaw 或自建 personal agent 平台，那一层可以做：
- **per-peer agent 实例隔离**（openclaw 本来支持 per-binding workspace + agent——memoirist 就是这个模式）。每个 Requester 有独立 agent 进程，主 agent 不存在跨 session 交叉问题
- **gateway 层 hook**：在 Lark inbound 到达 agent 前，gateway 直接路由到正确的 per-peer 子 agent，主 agent 不参与 routing
- **文件权限分层**：session folder 的 group 权限只允许对应的 per-peer agent 进程访问（UID 隔离或 capability 隔离）

这才是**架构级隔离**，而不是 hermes 这种 shared main-agent 架构的"劝退式"软规则。

**方向 C · macOS sandboxing（重但彻底）**

每次脚本调用跑在 firejail / bubblewrap / 或 macOS 的 `sandbox-exec` 下，只挂载该 session 的 folder，别的不可见。脚本外的 Read/Grep 也读不到。重，但根本。

### 触发重新解决的条件

- 出现真实污染事件（主 agent 把 A 的材料带进 B 的回复）
- 扩展到 multi-Responder 或外部团队用户（v1 起）
- 搬到 openclaw / 自建 personal agent 平台重构（那时直接走方向 B）

### 相关代码 / 文档锚点

- MEMORY.md line 110+ "⚠ SESSION CONTEXT ISOLATION"
- SKILL.md 新增的 "⚠ Session Context Isolation" 段
- 各 script 的 stderr 输出契约（`qa-step.py` line 230+，`start-review.sh` / `confirm-and-scan.sh` 全文）
- hermes approval.py 的 `DANGEROUS_PATTERNS`（`~/.hermes/hermes-agent/tools/approval.py:75`）

---

## （为后续 issue 预留）

新 issue 格式：
```
## I-NNN · 标题
**发现**: 日期
**影响**: 一段
### v0 现状
### 为什么不解
### 未来方向
### 触发条件
### 锚点
```
