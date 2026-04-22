#!/usr/bin/env python3
"""lark-doc-probe.py — connectivity probe for Lark docx write + comment APIs.

Tests, in order:
  1. Tenant access token (read only — already known to work)
  2. Create a new docx (write scope: docx:document)
  3. Insert text blocks into the docx (same scope)
  4. Add a whole-file comment via Drive API
  5. Add a position-specific / block-anchored comment

Reports pass/fail per step. Only creates; does not delete (user can clean up
via the reported doc URL or use --cleanup flag after).

Usage:
  lark-doc-probe.py [--keep-doc]    # keep doc after probe (default: keep)
  lark-doc-probe.py --cleanup <doc_token>  # delete a previously created probe doc
"""
import argparse
import json
import os
import sys
import urllib.request
import urllib.error
from datetime import datetime
from pathlib import Path


def load_env_key(env_path, key):
    if not Path(env_path).exists(): return None
    for line in Path(env_path).read_text().splitlines():
        if line.startswith(f"{key}="):
            return line.split("=", 1)[1].strip()
    return None


HERMES_ENV = Path.home() / ".hermes" / ".env"
APP_ID = load_env_key(HERMES_ENV, "FEISHU_APP_ID")
APP_SECRET = load_env_key(HERMES_ENV, "FEISHU_APP_SECRET")
DOMAIN_RAW = load_env_key(HERMES_ENV, "FEISHU_DOMAIN") or "lark"
DOMAIN = "https://open.larksuite.com" if DOMAIN_RAW in ("lark","larksuite") else "https://open.feishu.cn"


def api(method: str, path: str, token: str = None, body: dict = None, query: dict = None):
    """Thin request wrapper. Returns (status, json_body)."""
    import urllib.parse
    url = DOMAIN + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        try: body = json.loads(e.read())
        except: body = {"error": e.reason, "status": e.code}
        return e.code, body
    except Exception as e:
        return 0, {"error": str(e)}


def step(n, label):
    print(f"\n─── Step {n}: {label} ─────────────────")


def result(ok, msg):
    mark = "✓" if ok else "✗"
    print(f"  {mark} {msg}")
    return ok


def get_token():
    status, resp = api("POST", "/open-apis/auth/v3/tenant_access_token/internal",
                       body={"app_id": APP_ID, "app_secret": APP_SECRET})
    tok = resp.get("tenant_access_token", "")
    return tok, resp


