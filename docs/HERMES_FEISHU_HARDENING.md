# Hermes Feishu Hardening — Allowlist + Pairing Flow + Admin Notify

> **Who this is for**: multi-user VPS deployments where you want to restrict which Lark users can interact with the bot, give unpaired users a clean "please contact admin" path, and notify the Admin whenever someone tries to pair.
>
> **Not needed for**: single-user setups (Admin == Responder == Requester, all the same person). There `FEISHU_ALLOW_ALL_USERS=true` is fine.

## Threat model

Hermes bots are DMable by anyone in your Lark org who can find the bot. Without hardening:

- Any colleague can start chatting with your agent (spending your OpenRouter credits and polluting `~/.hermes/logs/`)
- Unapproved users silently pair with hermes unless you check `hermes pairing list` regularly
- No notification when someone new hits your bot — you only find out by grepping logs

The three-layer setup below fixes all three.

---

## The three layers (what each does)

| Layer | File | Purpose |
|---|---|---|
| **1 · env** | `~/.hermes/.env` | declares who's allowed + who's Admin |
| **2 · config** | `~/.hermes/config.yaml` | tells gateway to pair-prompt on unauthorized DM (not ignore) |
| **3 · code patch** | `gateway/run.py` | adds Admin-notify hook after pairing code is sent |

Layers 1 + 2 are plain config. Layer 3 is a **local patch** of hermes' upstream source — needed because hermes has no built-in Admin notify today. The patcher is idempotent and marker-guarded, so `hermes update` overwriting `run.py` is recoverable by re-running it.

---

## Layer 1 — `.env` (allowlist + Admin list)

Edit `~/.hermes/.env`:

```bash
# Enforce allowlist (default: everyone allowed)
FEISHU_ALLOW_ALL_USERS=false

# Comma-separated Lark open_ids that may DM the bot
FEISHU_ALLOWED_USERS=ou_aaaa,ou_bbbb

# Comma-separated Lark open_ids to notify when a new user tries to pair
# (usually just you, the Admin)
FEISHU_ADMIN_USERS=ou_aaaa
```

**Get your `open_id`**: DM the bot once while `FEISHU_ALLOW_ALL_USERS=true`, then run `hermes pairing list`.

Then restart:

```bash
systemctl --user restart hermes-gateway
```

---

## Layer 2 — `config.yaml` (pair-prompt, not ignore)

Without this layer, setting the allowlist causes hermes to silently drop unauthorized DMs (`ignore`). Users get no feedback. You want `pair` so unauthorized users see the pairing code and can forward it to you for approval.

Add to `~/.hermes/config.yaml`:

```yaml
feishu:
  unauthorized_dm_behavior: pair
```

### ⚠ Why the value-setting form does NOT work

Hermes' lookup logic in `gateway/run.py::_get_unauthorized_dm_behavior` has a subtle fallback:

1. Per-platform extra dict **key-exists** → use that value. ✓
2. Global config **value != "pair"** → use that. (Default is already `"pair"`, so this branch does nothing.)
3. Fallback: **any allowlist non-empty → return `"ignore"`**.

Setting `unauthorized_dm_behavior: pair` at the top level hits branch 2's check, which is `!= "pair"` — so it never takes effect and you drop through to the allowlist-ignore fallback. **You must use the `feishu:` per-platform key form shown above.**

### Verify

```bash
grep -A 1 '^feishu:' ~/.hermes/config.yaml
# should include:
#   unauthorized_dm_behavior: pair

systemctl --user restart hermes-gateway
```

From an account NOT in `FEISHU_ALLOWED_USERS`, DM the bot. You should see a pairing code reply instead of silence.

---

## Layer 3 — Admin-notify patch

Without this, an unauthorized user sees the pairing code on their end, but you have no way of knowing they tried unless you check `hermes pairing list`. The patch adds a best-effort hook right after the pairing code is sent: it DMs each `FEISHU_ADMIN_USERS` open_id with the pairing info.

The patcher lives at `install/hermes_patches/admin_notify_patch.py`. It:

