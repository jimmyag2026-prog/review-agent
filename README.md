# review-agent

**An async pre-meeting review coach for hermes + Lark.** Before a Requester gets time with a Responder, review-agent challenges their draft through six dimensions of scrutiny (data / logic / feasibility / stakeholders / risk / ROI), runs them through a Q&A loop until the material is decision-ready, then hands the Responder a distilled pre-read.

Rooted in the 1942 US Army doctrine of **Completed Staff Work**: "the chief only signs yes or no; all the thinking has been done by staff." Modernized with LLM orchestration + Lark Doc integration.

> **Status**: v1.0 — usable end-to-end on a fresh hermes + Lark install. See [CHANGELOG.md](CHANGELOG.md) for what's in and what's known-limited.

## What it does

- **Inbound**: Requester DMs a Lark bot with a draft / doc link / proposal.
- **Pipeline**: subject-alignment → four-pillar scan + Responder simulation → Q&A loop with shortcut replies → revised draft → final-gate → decision-ready brief.
- **Outputs**:
  - **Live Lark Doc** with original material + inline agent callouts
  - **6-section decision brief** delivered to Responder via Lark DM on close
  - **Local admin dashboard** at `http://127.0.0.1:8765`

## Core principle

Agent = **challenger**, not summarizer. Points out problems. Asks questions. Never writes the answer for the Requester. The Responder gets material that's already been through the critical eye — their meeting time goes into decisions, not context rebuilding.

The six challenge dimensions covered in every review:

1. **Data integrity** · "You said growth is good — where are the DAU / retention numbers?"
2. **Logical consistency** · "You want to kill feature A, but earlier called it the core value — reconcile."
3. **Plan feasibility** · "Three engineers for two months, but the team has one person."
4. **Stakeholders** · "Legal / compliance weren't consulted — this project touches user data."
5. **Risk assessment** · "What's Plan B if the main approach fails? Not in the material."
6. **ROI clarity** · "Expected upside is $1M — where's the cost estimate?"

## Install

**Pre-configured machine** (hermes + Lark creds already present):

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

# 2. install hermes, configure ~/.hermes/.env with Lark + OpenRouter creds
# 3. finally:
bash install.sh
```

See [**INSTALL.md**](INSTALL.md) for the full walkthrough: prerequisites, OS package lists, repo-access options (gh / SSH / PAT), verify steps, troubleshooting, uninstall.

## Architecture

```
Lark inbound → hermes main agent → MEMORY.md SOP
                                    │
             ┌──────────────────────┼──────────────────────┐
             │                      │                      │
      unregistered           Admin/Responder          Requester
      polite refuse          normal chat / mgmt cmds  check /review cmd
                                                       │
                                   ┌───────────────────┤
                                   │                   │
                          active session?         no active session
                          qa-step.py              +review intent?
                                                       │
                                       start-review.sh (ingest →
                                       confirm-topic → scan →
                                       auto-scope top-3 →
                                       lark-doc-publish)
                                                       │
                                   Q&A loop with a/b/c/p/custom shortcuts
                                                       │
                              final-gate → _build_summary (LLM synth)
                                                       │
                              deliver: Lark DM to Responder + Requester
                                        + local archive + optional email
```

Runtime: **hermes** (native Lark gateway) + **OpenRouter** (Sonnet 4.6 default).
Storage: `~/.review-agent/` (users / sessions / rules / logs).
Dashboard: `http://127.0.0.1:8765` (local-only, read-only).

## Repo layout

```
review-agent/
├── install.sh                  # one-shot installer
├── install/                    # bootstrap + prereq check + config patchers
│   ├── bootstrap.sh            # system-dep installer (apt/dnf/brew/apk/pacman)
│   ├── check_prereqs.sh        # env validation with OS-specific hints
│   ├── patch_hermes_config.py  # display.platforms.feishu = MINIMAL
│   ├── patch_memory_sop.py     # prepend SOP to MEMORY.md (idempotent)
│   └── orchestrator_sop.md     # the SOP block (single source of truth)
├── skill/                      # the hermes skill
│   ├── SKILL.md                # skill manifest
│   ├── references/             # persona / four_pillars / schema / templates
│   └── scripts/                # ~30 scripts covering the full pipeline
├── design/                     # architecture + flow design docs
├── publish/                    # LESSONS / NOTES for skill authors
├── research/                   # methodology landscape survey
├── test_logs/                  # test plans
├── CHANGELOG.md
├── INSTALL.md                  # full install walkthrough
├── OPEN_ISSUES.md              # deferred architectural problems
└── LICENSE                     # MIT
```

## Framework references

- [CSW — Completed Staff Work (1942)](https://en.wikipedia.org/wiki/Completed_staff_work) — quality bar
- BLUF — "bottom line up front" — military briefing format
- Amazon 6-pager — narrative-brief discipline
- Devil's advocate / red team — multi-agent critique pattern
- [Agent Skills open standard](https://agentskills.io) — skill packaging (agentskills.io-compatible)

## Philosophy

Most 2026 pre-meeting AI tools go **bottom-up** (give the receiver a pre-read). review-agent goes **top-down**: trains the briefer to meet the receiver's bar *before* the meeting is even on the calendar. The 60-second summary the receiver reads is the tip; the rigor happened one layer down.

## License

MIT — see [LICENSE](LICENSE).

## Contributing

Issues / PRs welcome. Substantial changes should first be discussed via an issue; the project follows the architectural constraints in `design/`.

Known open issues: [OPEN_ISSUES.md](OPEN_ISSUES.md).
