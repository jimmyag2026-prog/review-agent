#!/bin/bash
# DEPRECATED: renamed to list-users.sh.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
echo "warning: list-reviewers.sh is deprecated — use list-users.sh" >&2
exec bash "$SKILL_DIR/scripts/list-users.sh" "$@"
