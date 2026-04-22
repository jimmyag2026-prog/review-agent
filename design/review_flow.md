# Review Flow Design (authoritative, v0)

Each review = one independent session, isolated context. Lifecycle below is what the agent executes on each inbound message.

## 0. Inputs loaded at session boundary (frozen)

When a new session is created, these files are **copied** into `sessions/<id>/` so the session's standards don't shift mid-review even if the Admin edits them globally:

| Source (live) | Frozen session copy | What it provides |
|---|---|---|
| `~/.review-agent/admin_style.md` | `sessions/<id>/admin_style.md` | Admin's preferences about **how the agent behaves**: language mirroring rule, tone, message pacing, formatting, emoji policy, when to escalate vs drop, length caps |
| `~/.review-agent/rules/review_rules.md` | `sessions/<id>/review_rules.md` | Shared review protocol: 7 axes, round caps, dissent handling, gate criteria |
| `~/.review-agent/users/<responder>/profile.md` | `sessions/<id>/profile.md` | This Responder's content standards: pet peeves, axis thresholds, always-ask questions, delivery preferences |
| Requester's first message(s) | `sessions/<id>/input/<ts>_*.<ext>` + normalized → `normalized.md` | What they want reviewed and what they've sent |
| Optional | `sessions/<id>/review_criteria.md` | Session-specific override (e.g., "this is a funding brief, apply major-brief thresholds") |

Admin/Responder edits to live files take effect on the **next** session only. In-flight sessions are stable.

## 1. Stages of a session

```
┌─────────────────┐
│ INTAKE          │ 0a. Incoming message identified as review-triggerable (DM or group @-mention with intent)
│                 │ 0b. Resolve sender → user meta.json → Responder → session folder (create if new)
│                 │ 0c. Freeze configs, save input, normalize → normalized.md
└────────┬────────┘
         │
┌────────▼────────┐
│ SUBJECT         │ 1.5a. ingest.py → normalized.md (multi-modal: md/pdf/image/audio/
│ CONFIRMATION    │       Lark-wiki/Gdocs)
│                 │ 1.5b. confirm-topic.py (OpenRouter + persona) → generate 2-4 candidate
│                 │       single-decision topics; send to Requester via Lark.
│                 │ 1.5c. WAIT for Requester's confirmation ("b" / "都不是, ..." / etc.)
│                 │ 1.5d. Do NOT scan yet. Alignment first.
└────────┬────────┘
         │
┌────────▼────────┐
│ FOUR-PILLAR +   │ 2a. Read admin_style + review_rules + profile + normalized.md
│ RESPONDER SIM   │ 2b. Layer A: four-pillar scan (Background/Materials/Framework/Intent)
│                 │     → annotations.jsonl entries with source="four_pillar_scan"
│                 │ 2c. Layer B: responder simulation (role-play {responder_name} using
│                 │     profile.md) → top 5 questions → more entries, source="responder_simulation"
│                 │ 2d. Merge into annotations.jsonl (BLOCKER/IMPROVEMENT/NICE)
│                 │ 2e. Set cursor.json: first BLOCKER → current, rest → pending
│                 │ 2f. If input is below minimal brief form → reply PREMATURE_INPUT,
│                 │     request context+ask+constraint, mark session awaiting_basics
└────────┬────────┘
         │
┌────────▼────────┐
│ Q&A LOOP        │ 3a. Emit current finding to Requester via Lark (DM or group) as one message:
│                 │     - Intent / Background BLOCKER → direct ("这句改成X")
│                 │     - Materials / Framework → Socratic ("如果A失败，fallback是什么？")
│                 │     - Responder Simulation findings → Socratic (已是问题形式)
│                 │     - Include anchor snippet so Requester knows what's being discussed
│                 │ 3b. Requester replies. Classify intent:
│                 │     - accepted | rejected+reason | modified | question | skip | force-close
│                 │ 3c. Update annotation status; rejected → append to dissent.md; advance cursor
│                 │ 3d. If pending empty AND CSW gate met → propose ready; wait for confirm
│                 │ 3e. If round N completes and Requester sends a new draft → re-scan with round+1
│                 │ 3f. Hard cap after 3 rounds (5 with explicit request); remaining BLOCKERs
│                 │     → status=unresolvable with reason "max rounds"
└────────┬────────┘
         │
┌────────▼────────┐
│ DOCUMENT MERGE  │ 3a. (If agent has doc-editing permission AND Responder profile allows)
│  (conditional)  │     → produce revised draft: sessions/<id>/final/revised.md
│                 │     → show unified diff to Requester; Requester confirms/edits
│                 │ 3b. (If agent does NOT have doc-editing permission)
│                 │     → Requester uploads their own revised draft to final/<filename>
│                 │     OR says "keep current draft + accepted annotations as final"
└────────┬────────┘
         │
┌────────▼────────┐
│ FINAL GATE      │ 4a. Re-scan final/<primary> against the frozen profile (7 axes)
│                 │ 4b. Verify: no open BLOCKER remains except explicit unresolvable entries
│                 │ 4c. Produce gate_verdict: READY | READY_WITH_OPEN_ITEMS | FORCED_PARTIAL | FAIL
│                 │ 4d. If FAIL (unexpected regression) → NOT auto-close; alert Requester with
│                 │     specific axes that regressed; back to Q&A loop
└────────┬────────┘
         │
┌────────▼────────┐
│ CLOSE + FORWARD │ 5a. scripts/close-session.sh <session_id> [--termination mutual|forced_by_briefer]
│                 │ 5b. Build summary.md (includes: gate verdict, accepted, dissent,
│                 │     open items with A/B framing, recommended agenda ≤3)
│                 │ 5c. Run deliver.sh:
│                 │     - Local archive (always)
│                 │     - Lark DM summary to Responder (forward)
│                 │     - Lark DM summary to Requester (their copy)
│                 │     - Optional: post to originating group chat (if trigger was B' group mention)
│                 │     - Optional: email for tagged briefs (funding/board)
│                 │ 5d. Update dashboard.md. Move session into sessions/_closed/YYYY-MM/
└─────────────────┘
```

