# Installing review-agent on a new hermes

One-command install for any fresh hermes environment.

## Prerequisites

| | |
|---|---|
| **hermes** installed + Lark channel configured | — `hermes` CLI in PATH, `~/.hermes/.env` contains `FEISHU_APP_ID` / `FEISHU_APP_SECRET` |
| **Lark bot scopes** | `im:message:send_as_bot`, `im:message`, `docx:document`, `drive:file`, `drive:drive` |
| **OpenRouter API key** | in `~/.hermes/.env` as `OPENROUTER_API_KEY` — used for the LLM that runs scan / classify / synthesize |
| **python3** ≥ 3.9 | `python3 --version` |
| (optional) `whisper` `pdftotext` | for audio / PDF ingest; without these, users just paste text |

## Install (3 steps)

```bash
# 1. clone
gh repo clone jimmyag2026-prog/review-agent ~/code/review-agent

# 2. run installer (interactive — will prompt for your Lark open_id)
cd ~/code/review-agent
bash install.sh

# 3. restart hermes gateway to apply config
hermes gateway restart
```

**Non-interactive variant**:

```bash
bash install.sh --admin-open-id ou_xxxxxxxx... --admin-name "Your Name"
```

## What gets installed

| Location | What | Idempotent |
|---|---|---|
| `~/.hermes/skills/productivity/review-agent/` | Skill files (SKILL.md + scripts + references) | ✓ (overwrites) |
| `~/.hermes/memories/MEMORY.md` | Orchestrator SOP (prepended at top, marker-guarded) | ✓ (skipped if marker present) |
| `~/.hermes/config.yaml` | `display.interim_assistant_messages=false`, `display.platforms.feishu=MINIMAL` | ✓ (no-op if already correct) |
| `~/.review-agent/` | Runtime data root: `users/`, `rules/`, `admin_style.md`, `delivery_targets.json`, `dashboard.md` | ✓ (skipped if exists) |

Backups of `config.yaml` and `MEMORY.md` are saved with `.bak.review-agent-<timestamp>` suffix before modification.

## After install

### 1. Edit your Responder profile

Your "pet peeves", decision style, time budget, things to always ask.

```bash
vim ~/.review-agent/users/<your_open_id>/profile.md
```

Bad defaults → bad reviews. Take 10 minutes here.

### 2. (Optional) Customize agent style

Tone, message pacing, emoji policy, gate strictness.

```bash
vim ~/.review-agent/admin_style.md
```

### 3. Enroll your first Requester

```bash
bash ~/.hermes/skills/productivity/review-agent/scripts/add-requester.sh \
  <requester_lark_open_id> --name "Name"
```

If you don't know the Requester's open_id yet, have them DM your bot once, then check `hermes pairing list`.

### 4. Watch the dashboard

```bash
bash ~/.hermes/skills/productivity/review-agent/scripts/dashboard-web.sh --open
```

Opens `http://127.0.0.1:8765` — shows all users, active sessions, findings progress.

### 5. Let the Requester send their first material

They DM your Lark bot with a doc / draft / proposal. hermes routes based on the SOP in MEMORY.md:
- If review intent detected → `start-review.sh` → subject confirmation → scan → Q&A
- Otherwise → normal chat

## Verify install

```bash
hermes skills list | grep review-agent     # should show 'local'
grep -c 'review-agent:orchestrator-sop' ~/.hermes/memories/MEMORY.md   # should print 1 or 2
python3 -c "import yaml; print(yaml.safe_load(open('$HOME/.hermes/config.yaml'))['display']['platforms']['feishu'])"
ls ~/.review-agent/                        # should have users/ rules/ admin_style.md ...
```

## Uninstall

```bash
# remove skill files
rm -rf ~/.hermes/skills/productivity/review-agent

# remove runtime data (WARNING: kills all sessions)
rm -rf ~/.review-agent

# revert hermes config (restore from latest .bak)
ls ~/.hermes/config.yaml.bak.review-agent-* | tail -1 | xargs -I{} cp {} ~/.hermes/config.yaml

# remove SOP from MEMORY.md — manual: delete everything between the two
# <!-- review-agent:orchestrator-sop:v1 --> marker lines
vim ~/.hermes/memories/MEMORY.md
```

## Troubleshooting

**"hermes skills list 没显示 review-agent"**
→ hermes 不跟 symlink。确认 `~/.hermes/skills/productivity/review-agent/` 是真实目录（不是 symlink）；run `sync-to-hermes.sh` 从 dev 路径同步。

**"主 agent 看到 Requester DM 后还是直接回答而没启 review"**
→ 很可能当前 hermes session 没 reload MEMORY.md；重启 gateway（`hermes gateway restart`）后新 session 会加载。或者在当前 session 里手动 `@hermes 请你 reload memories`。

**"Requester 在 Lark 里看到了 python3 / bash 字样"**
→ IM outbound 泄露了工具调用。检查 `display.platforms.feishu` 里是不是设置了 `tool_progress: off`。`hermes gateway restart` 让 config 生效。

**"scan.py 失败 no OPENROUTER_API_KEY"**
→ `echo 'OPENROUTER_API_KEY=sk-or-v1-xxx' >> ~/.hermes/.env`

**"lark-doc-publish 报 'scope' 类错误"**
→ Lark 开发者后台给 bot 加以下 scopes：
  - `im:message:send_as_bot`（发 DM）
  - `docx:document`（创建/编辑 docx）
  - `drive:file`（评论 / 权限管理）
  - `drive:drive`（读/写文件）

## Architecture summary

```
┌─ Lark inbound (DM / group @) ──────────────────┐
│ hermes main agent reads MEMORY.md SOP → 路由    │
│                                                │
│  ├─ unregistered → polite refuse              │
│  ├─ Admin/Responder → normal chat / mgmt cmd  │
│  ├─ Requester + /review cmd → review-cmd.sh   │
│  ├─ Requester + active session → qa-step.py   │
│  └─ Requester + review intent → start-review.sh│
│         → ingest → confirm-topic → [user confirms]
│         → scan (four-pillar + Responder sim)   │
│         → auto-scope top 3 findings            │
│         → lark-doc-publish (inline callouts)   │
│         → Q&A loop: one finding at a time      │
│         → user says "结束"/all done            │
│         → final-gate → _build_summary (LLM)   │
│         → deliver to Responder + Requester     │
└────────────────────────────────────────────────┘

Storage: ~/.review-agent/ (users / sessions / rules / logs / dashboard)
LLM: OpenRouter (Sonnet 4.6 default)
Dashboard: http://127.0.0.1:8765 (local read-only)
```

See `design/review_flow.md` for the full specification.