- Backs up `gateway/run.py` → `run.py.pre_admin_patch`
- Checks for marker `_notify_pairing_admins`; if present, exits 0 (idempotent)
- Inserts the helper + hook call in the right spot
- Tolerates being re-run after a `hermes update` overwrites `run.py`

### Apply

```bash
# on VPS, assuming hermes-agent is cloned at ~/.hermes/hermes-agent/
python3 ~/code/review-agent/install/hermes_patches/admin_notify_patch.py \
  --run-py ~/.hermes/hermes-agent/gateway/run.py
systemctl --user restart hermes-gateway
```

### How the hook works

In `FeishuAdapter.send(chat_id, content)`, hermes writes `receive_id_type="chat_id"` by its own nature — so there's no high-level API to proactively DM an open_id. The hook bypasses the adapter wrapper and calls the underlying Feishu SDK directly:

```python
body = adapter._build_create_message_body(
    receive_id=admin_open_id, msg_type="text",
    content=json.dumps({"text": text}, ensure_ascii=False),
    uuid_value=str(uuid.uuid4()),
)
req = adapter._build_create_message_request("open_id", body)
await asyncio.to_thread(adapter._client.im.v1.message.create, req)
```

Wrapped in `try/except` — a failed notify never breaks the main pairing flow.

### Test

```bash
# From another Lark account (not in allowlist), DM the bot
# You (Admin) should see within ~1-2s:
#   "[hermes] Pairing requested by open_id=ou_xxxx, code=123456 (source=feishu)"
```

---

## Operational gotchas we've hit

### "PID file race lost to another gateway instance"

Gateway refuses to start. `~/.hermes/gateway.pid` has a stale PID; new process sees the file and bails.

```bash
rm -f ~/.hermes/gateway.pid
systemctl --user reset-failed hermes-gateway
systemctl --user restart hermes-gateway
```

### `fail2ban` drops SSH after rapid reconnects

Doing a lot of `ssh`/`scp` in a short window → connection refused. Not a service issue — you tripped fail2ban on your own VPS.

- Consolidate multiple commands into a single `ssh host -- 'cmd1 && cmd2 && cmd3'`
- Wait it out: `until nc -z your.vps.ip 22; do sleep 5; done`

### `hermes update` overwrites the patch

Because `gateway/run.py` lives inside the hermes-agent repo (`origin = NousResearch/hermes-agent`), any upstream pull replaces our patched file.

Our countermeasure is the idempotent patch script:
- Detects marker `_notify_pairing_admins`; re-applies only if missing
- Always backs up to `run.py.pre_admin_patch.<timestamp>`
- Safe to run as a post-update hook:

```bash
# add to your VPS update routine:
hermes update
python3 ~/code/review-agent/install/hermes_patches/admin_notify_patch.py \
  --run-py ~/.hermes/hermes-agent/gateway/run.py
systemctl --user restart hermes-gateway
```

---

## Quick sanity audit

After everything is applied, from the VPS:

```bash
# Layer 1
grep -E '^FEISHU_(ALLOW_ALL_USERS|ALLOWED_USERS|ADMIN_USERS)=' ~/.hermes/.env

# Layer 2
grep -A 2 '^feishu:' ~/.hermes/config.yaml | grep unauthorized_dm_behavior

# Layer 3
grep -l _notify_pairing_admins ~/.hermes/hermes-agent/gateway/run.py \
  && echo "patch applied" \
  || echo "patch missing — re-run admin_notify_patch.py"

# Runtime
systemctl --user is-active hermes-gateway
```

All four should be affirmative.

---

## When to skip this guide

- **Solo use** (you're both Admin and Responder, nobody else DMs the bot): keep `FEISHU_ALLOW_ALL_USERS=true`, skip all three layers.
- **Closed team of ≤3 where everyone already knows to `hermes pairing list`**: Layer 1 is enough.
- **You don't control the hermes-agent source checkout** (e.g. someone else runs it for you): you can ask them to apply Layer 3, or stop at Layer 2 — you'll just need to poll `hermes pairing list` yourself.
