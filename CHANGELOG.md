# Changelog

All notable changes to review-agent are tracked here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed

- **LLM model follows hermes main agent** instead of hard-pinning `anthropic/claude-sonnet-4.6`. All LLM-calling scripts now resolve the model from `~/.hermes/config.yaml` → `model.default` and map hermes-style ids to OpenRouter format (strip `-YYYYMMDD` date suffix, convert trailing `-N-N` to `-N.N`, add provider prefix). Precedence: `REVIEW_AGENT_MODEL` env var > hermes config > fallback `anthropic/claude-sonnet-4.6`.
- New shared helper `skill/scripts/_model.py` exposes `get_main_agent_model()`.
- `--model` CLI flag on each script now defaults to `None` (resolve at call time) instead of a hardcoded string. Pass `--model <id>` to override per-call.
- Removed `model:` pin from `skill/SKILL.md` frontmatter.
- **Installer split into two phases**: Phase A installs files (always runs, reversible), Phase B configures Admin/Responder + patches `config.yaml` + installs MEMORY.md SOP (opt-in via prompt or `--enable-only`). Run with `--install-only` to stage files without activating.
- **Responder profile default**: `boss_profile.md` template rewritten as a functional senior-reviewer default — reviews now work out of the box without editing, though personalizing still improves quality. Old version was all placeholders and produced degraded reviews when unedited.

### Added

- `skill/scripts/check-profile.py` — scans a profile for leftover `<e.g., …>` / `<your …>` placeholders. Invoked by `install.sh` Phase B (user-facing warning) and `new-session.sh` (stderr log only, never blocks).
- `~/.review-agent/enabled.json` stamp written after Phase B for install/enable-state detection.

## [1.0.0] — 2026-04-22

First public release. Complete end-to-end pipeline for async pre-meeting review coaching via Lark IM + Lark Doc, with a local admin dashboard.

### Architecture

- **Three-role model**: Admin / Responder / Requester. Default install folds Admin+Responder into one user; multi-Responder is on the v1.x roadmap.
- **Per-subtask isolation**: `~/.review-agent/users/<open_id>/sessions/<id>/` each with frozen copies of `admin_style.md` + per-Responder `profile.md` + shared `review_rules.md`.
- **Runtime**: hermes (native Lark gateway) + OpenRouter (Sonnet 4.6 default) for LLM calls. No hermes fork or private API needed.

### Review framework

- **Core principle**: agent is a challenger, not a summarizer. Points out problems, asks questions, never writes answers for the Requester.
- **Six challenge dimensions**: data integrity / logical consistency / plan feasibility / stakeholders / risk assessment / ROI clarity.
- **Four pillars** (replaces earlier 7-axis model; legacy axis-based annotations are backward-compat mapped):
  - Background · Materials · Framework · **Intent (CSW gate)**
- **Responder Simulation top layer**: LLM role-plays the Responder using their profile.md and produces top-5 questions in their voice.

### Pipeline (6 stages)

INTAKE → SUBJECT CONFIRMATION → FOUR-PILLAR SCAN + RESPONDER SIMULATION → Q&A LOOP → DOCUMENT MERGE (conditional) → FINAL GATE + CLOSE + FORWARD.

### User-facing features

- **IM-based Q&A loop** with shortcut replies: `a` / `b` / `c` / `p` (pass) / `custom` / free text, auto-scoped to top-3 BLOCKER findings with remainder deferred for later.
- **Lark Doc publishing**: material + findings go into an auto-created Lark docx with inline agent callouts (content-injection style; Lark Open API doesn't expose true inline comment anchoring), shared to Requester (edit) and Responder (view).
- **Decision-ready summary**: LLM synthesizes a 6-section brief (议题摘要 / 核心数据 / 团队自检结果 / 待决策事项 / 建议时间分配 / 风险提示) delivered to both parties on close. Audit-trail version saved separately.
- **Local dashboard**: `http://127.0.0.1:8765`, read-only view of all users, active sessions, findings progress.

### Engineering hardening

- **Session isolation guardrails**: MEMORY.md SOP forbids main agent from reading session files; scripts run as isolated Python processes; stderr shrunk to minimal lifecycle markers.
- **IM outbound hygiene**: hermes config patched to stop `tool_progress` from leaking into Lark DMs (feishu platform tier = MINIMAL).
- **Lenient JSON parser**: handles LLM output with unescaped newlines, inner quotes, trailing commas, markdown fences, line comments.
- **Idempotent install**: marker-guarded SOP append, backup-on-patch, re-run safe.

### Tooling

- **One-command install** for pre-configured hermes + **bootstrap.sh** for bare-metal/VPS (auto-detects OS across Ubuntu/Debian/Fedora/Arch/Alpine/macOS).
- **check_prereqs.sh** with OS-specific install hints for each missing dep.
- **sync-to-hermes.sh** for dev → skill copy iteration.

### Known limitations

- Session context isolation at main-agent layer is documentation-enforced only; see [OPEN_ISSUES.md I-001](OPEN_ISSUES.md) for hardening path.
- Lark API does not support programmatic inline comment anchoring on docx; worked around via content injection.
- Single-Responder v0 scope; multi-Responder deferred to v1.x.
- `more` / `deepen` follow-up commands from Responder on the delivered summary are documented in output but backend routing not yet implemented.

### Scripts index

User mgmt: `setup` / `add-requester` / `add-responder` / `set-role` / `list-users` / `remove-user`.
Session lifecycle: `new-session` / `close-session` / `review-cmd` / `start-review` / `confirm-and-scan`.
LLM stages: `confirm-topic.py` / `scan.py` / `qa-step.py` / `merge-draft.py` / `_build_summary.py` / `final-gate.py`.
Input normalization: `ingest.py` / `lark-fetch.sh`.
Outputs: `_deliver.py` / `deliver.sh` / `send-lark.sh` / `lark-doc-publish.py`.
Ops: `dashboard-web.sh` / `dashboard-server.py` / `dashboard.sh` / `sync-to-hermes.sh`.
Install: `install.sh` + `install/{bootstrap,check_prereqs,patch_hermes_config,patch_memory_sop}`.

### Repo layout

```
review-agent/
├── install.sh           # one-shot installer
├── install/             # bootstrap + prereq + config patchers + SOP source
├── skill/               # the hermes skill (SKILL.md + scripts + references)
├── design/              # architecture & flow design docs
├── publish/             # LESSONS / NOTES for skill authors + public README
├── research/            # methodology landscape survey
└── test_logs/           # test plans
```