def main_cleanup(doc_token):
    tok, _ = get_token()
    if not tok:
        print("cannot get token"); return 1
    s, r = api("DELETE", f"/open-apis/docx/v1/documents/{doc_token}", token=tok)
    print(f"delete {doc_token}: status={s} body={r}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cleanup", metavar="DOC_TOKEN",
                    help="delete a previously created doc by token")
    ap.add_argument("--keep-doc", action="store_true", default=True,
                    help="(default) keep the created doc for inspection")
    args = ap.parse_args()

    if args.cleanup:
        return main_cleanup(args.cleanup)

    if not APP_ID or not APP_SECRET:
        print("error: FEISHU_APP_ID / FEISHU_APP_SECRET not found in ~/.hermes/.env")
        return 2

    print(f"Domain: {DOMAIN}")
    print(f"App:    {APP_ID}")

    # ─── Step 1: token ───
    step(1, "tenant_access_token")
    tok, resp = get_token()
    if not result(bool(tok), f"code={resp.get('code')} msg={resp.get('msg','?')}"):
        return 3

    # ─── Step 2: create docx ───
    step(2, "create new docx  (POST /open-apis/docx/v1/documents)")
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    s, r = api("POST", "/open-apis/docx/v1/documents", token=tok,
               body={"title": f"【review-agent probe】{ts}"})
    if s != 200 or r.get("code") != 0:
        result(False, f"HTTP {s}, body={r}")
        print("\n→ 缺 docx:document 写权限。去 Lark 开发者后台给 myhermes app 加:")
        print("   docx:document  (读+写)  /或独立的  docx:document:create")
        return 4
    doc = r.get("data", {}).get("document", {})
    doc_id = doc.get("document_id", "")
    title = doc.get("title", "")
    revision_id = doc.get("revision_id", 0)
    result(True, f"created doc_id={doc_id}  title='{title}'")
    doc_url = f"{DOMAIN.replace('open.', '')}/docx/{doc_id}"
    print(f"    URL: {doc_url}")

    # ─── Step 3: fetch root block ───
    step(3, "get doc blocks (find root page block to insert under)")
    s, r = api("GET", f"/open-apis/docx/v1/documents/{doc_id}/blocks",
               token=tok, query={"document_revision_id": -1, "page_size": 20})
    if s != 200 or r.get("code") != 0:
        result(False, f"HTTP {s}, body={r}")
        return 5
    blocks = r.get("data", {}).get("items", [])
    result(True, f"found {len(blocks)} block(s); root={blocks[0]['block_id'] if blocks else '(none)'}")
    if not blocks:
        return 5
    root_block_id = blocks[0]["block_id"]   # page block

    # ─── Step 4: insert text blocks ───
    step(4, "insert 3 text blocks (block API batch_update)")
    insert_body = {
        "children": [
            {
                "block_type": 2,   # text block
                "text": {
                    "elements": [
                        {"text_run": {"content": "这是 review-agent 的连通性测试文档。"}}
                    ],
                    "style": {}
                }
            },
            {
                "block_type": 2,
                "text": {
                    "elements": [
                        {"text_run": {"content": "第二段：agent 在此位置建议补充数据来源。"}}
                    ],
                    "style": {}
                }
            },
            {
                "block_type": 2,
                "text": {
                    "elements": [
                        {"text_run": {"content": "第三段：agent 建议删除，因为与核心论点无关。"}}
                    ],
                    "style": {}
                }
            }
        ],
        "index": 0
    }
    s, r = api("POST",
               f"/open-apis/docx/v1/documents/{doc_id}/blocks/{root_block_id}/children",
               token=tok, body=insert_body)
    if s != 200 or r.get("code") != 0:
        result(False, f"HTTP {s}, body={r}")
        return 6
    new_blocks = r.get("data", {}).get("children", [])
    inserted_ids = [b.get("block_id") for b in new_blocks]
    result(True, f"inserted {len(inserted_ids)} blocks: {inserted_ids}")

    # ─── Step 5: add whole-file comment ───
    step(5, "add whole-file comment  (POST /open-apis/drive/v1/files/:token/comments)")
    # Lark API expects reply_list.replies[0].content.elements
    comment_body = {
        "is_whole": True,
        "reply_list": {
            "replies": [
                {
                    "content": {
                        "elements": [
                            {"type": "text_run",
                             "text_run": {"text": "[review-agent] 整份文档总评：需要加数据来源和明确 ask。"}}
                        ]
                    }
                }
            ]
        }
    }
    s, r = api("POST",
               f"/open-apis/drive/v1/files/{doc_id}/comments",
               token=tok,
               body=comment_body,
               query={"file_type": "docx"})
    whole_comment_id = None
    if s == 200 and r.get("code") == 0:
        whole_comment_id = r.get("data", {}).get("comment_id")
        result(True, f"whole-file comment created: {whole_comment_id}")
    else:
        result(False, f"HTTP {s}, code={r.get('code')}, msg={r.get('msg')}, body={str(r)[:400]}")

    # ─── Step 6: try block-anchored comment (position-specific, via quote) ───
    step(6, "add block-anchored comment (quote= paragraph 2 text)")
    if len(inserted_ids) < 2:
        result(False, "not enough inserted blocks to anchor")
    else:
        comment_body2 = {
            "is_whole": False,
            "quote": "第二段：agent 在此位置建议补充数据来源。",
            "reply_list": {
                "replies": [
                    {
                        "content": {
                            "elements": [
                                {"type": "text_run",
                                 "text_run": {"text": "[review-agent] 这一段需要补 DAU / 留存率数据，请给来源。"}}
                            ]
                        }
                    }
                ]
            }
        }
        s, r = api("POST",
                   f"/open-apis/drive/v1/files/{doc_id}/comments",
                   token=tok,
                   body=comment_body2,
                   query={"file_type": "docx"})
        if s == 200 and r.get("code") == 0:
            cid = r.get("data", {}).get("comment_id")
            result(True, f"block-anchored comment created: {cid} (quote matched paragraph 2)")
        else:
            result(False, f"HTTP {s}, code={r.get('code')}, msg={r.get('msg')}, body={str(r)[:400]}")

    # ─── summary ───
    print("\n─── summary ───")
    print(f"  Doc created:     {doc_url}")
    print(f"  Doc token:       {doc_id}")
    print(f"  Inserted blocks: {len(inserted_ids)}")
    print(f"  Whole comment:   {'YES' if whole_comment_id else 'NO'}")
    print(f"  To clean up:     python3 {sys.argv[0]} --cleanup {doc_id}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
