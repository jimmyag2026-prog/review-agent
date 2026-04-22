#!/usr/bin/env python3
"""admin_notify_patch.py — idempotent local patch of hermes gateway to DM
Admin(s) whenever a new user triggers the pairing flow.

Rationale (see docs/HERMES_FEISHU_HARDENING.md):
  - Upstream hermes sends the pairing code to the requesting user, but does
    NOT notify the Admin. You only find out by polling `hermes pairing list`.
  - Adding a best-effort hook after the code-send is a small, local change.
  - The hermes-agent repo is upstream (NousResearch/hermes-agent), so any
    `hermes update` overwrites run.py. This patcher is idempotent and
    marker-guarded so it can be re-run after every update.

What it does:
  1. Locates gateway/run.py (path required via --run-py).
  2. If marker `_notify_pairing_admins` already present → exits 0 (no-op).
  3. Timestamped backup → run.py.pre_admin_patch.<ts>.
  4. Inserts the helper function + hook call at the first matching anchor.
  5. Dry-run preview available via --dry-run.

The patch is conservative: if anchors aren't found (hermes source changed
shape), it exits non-zero with instructions instead of guessing. You can
then adapt the ANCHOR_* constants below for your local hermes version.

Usage:
  python3 admin_notify_patch.py --run-py ~/.hermes/hermes-agent/gateway/run.py
  python3 admin_notify_patch.py --run-py <path> --dry-run
  python3 admin_notify_patch.py --run-py <path> --revert   # restore latest backup
"""
import argparse
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path


MARKER_HELPER_NAME = "_notify_pairing_admins"

# Anchor 1 — where to INSERT the helper function.
# We insert just before the first top-level `async def` in the file.
ANCHOR_HELPER_INSERT = re.compile(r"^(async def [A-Za-z_][\w]*\()", re.M)

# Anchor 2 — where to CALL the hook. Upstream hermes, after generating a
# pairing code, does something like `await adapter.send(chat_id, ...)` in
# the unauthorized-DM handler. We call the hook on the line after the first
# `await adapter.send(` that's within ~50 lines of a `generate_code` call.
ANCHOR_CALL_REGEX = re.compile(
    r"(\n([ \t]+)await\s+adapter\.send\(.*?\)\s*?\n)",
    re.S,
)

HELPER_BODY = '''
# ─── review-agent local patch: admin-notify on pairing ─────────────────
import os as _ra_os
import json as _ra_json
import uuid as _ra_uuid
import asyncio as _ra_asyncio
import logging as _ra_logging

_RA_LOG = _ra_logging.getLogger("hermes.admin_notify")


async def _notify_pairing_admins(adapter, platform_name, source, code, requester_open_id=None):
    """Best-effort DM to each open_id in FEISHU_ADMIN_USERS env.
    Never raises — a failed notify must not break the pairing flow.
    """
    raw = _ra_os.environ.get("FEISHU_ADMIN_USERS", "").strip()
    if not raw:
        return
    admin_ids = [x.strip() for x in raw.split(",") if x.strip()]
    if not admin_ids:
        return
    text = (
        f"[hermes] Pairing requested by open_id={requester_open_id or '?'}, "
        f"code={code} (source={source}, platform={platform_name})"
    )
    for aid in admin_ids:
        try:
            body = adapter._build_create_message_body(
                receive_id=aid,
                msg_type="text",
                content=_ra_json.dumps({"text": text}, ensure_ascii=False),
                uuid_value=str(_ra_uuid.uuid4()),
            )
            req = adapter._build_create_message_request("open_id", body)
            await _ra_asyncio.to_thread(adapter._client.im.v1.message.create, req)
        except Exception as e:   # noqa: BLE001
            _RA_LOG.warning("admin-notify failed for %s: %s", aid, e)
# ─── /review-agent local patch ─────────────────────────────────────────

'''

HOOK_CALL_TEMPLATE = (
    '{indent}# review-agent local patch: notify admin(s) of new pairing\n'
    '{indent}try:\n'
    '{indent}    await _notify_pairing_admins(adapter, platform_name, source, code, '
    'requester_open_id=locals().get("open_id") or locals().get("user_open_id"))\n'
    '{indent}except Exception:\n'
    '{indent}    pass\n'
)


