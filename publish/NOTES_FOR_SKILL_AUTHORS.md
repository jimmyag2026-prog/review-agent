# Notes for Skill Authors — abstracted "注意事项" / gotchas

> If you're building a skill in the review-agent family (proxy coach, pre-meeting review, IM-driven workflow), read this before you start.

## SKILL.md conventions that bit us

1. **Description field is truncated at 1536 chars** combined with `when_to_use`. Put the trigger phrase early.
2. **Frontmatter `allowed-tools` only pre-approves — doesn't restrict**. To actually lock a skill down, use `deny` rules in settings.
3. **SKILL.md body stays resident for the whole session** once invoked. Don't put session-specific state in the body.
4. **`context: fork` isolates cleanly but blinds the fork to your main conversation**. Pass needed info via `$ARGUMENTS` or bundled references.
5. **`${CLAUDE_SKILL_DIR}` is essential for portability**. Hardcoding `~/review_agent_development/` works on your laptop and nowhere else.

## Openclaw gateway gotchas (if you're building on it)

1. **`openclaw message send` doesn't support feishu** — you must call Lark Open API directly. `send-lark.sh` in this repo is a working reference.
2. **Lark app permission `im:resource:upload` is separately approved** and often absent. Test file send early or design around inline-text payloads.
3. **`openclaw.json` is shared prod config**. Back up before every mutation. Our `add-reviewer.sh` does `cp $OC_CFG $OC_CFG.bak.review-<ts>`.
4. **`openclaw gateway restart` takes a few seconds and briefly drops incoming messages**. Don't restart on every binding — batch changes if you're adding many peers.
5. **Telegram/WhatsApp built-in channels don't support dynamic agents** (no routing hook). Lark/WeCom do. If your skill needs per-peer agents on Telegram, you script binding + restart.
6. **Sessions rotate as `.jsonl.reset.<ts>.Z`** (per memory). If you parse historical sessions, include both current and rotated archives.

## macOS / local gotchas

1. **TCC blocks ~/Desktop even from cron**. If the skill writes or reads from Desktop-adjacent dirs, use osascript + Finder workaround.
2. **cron on macOS doesn't inherit PATH or Keychain access**. Export PATH explicitly in any cron-invoked script, and don't rely on Keychain.
3. **`iconv` on macOS is BSD not GNU** — the `//TRANSLIT` flag works but with different behavior. Slug generation in `new-session.sh` uses `iconv -c` which is portable.

## Review-agent-specific gotchas

1. **Briefer may submit draft in any format**. v0 relies on briefer pasting text if tooling for PDF/OCR/STT isn't installed. Make the fallback path graceful in the IM reply.
2. **"Boss" and "briefer" both being Lark open_ids on the same tenant is easy**. Cross-tenant boss+briefer requires different apps.
3. **Annotation `text_hash` anchors break if briefer rewrites whole paragraphs**. Round 2+ scan should not try to match against old hashes — just re-scan fresh.
4. **Cursor file can desync if both sides race**. Lock or single-threaded-per-session is simpler than CAS on cursor.json.
5. **"结束" or "不再修改了" as force-close triggers in Chinese**. Multilingual briefers will say it different ways. Reviewer agent's classifier in AGENTS.md lists several; extend for your team's languages.
6. **Forced close with no reason = don't close**. Always require the one-line reason before archiving.
7. **dissent.md is boss-visible; briefer knows this**. If the briefer is worried about appearing combative, they'll auto-accept instead of rejecting. Frame "dissent" as signal, not judgment.

## Model behavior notes

1. **Without `context: fork`, reviewer becomes sycophantic** because it sees main conversation history. Always fork.
2. **LLMs love to add "nice-to-have" findings**. Enforce the ≤5 per round cap in AGENTS.md or they'll dump 20.
3. **Chinese prompts + English technical terms mix fine**. We use Chinese for persona/style directives and English for schema keys.
4. **"BLUF" as a term is sometimes lost** on non-military models. Write it once + definition, don't assume.
5. **Model tends to restate the draft in its reply** — waste of tokens. Instruct explicitly: cite the snippet, don't paraphrase.

## Testing gotchas

1. **Smoke test in `REVIEW_AGENT_ROOT=/tmp/...`** to avoid polluting your real state. Our scripts respect the env var.
2. **End-to-end on Lark requires real openclaw.json mutation**. Don't auto-run — let the user trigger.
3. **Use a test peer (friend / second Lark account)** rather than yourself to validate routing.
4. **Force-close path is easy to forget in tests** — specifically test "briefer sends 不再修改了" flow.
5. **Check `~/.review-agent/logs/delivery.jsonl`** after every close — silent delivery failures are the #1 production issue.

## Publishing checklist

- [ ] SKILL.md description contains trigger keywords (`review`, `briefing`, `pre-meeting`, `boss`)
- [ ] All paths use `${CLAUDE_SKILL_DIR}` or relative/arg-passed
- [ ] No hardcoded owner name — use `owner.json`
- [ ] Backup → mutate → verify for any config file mutation
- [ ] Logs go to `~/.review-agent/logs/`, not stdout (stdout goes to the briefer in IM)
- [ ] README.md has setup + rollback in ≤5 commands each
- [ ] Explicit v0 vs v1 feature matrix so users don't hit "not implemented" surprises
