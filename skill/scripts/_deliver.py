#!/usr/bin/env python3
"""Execute delivery targets for a closed session.

Backends in v0:
  - local_path  : copy payload files into a directory
  - lark_dm     : send text via Lark Open API (uses send-lark.sh)
  - email_smtp  : send via ~/bin/send_mail
"""
import json
import os
import sys
import shutil
import subprocess
from datetime import datetime
from pathlib import Path


LOG_PATH = Path(os.environ.get(
    "REVIEW_AGENT_ROOT", str(Path.home() / ".review-agent")
)) / "logs" / "delivery.jsonl"


def log(record):
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    record["ts"] = datetime.now().astimezone().isoformat(timespec="seconds")
    with open(LOG_PATH, "a") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")


def substitute(s, vars_):
    if not isinstance(s, str):
        return s
    for k, v in vars_.items():
        s = s.replace("{{" + k + "}}", str(v))
    return s


def collect_payload(session_dir, payload_list):
    sd = Path(session_dir)
    files = []
    if "summary" in payload_list and (sd / "summary.md").exists():
        files.append(sd / "summary.md")
    if "summary_audit" in payload_list and (sd / "summary_audit.md").exists():
        files.append(sd / "summary_audit.md")
    if "final" in payload_list and (sd / "final").exists():
        for f in sorted((sd / "final").iterdir()):
            if f.is_file():
                files.append(f)
    if "conversation" in payload_list and (sd / "conversation.jsonl").exists():
        files.append(sd / "conversation.jsonl")
    if "annotations" in payload_list and (sd / "annotations.jsonl").exists():
        files.append(sd / "annotations.jsonl")
    if "dissent" in payload_list and (sd / "dissent.md").exists():
        files.append(sd / "dissent.md")
    return files


def deliver_local_path(target, session_dir, vars_):
    path = Path(os.path.expanduser(substitute(target["path"], vars_))).resolve()
    path.mkdir(parents=True, exist_ok=True)
    files = collect_payload(session_dir, target.get("payload", ["summary"]))
    for src in files:
        dst = path / src.name
        shutil.copy2(src, dst)
    log({"target": target.get("name"), "backend": "local_path", "path": str(path),
         "files": [f.name for f in files], "ok": True})
    print(f"  local_path → {path} ({len(files)} files)")


def find_lark_send():
    candidates = [
        Path.home() / "bin" / "lark_send",
        Path(__file__).parent / "send-lark.sh",
    ]
    for c in candidates:
        if c.exists():
            return c
    return None


def deliver_lark_dm(target, session_dir, vars_):
    open_id = substitute(target["open_id"], vars_)
    if not open_id or open_id.startswith("{{"):
        log({"target": target.get("name"), "backend": "lark_dm",
             "ok": False, "error": f"unresolved open_id: {open_id}"})
        print(f"  lark_dm → SKIP (open_id unresolved: {open_id})")
        return
    payload_files = collect_payload(session_dir, target.get("payload", ["summary"]))
    summary_path = next((f for f in payload_files if f.name == "summary.md"), None)
    if not summary_path:
        log({"target": target.get("name"), "backend": "lark_dm",
             "ok": False, "error": "no summary.md"})
        return
    text = summary_path.read_text()
    if len(text) > 60000:
        text = text[:60000] + "\n\n_[truncated, see local archive]_"
    binary = find_lark_send()
    if not binary:
        log({"target": target.get("name"), "backend": "lark_dm",
             "ok": False, "error": "no lark_send binary found"})
        print(f"  lark_dm → FAIL (no lark_send)")
        return
    try:
        result = subprocess.run(
            [str(binary), "--open-id", open_id, "--text", text],
            capture_output=True, text=True, timeout=30
        )
        ok = result.returncode == 0
        log({"target": target.get("name"), "backend": "lark_dm",
             "open_id": open_id, "ok": ok,
             "stderr": result.stderr[-500:] if not ok else ""})
        print(f"  lark_dm → {'OK' if ok else 'FAIL'} (open_id={open_id})")
    except Exception as e:
        log({"target": target.get("name"), "backend": "lark_dm",
             "ok": False, "error": str(e)})
        print(f"  lark_dm → FAIL ({e})")


