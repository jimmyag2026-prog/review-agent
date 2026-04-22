#!/bin/bash
# dashboard.sh — print or refresh ~/.review-agent/dashboard.md
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${REVIEW_AGENT_ROOT:-$HOME/.review-agent}"
DB="$ROOT/dashboard.md"

if [ "${1:-}" = "--refresh" ]; then
  python3 "$SKILL_DIR/scripts/_dashboard.py" "$ROOT" > "$DB"
  echo "dashboard refreshed: $DB"
else
  [ -f "$DB" ] && cat "$DB" || echo "(no dashboard yet; run: $0 --refresh)"
fi
