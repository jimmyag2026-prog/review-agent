#!/bin/bash
# DEPRECATED: renamed to remove-user.sh.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
echo "warning: remove-reviewer.sh is deprecated — use remove-user.sh" >&2
exec bash "$SKILL_DIR/scripts/remove-user.sh" "$@"
