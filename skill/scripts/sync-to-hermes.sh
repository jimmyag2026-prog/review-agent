#!/bin/bash
# sync-to-hermes.sh — copy this skill to ~/.hermes/skills/productivity/review-agent/
# Hermes doesn't follow symlinks into skill dirs, so we use rsync.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
DST="$HOME/.hermes/skills/productivity/review-agent"

mkdir -p "$(dirname "$DST")"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete --exclude=".git" --exclude=".DS_Store" "$SRC/" "$DST/"
else
  rm -rf "$DST"
  cp -rL "$SRC" "$DST"
fi

echo "synced: $SRC → $DST"
hermes skills list --source local 2>&1 | grep -i "review-agent" || true
