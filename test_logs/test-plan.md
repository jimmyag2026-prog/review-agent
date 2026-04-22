# Test plan — review-agent on Lark (hermes + openclaw)

## Smoke test already passed (in /tmp)

- `setup.sh` — initialized root, wrote profile/rules/delivery_targets/dashboard ✓
- `new-session.sh` — created session folder with correct structure ✓
- seeded realistic annotations (5 findings across 5 axes) ✓
- `close-session.sh` — generated summary.md with:
  - gate verdict READY_WITH_OPEN_ITEMS ✓
  - dissent surfaced correctly ✓
  - unresolvable → open items with A/B framing ✓
  - recommended agenda ≤3 ✓
  - local_path archive succeeded ✓
- `dashboard.sh --refresh` — built table ✓
- `list-reviewers.sh` / `list-sessions.sh` ✓

## End-to-end test — run manually (not auto-executed)

### Pre-requisites

- You have the briefer's Lark open_id (look at `~/.openclaw/credentials/feishu-default-allowFrom.json` or have them message your bot once to let openclaw discover them)
- You have your own Lark open_id (to receive the summary DM)
- openclaw gateway is running

### Step 0 — Install the skill into hermes

```bash
# Symlink (live change detection; remove easily)
mkdir -p ~/.hermes/skills/productivity
ln -sfn ~/review_agent_development/skill ~/.hermes/skills/productivity/review-agent

# Verify hermes sees it
hermes skills 2>&1 | grep -i review
```

### Step 1 — Setup root

```bash
bash ~/review_agent_development/skill/scripts/setup.sh \
  --name "Jimmy" \
  --lark-open-id "ou_YOUR_OWN_OPEN_ID"

# Then edit your preferences:
vim ~/.review-agent/profile/boss_profile.md
```

Minimum to edit in boss_profile.md:
- Fill `**Name**: Jimmy` (already pre-filled if passed --name)
- Write real "pet peeves" — the more specific the better the review
- Set `annotation_mode: sidecar-jsonl`
- List 2-3 "Things to ALWAYS ask" (these become global injected questions)

### Step 2 — Bind a briefer

Pick a test subordinate first. Can be a friend or yourself on a second Lark account.

```bash
bash ~/review_agent_development/skill/scripts/add-reviewer.sh \
  "ou_BRIEFER_OPEN_ID" \
  "Test Briefer Name"
```

This mutates `~/.openclaw/openclaw.json` (backup auto-saved) and restarts the gateway.

### Step 3 — Briefer sends first message

From the briefer's Lark account, DM your openclaw bot with a draft. Can be:
- Plain text ("I want to propose launching X on date Y, budget Z, ask is…")
- Paste of a markdown draft
- Attached PDF / image / voice (v0 may ask for text paste if OCR/STT backend missing)

### Step 4 — Observe

- Check `~/.review-agent/peers/<open_id>/sessions/` for the auto-created session folder
- Verify:
  - `input/` has the raw message
  - `normalized.md` was produced (or agent asked for text paste)
  - `annotations.jsonl` was populated on first scan
  - Agent's first IM reply was short, anchor-cited, one-finding-at-a-time
  - `conversation.jsonl` logging every turn

### Step 5 — Test interaction paths

From briefer side, test each response type:
- "OK" / "好" → status becomes `accepted`, advance cursor
- "不同意，因为 ..." → status becomes `rejected`, appears in `dissent.md`
- "改成 X" → status becomes `modified`
- "skip to s3" → cursor jumps
- Send a revised draft → round increments, new scan

### Step 6 — Test close paths

**Mutual**: after agent says `ready` (or you say "我觉得可以了"), briefer says "结束" → close triggered, summary sent to both parties per delivery_targets.

**Forced**: briefer says "不再修改了，立即结束" → agent asks for reason, briefer gives one, close proceeds with `termination: forced_by_briefer`.

### Step 7 — Verify delivery

- Boss's Lark DM should receive summary.md content as text (or truncated with pointer to local archive)
- Briefer's Lark DM should also receive summary (per default delivery_targets config)
- `~/.review-agent/sessions/_closed/2026-04/<session_id>/` should have all archived files
- `~/.review-agent/logs/delivery.jsonl` logs each attempt

### Step 8 — Dashboard pull check

```bash
bash ~/review_agent_development/skill/scripts/dashboard.sh --refresh
bash ~/review_agent_development/skill/scripts/dashboard.sh
```

Should list the closed session.

## Rollback

```bash
# Remove binding + workspace
bash ~/review_agent_development/skill/scripts/remove-reviewer.sh ou_BRIEFER_OPEN_ID
# Unlink skill from hermes
rm ~/.hermes/skills/productivity/review-agent
# Nuke root data (if desired)
rm -rf ~/.review-agent
```

## Known gaps in v0 (fix in v1)

- Input normalization: PDF / PPT / image / voice need external tools; v0 falls back to asking for text
- lark_doc and gdrive delivery backends not implemented
- Lark file attachments not sent (app lacks `im:resource:upload`); falls back to inline text
- Annotation emission via IM is described in AGENTS.md but requires the model to follow it — no hard enforcement
- Per-subtask routing (G5) currently uses "most recently active" heuristic when briefer doesn't `/new`; may misroute on topic switches

## What to observe in the test

Collect these for the lessons file:
1. Does the agent correctly split new subject vs continue existing?
2. Does the review style feel like coaching or like a checklist? (Target: hybrid)
3. Does dissent flow correctly without friction?
4. Is the summary actually useful to the boss? (If you'd still have to rewrite it → redesign)
5. Latency of first response (openclaw roundtrip + model)
6. Does gateway restart race with in-flight messages?
