#!/bin/bash
# remove-user.sh — Admin: remove a user (any role)
set -euo pipefail

ROOT="${REVIEW_AGENT_ROOT:-$HOME/.review-agent}"

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'

usage() {
  echo "Usage: $(basename "$0") <open_id> [--keep-data] [--revoke-pairing]" >&2
  exit 1
}

if [ $# -lt 1 ]; then usage; fi

OID="$1"; shift
KEEP=0
REVOKE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --keep-data) KEEP=1; shift ;;
    --revoke-pairing) REVOKE=1; shift ;;
    *) usage ;;
  esac
done

UDIR="$ROOT/users/$OID"

if [ $REVOKE -eq 1 ] && command -v hermes >/dev/null 2>&1; then
  hermes pairing revoke "$OID" 2>&1 | head -3 || echo -e "${YELLOW}  warn: revoke failed${NC}"
fi

if [ $KEEP -eq 0 ]; then
  [ -d "$UDIR" ] && rm -rf "$UDIR" && echo -e "${GREEN}  removed${NC} $UDIR"
else
  echo -e "${YELLOW}  retained${NC} $UDIR (--keep-data)"
fi
