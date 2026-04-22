# review-agent v1.0 · launch post

Three formats for different channels. Pick and adapt.

---

## A · Tweet / X (280 chars)

```
Shipped v1.0: review-agent — an async pre-meeting review coach built on the 1942 Completed Staff Work doctrine.

Most 2026 AI meeting tools go bottom-up (pre-read for receiver). This goes top-down — trains the briefer before the meeting is even scheduled.

github.com/jimmyag2026-prog/review-agent
```

## B · Short post (LinkedIn / Medium / X long-form) · ~300 words

---

**Shipped v1.0 of review-agent — an async pre-meeting review coach.**

Most 2026 AI meeting tools solve the receiver's problem: give them a pre-read so they don't walk in cold. Fellow, read.ai, Monday Briefing — all bottom-up.

But the real waste isn't receiver-side. It's the meeting where the briefer hasn't done their thinking, and the boss spends 20 minutes asking questions the briefer should have answered in the doc.

review-agent inverts the frame. **It trains the briefer to meet the receiver's bar — before the meeting is even on the calendar.**

Rooted in the 1942 US Army doctrine of Completed Staff Work: *"the chief only signs yes or no; all the work has been done by staff."* Forgotten by most of the AI industry.

Concretely:
- Subordinate DMs a Lark bot with their draft
- Agent scans across 6 dimensions (data / logic / feasibility / stakeholders / risk / ROI)
- Role-plays the specific boss using their profile and standards — surfaces the questions that boss would actually ask
- Walks the subordinate through Q&A, one issue at a time, until the material is signing-ready
- Delivers a 6-section decision brief to the boss with what was addressed, what the subordinate disagreed with, and what's genuinely open

**The agent is a challenger, not a summarizer.** It never writes answers. It only asks questions and points out problems. The subordinate does the work — which is the whole point.

Built on **hermes** + **Lark** (native docx API for inline callouts + IM Q&A loop) + **OpenRouter** (Sonnet 4.6 for reasoning). One-command install on any bare VPS.

Open source (MIT): **github.com/jimmyag2026-prog/review-agent**

Works for: founders training direct reports, PMs coaching designers, editors training junior writers, investors training portco CEOs, anyone who spends time in meetings that should have been decisions.

---

## C · DM / email to founders (~500 words, conversational)

Subject: Built a thing — async pre-meeting review for CSW-grade briefings

---

Hey [name],

Quick share: I shipped v1.0 of something I've been building the last two weeks.

**Problem I kept seeing**: I'd meet with people (portcos, team leads, friends) and they'd come with a document or a pitch, and 20 minutes into the conversation I'm asking the same questions they should have anticipated and answered before the meeting. Not because they're not smart — because nobody pre-critiqued their material at the bar I'd apply.

I looked at what AI meeting tools exist in 2026. All of them are receiver-side: give Jimmy a pre-read so he's ready. None of them are briefer-side: train the person preparing to meet Jimmy's bar *before* the meeting happens.

So I built review-agent. It inverts the usual frame.

**How it works**:
1. A subordinate DMs a Lark bot with their draft (could be markdown, a Lark doc link, a PDF, a voice note).
2. The agent runs the draft through six dimensions of challenge: data integrity, logical consistency, plan feasibility, stakeholder voices, risk assessment, ROI clarity.
3. **Crucially**: it also role-plays the specific Responder — loads their profile.md (pet peeves, decision style, what they always ask) and simulates "what would this person's top 5 questions be?"
4. Walks the subordinate through the findings one at a time in DM. Requester can accept / reject with reason / modify / pass / custom reply. All dissent is logged transparently.
5. On close, delivers a 6-section decision brief to the Responder: one-line summary, key data highlighted, what was debated, open items with A/B framing, recommended time allocation, blind spots the agent still sees.

**The agent is a challenger, not a summarizer.** It never writes the answer. It only asks. The subordinate does the work — which is the entire point of CSW.

Technically: hermes (native Lark gateway) + OpenRouter (Sonnet 4.6 for reasoning) + ~30 scripts orchestrating a pipeline with per-session isolation and idempotent installs. Runs on any fresh Ubuntu VPS in about 15 minutes. Local admin dashboard at http://127.0.0.1:8765.

**Repo** (MIT, public): github.com/jimmyag2026-prog/review-agent

I think this maps onto a few of your patterns — happy to walk through any part of the design or help you spin one up for your team. The four-pillar + simulation setup is generalizable beyond meeting prep (hiring memos, investment decisions, technical RFC reviews).

What I'd love from you: pushback on the framework, or a stress test against a use case that would break it.

— [Your name]

---

## Talking points if someone asks

**"Why not just use ChatGPT / Claude directly?"**
→ General LLMs don't enforce CSW structure. Without structure, the Requester gets "here are 20 things you could improve" and drowns. Four-pillar + auto-scope top-3 + single-finding emission is designed so the Requester can actually process and iterate. Also: general LLMs don't role-play *your specific* boss.

**"Does it work for remote async teams?"**
→ That's the primary use case. The Requester and Responder might be in different time zones; the bot mediates. Responder only gets pinged on close.

**"What about privacy?"**
→ Material flows to OpenRouter for LLM calls. If that's an issue, swap the OPENROUTER_API_KEY for a local model endpoint — the scripts treat any OpenAI-compatible API the same.

**"How do you handle multi-team / multi-boss?"**
→ v1.0 is single-Responder. v1.1 adds multi-Responder with proper namespacing.

**"What if the subordinate pushes back?"**
→ They can. Dissent is first-class — rejected findings go into a dissent log with reasons, and show up in the Responder's summary. The agent doesn't veto. The Responder decides in the meeting.

**"What does the Responder's setup look like?"**
→ Writes a profile.md once (~15 min of real work): pet peeves, decision style, time budget, questions they always ask. This is what the agent role-plays against. Bad profile = generic reviews. Good profile = uncannily specific reviews.
