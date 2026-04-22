#!/usr/bin/env python3
"""lark-doc-publish.py — publish session material + findings as a Lark doc
with **inline agent callouts** (content-injection style, not side-panel comments).

Lark Open API doesn't expose true inline comment anchoring for docx. So instead
of whole-file side-panel comments, we interleave agent findings DIRECTLY INTO
the document content: each material paragraph is followed immediately by
styled "agent callout" text blocks for any finding whose anchor.snippet
matches that paragraph. Visually Requester sees:

    [material para 1]
    💬 [review-agent · Intent · BLOCKER]  Ask 不明确。建议：...
    💬 [review-agent · Materials · BLOCKER]  数据无来源。建议：...
    [material para 2]
    💬 ...

Agent callouts are distinguished by emoji prefix + italic style +
background color. Still uses Lark drive comments as SECONDARY audit trail
(shows total findings in side panel) but NOT for anchoring.
"""
import argparse
import json
import os
import sys
import urllib.request
import urllib.error
import urllib.parse
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
DOMAIN = "https://open.larksuite.com" if DOMAIN_RAW in ("lark", "larksuite") else "https://open.feishu.cn"
WEB_DOMAIN = DOMAIN.replace("open.", "")


def api(method, path, token=None, body=None, query=None):
    url = DOMAIN + path
    if query: url += "?" + urllib.parse.urlencode(query)
    headers = {"Content-Type": "application/json"}
    if token: headers["Authorization"] = f"Bearer {token}"
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


def get_token():
    s, r = api("POST", "/open-apis/auth/v3/tenant_access_token/internal",
               body={"app_id": APP_ID, "app_secret": APP_SECRET})
    return r.get("tenant_access_token", ""), r


def create_docx(token, title):
    s, r = api("POST", "/open-apis/docx/v1/documents", token=token,
               body={"title": title})
    if s == 200 and r.get("code") == 0:
        return r["data"]["document"]["document_id"], None
    return None, f"HTTP {s} code={r.get('code')} msg={r.get('msg')}"


def share_doc(token, doc_id, open_id, perm="view"):
    body = {"member_type": "openid", "member_id": open_id, "perm": perm, "type": "user"}
    s, r = api("POST", f"/open-apis/drive/v1/permissions/{doc_id}/members",
               token=token, body=body, query={"type": "docx", "need_notification": "false"})
    if s == 200 and r.get("code") == 0:
        return True, None
    return False, f"HTTP {s} code={r.get('code')} msg={r.get('msg')}"


# ── Block builders ──

def material_paragraph_block(text):
    """Plain material text as a normal paragraph."""
    return {
        "block_type": 2,
        "text": {
            "elements": [{"text_run": {"content": text}}],
            "style": {}
        }
    }


def header_paragraph_block(text):
    """Bold header paragraph."""
    return {
        "block_type": 2,
        "text": {
            "elements": [{"text_run": {"content": text,
                                       "text_element_style": {"bold": True}}}],
            "style": {}
        }
    }


# Severity → background color id (Lark color ids)
SEV_COLOR = {
    "BLOCKER": 1,       # light red-ish
    "IMPROVEMENT": 5,   # light yellow
    "NICE-TO-HAVE": 7,  # light gray
}


def agent_callout_block(finding):
    """Inline agent callout — styled text block visually distinct from material."""
    pillar = finding.get("pillar", "?")
    sev = finding.get("severity", "IMPROVEMENT")
    source = finding.get("source", "")
    is_sim = source == "responder_simulation"

    if is_sim:
        body = finding.get("simulated_question", "")
        header = f"💬 [review-agent · {pillar} · {sev} · Responder 视角追问]"
        content_parts = [body]
    else:
        issue = finding.get("issue", "")
        suggest = finding.get("suggest", "")
        header = f"💬 [review-agent · {pillar} · {sev}]"
        content_parts = [issue]
        if suggest:
            content_parts.append(f"建议：{suggest}")

    body_text = "  ·  ".join(content_parts)
    bg = SEV_COLOR.get(sev, 7)

    return {
        "block_type": 2,
        "text": {
            "elements": [
                {
                    "text_run": {
                        "content": header + "\n",
                        "text_element_style": {"bold": True, "italic": True, "background_color": bg}
                    }
                },
                {
                    "text_run": {
                        "content": body_text,
                        "text_element_style": {"italic": True, "background_color": bg}
                    }
                }
            ],
            "style": {}
        }
    }


