# Registering review-agent on agentskills.io

[agentskills.io](https://agentskills.io) is the open standard registry for Agent Skills (the format review-agent already conforms to). Publishing makes it one-command installable: `hermes skills install review-agent`.

This doc is for **maintainers** — instructions for the registration step that must be done manually via GitHub PR.

## Prerequisites (already met)

- [x] `skill/SKILL.md` has valid frontmatter (name, description, version)
- [x] Skill self-contained in one directory
- [x] MIT license
- [x] Public repo
- [x] Clear install instructions

## Publishing steps

### 1. Prepare the skill manifest

agentskills.io expects a top-level manifest referencing the skill. Confirm `skill/SKILL.md` frontmatter:

```yaml
---
name: review-agent
description: <≤ 1536 chars; front-load trigger keywords>
version: 1.0.0
author: <your handle>
license: MIT
metadata:
  hermes:
    tags: [Review, Meeting, Briefing, Lark, Feishu, Coaching, CSW, PreMeeting]
---
```

Make sure `version` in SKILL.md matches the git tag you're publishing (`v1.0`).

### 2. Fork the agentskills registry repo

```bash
gh repo fork agentskills/agentskills --clone
cd agentskills
```

### 3. Add your skill entry

Create a new file in the `skills/` directory:

`skills/review-agent.yml`:

```yaml
name: review-agent
source:
  type: github
  repo: jimmyag2026-prog/review-agent
  path: skill
  ref: v1.0     # pin to release tag — update on new versions
category: productivity
description: |
  Async pre-meeting review coach built on Completed Staff Work.
  Trains briefers to meet their Responder's bar before the meeting —
  challenger (not summarizer) across 6 dimensions + 4 pillars +
  Responder simulation. Lark IM + docx inline callouts.
tags:
  - review
  - meeting-prep
  - csw
  - lark
  - feishu
  - coaching
  - briefing
  - pre-meeting
license: MIT
homepage: https://github.com/jimmyag2026-prog/review-agent
maintainers:
  - jimmyag2026-prog
```

### 4. Validate locally

The registry repo ships a validator. Run:

```bash
./scripts/validate.sh skills/review-agent.yml
```

Fix any errors (usually: missing required fields, invalid SKILL.md description length, broken github ref).

### 5. Submit PR

```bash
git checkout -b add-review-agent
git add skills/review-agent.yml
git commit -m "Add review-agent skill

CSW-style pre-meeting review coach. Six challenge dimensions +
four-pillar framework + Responder simulation. Runs on hermes +
Lark + OpenRouter.

Repo: github.com/jimmyag2026-prog/review-agent
Tag:  v1.0
License: MIT"
git push origin add-review-agent
gh pr create --title "Add review-agent skill" --body-file <path-to-pr-template-if-any>
```

PR description should include:
- Link to your repo + tag
- Short pitch (1-2 sentences)
- Dependencies (hermes + Lark bot + OpenRouter key)
- Link to your INSTALL.md for verification steps

### 6. After merge

Users can install with:

```bash
hermes skills install review-agent
```

hermes skills install flow still doesn't handle the MEMORY.md SOP patch or `~/.review-agent/` init — users still need to run `install.sh` afterward. We can either:

- **(Option A)** Update install.sh to detect post-hermes-install state and only do the delta steps (SOP + ~/.review-agent).
- **(Option B)** Mention in the registry description: "after hermes skills install, run `bash ~/.hermes/skills/productivity/review-agent/install.sh` to finish setup."

Option B is simpler; Option A is nicer UX. Pick based on user feedback after release.

### 7. Update on new versions

Each v1.x / v2.0 release:

1. Cut a new git tag in this repo.
2. Update `ref:` and `description:` in the agentskills.io manifest.
3. Submit a PR to the registry.

Consider automating via a GitHub Action that opens the registry PR when a tag is pushed.

## Alternative: skills.sh

If agentskills.io isn't the right registry, [skills.sh](https://skills.sh) (another Agent Skills registry) accepts similar submissions. Both are hermes-compatible.

## Resources

- Agent Skills open standard: https://agentskills.io
- hermes skills CLI: `hermes skills --help`
- Example already-published skill: https://github.com/anthropics/skills/tree/main/skills/skill-creator
