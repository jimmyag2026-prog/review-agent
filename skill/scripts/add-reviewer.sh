#!/bin/bash
# DEPRECATED: renamed to add-requester.sh (three-role model).
# This shim forwards to add-requester.sh.
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
echo "warning: add-reviewer.sh is deprecated — use add-requester.sh" >&2
exec bash "$SKILL_DIR/scripts/add-requester.sh" "$@"
