# VPS Setup Guide

**Goal**: run review-agent on a headless Ubuntu 22.04 VPS with systemd, SSH-tunneled dashboard, proper log/backup hygiene. Target: end-to-end in ~20 minutes from a fresh server.

## TL;DR

```bash
# On the VPS, logged in as non-root user (see step 1 if starting as root):
git clone https://github.com/jimmyag2026-prog/review-agent.git ~/code/review-agent
cd ~/code/review-agent
bash install/bootstrap.sh                 # system deps
# → install hermes (see step 3)
# → write ~/.hermes/.env with Lark + OpenRouter creds (step 4)
hermes gateway install && hermes gateway start   # systemd service, survives reboot
bash install.sh                          # skill install
```

From your local machine, to view the dashboard:
```bash
ssh -L 8765:127.0.0.1:8765 user@your.vps.ip
# Then on the VPS: bash ~/.hermes/skills/productivity/review-agent/scripts/dashboard-web.sh
# On your local browser: http://127.0.0.1:8765
```

Full walkthrough below.

---

## Provider choice

Any $5-10/month Linux VPS works. Review-agent is lightweight (LLM calls go to OpenRouter, not local compute).

**Specs — minimum**:
- 1 vCPU · 1GB RAM · 10GB disk · Ubuntu 22.04 LTS
- ~$5/month at Hetzner / DigitalOcean / Linode / Vultr / any.

**Region**: any region with stable outbound HTTPS to OpenRouter and Lark websocket endpoints. US (east/west), EU, SG all fine.

**Avoid**: oversubscribed $2 "budget" providers — Lark websocket flakiness causes session drops.

---

## Step 1. Initial server setup (5 min)

If you SSH'd in as root, create a non-root user first. Don't run hermes as root.

```bash
# as root on the VPS:
adduser hermes-user              # choose a password
usermod -aG sudo hermes-user     # sudo rights (for bootstrap apt install)
mkdir -p /home/hermes-user/.ssh
cp ~/.ssh/authorized_keys /home/hermes-user/.ssh/
chown -R hermes-user:hermes-user /home/hermes-user/.ssh
chmod 700 /home/hermes-user/.ssh
chmod 600 /home/hermes-user/.ssh/authorized_keys

# lock down SSH: disable password auth, keep key-only
# /etc/ssh/sshd_config:
#   PasswordAuthentication no
#   PermitRootLogin no
systemctl reload ssh
```

Re-ssh as `hermes-user`. Everything below runs as this user (with `sudo` for system packages).

### Firewall (optional but recommended)

```bash
sudo ufw allow 22/tcp            # SSH
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable
```

**Do not** expose port 8765 (dashboard) publicly. It has no auth. Access via SSH tunnel only.

---

## Step 2. System dependencies (2 min)

```bash
cd ~
git clone https://github.com/jimmyag2026-prog/review-agent.git code/review-agent
cd code/review-agent
bash install/bootstrap.sh
```

This runs `sudo apt install` for: git, python3, python3-yaml, rsync, curl, poppler-utils, tesseract-ocr (+ chi_sim lang), ffmpeg. Also pip-installs whisper.

If anything fails (e.g. your VPS image is slim / missing repo), the script prints specific `apt install` lines you can run manually.

---

## Step 3. Install hermes (5 min)

Follow hermes' own install instructions: https://github.com/hermes-agent/hermes

Short version (verify on hermes repo for latest):

```bash
# install via hermes' official installer (uv-based)
curl -fsSL https://hermes.example.com/install.sh | bash   # placeholder — use hermes' real URL
hermes setup                     # interactive — creates ~/.hermes/
hermes status                    # verify
```