def separator_block():
    """Pseudo-divider — just a styled text line (Lark API rejects block_type 17 for us)."""
    return {
        "block_type": 2,
        "text": {
            "elements": [{"text_run": {"content": "─" * 40,
                                       "text_element_style": {"text_color": 7}}}],
            "style": {}
        }
    }


# ── Content parsing ──

def split_paragraphs(text):
    """Split markdown-ish content into paragraphs (one string per paragraph)."""
    paragraphs = []
    for chunk in text.split("\n\n"):
        chunk = chunk.strip()
        if not chunk: continue
        lines = [l for l in chunk.split("\n") if l.strip()]
        if len(lines) == 1:
            paragraphs.append(lines[0])
        else:
            paragraphs.extend(lines)
    return paragraphs


def match_finding_to_paragraph(finding, paragraphs):
    """Return paragraph index (0-based) whose text contains the finding's anchor
    snippet, or None if no match."""
    snippet = (finding.get("anchor", {}) or {}).get("snippet", "")
    snippet = snippet.strip() if snippet else ""
    if not snippet:
        return None
    # Exact substring match
    for i, p in enumerate(paragraphs):
        if snippet in p:
            return i
    # Looser match: first 30 chars
    probe = snippet[:30]
    if probe:
        for i, p in enumerate(paragraphs):
            if probe in p:
                return i
    return None


