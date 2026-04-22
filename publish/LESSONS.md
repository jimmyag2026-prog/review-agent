# Lessons & skill-design notes — review-agent

> Abstracted for the wider Agent Skills community. If you're building a similar "boss-proxy coach" skill, steal what's useful.

## What's generalizable

### 1. "Boss-proxy coach" is a new skill category

Most AI skills fall into two buckets:
- **Worker skills** (do something for me): deploy, fix, summarize, search
- **Context skills** (give me background): domain knowledge, API conventions

"**Proxy coach**" is a third pattern: the skill *embodies a specific person's standards* and trains *someone else*'s output against those standards. The skill is neither the boss nor the subordinate — it's a transparent overlay on the subordinate's IM session that the boss pre-programmed.

Other uses of the pattern: editor training junior reporters, PM coaching designers, investor training portcos' pre-meeting prep.

### 2. Completed Staff Work is an underused AI frame

CSW (1942) is the best-known precursor to "signing-ready" deliverables, yet almost no AI product has been built around it in 2026. Most AI "pre-meeting" tools do bottom-up info aggregation for receivers (read.ai, Fellow, Monday Briefing). CSW inverts: the *sender* must do all the work, and the AI enforces that bar. This is a wide-open design direction.

### 3. Hybrid emission beats pure Socratic or pure punch-list

Pure Socratic = "coaching conversation" that feels good but wastes rounds on obvious gaps.
Pure punch-list = "critic report" that closes loops fast but the briefer learns nothing and resents the feedback.

The rule that worked:
- **Structural axes (BLUF, Completeness, Assumptions, Decision Readiness)** → punch-list, direct
- **Evidential/adversarial axes (Evidence, Red Team, Stakeholder)** → Socratic, question-first
- **Cosmetic findings** → batch silently into JSONL, don't burn conversation turns

### 4. Conversation-driven annotation emission (batch + cursor)

Generate all annotations up front in a JSONL batch (audit trail, programmatic closability), but **emit to IM one at a time** via a cursor file. This gets the best of both:
- Reviewer does full scan once (so context is coherent)
- Briefer sees a conversation, not a wall

The cursor file (`{current_id, pending, done}`) is 3 fields but unlocks: skip/jump, batch-accept, re-scan on new round. Don't skip it.

### 5. Dissent transparency > reviewer veto

Early instinct: if briefer rejects too many findings, escalate / flag as "stubborn".
Better instinct: briefers are often right locally; reviewer doesn't have all the context. Let rejections pass silently *at the IM level* but **surface every rejection in the boss summary with the briefer's reason**. Boss decides in the meeting; reviewer doesn't.

This simple rule eliminates a whole class of friction and aligns the skill with how humans actually review.

### 6. Per-subtask isolation via subfolder (not per-peer)

The obvious memoirist-style pattern is one agent per peer. But a real briefer has multiple concurrent subjects ("funding deck" ≠ "Q3 roadmap" ≠ "hiring JD review"). Folding them into one session cross-contaminates context.

The fix: **per-peer binding, per-subtask folder**. One openclaw agent per briefer (cheap to bind), but inside the workspace each `sessions/<id>/` is a self-contained micro-project with its own frozen profile, rules, annotations, and conversation. Agent loads only the current session folder per turn.

### 7. Dashboard pull-only beats push for the boss

Initial design pushed progress updates to the boss. Users reject this immediately — the whole point of delegating review is not having to watch it. So: mid-flight = pull-only file; close = single push.

This also enables the async rhythm: briefer chats with reviewer all day, boss reads dashboards on their schedule, meeting convenes only with ready material.

### 8. Delivery targets as config, not code

Letting the boss point summaries at any combination of (Lark DM / email / local archive / Gdrive / future Lark Doc) through a JSON config turned out to be one of the most impactful abstractions. It makes the skill work across teams with very different tooling preferences without forking.

Filter predicates (`tags_any`, `termination`) let important briefs escalate to email while routine ones stay in IM — this matches how humans actually triage.

## Anti-patterns we avoided

- **Reviewer finalizes the brief**: violates CSW ("don't do the subordinate's work"). Reviewer emits findings; briefer ships.
- **Reviewer messages the boss mid-flight**: breaks the delegation contract. Pull-only until close.
- **"Needs to be more complete" findings**: banned. Every finding must cite anchor + give concrete suggestion with verb-first form.
- **Unlimited rounds**: lets perfectionism poison velocity. Hard cap at 3 (with briefer opt-in for 2 more).
- **Hard-coded boss name**: portability killer. Read from owner.json per session.
- **Same model for main agent and reviewer without fork**: reviewer becomes sycophantic because it sees main context. Use `context: fork` or binding isolation.

## Things I'd change for v1

1. **Input normalization is the biggest gap**. PDF/PPT/image/voice all fall back to "please paste text" in v0. A built-in normalizer subagent that produces `normalized.md` from any input would close this.
2. **Annotation mode `lark-doc`**: many teams already live in Lark docs. Emitting annotations as Lark doc comments (instead of IM conversation) is a much better fit for formal briefs.
3. **Multi-boss matrix**: v0 is one boss. A board member or advisor using the same instance for multiple principals needs boss_id namespacing.
4. **Subtask routing**: currently uses last-active heuristic. An LLM classifier on first-message content would route better.
5. **Reviewer model override per session**: some briefs (e.g., legal/compliance) want a different reviewer persona or a stronger model. Support `session.model` override.

## Open research

- Does the review-agent converge faster or slower than human pre-review? (Hypothesis: faster on structural axes, similar on judgment axes.)
- Does boss-perceived meeting quality improve? Measurable via post-meeting survey.
- How many rounds does the average session take? If < 2, the gate is too loose; if > 3, the briefer isn't being trained properly.

## Checklist for anyone building a similar proxy-coach skill

- [ ] Identify a well-codified doctrine (CSW, BLUF, etc.) — don't freelance the review criteria
- [ ] Separate the *content* checklist from the *emission style* rules
- [ ] Use hybrid emission (direct for structural, Socratic for evidential)
- [ ] Batch annotations + cursor for conversation-driven delivery
- [ ] Make dissent transparent, not blocked
- [ ] Per-subtask folder, not per-peer session
- [ ] Pull-only dashboard for the principal; single push on close
- [ ] Delivery backends as config, not code
- [ ] Explicit termination modes (mutual vs forced) — always log forced reason
- [ ] Round cap with escape hatch
- [ ] owner.json pattern — never hard-code identity
