#!/bin/bash
# dashboard-web.sh — launch local admin dashboard at http://127.0.0.1:8765
#
# Usage:
#   dashboard-web.sh              # serves in foreground, Ctrl+C to stop
#   dashboard-web.sh --open       # also opens default browser
#   dashboard-web.sh --port 9999  # custom port
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Admin-facing update notice. Silent on up-to-date / disabled / offline.
# 6s timeout is plenty — urllib already caps at 5s and caches for 24h.
UPDATE_LINE=$(timeout 6 python3 "$SKILL_DIR/scripts/check-updates.py" --oneline 2>/dev/null || true)
if [ -n "$UPDATE_LINE" ]; then
  echo "[review-agent] $UPDATE_LINE"
  echo
fi

exec python3 "$SKILL_DIR/scripts/dashboard-server.py" "$@"
