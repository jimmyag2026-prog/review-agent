#!/usr/bin/env python3
"""check_lark_scopes.py — verify the Lark app has the scopes review-agent needs.

Runs after Phase B setup but is strictly a warning — granting missing scopes
requires going to the Lark developer console and possibly an app-admin review,
so this script never blocks the install.

Checks:
  1. Reads FEISHU_APP_ID + FEISHU_APP_SECRET from ~/.hermes/.env.
  2. Fetches an app access token.
  3. Queries /open-apis/application/v6/applications/{app_id}/scopes
     (or falls back to making a harmless API call per required scope).
  4. Reports per-scope PRESENT / MISSING with a link to the app console
     where the user can grant them.

Exit codes:
  0 — check ran (regardless of result) OR creds missing (soft no-op)
  0 — network failure (fail open — never blocks)

Usage:
  python3 install/check_lark_scopes.py
  python3 install/check_lark_scopes.py --json
"""
import argparse
import json
import os
import sys
import urllib.request
import urllib.error
from pathlib import Path


REQUIRED_SCOPES = [
    ("im:message",             "send/receive DMs"),
    ("im:message:send_as_bot", "send messages as the bot"),
    ("docx:document",          "create/edit Lark docs for review publish"),
    ("drive:file",             "share Lark docs to Responder + Requester"),
    ("drive:drive",            "list/create drive artifacts"),
]

HERMES_ENV = Path.home() / ".hermes" / ".env"
API_BASE_LARK   = "https://open.larksuite.com"
API_BASE_FEISHU = "https://open.feishu.cn"


def load_env():
    if not HERMES_ENV.exists():
        return {}
    out = {}
    for line in HERMES_ENV.read_text().splitlines():
        if "=" not in line or line.startswith("#"):
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def pick_api_base(env):
    """Choose api host based on FEISHU_DOMAIN env."""
    domain = env.get("FEISHU_DOMAIN", "lark").lower()
    return API_BASE_FEISHU if domain == "feishu" else API_BASE_LARK


def fetch_tenant_token(env):
    """Get a tenant access token. Returns (token, base_url) or (None, base_url)."""
    base = pick_api_base(env)
    app_id = env.get("FEISHU_APP_ID")
    app_secret = env.get("FEISHU_APP_SECRET")
    if not app_id or not app_secret:
        return None, base
    url = f"{base}/open-apis/auth/v3/tenant_access_token/internal"
    body = json.dumps({"app_id": app_id, "app_secret": app_secret}).encode()
    req = urllib.request.Request(url, data=body,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=6) as r:
            d = json.loads(r.read())
        if d.get("code") == 0:
            return d.get("tenant_access_token"), base
        return None, base
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError):
        return None, base
    except Exception:
        return None, base


def probe_scope(base, token, scope):
    """Best-effort probe per scope. Returns 'present' | 'missing' | 'unknown'.

    Strategy: call an endpoint that exercises the scope, inspect the response
    code. Scope-denied errors return 1254000-range codes or HTTP 403 with a
    'scope' keyword in the message.

    For docx:document we deliberately request a non-existent doc id: a 1254006
    (doc not found) / 404 response means we DO have the scope (otherwise we'd
    be rejected at auth); any explicit scope error means we don't.
    """
    # (endpoint, expected_success_codes, expected_not_found_codes_that_imply_scope_granted)
    endpoints = {
        "im:message":             ("/open-apis/im/v1/chats?page_size=1", [0], []),
        "im:message:send_as_bot": ("/open-apis/im/v1/chats?page_size=1", [0], []),
        # docx: fetch a bogus document. Lark requires doc_id >=27 chars — use
        # a syntactically-plausible fake. 1254006 / 1770002 = "doc not found"
        # → scope OK. HTTP 404 is also treated as "present" generically.
        "docx:document":          ("/open-apis/docx/v1/documents/doxcnAAAAAAAAAAAAAAAAAAAAAA/raw_content", [0, 1254006, 1770002], [1254006, 1770002]),
        "drive:file":             ("/open-apis/drive/v1/files?page_size=1", [0], []),
        "drive:drive":            ("/open-apis/drive/v1/files?page_size=1", [0], []),
    }
    tup = endpoints.get(scope)
    if not tup:
        return "unknown"
    path, ok_codes, granted_not_found_codes = tup
    url = f"{base}{path}"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, timeout=6) as r:
            d = json.loads(r.read())
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            return "missing"
        # HTTP 404 on a probe URL means the endpoint is reachable and the
        # scope allowed us through — we just couldn't find the fake resource.
        if e.code == 404:
            return "present"
        # Some Lark endpoints return 400 with body codes — parse to disambiguate
        try:
            body = json.loads(e.read())
            code = body.get("code", -1)
            if code in ok_codes or code in granted_not_found_codes:
                return "present"
            msg = (body.get("msg") or "").lower()
            if "scope" in msg or code in (99991672, 99991663, 1254017, 1061004):
                return "missing"
        except Exception:
            pass
        return "unknown"
    except (urllib.error.URLError, TimeoutError, OSError):
        return "unknown"
    except Exception:
        return "unknown"

    code = d.get("code", -1)
    if code in ok_codes or code in granted_not_found_codes:
        return "present"
    msg = (d.get("msg") or "").lower()
    if "scope" in msg or "permission" in msg or code in (1254017, 1061004):
        return "missing"
    return "unknown"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", dest="as_json", action="store_true")
    args = ap.parse_args()

    env = load_env()
    token, base = fetch_tenant_token(env)

    if not token:
        msg = (
            "Lark scope check skipped — couldn't get a tenant access token "
            "(FEISHU_APP_ID/SECRET missing or network down). This is a soft "
            "check; you'll hit scope errors at runtime if any are missing."
        )
        if args.as_json:
            print(json.dumps({"status": "skipped", "reason": msg}))
        else:
            print(f"\033[0;33m!\033[0m {msg}")
        return 0

    console_url = (f"{'https://open.feishu.cn' if 'feishu' in base else 'https://open.larksuite.com'}"
                   f"/app/{env.get('FEISHU_APP_ID','<app_id>')}/manage/permission")

    results = []
    for scope, purpose in REQUIRED_SCOPES:
        state = probe_scope(base, token, scope)
        results.append({"scope": scope, "purpose": purpose, "state": state})

    missing = [r for r in results if r["state"] == "missing"]
    unknown = [r for r in results if r["state"] == "unknown"]

    if args.as_json:
        print(json.dumps({
            "status": "ran",
            "results": results,
            "console_url": console_url,
        }, indent=2, ensure_ascii=False))
        return 0

    for r in results:
        tag = {
            "present": "\033[0;32m✓ present\033[0m",
            "missing": "\033[0;31m✗ MISSING\033[0m",
            "unknown": "\033[0;33m? unknown\033[0m",
        }.get(r["state"], r["state"])
        print(f"  {tag}  {r['scope']:<26}  ({r['purpose']})")

    print()
    if missing:
        print(f"\033[0;33m!\033[0m {len(missing)} scope(s) missing. Grant them in the Lark app console:")
        print(f"    {console_url}")
        print(f"  After granting, restart the gateway:")
        print(f"    hermes gateway restart")
    elif unknown:
        print(f"\033[0;33m!\033[0m {len(unknown)} scope(s) couldn't be probed definitively.")
        print(f"  This usually means the probe endpoint returned an unrelated error.")
        print(f"  Check manually at: {console_url}")
    else:
        print("\033[0;32m✓\033[0m all required scopes present.")

    # Never block the install, regardless of outcome.
    return 0


if __name__ == "__main__":
    sys.exit(main())