After install, hermes binary should be at `~/.local/bin/hermes`. Make sure this is in `$PATH`:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
hermes --version
```

### Systemd service for the gateway

Critical for VPS: you want the gateway to run 24/7 and restart on reboot.

```bash
hermes gateway install    # creates a systemd user unit at ~/.config/systemd/user/hermes-gateway.service
systemctl --user daemon-reload
systemctl --user enable --now hermes-gateway
loginctl enable-linger hermes-user     # keep user services alive after logout (IMPORTANT)
systemctl --user status hermes-gateway
```

**The `loginctl enable-linger` is critical** — without it, the gateway dies when you SSH-out of the session. With it, the gateway stays up across disconnects and reboots.

Verify by:
```bash
exit             # disconnect from VPS
sleep 60
ssh hermes-user@your.vps.ip
systemctl --user is-active hermes-gateway    # → active
```

---

## Step 4. Configure credentials (3 min)

Edit `~/.hermes/.env`:

```bash
cat >> ~/.hermes/.env <<'EOF'
FEISHU_APP_ID=cli_xxxxxxxxxxxxxxxx
FEISHU_APP_SECRET=xxxxxxxxxxxxxxxx
FEISHU_DOMAIN=lark
FEISHU_CONNECTION_MODE=websocket
OPENROUTER_API_KEY=sk-or-v1-xxxxxxxxxxxx
EOF
chmod 600 ~/.hermes/.env    # lock down — secrets
```

**Credential sources**:
- **FEISHU_APP_ID / SECRET**: https://open.larksuite.com/app — create a "Custom App", grant scopes: `im:message:send_as_bot`, `im:message`, `docx:document`, `drive:file`, `drive:drive`
- **OPENROUTER_API_KEY**: https://openrouter.ai/keys — start a new key, funds ≥$5

### Pair your personal Lark account with the bot

Restart gateway after .env change:

```bash
systemctl --user restart hermes-gateway
sleep 5
hermes pairing list              # empty initially
```

Now from your Lark mobile / desktop app:
1. Search for your bot (by the name you gave it in Lark app console)
2. DM it any message
3. Back on VPS:
```bash
hermes pairing list              # should now show a pending feishu pairing
hermes pairing approve <your_open_id>
```

---

## Step 5. Install review-agent (2 min)

```bash
cd ~/code/review-agent
bash install.sh                   # interactive — asks for your Lark open_id
systemctl --user restart hermes-gateway    # apply config.yaml patches
```

The installer:
- copies skill to `~/.hermes/skills/productivity/review-agent/`
- patches `~/.hermes/config.yaml` (feishu display = MINIMAL — no tool-progress leaks to Lark)
- prepends orchestrator SOP to `~/.hermes/memories/MEMORY.md`
- initializes `~/.review-agent/` with your Admin user
- runs `scripts/setup.sh`

### Customize your Responder profile

```bash
vim ~/.review-agent/users/<your_open_id>/profile.md
```

Write your actual standards. Pet peeves, decision style, time budget, things you always ask. 15 minutes of real work here — bad profile = generic reviews.

### Enroll your first Requester

Have the Requester DM your bot once so their open_id lands in `hermes pairing list`. Then:

```bash
bash ~/.hermes/skills/productivity/review-agent/scripts/add-requester.sh \
  <requester_open_id> --name "Name" --approve-pairing
```

---

## Step 6. Dashboard via SSH tunnel

The dashboard binds to `127.0.0.1:8765` only — safe default, no public exposure. To view from your laptop:

```bash
# on your LOCAL machine:
ssh -L 8765:127.0.0.1:8765 hermes-user@your.vps.ip
```

That command establishes a tunnel. Inside the SSH session, start the dashboard:

```bash
# on VPS (inside the SSH session):
bash ~/.hermes/skills/productivity/review-agent/scripts/dashboard-web.sh
```

Now open `http://127.0.0.1:8765` in your **local** browser. The request goes through the SSH tunnel to the VPS.

Dashboard auto-refreshes every 30 seconds. Kill with Ctrl+C when done.

### Want the dashboard always running?

Create a systemd user unit:

```bash
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/review-agent-dashboard.service <<'EOF'
[Unit]
Description=review-agent admin dashboard
After=network.target

[Service]
ExecStart=/bin/bash %h/.hermes/skills/productivity/review-agent/scripts/dashboard-web.sh
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now review-agent-dashboard
```

Then SSH-tunnel to `8765` whenever you want to check it.

---

## Logs and monitoring

### Where logs live

