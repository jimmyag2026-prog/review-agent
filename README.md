# review_agent_development

Development folder for the `review-agent` skill — a Completed-Staff-Work-style pre-meeting review coach for hermes/openclaw agents.

## Folder map

```
review_agent_development/
├── research/                         # Step 1 — landscape + skill conventions
│   ├── 01_landscape.md              # methodology survey (CSW, BLUF, 6-pager, red team, policy memo, market gap)
│   └── 02_hermes_skill_conventions.md # SKILL.md format + hermes/openclaw mechanics
├── design/                           # Step 2 — framework (v1 is final)
│   ├── framework.md                 # v0 (superseded — kept for history)
│   ├── framework_v1.md              # v1 — IM + async subtask architecture, 10 design gaps answered
│   └── workflow.md                  # detailed per-session lifecycle
├── skill/                            # Step 3 — shippable skill (installed via symlink)
│   ├── SKILL.md                     # manager skill entry
│   ├── references/                  # checklists, schema, templates, delivery spec
│   │   ├── checklist.md             # seven-axis review criteria
│   │   ├── annotation_schema.md     # sidecar JSONL format
│   │   ├── summary_template.md      # boss-summary structure
│   │   ├── delivery/README.md       # delivery backend spec (lark_dm, email, local, ...)
│   │   └── template/                # per-peer workspace template (AGENTS.md, profile, rules)
│   └── scripts/                     # setup / add-reviewer / new-session / close-session / deliver / dashboard / ...
├── test_logs/                        # Step 3 validation
│   └── test-plan.md                 # smoke-test results + end-to-end manual plan
└── publish/                          # Step 4 — release artifacts
    ├── README.md                    # public README (clone + install + use)
    ├── LESSONS.md                   # abstracted design lessons for skill authors
    └── NOTES_FOR_SKILL_AUTHORS.md   # gotchas and checklists
```

## Status

- [x] Step 1: Research (CSW as backbone; market gap confirmed — no "proxy coach" tool exists)
- [x] Step 2: Design v1 (ten gaps answered, all architectural decisions locked)
- [x] Step 3: Implementation (smoke-tested; copied to `~/.hermes/skills/productivity/review-agent/`)
- [x] Step 3.5: Framework evolution — 7-axis → 4-pillar + Responder simulation
- [x] Step 3.6: Orchestrator layer (MEMORY.md SOP + review-cmd/start-review/qa-step/confirm-and-scan)
- [x] Step 3.7: Document merge (`merge-draft.py`) + final-gate `--verify-final`
- [x] Step 3.8: Six challenge dimensions + challenger core principle into persona
- [x] Step 3.9: Decision-ready 6-section brief output (LLM synthesis) + audit trail
- [x] Step 3.10: Local web dashboard (`dashboard-server.py` / `dashboard-web.sh`) at http://127.0.0.1:8765
- [x] Step 4: Publish artifacts (README, lessons, skill-author notes)

## Install on a new hermes

**Pre-configured machine** (has hermes + creds):

```bash
gh repo clone jimmyag2026-prog/review-agent ~/code/review-agent
cd ~/code/review-agent && bash install.sh
hermes gateway restart
```

**From scratch / bare VPS** (Ubuntu, Debian, Fedora, Arch, Alpine, macOS):

```bash
# 1. system deps (auto-detect OS)
git clone https://github.com/jimmyag2026-prog/review-agent.git ~/code/review-agent
cd ~/code/review-agent
bash install/bootstrap.sh

# 2. then install hermes, configure ~/.hermes/.env with Lark + OpenRouter creds
# 3. finally:
bash install.sh
```

See [`INSTALL.md`](INSTALL.md) for the full walkthrough, including prerequisites, OS package list, repo-access without `gh`, verify steps, and troubleshooting.

## Open issues (deferred)

See [`OPEN_ISSUES.md`](OPEN_ISSUES.md) for deferred architectural problems.

Current entries:
- **I-001** — Session context isolation has only soft (doc + script) guarantees at the main-agent layer. Future hard fix path: session-broker, or full migration to openclaw-style per-peer agent architecture.

## Why the end-to-end isn't auto-executed

Under the session's auto mode I avoided running `add-reviewer.sh` on the real `~/.openclaw/openclaw.json` because:
- It mutates shared production config affecting live Telegram / WeCom memoirist bindings
- It restarts the gateway (briefly drops inbound messages)
- It requires a real Lark open_id of a briefer you intend to test with

You run that step when you pick a test briefer. See `test_logs/test-plan.md` for the exact commands.

## Key design decisions (the ten gaps, all resolved)

| G# | Decision |
|---|---|
| G1 | Mid-flight = pull-only dashboard; close = push to both boss and briefer |
| G2 | Dissent transparent: rejected findings enter `dissent.md` + boss summary with briefer's reason. Annotation format: sidecar JSONL by default, emitted conversation-driven (one at a time); `annotation_mode` in boss_profile allows Lark-doc override (v1) |
| G3 | Close on (a) mutual ready+confirm OR (b) briefer force-close with logged reason |
| G4 | Reviewer stores final material + delivers to boss-configured targets |
| G5 | Per-subtask isolation (session folder with frozen profile/rules) |
| G6 | Cross-session contamination forbidden; agent loads only current session folder |
| G7 | Lark (feishu) first, via openclaw websocket + Lark Open API |
| G8 | Delivery-targets backends: v0 = lark_dm + local_path + email_smtp; v1 = lark_doc + gdrive |
| G9 | End-to-end on Lark (no CLI mock shortcut) |
| G10 | v0 = single boss; v1 = multi-boss matrix |

## If you want to hand this off to another engineer

Start at `design/framework_v1.md`, then `skill/SKILL.md`, then `skill/references/template/AGENTS.md`. The third file is the reviewer's persona prompt — any behavior change starts there.
