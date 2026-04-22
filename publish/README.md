# review-agent

**Turn your boss's standards into an always-on review coach that trains subordinates' pre-meeting briefings to "signing-ready" quality — asynchronously, over IM, one subtask at a time.**

Theoretical backbone: the 1942 US Army *Completed Staff Work* doctrine — "the chief only signs yes or no; all the work has been done by staff." Modernized with BLUF, Amazon 6-pager quality bar, and Devil's-Advocate red-teaming.

## Why this exists

Every AI meeting tool in 2026 is built bottom-up: *give the receiver a pre-read*. None are built top-down: *train the briefer to meet the receiver's bar*. review-agent is the latter.

Typical failure mode without it:
> Subordinate: "I want to discuss X."
> Boss: *spends 20 min in meeting asking basic questions the subordinate should have answered in the doc.*
> Boss leaves meeting without the decision actually made.

With review-agent:
> Subordinate drafts, sends to review-agent over IM.
> review-agent scans seven axes, asks the questions the boss would ask, coaches revisions for up to 3 rounds.
> On close, boss receives a summary: what was accepted, what the subordinate disagreed with (and why), what genuinely requires meeting discussion.
> Meeting time drops to signing + real open items.

## Installation

```bash
git clone https://github.com/<your-org>/review-agent
cd review-agent

# Claude Code (personal)
ln -s "$(pwd)" ~/.claude/skills/review-agent

# Hermes
mkdir -p ~/.hermes/skills/productivity
ln -s "$(pwd)" ~/.hermes/skills/productivity/review-agent

# Other Agent Skills (agentskills.io) compatible agents:
# point them at SKILL.md — all logic is self-contained there
```

## Setup

```bash
# 1. Initialize
bash scripts/setup.sh --name "Your Name" --lark-open-id "ou_xxx_your_own"

# 2. Edit your preferences
vim ~/.review-agent/profile/boss_profile.md
# - write your pet peeves (specific ones)
# - set annotation_mode (sidecar-jsonl default)
# - list "things to ALWAYS ask" (global injected questions)

# 3. (Optional) configure delivery
vim ~/.review-agent/profile/delivery_targets.json
# - lark_dm to you (default if --lark-open-id passed)
# - add email_smtp if you want copies
# - add filters (e.g., only "funding" tagged sessions → email)

# 4. Bind a briefer
bash scripts/add-reviewer.sh "ou_briefer_open_id" "Display Name"
```

## Daily use

No CLI. The briefer just DMs your Lark bot. The review happens asynchronously in the Lark thread, conversation-driven, one finding at a time. When done:

- Boss + briefer both receive the summary in their configured targets
- Session folder is archived under `~/.review-agent/sessions/_closed/YYYY-MM/`
- Dashboard updates (`bash scripts/dashboard.sh` to view)

## Architecture (1 paragraph)

Three layers:
1. **Manager skill** (this repo) — setup, bind, list, close. Lives in your agent host (Claude Code / Hermes).
2. **Per-peer review agent** — one per briefer, bound to a Lark DM via openclaw gateway. Workspace contains the reviewer persona (`AGENTS.md`) and session state.
3. **Per-subtask session** — each new briefing subject creates an isolated folder under `peers/<open_id>/sessions/<id>/` with its own annotations, conversation, dissent log, and summary. Contexts don't cross.

## Seven review axes

1. **Ask Clarity (BLUF)** — first 3 lines state the decision requested
2. **Completeness** — ≥2 options, recommendation, reasoning
3. **Evidence Freshness** — sourced data, internal + external anchors
4. **Explicit Assumptions** — 3–5 with "if wrong then..."
5. **Red Team / Counterargs** — strongest opposing view + fallback
6. **Stakeholder Reality** — actual positions of affected parties
7. **Decision Readiness (CSW gate)** — boss only does yes/no

See [`references/checklist.md`](references/checklist.md) for pass/fail criteria per axis.

## Design invariants

- **Peer isolation**: no cross-briefer context
- **Subtask isolation**: each session has its own frozen profile + rules + context
- **No auto-drafting**: the briefer owns the final; the reviewer coaches but doesn't ship
- **No boss-burden**: never end a finding with "the boss should also look at X"
- **Dissent transparency**: rejected findings always surface in `dissent.md` and the boss summary
- **Pull-only mid-flight**: boss can view `dashboard.md` anytime but receives no push until close
- **Conversation-driven emission**: annotations are a JSONL batch but delivered to the briefer one at a time

## Compatibility

Works in any [Agent Skills](https://agentskills.io) host:
- Claude Code (tested)
- Hermes (tested — primary dev target)
- Cursor / Cline / Roo / Custom GPTs — paste SKILL.md body as system prompt

IM channels:
- Lark (Feishu international) — v0 via openclaw websocket + Lark Open API
- Telegram / WhatsApp / WeCom — v1 (same architecture, different channel binding)

## Configuration reference

| File | Purpose |
|---|---|
| `~/.review-agent/profile/boss_profile.md` | Boss's standards, pet peeves, language, thresholds |
| `~/.review-agent/profile/delivery_targets.json` | Where summaries go on close |
| `~/.review-agent/rules/review_rules.md` | Standing rules for the review agent (seven axes, emission style, round caps) |
| `~/.review-agent/peers/<open_id>/` | Per-briefer state |
| `~/.review-agent/peers/<open_id>/sessions/<id>/` | Per-subtask isolated session |
| `~/.review-agent/dashboard.md` | Pull-only view of all sessions |
| `~/.review-agent/logs/*.jsonl` | Delivery and error logs |

## Removal

```bash
bash scripts/remove-reviewer.sh ou_briefer_open_id
rm -rf ~/.review-agent  # if fully uninstalling
rm ~/.hermes/skills/productivity/review-agent
rm ~/.claude/skills/review-agent
```

## License

MIT.

## Acknowledgments

- **Completed Staff Work** (Col. Archer J. Lerch, 1942) — the quality bar.
- **Amazon 6-pager** — the narrative-brief discipline.
- **BLUF** — the lede test.
- **Devil's advocate architecture** (multi-agent AI pattern, 2024–2026) — independent critic context.
- **Anthropic Agent Skills** (agentskills.io) — the distribution standard.
- **memoirist-agent** — the per-peer openclaw binding pattern that made this architecturally cheap.