## 2. Document editing permission matrix

`admin_style.md` declares the global default; `profile.md` can override per-Responder; session start may override per-subject.

| Permission value | What the agent does with docs |
|---|---|
| `none` | Read-only. Feedback as annotations/messages. Requester owns all edits. (CSW-pure) |
| `suggest` (default) | Agent produces `final/revised.md` as a SUGGESTED rewrite. Requester accepts, modifies, or rejects the whole thing. Original preserved in `input/`. |
| `direct` | Agent edits shared doc in place (Lark Doc / Google Doc via API). Requires corresponding API creds. v1 only. |

For v0, `suggest` is the ceiling. Lark-doc / Gdrive direct-edit is v1.

## 3. Final-gate verification (step 4)

Implementation: `scripts/final-gate.py <session_dir>` — aggregates annotations by **pillar** (Background / Materials / Framework / Intent), returns JSON:

```json
{
  "verdict": "READY" | "READY_WITH_OPEN_ITEMS" | "FORCED_PARTIAL" | "FAIL",
  "csw_gate_pillar": "Intent",
  "csw_gate_status": "pass" | "fail" | "unresolvable",
  "pillar_verdict": {
    "Background": "pass", "Materials": "fail",
    "Framework": "pass", "Intent": "pass"
  },
  "pillar_counts": { /* per pillar: pass/open_blocker/unresolvable/total */ },
  "by_source": { "four_pillar_scan": 9, "responder_simulation": 5, "legacy": 0 },
  "regressions": []
}
```

**Intent pillar is the CSW gate** — failing here alone → verdict FAIL. The agent reopens Q&A instead of closing. `close-session.sh` enforces this unless `--force`.

Backward compat: legacy 7-axis annotations (produced before 2026-04-21) are auto-mapped to pillars:
- BLUF, Decision Readiness → Intent
- Completeness → Framework
- Assumptions, Evidence, Red Team, Stakeholder → Materials

## 4. Forward to Responder (step 5c)

`deliver.sh` in v0 already handles multi-target delivery. The "forward to Responder" is the `lark_dm` target with `role: responder` — included in default `delivery_targets.json`. Payload delivered:
- `summary.md` — always (this is the Responder's pre-read)
- `final/<primary>.md` — **the revised brief itself**, so Responder gets the actual material to sign on
- `dissent.md` — so Responder knows what Requester pushed back on (material for the meeting)

## 5. What's new vs previous design

- Admin's style is **separated** from Responder's profile — admin_style.md is a new top-level config
- Final gate is **explicit** (step 4), not just implicit in close
- Document editing permission is a **configurable** spectrum, defaults to `suggest`
- Final material delivered to Responder includes `final/<primary>.md`, not just summary — so Responder gets the actual brief to sign on

## 6. What NOT to do (recap, unchanged)

- Don't write the brief from scratch (even with `suggest` permission, the revised.md is a derivative of Requester's input, not a from-scratch writeup)
- Don't bypass the final gate — it's the CSW sign-off contract
- Don't push to Responder mid-flight (only at close)
- Don't lose dissent — it flows through every stage into the Responder summary
