#!/usr/bin/env python3
"""install/patch_hermes_config.py — apply review-agent-specific overrides
to ~/.hermes/config.yaml so tool calls, code previews, and progress markers
don't leak into Lark DMs.

The visible symptom we're defending against (reported 2026-04-22):
  Requester sees lines like '💻 terminal: "python3 -c ..."' in the Lark chat
  while the main agent is processing their message.

Settings applied:
  display.interim_assistant_messages = false          # no mid-turn status
  display.platforms.feishu = {                        # MINIMAL render tier
      tool_progress: off,                             # no per-step progress
      tool_preview_length: 0,                         # no preview of tool args
      show_reasoning: false,                          # no thinking blocks
      show_tool_calls: false,                         # defensive — suppress tool bubbles
      show_tool_results: false,                       # defensive — suppress tool result bubbles
      show_code_blocks: false,                        # defensive — suppress ```lang blocks
      show_bash: false,                               # defensive — suppress bash previews
      streaming: false,                               # flush once at end, no partials
  }

  feishu.unauthorized_dm_behavior = pair              # see HERMES_FEISHU_HARDENING.md
                                                      # only set if absent (don't clobber user choice)

Unknown keys are harmless on hermes versions that ignore them. Known keys are
applied in a single pass. Idempotent — safe to run repeatedly; .bak created
only if something changed.

Usage:  python3 install/patch_hermes_config.py
"""
import os
import shutil
import sys
from datetime import datetime
from pathlib import Path

import yaml

CONFIG = Path.home() / ".hermes" / "config.yaml"

FEISHU_DISPLAY_TARGET = {
    "tool_progress": "off",
    "tool_preview_length": 0,
    "show_reasoning": False,
    "show_tool_calls": False,
    "show_tool_results": False,
    "show_code_blocks": False,
    "show_bash": False,
    "streaming": False,
}


def _merge_feishu_display(current):
    """Return (merged, changed) where merged includes every key from target
    overwritten to target values. Preserves unknown keys the user set."""
    if not isinstance(current, dict):
        return dict(FEISHU_DISPLAY_TARGET), True
    merged = dict(current)
    changed = False
    for k, v in FEISHU_DISPLAY_TARGET.items():
        if merged.get(k) != v:
            merged[k] = v
            changed = True
    return merged, changed


def main():
    if not CONFIG.exists():
        print(f"error: {CONFIG} not found — run 'hermes setup' first",
              file=sys.stderr)
        sys.exit(2)

    cfg = yaml.safe_load(open(CONFIG)) or {}
    changed = []

    # 1. display.interim_assistant_messages
    d = cfg.setdefault("display", {}) or {}
    if d.get("interim_assistant_messages") is not False:
        d["interim_assistant_messages"] = False
        changed.append("display.interim_assistant_messages=false")

    # 2. display.platforms.feishu (MINIMAL tier)
    platforms = d.setdefault("platforms", {}) or {}
    merged_feishu, feishu_changed = _merge_feishu_display(platforms.get("feishu"))
    if feishu_changed:
        platforms["feishu"] = merged_feishu
        changed.append("display.platforms.feishu=MINIMAL")
    d["platforms"] = platforms
    cfg["display"] = d

    # 3. feishu.unauthorized_dm_behavior — only if absent. Respect user choice.
    feishu_block = cfg.setdefault("feishu", {}) or {}
    if "unauthorized_dm_behavior" not in feishu_block:
        feishu_block["unauthorized_dm_behavior"] = "pair"
        changed.append("feishu.unauthorized_dm_behavior=pair (new key)")
    cfg["feishu"] = feishu_block

    if not changed:
        print("already up to date — no changes.")
        return

    ts = datetime.now().strftime("%Y%m%d%H%M%S")
    bak = CONFIG.with_suffix(f".yaml.bak.review-agent-{ts}")
    shutil.copy2(CONFIG, bak)
    with open(CONFIG, "w") as f:
        yaml.safe_dump(cfg, f, allow_unicode=True, default_flow_style=False,
                       sort_keys=False)
    print("patched:")
    for c in changed:
        print(f"  • {c}")
    print(f"backup: {bak}")
    print()
    print("run 'hermes gateway restart' (or 'systemctl --user restart hermes-gateway' on Linux) to apply.")


if __name__ == "__main__":
    main()