def find_latest_backup(run_py: Path):
    candidates = sorted(run_py.parent.glob(run_py.name + ".pre_admin_patch.*"))
    return candidates[-1] if candidates else None


def do_revert(run_py: Path):
    bak = find_latest_backup(run_py)
    if not bak:
        print("no backup found; nothing to revert.", file=sys.stderr)
        sys.exit(2)
    shutil.copy2(bak, run_py)
    print(f"reverted {run_py} ← {bak.name}")


def do_patch(run_py: Path, dry_run: bool):
    src = run_py.read_text()

    if MARKER_HELPER_NAME in src:
        print(f"already patched (marker '{MARKER_HELPER_NAME}' present). no-op.")
        return 0

    # Anchor 1 — helper insertion point
    m1 = ANCHOR_HELPER_INSERT.search(src)
    if not m1:
        print(
            "error: couldn't find a top-level 'async def' to anchor the helper.\n"
            "  your hermes source shape may differ. Inspect run.py and either:\n"
            "    (a) update ANCHOR_HELPER_INSERT in this patch script, or\n"
            "    (b) apply the patch manually (see docs/HERMES_FEISHU_HARDENING.md).",
            file=sys.stderr,
        )
        return 2

    # Anchor 2 — hook call insertion point (right after adapter.send that
    # follows a generate_code)
    gc_idx = src.find("generate_code")
    if gc_idx < 0:
        print(
            "error: no 'generate_code' reference found in run.py.\n"
            "  your hermes version may structure pairing differently.\n"
            "  inspect the file and patch manually if needed.",
            file=sys.stderr,
        )
        return 2
    m2 = ANCHOR_CALL_REGEX.search(src, pos=gc_idx)
    if not m2:
        print(
            "error: found 'generate_code' but no 'await adapter.send(...)' after it.\n"
            "  insertion anchor not obvious — review manually.",
            file=sys.stderr,
        )
        return 2

    indent = m2.group(2)
    hook_block = HOOK_CALL_TEMPLATE.format(indent=indent)

    # Build new source: insert helper before first async def, then hook after
    # the matched adapter.send. Do hook-insert FIRST (preserves m1 position).
    new_src = src[:m2.end()] + hook_block + src[m2.end():]
    # Re-locate helper anchor in the new_src (positions shifted after m2)
    m1_new = ANCHOR_HELPER_INSERT.search(new_src)
    assert m1_new, "helper anchor disappeared after hook insert"
    new_src = new_src[:m1_new.start()] + HELPER_BODY + new_src[m1_new.start():]

    if dry_run:
        print(f"--- {run_py} (dry-run) ---")
        print(f"helper would be inserted at byte {m1_new.start()}")
        print(f"hook call would be inserted after byte {m2.end()}")
        print(f"new file would be {len(new_src)} bytes (was {len(src)})")
        return 0

    ts = datetime.now().strftime("%Y%m%d%H%M%S")
    bak = run_py.with_suffix(run_py.suffix + f".pre_admin_patch.{ts}")
    shutil.copy2(run_py, bak)
    run_py.write_text(new_src)
    print(f"patched {run_py}")
    print(f"backup: {bak}")
    print()
    print("next steps:")
    print("  1. ensure FEISHU_ADMIN_USERS=<ou_xxxx[,ou_yyyy...]> is set in ~/.hermes/.env")
    print("  2. systemctl --user restart hermes-gateway")
    print("  3. test: DM the bot from an account NOT in FEISHU_ALLOWED_USERS — you (the Admin) should receive a notification within ~2s.")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-py", required=True,
                    help="path to hermes gateway/run.py")
    ap.add_argument("--dry-run", action="store_true",
                    help="show what would change without writing")
    ap.add_argument("--revert", action="store_true",
                    help="restore the latest .pre_admin_patch.<ts> backup")
    args = ap.parse_args()

    run_py = Path(args.run_py).expanduser().resolve()
    if not run_py.exists():
        print(f"error: {run_py} not found", file=sys.stderr)
        sys.exit(2)

    if args.revert:
        do_revert(run_py)
        return

    rc = do_patch(run_py, args.dry_run)
    sys.exit(rc or 0)


if __name__ == "__main__":
    main()
