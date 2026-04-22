# Contributing to review-agent

Thank you for considering a contribution. This project has strong architectural invariants — read this doc before opening a PR.

## Development setup

```bash
# Clone
gh repo clone jimmyag2026-prog/review-agent ~/code/review-agent
cd ~/code/review-agent

# Bootstrap system deps (once per machine)
bash install/bootstrap.sh

# Install the skill into your hermes (creates ~/.hermes/skills/... symlinked from your dev path only via sync)
bash install.sh

# Iteration loop: edit skill/ in this repo → sync to hermes → test
bash skill/scripts/sync-to-hermes.sh
# (skill/scripts/sync-to-hermes.sh does rsync since hermes doesn't follow symlinks for skill discovery)
```

## Running smoke tests

Most test paths run in `/tmp/ra-*` to avoid touching real state:

```bash
# Tests live inside individual scripts; run them directly with REVIEW_AGENT_ROOT pointing to a tmp dir:
export REVIEW_AGENT_ROOT=/tmp/ra-dev
rm -rf /tmp/ra-dev
bash skill/scripts/setup.sh --admin-open-id ou_TEST_ADMIN --admin-name "TestUser"
bash skill/scripts/add-requester.sh ou_TEST_REQ --name "TestReq" --no-pairing-check
# ... etc
```

Always clean `/tmp/ra-*` at the end.

**Never test against `~/.review-agent/`** in dev work — that's your live state.

**Never test by actually sending Lark messages** during development unless you're on a burn-it-down test bot — use `--no-send` flags or stub creds.

## Style

- **Python**: 3.9 compatible. Avoid `dict | None` union syntax; use `Optional[dict]`. Use `typing.Optional` explicitly.
- **Bash**: `#!/bin/bash` + `set -euo pipefail`. Test with `bash -n` before committing.
- **Paths**: never hardcode `/Users/...` or `/home/...`. Use `$HOME` / `Path.home()` / `${REVIEW_AGENT_ROOT}`.
- **Secrets**: no API keys, tokens, open_ids in code. All creds from env (`~/.hermes/.env`).
- **Python-in-bash**: use env var passing (`KEY="$VAL" python3 <<'PYEOF' ... PYEOF`), not `$(python3 -c "...")` with curly braces — see `feedback_bash_python_heredoc` in project memory. The `_json_repair.py` lenient parser is the canonical example.

## Architectural invariants (PRs violating these will be rejected)

These are **not** opinions — they're design principles that have been validated and shouldn't be undone without explicit discussion (open an issue first):

1. **Agent is a challenger, not a summarizer.** PR must not introduce "agent writes the answer for the Requester" behavior. Point out problems, ask questions.

2. **Per-subtask folder isolation.** Each `~/.review-agent/users/<oid>/sessions/<id>/` is self-contained with frozen copies of `admin_style.md` / `profile.md` / `review_rules.md`. Don't read across sessions.

3. **Main agent = router only.** The hermes main agent must NOT read session files or reason about session content. All session reasoning happens in isolated Python subprocesses. See `install/orchestrator_sop.md`.

4. **Dissent transparency.** Rejected findings always land in `dissent.md` with the Requester's reason. Never silently drop.

5. **Pull-only mid-flight.** Responder gets zero push during an active session. Only on close does `summary.md` get delivered.

6. **Option block convention.** Every IM question ends with a structured block including `(p) pass` + `(custom)` fallbacks. See `skill/references/agent_persona.md`.

7. **Script output contract.** All pipeline scripts: stdout = final IM reply only; stderr = minimal lifecycle markers (no session content).

## PR process

1. Open an issue first for anything non-trivial (scope: Medium / Large). Let's align on the problem before the patch.
2. Branch from `main`: `git checkout -b <feature-name>`.
3. One logical change per PR. Squash commits if needed.
4. Commit message format:
   ```
   <area>: <short summary>

   <why — not what; the diff shows what>

   <breaking changes / migration notes if any>
   ```
   Areas: `feat` / `fix` / `docs` / `refactor` / `install` / `framework` / `pipeline` / `delivery`.
5. Self-review: run `bash install/check_prereqs.sh`, confirm smoke tests pass, verify no PII introduced (`grep -rnE "ou_[a-f0-9]{30,}|Jimmy|Evie|<your name>"`).
6. Update `CHANGELOG.md` if user-visible.
7. Open PR with:
   - Problem link (issue)
   - What changed
   - How to test
   - Rollback plan if it goes wrong

## v1.x roadmap

Open to PRs on any of these. If you're tackling one, claim it in the corresponding issue first.

### v1.1 — Responder quality-of-life

- [ ] **`more` / `deepen <id>` backend** — when Responder replies with these words on the delivered summary, re-open the session with new findings drawn from `deferred_by_scope` annotations or a fresh scan pass. Text-layer prompt is already in summary; backend routing is TODO.
- [ ] **Multi-Responder (proper)** — remove the single-Responder guard in `add-responder.sh`; extend cursor to track `(requester, responder)` pair; delivery_targets per-Responder override.
- [ ] **agentskills.io registry publish** — see `publish/AGENTSKILLS_REGISTRATION.md`. Makes `hermes skills install review-agent` work directly.
- [ ] **Responder dashboard read-mode** — tighter view that only shows sessions where they are the Responder (currently dashboard shows all for Admin).

### v1.2 — Engineering hardening

- [ ] **Session-broker for hard isolation** — resolves [I-001](OPEN_ISSUES.md). A tiny broker that the main agent MUST go through to read any session data, rather than raw file access. Addresses the context-contamination risk documented in OPEN_ISSUES.
- [ ] **Webhook-based routing** — sidestep the main agent entirely: Lark inbound → hermes webhook → direct orchestrator script. Removes the "main agent ignored MEMORY.md SOP" failure mode at the root.
- [ ] **Lark doc comment 2-way sync** — watch for Requester resolving / replying to inline callouts in the Lark doc, reflect back into `annotations.jsonl`.

### v1.3 — Multi-modal + multi-channel

- [ ] **Ingest reach** — native PDF via `pdftotext`, image OCR, audio transcription without relying on external tools.
- [ ] **Non-Lark channels** — Telegram / Discord / Slack as first-class delivery targets (not just Lark-only).
- [ ] **Lark doc write `direct` mode** — instead of producing `final/revised.md` locally, edit the shared Lark doc in place (Requester confirms via comment resolution).

### v2 — Different architectures

Not committed. Ideas:

- [ ] Migration to **openclaw**-style per-peer agent architecture (true OS-level isolation via per-binding workspace).
- [ ] **Multi-tenant SaaS** — one review-agent instance serving multiple organizations with proper namespacing.
- [ ] **Non-Agent-Skills platforms** — Cursor / Cline / custom agent hosts.

## Non-goals

Things the project deliberately won't do:

- **Become a general-purpose meeting-prep tool.** Scope is pre-review-then-meeting. Not meeting recording, not transcription, not agenda management.
- **Generate the final brief *for* the Requester in default mode.** CSW principle — the Requester ships. The agent only suggests revisions (and in `direct` mode applies them for Requester approval); it doesn't replace the Requester's authorship.
- **Support real-time collaborative editing.** Async IM + doc is the interaction model. If you want real-time, use a different tool.

## Questions

Open an issue with the label `question`. Don't DM; keep discussions discoverable.
