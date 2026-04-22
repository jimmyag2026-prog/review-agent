#!/usr/bin/env python3
"""install/patch_hermes_config.py — apply review-agent-specific overrides to ~/.hermes/config.yaml.

Changes:
  1. display.interim_assistant_messages = false   (hide mid-turn status from all gateway chats)
  2. display.platforms.feishu = MINIMAL tier      (no tool_progress leaking to Lark DMs)

Idempotent — safe to run multiple times. Creates .bak before writing.

Usage:  python3 install/patch_hermes_config.py
"""
import json
import os
import shutil
import sys
from datetime import datetime
from pathlib import Path

import yaml

CONFIG = Path.home() / ".hermes" / "config.yaml"

if not CONFIG.exists():
    print(f"error: {CONFIG} not found — run 'hermes setup' first", file=sys.stderr)
    sys.exit(2)

# Backup
ts = datetime.now().strftime("%Y%m%d%H%M%S")
bak = CONFIG.with_suffix(f".yaml.bak.review-agent-{ts}")
shutil.copy2(CONFIG, bak)

cfg = yaml.safe_load(open(CONFIG)) or {}
d = cfg.setdefault("display", {})

changed = []
if d.get("interim_assistant_messages") != False:
    d["interim_assistant_messages"] = False
    changed.append("display.interim_assistant_messages=false")

platforms = d.setdefault("platforms", {}) or {}
feishu_target = {
    "tool_progress": "off",
    "show_reasoning": False,
    "tool_preview_length": 0,
    "streaming": False,
}
if platforms.get("feishu") != feishu_target:
    platforms["feishu"] = feishu_target
    changed.append("display.platforms.feishu=MINIMAL")
d["platforms"] = platforms

if changed:
    with open(CONFIG, "w") as f:
        yaml.safe_dump(cfg, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
    print(f"patched: {', '.join(changed)}")
    print(f"backup: {bak}")
    print("run 'hermes gateway restart' to apply.")
else:
    print("already up to date — no changes.")
    bak.unlink()   # remove useless backup
