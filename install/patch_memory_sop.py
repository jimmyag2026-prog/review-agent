#!/usr/bin/env python3
"""install/patch_memory_sop.py — install/update the orchestrator SOP into ~/.hermes/memories/MEMORY.md.

Idempotent:
  - If marker <!-- review-agent:orchestrator-sop:v1 --> already present, skip.
  - Otherwise, PREPEND the SOP block to the file (top position = highest priority).

Usage:  python3 install/patch_memory_sop.py
"""
import os
import sys
import shutil
from datetime import datetime
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SOP_FILE = SCRIPT_DIR / "orchestrator_sop.md"
MEM = Path.home() / ".hermes" / "memories" / "MEMORY.md"
MARKER_OPEN = "<!-- review-agent:orchestrator-sop:v1 -->"

if not SOP_FILE.exists():
    print(f"error: SOP file missing at {SOP_FILE}", file=sys.stderr)
    sys.exit(2)

sop = SOP_FILE.read_text()

# Ensure memories dir exists
MEM.parent.mkdir(parents=True, exist_ok=True)
if not MEM.exists():
    MEM.write_text("")

content = MEM.read_text()

if MARKER_OPEN in content:
    print(f"already installed (marker found in {MEM}) — skipping.")
    sys.exit(0)

# Backup
ts = datetime.now().strftime("%Y%m%d%H%M%S")
bak = MEM.with_suffix(f".md.bak.review-agent-{ts}")
shutil.copy2(MEM, bak)

# Prepend SOP + separator
new_content = sop + "\n\n§\n\n" + content
MEM.write_text(new_content)

print(f"installed SOP at top of {MEM}")
print(f"backup: {bak}")
