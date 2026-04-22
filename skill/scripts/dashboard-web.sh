#!/bin/bash
# dashboard-web.sh — launch local admin dashboard at http://127.0.0.1:8765
#
# Usage:
#   dashboard-web.sh              # serves in foreground, Ctrl+C to stop
#   dashboard-web.sh --open       # also opens default browser
#   dashboard-web.sh --port 9999  # custom port
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$SKILL_DIR/scripts/dashboard-server.py" "$@"
