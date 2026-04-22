# Installing review-agent

Two paths:
- **[Quick install](#quick-install)** — you already have hermes + Lark creds + OpenRouter key.
- **[From scratch (bare-metal VPS)](#from-scratch)** — no packages, no hermes, nothing.

---

## Prerequisites (regardless of path)

- Lark Open app (bot) with scopes: `im:message:send_as_bot`, `im:message`, `docx:document`, `drive:file`, `drive:drive` — create at https://open.larksuite.com/app
- OpenRouter API key — https://openrouter.ai/keys
- (Eventually) hermes installed — https://github.com/hermes-agent/hermes

## Quick install

For environments that already have hermes running with Lark channel configured.

```bash
# 1. clone
gh repo clone jimmyag2026-prog/review-agent ~/code/review-agent

# 2. run installer (interactive — prompts for your Lark open_id)
cd ~/code/review-agent && bash install.sh

# 3. apply config
hermes gateway restart
```

Non-interactive:

```bash
bash install.sh --admin-open-id ou_xxxxxxxx --admin-name "Your Name"
```

---

## From scratch

Fresh VPS / bare metal / new Mac. Ordered steps.

### Step A — System packages (2 min)

**Bootstrap script** (auto-detects OS, installs all deps):

```bash
# on Ubuntu/Debian VPS
git clone https://github.com/jimmyag2026-prog/review-agent.git ~/code/review-agent   # see below if git/auth fails
cd ~/code/review-agent
bash install/bootstrap.sh
```

Supports: Ubuntu / Debian / Fedora / RHEL / Arch / Alpine / macOS.

**Manual equivalents** if you prefer not to run the script:

| OS | Command |
|---|---|
| Ubuntu / Debian | `sudo apt update && sudo apt install -y git python3 python3-pip python3-yaml rsync curl poppler-utils tesseract-ocr tesseract-ocr-chi-sim ffmpeg` |
| Fedora / RHEL | `sudo dnf install -y git python3 python3-pip python3-pyyaml rsync curl poppler-utils tesseract tesseract-langpack-chi_sim ffmpeg` |
| Arch | `sudo pacman -S --needed git python python-pip python-yaml rsync curl poppler tesseract tesseract-data-chi_sim ffmpeg` |
| Alpine | `sudo apk add git python3 py3-pip py3-yaml rsync curl bash poppler-utils tesseract-ocr ffmpeg` |
| macOS | `brew install git python@3.11 rsync curl poppler tesseract tesseract-lang ffmpeg openai-whisper` |
| Windows | unsupported (use WSL2) |

### Step B — Install hermes (5 min)

Follow official hermes install instructions: https://github.com/hermes-agent/hermes

After install, verify:
```bash
hermes --version
hermes setup         # interactive: sets up config.yaml, skills dir, etc.
```

### Step C — Configure credentials (3 min)

Edit `~/.hermes/.env` and add:

```bash
FEISHU_APP_ID=cli_xxxxxxxxxxxxxxxx
FEISHU_APP_SECRET=xxxxxxxxxxxxxxxx
FEISHU_DOMAIN=lark                   # 'lark' (国际版) or 'feishu' (国内版)
FEISHU_CONNECTION_MODE=websocket
OPENROUTER_API_KEY=sk-or-v1-xxxxxxxx
```

Then pair your personal Lark account with the bot:
```bash
hermes gateway install       # one-time (launchd on mac / systemd on linux)
hermes gateway start
# Open Lark, find your bot, DM it any message
hermes pairing list          # should show a pending feishu pairing
hermes pairing approve <open_id_from_list>
```

### Step D — Clone the review-agent repo

The repo is **private**. Pick one access method:

**Option 1 · GitHub CLI** (recommended, simplest):

```bash
# Install gh (Ubuntu / Debian)
sudo apt install -y gh        # or follow https://github.com/cli/cli#installation
# Auth + clone
gh auth login                 # interactive
gh repo clone jimmyag2026-prog/review-agent ~/code/review-agent
```

**Option 2 · SSH key**:

```bash
ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)"
cat ~/.ssh/id_ed25519.pub     # copy
# Paste into https://github.com/settings/keys
git clone git@github.com:jimmyag2026-prog/review-agent.git ~/code/review-agent
```

**Option 3 · Personal Access Token**:

```bash
# Create a PAT with 'repo' scope at https://github.com/settings/tokens
git clone https://<YOUR_TOKEN>@github.com/jimmyag2026-prog/review-agent.git ~/code/review-agent
```

### Step E — Run the installer

```bash
cd ~/code/review-agent
bash install.sh
hermes gateway restart
```

Total time from fresh VPS: ~15 minutes.

---

## What `install.sh` does

Idempotent — safe to re-run.

| Step | Action | Idempotent? |
|---|---|---|
| 1 | `check_prereqs.sh` — blocks if hermes/python/creds missing | ✓ read-only |
| 2 | `rsync skill/` → `~/.hermes/skills/productivity/review-agent/` | ✓ overwrites |
| 3 | Patch `~/.hermes/config.yaml` (feishu display tier, kill interim msgs) | ✓ no-op if correct |
| 4 | Prepend orchestrator SOP to `~/.hermes/memories/MEMORY.md` | ✓ marker-guarded |
| 5 | Initialize `~/.review-agent/` with Admin open_id | ✓ skipped if exists |
| 6 | Print next steps | — |

Backups of `config.yaml` and `MEMORY.md` saved as `.bak.review-agent-<timestamp>` before write.

---

## After install

### 1. Edit your Responder profile

Your "pet peeves", decision style, time budget, things to always ask.

```bash
vim ~/.review-agent/users/<your_open_id>/profile.md
```

Bad defaults → bad reviews. Take 10 minutes.

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

### 4. Open the dashboard

```bash
bash ~/.hermes/skills/productivity/review-agent/scripts/dashboard-web.sh --open
```

Serves `http://127.0.0.1:8765` — lists all users, active sessions, findings progress. Local-only, no external access.

### 5. Let the Requester send material

They DM the Lark bot with a draft / doc link / proposal. hermes routes based on `MEMORY.md` SOP:
- If review intent detected → subject confirmation → scan → auto-scope top 3 → Q&A
- Otherwise → normal chat

---

## Verify install

```bash
# Skill registered
hermes skills list --source local | grep review-agent

# SOP installed
grep -c 'review-agent:orchestrator-sop' ~/.hermes/memories/MEMORY.md   # → 1 or 2

# Config patched
python3 -c "import yaml; cfg = yaml.safe_load(open('$HOME/.hermes/config.yaml'));
print('interim:', cfg['display']['interim_assistant_messages']);
print('feishu:', cfg['display']['platforms']['feishu'])"

# Runtime initialized
ls ~/.review-agent/users/
```

---

## Uninstall

```bash
# remove skill
rm -rf ~/.hermes/skills/productivity/review-agent

# remove runtime data (kills all sessions)
rm -rf ~/.review-agent

# revert hermes config (restore latest backup)
ls ~/.hermes/config.yaml.bak.review-agent-* | tail -1 | xargs -I{} cp {} ~/.hermes/config.yaml

# remove SOP from MEMORY.md — delete everything between the two
# <!-- review-agent:orchestrator-sop:v1 --> marker lines
vim ~/.hermes/memories/MEMORY.md
```

---

## Troubleshooting

**"Command 'gh' not found"**
→ `sudo apt install gh` (Ubuntu/Debian) or follow bootstrap.sh. You can also clone with SSH or HTTPS + token (see [Step D](#step-d--clone-the-review-agent-repo)).

**"apt: command not found" (on macOS)**
→ You're on Mac. Use `brew` instead: `brew install git python@3.11 rsync`.

**"hermes skills list 不显示 review-agent"**
→ hermes 不跟 symlink。确认 `~/.hermes/skills/productivity/review-agent/` 是真实目录（不是 symlink）；重跑 `install.sh` 或 `skill/scripts/sync-to-hermes.sh`。

**"主 agent 收到 Requester DM 后还是直接回答而没启 review"**
→ 当前 hermes session 没 reload MEMORY.md；重启 gateway（`hermes gateway restart`）后新 session 会加载。

**"Requester 在 Lark 里看到了 python3 / bash 字样"**
→ IM outbound 泄露了工具调用。检查 `display.platforms.feishu.tool_progress` 是否为 `off`。`hermes gateway restart` 让 config 生效。

**"scan.py 失败: no OPENROUTER_API_KEY"**
→ `echo 'OPENROUTER_API_KEY=sk-or-v1-xxx' >> ~/.hermes/.env` 然后 gateway restart

**"lark-doc-publish 报 scope 错误"**
→ 在 Lark 开发者后台给 bot 加：`im:message:send_as_bot`, `im:message`, `docx:document`, `drive:file`, `drive:drive`

**"ImportError: No module named yaml"**
→ `pip3 install pyyaml` 或 OS 包管理器装 `python3-yaml` / `py3-yaml`

**"hermes gateway not running"**
→ `hermes gateway install && hermes gateway start` (first time); 或 `hermes gateway restart`

---

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
│         → final-gate → _build_summary (LLM)   │
│         → deliver to Responder + Requester     │
└────────────────────────────────────────────────┘

Storage: ~/.review-agent/ (users / sessions / rules / logs / dashboard)
LLM: OpenRouter (Sonnet 4.6 default)
Dashboard: http://127.0.0.1:8765 (local read-only)
```

See `design/review_flow.md` for the full specification.
