#!/usr/bin/env python3
"""install/patch_memory_sop.py — install / upgrade the orchestrator SOP
in ~/.hermes/memories/MEMORY.md.

Idempotent with auto-upgrade:
  - Scans MEMORY.md for existing markers `<!-- review-agent:orchestrator-sop:vN -->`
    ... `<!-- /review-agent:orchestrator-sop:vN -->` (any N).
  - If an OLDER version is installed, replaces the block in place.
  - If the CURRENT version is already installed, no-ops.
  - If nothing is installed, prepends at the top (highest priority position).

The current SOP version is derived from the opening marker in
`orchestrator_sop.md` itself — single source of truth.

Usage:  python3 install/patch_memory_sop.py
"""
import os
import re
import sys
import shutil
from datetime import datetime
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SOP_FILE = SCRIPT_DIR / "orchestrator_sop.md"
MEM = Path.home() / ".hermes" / "memories" / "MEMORY.md"

# Generic marker pattern: matches any version. The opening and closing markers
# must be paired and must wrap the SOP body we ship.
OPEN_RE = re.compile(r"<!--\s*review-agent:orchestrator-sop:v(\d+)\s*-->")
CLOSE_RE = re.compile(r"<!--\s*/review-agent:orchestrator-sop:v(\d+)\s*-->")
# Full block (greedy across lines) — used to excise an existing install.
BLOCK_RE = re.compile(
    r"(?:#\s*🚨[^\n]*\n+)?"                                   # optional leading heading line
    r"<!--\s*review-agent:orchestrator-sop:v\d+\s*-->"
    r".*?"
    r"<!--\s*/review-agent:orchestrator-sop:v\d+\s*-->",
    re.S,
)

if not SOP_FILE.exists():
    print(f"error: SOP file missing at {SOP_FILE}", file=sys.stderr)
    sys.exit(2)

sop = SOP_FILE.read_text()

m_new = OPEN_RE.search(sop)
if not m_new:
    print(f"error: SOP file {SOP_FILE} has no opening marker; cannot install.",
          file=sys.stderr)
    sys.exit(2)
new_version = int(m_new.group(1))

# Ensure memories dir exists
MEM.parent.mkdir(parents=True, exist_ok=True)
if not MEM.exists():
    MEM.write_text("")

content = MEM.read_text()

existing = OPEN_RE.search(content)
if existing:
    existing_version = int(existing.group(1))
    if existing_version == new_version:
        print(f"already installed (v{existing_version} == current) — no change.")
        sys.exit(0)

    # Upgrade path: excise the old block, insert the new one at its position.
    m_block = BLOCK_RE.search(content)
    if not m_block:
        print(
            f"warning: found opening marker v{existing_version} but could not "
            "locate closing marker — falling back to prepend.",
            file=sys.stderr,
        )
        existing = None   # fall through to prepend branch

    if existing:
        ts = datetime.now().strftime("%Y%m%d%H%M%S")
        bak = MEM.with_suffix(f".md.bak.review-agent-upgrade-{ts}")
        shutil.copy2(MEM, bak)

        pre  = content[:m_block.start()]
        post = content[m_block.end():]
        new_content = pre + sop.rstrip() + post
        MEM.write_text(new_content)
        print(f"upgraded SOP in place: v{existing_version} → v{new_version}")
        print(f"backup: {bak}")
        sys.exit(0)

# No existing install — prepend.
ts = datetime.now().strftime("%Y%m%d%H%M%S")
bak = MEM.with_suffix(f".md.bak.review-agent-{ts}")
shutil.copy2(MEM, bak)

new_content = sop + "\n\n§\n\n" + content
MEM.write_text(new_content)
print(f"installed SOP at top of {MEM} (v{new_version})")
print(f"backup: {bak}")