def build_interleaved_children(subject, meta, paragraphs, findings):
    """Build the full block sequence for insertion:
       [header block(s), material + agent callouts interleaved, orphan-findings section]
    """
    children = []

    # Header
    children.append(header_paragraph_block(f"Review material for: {subject}"))
    children.append(material_paragraph_block(
        f"Requester: {meta.get('requester_open_id','?')}"
    ))
    children.append(material_paragraph_block(
        f"Responder: {meta.get('responder_open_id','?')}"
    ))
    children.append(material_paragraph_block(
        f"Session: {meta.get('session_id','?')}"
    ))
    children.append(separator_block())
    children.append(header_paragraph_block("── 材料 + 批注 ──"))

    # Bucket findings by paragraph index
    by_para = {}
    orphans = []
    for f in findings:
        if f.get("status") not in ("open", None):
            continue
        idx = match_finding_to_paragraph(f, paragraphs)
        if idx is None:
            orphans.append(f)
        else:
            by_para.setdefault(idx, []).append(f)

    # Interleave
    for i, p in enumerate(paragraphs):
        children.append(material_paragraph_block(p))
        for f in by_para.get(i, []):
            children.append(agent_callout_block(f))

    # Orphans
    if orphans:
        children.append(separator_block())
        children.append(header_paragraph_block("── 未锚定到具体段落的 finding ──"))
        for f in orphans:
            children.append(agent_callout_block(f))

    return children, by_para, orphans


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("session_dir")
    ap.add_argument("--no-share", action="store_true")
    ap.add_argument("--no-drive-comments", action="store_true",
                    help="skip secondary whole-file drive comments (audit trail)")
    args = ap.parse_args()

    sd = Path(args.session_dir)
    if not sd.is_dir():
        print(f"error: {sd} not a directory", file=sys.stderr); return 2

    meta_path = sd / "meta.json"
    meta = json.load(open(meta_path))

    if not APP_ID or not APP_SECRET:
        print("error: FEISHU creds missing", file=sys.stderr); return 2

    tok, _ = get_token()
    if not tok:
        print("error: token fetch failed", file=sys.stderr); return 3

    doc_id = meta.get("lark_doc_id")
    subject = meta.get("subject", "")
    already_published = set(meta.get("commented_finding_ids", []))

    # Load content + findings
    normalized = (sd / "normalized.md").read_text() if (sd / "normalized.md").exists() else ""
    anns_path = sd / "annotations.jsonl"
    anns = [json.loads(l) for l in anns_path.read_text().splitlines() if l.strip()] if anns_path.exists() else []
    paragraphs = split_paragraphs(normalized) if normalized else []

    # Only publish findings that haven't been (to keep idempotent across scan rounds)
    new_findings = [a for a in anns if a.get("id") not in already_published
                    and a.get("status") in ("open", None)]

    if not doc_id:
        # First publish — create doc + insert full interleaved content
        title = f"【Review】{subject}"
        doc_id, err = create_docx(tok, title)
        if not doc_id:
            print(f"create doc failed: {err}", file=sys.stderr); return 4
        meta["lark_doc_id"] = doc_id
        meta["lark_doc_url"] = f"{WEB_DOMAIN}/docx/{doc_id}"
        print(f"[lark-doc-publish] created doc_id={doc_id}", file=sys.stderr)

        # Get root block
        s, r = api("GET", f"/open-apis/docx/v1/documents/{doc_id}/blocks",
                   token=tok, query={"document_revision_id": -1, "page_size": 20})
        if s != 200 or r.get("code") != 0:
            print(f"get root block failed: {r}", file=sys.stderr); return 5
        root = r["data"]["items"][0]["block_id"]

        # Build interleaved children
        children, by_para, orphans = build_interleaved_children(subject, meta, paragraphs, anns)
        print(f"[lark-doc-publish] inserting {len(children)} blocks "
              f"({len(paragraphs)} paragraphs + {sum(len(v) for v in by_para.values())} inline callouts + "
              f"{len(orphans)} orphan findings)", file=sys.stderr)

        s, r = api("POST", f"/open-apis/docx/v1/documents/{doc_id}/blocks/{root}/children",
                   token=tok, body={"children": children, "index": 0})
        if s != 200 or r.get("code") != 0:
            print(f"insert blocks failed: {r}", file=sys.stderr); return 6

        inserted_ids = [b.get("block_id") for b in r["data"].get("children", [])]
        print(f"[lark-doc-publish] inserted {len(inserted_ids)} blocks", file=sys.stderr)

        # Mark all findings as published
        all_fids = [a["id"] for a in anns if a.get("status") in ("open", None) and a.get("id")]
        already_published.update(all_fids)

        # Share doc
        if not args.no_share:
            req_oid = meta.get("requester_open_id")
            resp_oid = meta.get("responder_open_id")
            shared = []
            if req_oid:
                ok, err = share_doc(tok, doc_id, req_oid, perm="edit")
                shared.append(f"req={'ok' if ok else err}")
            if resp_oid:
                ok, err = share_doc(tok, doc_id, resp_oid, perm="view")
                shared.append(f"resp={'ok' if ok else err}")
            print(f"[lark-doc-publish] shared: {', '.join(shared)}", file=sys.stderr)

    else:
        # Doc already exists — incremental add for new findings only.
        # Append them at the end as an orphan section (can't re-insert into middle without knowing
        # which block_id came from which paragraph).
        if new_findings:
            s, r = api("GET", f"/open-apis/docx/v1/documents/{doc_id}/blocks",
                       token=tok, query={"document_revision_id": -1, "page_size": 100})
            if s == 200 and r.get("code") == 0:
                root = r["data"]["items"][0]["block_id"]
                children = [separator_block(),
                            header_paragraph_block(f"── 新增 findings (round {meta.get('round', 1)+1}) ──")]
                for f in new_findings:
                    children.append(agent_callout_block(f))
                api("POST", f"/open-apis/docx/v1/documents/{doc_id}/blocks/{root}/children",
                    token=tok, body={"children": children, "index": len(r["data"]["items"])})
                already_published.update(f["id"] for f in new_findings if f.get("id"))
                print(f"[lark-doc-publish] appended {len(new_findings)} new findings at end", file=sys.stderr)

    meta["commented_finding_ids"] = sorted(already_published)
    meta["lark_doc_updated_at"] = datetime.now().astimezone().isoformat(timespec="seconds")
    json.dump(meta, open(meta_path, "w"), indent=2, ensure_ascii=False)

    # stdout: URL
    print(meta["lark_doc_url"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
