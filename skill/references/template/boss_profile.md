# Boss Profile

> Filled by the boss at first-time setup (and edited anytime). Read by the review agent at the start of every session.

## Identity

- **Name**: <your name or alias, e.g., Jimmy>
- **Role**: <e.g., founder / CEO / investor — what seat do you sit in when reviewing>
- **Decision style**: <e.g., "data-first, skeptical of narratives without numbers"; "asymmetric bets only — anything inside mean is uninteresting"; "fast yes or fast no, never maybe">

## What you care about most in a brief

Rank 1 (most): <e.g., clarity of ask, founder-level ownership, real stakeholder positions>

Rank 2: ...

Rank 3: ...

## Pet peeves (auto-fail signals)

- <e.g., "consider" / "maybe" / "perhaps" in the ask>
- <e.g., presenting one option as if decision is already made>
- <e.g., no competitor context>
- <e.g., recommending something that costs me follow-up work>

## Your time budget for a brief

- **Max reading time**: <e.g., 20 minutes — anything longer than a 6-pager is a rewrite>
- **Meeting time per brief**: <e.g., 30 min — so brief quality gates at "can be actioned in 30 min">

## Language / tone

- Primary language for the review: <中文 / English / 双语>
- Tone: <e.g., "direct and critical, no softening; treat the briefer as a peer founder, not an employee">

## Annotation mode preference

One of:
- `sidecar-jsonl` (default; IM conversation + JSONL audit)
- `lark-doc` (v1; inline comments on a Lark document — requires the briefer to submit via Lark doc)
- `email-review` (v1; comments sent via email thread)

Value: `sidecar-jsonl`

## Seven-axis thresholds (optional overrides)

Leave blank to accept defaults from `review_rules.md`. Override if you have strong views:

- Axis 1 (BLUF): <default=BLOCKER; e.g., "make it a BLOCKER in all cases even for FYI briefs">
- Axis 3 (Evidence): <default=IMPROVEMENT; e.g., "escalate to BLOCKER if any number > 6mo stale">
- Axis 6 (Stakeholder): <default=IMPROVEMENT>

## Things to ALWAYS ask the briefer

Global questions the review agent should inject regardless of content, e.g.:
- "If this fails publicly, what's the narrative?"
- "Who on the team disagrees with this, and why?"
- "What's the smallest version that could be tested in a week?"

## Things to NEVER ask

- <e.g., "why do you think this is a good idea?" — too vague, waste of breath>

## Briefers I review (for manager's memory, not mandatory)

| Open ID | Name / Role | Typical subjects | Notes |
|---|---|---|---|
| <open_id> | <name> | <subjects they usually brief> | <notes> |

## Delivery of summary (where does the final summary go)

See `delivery_targets.json` for machine-readable config.

Narrative version: <e.g., "I want the summary in Lark DM to me when any session closes; for major funding briefs also email me a copy at admin@example.com">