| What | Path | Rotation |
|---|---|---|
| hermes gateway | `~/.hermes/logs/gateway.log` | hermes-managed |
| hermes agent | `~/.hermes/logs/agent.log` | hermes-managed |
| review-agent delivery attempts | `~/.review-agent/logs/delivery.jsonl` | none — jsonl append |
| review-agent errors | `~/.review-agent/logs/errors.jsonl` | none |
| systemd (gateway service) | `journalctl --user -u hermes-gateway` | journal-managed |

### Useful tail commands

```bash
# watch gateway live (Lark inbound, reconnects)
journalctl --user -u hermes-gateway -f

# delivery failures
tail -f ~/.review-agent/logs/delivery.jsonl | jq 'select(.ok == false)'

# any error
grep -i ERROR ~/.hermes/logs/agent.log | tail
```

### Simple health monitoring

One-liner cron (runs every 15 min, alerts via Lark DM if gateway down):

```bash
crontab -e
```

Add:

```cron
*/15 * * * * systemctl --user is-active hermes-gateway >/dev/null || \
  curl -s -X POST https://open.larksuite.com/open-apis/im/v1/messages?receive_id_type=open_id \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(<your-cached-token>)" \
  -d '{"receive_id":"ou_YOUR_OID","msg_type":"text","content":"{\"text\":\"review-agent gateway DOWN on VPS\"}"}'
```

(For a cleaner version, add a small `scripts/health-check.sh` that handles token refresh — PR welcome.)

---

## Backup strategy

Critical paths:

```bash
# What to back up (these have your data; skill code is in git):
~/.review-agent/               # all sessions, users, annotations, summaries
~/.hermes/.env                 # credentials
~/.hermes/memories/            # MEMORY.md + USER.md
~/.hermes/config.yaml          # hermes config with review-agent patches
```

Minimal backup script (to local machine via scp):

```bash
# on your LOCAL machine, cron-able:
rsync -av --delete \
  hermes-user@your.vps.ip:~/.review-agent/ \
  ~/backups/review-agent/$(date +%Y-%m-%d)/
rsync -av \
  hermes-user@your.vps.ip:~/.hermes/.env \
  hermes-user@your.vps.ip:~/.hermes/config.yaml \
  hermes-user@your.vps.ip:~/.hermes/memories/ \
  ~/backups/hermes-config/$(date +%Y-%m-%d)/
```

For cloud backup: point the rsync target at a mounted S3 bucket, a Backblaze B2 rclone mount, or your own off-box storage.

---

## Updating review-agent

```bash
cd ~/code/review-agent
git fetch --tags
git checkout v1.1                  # or whatever new tag
bash install.sh                    # idempotent — only touches what changed
systemctl --user restart hermes-gateway
```

`install.sh` is built to be safe on upgrade:
- rsync overwrites skill files (fine — no user content in there)
- `.env` untouched
- config.yaml diffed against expected state; only changed if different
- MEMORY.md SOP re-inserted only if marker missing (idempotent)
- `~/.review-agent/` data untouched (users/, sessions/, logs/)

---

## Common VPS gotchas

**Gateway dies after SSH disconnect**
→ Missing `loginctl enable-linger hermes-user`. Without linger, user services are killed on logout.

**Lark websocket drops every ~8h**
→ Normal. Gateway auto-reconnects within 30s. If you see > 10-minute gaps in `journalctl`, check your VPS network quality.

**"tool_progress" text leaking to Lark DMs**
→ config.yaml patch didn't land or gateway wasn't restarted. Verify:
```bash
grep -A 4 'platforms:' ~/.hermes/config.yaml
# should show: feishu: {tool_progress: off, show_reasoning: false, ...}
systemctl --user restart hermes-gateway
```

**Gateway fails to start with "PID file race lost to another gateway instance"**
→ stale PID file from a previous run; process is dead but `~/.hermes/gateway.pid` wasn't cleared.
```bash
rm -f ~/.hermes/gateway.pid
systemctl --user reset-failed hermes-gateway
systemctl --user restart hermes-gateway
```

**Unauthorized users DM the bot but I get no notification**
→ See [docs/HERMES_FEISHU_HARDENING.md](HERMES_FEISHU_HARDENING.md) — apply the admin-notify patch (Layer 3) so you're DMed whenever a new user triggers pairing.