def deliver_email_smtp(target, session_dir, vars_):
    to = substitute(target["to"], vars_)
    subject = substitute(target.get("subject", "[Review] {{session_subject}}"), vars_)
    body_source = target.get("body_source", "summary")
    files = collect_payload(session_dir, target.get("payload", ["summary"]))
    body_file = next((f for f in files if f.name in (f"{body_source}.md", body_source)), None)
    if not body_file and files:
        body_file = files[0]
    if not body_file:
        log({"target": target.get("name"), "backend": "email_smtp",
             "ok": False, "error": "no body source"})
        return
    send_mail = Path.home() / "bin" / "send_mail"
    if not send_mail.exists():
        log({"target": target.get("name"), "backend": "email_smtp",
             "ok": False, "error": "no ~/bin/send_mail"})
        print(f"  email_smtp → FAIL (no ~/bin/send_mail)")
        return
    try:
        args = [str(send_mail), "--to", to, "--subject", subject, "--body-file", str(body_file)]
        for f in files:
            if f != body_file:
                args += ["--attach", str(f)]
        result = subprocess.run(args, capture_output=True, text=True, timeout=60)
        ok = result.returncode == 0
        log({"target": target.get("name"), "backend": "email_smtp",
             "to": to, "ok": ok,
             "stderr": result.stderr[-500:] if not ok else ""})
        print(f"  email_smtp → {'OK' if ok else 'FAIL'} (to={to})")
    except Exception as e:
        log({"target": target.get("name"), "backend": "email_smtp",
             "ok": False, "error": str(e)})
        print(f"  email_smtp → FAIL ({e})")


def check_filter(target, session_dir):
    flt = target.get("filter")
    if not flt:
        return True
    meta = json.load(open(Path(session_dir) / "meta.json"))
    tags = set(meta.get("tags", []))
    if "tags_any" in flt and not (set(flt["tags_any"]) & tags):
        return False
    if "tags_all" in flt and not (set(flt["tags_all"]) <= tags):
        return False
    if "termination" in flt and meta.get("termination") != flt["termination"]:
        return False
    return True


def main(session_dir, requester_open_id, responder_open_id, delivery_targets_path):
    meta = json.load(open(Path(session_dir) / "meta.json"))
    now = datetime.now().astimezone()
    vars_ = {
        "session_id": meta["session_id"],
        "session_subject": meta.get("subject", ""),
        "requester_open_id": requester_open_id,
        "REQUESTER_OPEN_ID": requester_open_id,
        "responder_open_id": responder_open_id,
        "RESPONDER_OPEN_ID": responder_open_id,
        # legacy aliases
        "briefer_open_id": requester_open_id,
        "BRIEFER_OPEN_ID": requester_open_id,
        "YYYY": f"{now.year:04d}",
        "MM": f"{now.month:02d}",
        "DD": f"{now.day:02d}",
        "termination": meta.get("termination", "unknown"),
    }
    cfg = json.load(open(delivery_targets_path))
    targets = cfg.get("on_close", [])
    archive = [t for t in targets if t.get("backend") == "local_path"]
    other = [t for t in targets if t.get("backend") != "local_path"]

    for t in archive + other:
        if not check_filter(t, session_dir):
            print(f"  {t.get('name')} → SKIP (filter)")
            continue
        backend = t.get("backend")
        try:
            if backend == "local_path":
                deliver_local_path(t, session_dir, vars_)
            elif backend == "lark_dm":
                deliver_lark_dm(t, session_dir, vars_)
            elif backend == "email_smtp":
                deliver_email_smtp(t, session_dir, vars_)
            else:
                log({"target": t.get("name"), "backend": backend,
                     "ok": False, "error": "backend not implemented"})
                print(f"  {backend} → not implemented in v0")
        except Exception as e:
            log({"target": t.get("name"), "backend": backend,
                 "ok": False, "error": str(e)})
            print(f"  {t.get('name')} → FAIL ({e})")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        print("usage: _deliver.py <session_dir> <requester_open_id> <responder_open_id> <delivery_targets.json>",
              file=sys.stderr)
        sys.exit(1)
    main(*sys.argv[1:5])
