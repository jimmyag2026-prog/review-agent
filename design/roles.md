# Three-Role Model — added 2026-04-20 PM

## Roles

| Role | 中文 | Definition |
|---|---|---|
| **Responder** | 上级 | The reviewer-of-record. Their `profile.md` defines the standards used when reviewing materials submitted to them. They receive the summary on session close. |
| **Requester** | 下级 | The submitter. Sends drafts via Lark DM. Reviewed against the standards of their assigned Responder. |
| **Admin** | 管理员 | Manages the agent: setup, add/remove users, edit shared `review_rules.md`, edit any Responder's profile, force-close any session, configure delivery targets. **Defaults to same person as the (sole) Responder unless explicitly separated.** |

A user can hold multiple roles. The default install creates one user with roles `["Admin","Responder"]`. **v0 scope is single-Admin + single-Responder** (may or may not be the same person). Multi-Responder is planned for v1; the `add-responder.sh` script enforces the single-Responder constraint and errors out if a second Responder is added without `--force`.

## Permission matrix

| Action | Admin | Responder | Requester |
|---|---|---|---|
| Run `setup.sh` | ✓ | ✗ | ✗ |
| Add a Responder | ✓ | ✗ | ✗ |
| Add a Requester | ✓ | ✓ (assigned to themself) | ✗ |
| Remove a user | ✓ | ✗ | ✗ |
| Edit `review_rules.md` (shared) | ✓ | ✗ | ✗ |
| Edit `users/<id>/profile.md` (Responder profile) | ✓ (any) | ✓ (own) | ✗ |
| Edit shared `delivery_targets.json` | ✓ | ✗ | ✗ |
| Edit per-Responder `delivery_override.json` | ✓ | ✓ (own) | ✗ |
| View dashboard | ✓ (all sessions) | ✓ (sessions where they are Responder) | ✓ (own sessions only) |
| Force-close any session | ✓ | ✓ (own) | ✓ (own) |
| Receive summary on close | — | ✓ (the assigned Responder) | ✓ (the Requester) |

Enforcement is at the SKILL level: when a Lark DM arrives, the agent looks up the sender's `users/<open_id>/meta.json` to determine role; commands or session actions are gated accordingly. The agent does not invoke admin scripts when a Requester asks for them.

## Data layout (new)

```
~/.review-agent/
├── rules/review_rules.md             # shared across all Responders (Admin owns)
├── delivery_targets.json              # shared default
├── users/
│   ├── <open_id_A>/                  # the Admin+Responder (default install)
│   │   ├── meta.json                 # roles: ["Admin","Responder"], created_at, ...
│   │   └── profile.md                # this Responder's standards (was boss_profile.md)
│   ├── <open_id_B>/                  # a second Responder (multi-Responder mode)
│   │   ├── meta.json                 # roles: ["Responder"]
│   │   ├── profile.md
│   │   └── delivery_override.json    # optional, overrides shared delivery_targets
│   └── <open_id_R>/                  # a Requester
│       ├── meta.json                 # roles: ["Requester"], responder: <open_id_A>
│       ├── owner.json                # portability info (boss/responder name etc)
│       └── sessions/
│           └── <session_id>/
│               ├── meta.json
│               ├── profile.md        # frozen copy of Responder's profile
│               ├── review_rules.md   # frozen copy of shared rules
│               ├── input/
│               ├── normalized.md
│               ├── annotations.jsonl
│               ├── conversation.jsonl
│               ├── dissent.md
│               ├── cursor.json
│               ├── final/
│               └── summary.md         # generated on close
├── dashboard.md
└── logs/
```

(Migrated from `peers/<open_id>/` — old name was role-blind.)

## Script command map

| Command | Who can run | Effect |
|---|---|---|
| `setup.sh --admin-open-id <ou_> [--responder-open-id <ou_>]` | initial CLI / admin manually | Create `users/<admin>/` with default roles; if responder differs, create `users/<responder>/` separately |
| `add-requester.sh <ou_> [--responder <ou_>] [--name <text>]` | Admin or Responder | Create `users/<ou_>/` as Requester linked to specified Responder (default = sole Admin) |
| `add-responder.sh <ou_> [--name <text>]` | Admin only | Create `users/<ou_>/` as Responder; copies a starter `profile.md` |
| `set-role.sh <ou_> <add|remove> <Admin|Responder|Requester>` | Admin only | Mutate `users/<ou_>/meta.json` roles |
| `list-users.sh [--role <role>]` | any | Print users + roles |
| `remove-user.sh <ou_> [--keep-data] [--revoke-pairing]` | Admin only | Remove a user folder + optional pairing revoke |
| `new-session.sh <requester_ou_> "<subject>"` | called by reviewer flow | Create a subtask session under that Requester |
| `close-session.sh <session_id> [--force --reason ...]` | Requester (own) / Responder (own) / Admin (any) | Generate summary, deliver |
| `dashboard.sh` | any (filtered by role) | Print dashboard |