**Unauthorized users DM the bot and get no reply (silent drop) after I set an allowlist**
→ Add `feishu: { unauthorized_dm_behavior: pair }` to `~/.hermes/config.yaml` as a sub-block. Setting it at the top level does NOT work — hermes' lookup uses a per-platform key-exists check. See [HARDENING doc Layer 2](HERMES_FEISHU_HARDENING.md#layer-2--configyaml-pair-prompt-not-ignore).

**fail2ban drops SSH after rapid reconnects**
→ Multiple back-to-back `ssh`/`scp` trips your own VPS's fail2ban. Bundle commands into one SSH session (`ssh host -- 'cmd1 && cmd2'`) or wait for the ban window to clear (`until nc -z your.vps.ip 22; do sleep 5; done`).

**High RAM usage**
→ Normal is ~200-400MB. If > 1GB, check `~/.hermes/logs/` for runaway session files. Consider archiving old sessions:
```bash
tar czf ~/sessions-archive-$(date +%Y-%m).tar.gz ~/.review-agent/sessions/_closed
rm -rf ~/.review-agent/sessions/_closed/*
```

**"No space left on device"**
→ Session archives + logs accumulate. Add monthly cleanup to crontab:
```cron
0 2 1 * *  find ~/.review-agent/sessions/_closed -type d -mtime +90 -delete
0 2 1 * *  find ~/.hermes/logs -name '*.log.*' -mtime +30 -delete
```

**OpenRouter rate limits**
→ Sonnet 4.6 defaults to the paid tier. Top up at https://openrouter.ai/credits. A typical review cycle uses ~$0.05-0.15 in tokens.

---

## Security notes

- **Never** expose port 8765 publicly. SSH tunnel only.
- **Never** commit `~/.hermes/.env` — it has API keys.
- **File perms**: `chmod 600 ~/.hermes/.env` and `chmod 700 ~/.review-agent/` to prevent other users reading session content.
- **Lark app scopes**: grant only what's listed in INSTALL.md. Don't grant admin-level scopes.
- **OpenRouter key budget**: set a monthly cap in OpenRouter dashboard as circuit breaker.
- **Audit trail**: `~/.review-agent/logs/delivery.jsonl` keeps a record of every message sent out. Review periodically.

---

## Multi-user hardening (allowlist + pairing + admin notify)

If anyone in your Lark org can DM the bot, you'll want to restrict access. The default `FEISHU_ALLOW_ALL_USERS=true` is fine for solo use but open in any larger workspace. A three-layer hardening setup (allowlist env + `unauthorized_dm_behavior: pair` config + local hermes patch for admin-notify) is documented in [docs/HERMES_FEISHU_HARDENING.md](HERMES_FEISHU_HARDENING.md).

Short version:

```bash
# Layer 1: .env
cat >> ~/.hermes/.env <<'EOF'
FEISHU_ALLOW_ALL_USERS=false
FEISHU_ALLOWED_USERS=ou_aaaa,ou_bbbb
FEISHU_ADMIN_USERS=ou_aaaa
EOF

# Layer 2: config.yaml — feishu: block MUST use key-based form
python3 -c "
import yaml; p = '$HOME/.hermes/config.yaml'
c = yaml.safe_load(open(p)) or {}
c.setdefault('feishu', {})['unauthorized_dm_behavior'] = 'pair'
yaml.safe_dump(c, open(p,'w'), default_flow_style=False, sort_keys=False)
"

# Layer 3: patch hermes run.py for admin notify on pairing
python3 ~/code/review-agent/install/hermes_patches/admin_notify_patch.py \
  --run-py ~/.hermes/hermes-agent/gateway/run.py

systemctl --user restart hermes-gateway
```

The patch script is idempotent and marker-guarded, so `hermes update` overwriting `run.py` is recoverable by re-running it (add it to your post-update routine).

---

## Going from VPS to multi-instance / team

This doc assumes one Admin running one VPS. If you want to run review-agent for multiple Responders (different bosses, different teams), each needs their own instance today — v1.1 will add proper multi-Responder support. For now:

- Run one VPS per Responder (or use containers with isolated `$HOME`)
- Each instance has its own Lark bot app
- They don't share state

See [CONTRIBUTING.md](../CONTRIBUTING.md#v1x-roadmap) v1.1 section for the multi-Responder design.
