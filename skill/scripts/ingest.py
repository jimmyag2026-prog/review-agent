#!/usr/bin/env python3
"""Multi-modal input ingest for review-agent.

Scans sessions/<id>/input/ for artifacts, dispatches to appropriate extractors,
and produces sessions/<id>/normalized.md as the canonical text for review.

Supported:
  - .md / .txt / .markdown → copy as-is
  - .pdf → pdftotext (if available) / python pdfminer (fallback)
  - .png / .jpg / .jpeg / .webp → OCR (tesseract if available; else skip+warn)
  - .wav / .mp3 / .m4a / .ogg / .flac → whisper transcription
  - Lark / Feishu doc or wiki URL in a .url or .txt file → lark-fetch
  - Google Docs URL → gdrive CLI (if available)
  - .jsonl → pretty-print text content
  - unknown → warn + skip

Also scans input/*.txt files for URLs and fetches those inline.

Usage:
  ingest.py <session_dir> [--force]
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path


def which(cmd):
    return shutil.which(cmd)


def log(session_dir, msg):
    with open(Path(session_dir) / "ingest.log", "a") as f:
        f.write(f"[{datetime.now().astimezone().isoformat(timespec='seconds')}] {msg}\n")


def read_text(p: Path):
    try:
        return p.read_text(encoding="utf-8")
    except Exception as e:
        return f"[could not read {p.name}: {e}]"


def extract_pdf(path: Path) -> str:
    if which("pdftotext"):
        r = subprocess.run(["pdftotext", "-layout", str(path), "-"],
                          capture_output=True, text=True, timeout=60)
        if r.returncode == 0:
            return r.stdout
    # Fallback to pdfminer.six if installed
    try:
        from pdfminer.high_level import extract_text
        return extract_text(str(path))
    except ImportError:
        return f"[PDF ingest unavailable — install pdftotext or pdfminer.six; file saved as {path.name}]"


def extract_image(path: Path) -> str:
    if which("tesseract"):
        r = subprocess.run(["tesseract", str(path), "-", "-l", "chi_sim+eng"],
                          capture_output=True, text=True, timeout=60)
        if r.returncode == 0:
            return r.stdout
    return f"[OCR unavailable — install tesseract; image saved as {path.name}. Please paste text if needed.]"


def extract_audio(path: Path) -> str:
    if which("whisper"):
        try:
            out_dir = path.parent / f"_whisper_{path.stem}"
            out_dir.mkdir(exist_ok=True)
            r = subprocess.run(
                ["whisper", str(path), "--output_dir", str(out_dir),
                 "--output_format", "txt", "--language", "auto", "--model", "base"],
                capture_output=True, text=True, timeout=600
            )
            txt_file = out_dir / (path.stem + ".txt")
            if txt_file.exists():
                return txt_file.read_text()
        except Exception as e:
            return f"[whisper failed: {e}]"
    return f"[audio ingest unavailable — install whisper; file: {path.name}]"


LARK_URL_RE = re.compile(
    r'https?://[\w.-]*(?:larksuite\.com|feishu\.cn)/(?:wiki|docx|docs|sheets)/\S+',
    re.IGNORECASE
)
GDOCS_URL_RE = re.compile(
    r'https?://docs\.google\.com/\S+', re.IGNORECASE
)


def fetch_lark(url: str, session_dir: Path) -> str:
    """Fetch Lark doc/wiki via Open API using hermes .env creds."""
    script = Path(__file__).parent / "lark-fetch.sh"
    if not script.exists():
        return f"[lark-fetch.sh not found; URL saved: {url}]"
    try:
        r = subprocess.run([str(script), url], capture_output=True, text=True, timeout=60)
        if r.returncode == 0:
            return f"## Lark doc content from {url}\n\n{r.stdout}"
        return f"[lark-fetch failed for {url}: {r.stderr[:200]}]"
    except Exception as e:
        return f"[lark-fetch error {e}; URL: {url}]"


def fetch_gdocs(url: str) -> str:
    gdrive = Path.home() / "bin" / "gdrive"
    if not gdrive.exists():
        return f"[~/bin/gdrive not installed; URL: {url}]"
    # Extract doc id from URL
    m = re.search(r'/d/([a-zA-Z0-9_-]+)', url)
    if not m:
        return f"[could not extract doc id from {url}]"
    doc_id = m.group(1)
    try:
        r = subprocess.run([str(gdrive), "read-file-content", doc_id],
                          capture_output=True, text=True, timeout=60)
        if r.returncode == 0:
            return f"## Google Doc content from {url}\n\n{r.stdout}"
        return f"[gdrive read failed: {r.stderr[:200]}]"
    except Exception as e:
        return f"[gdrive error {e}; URL: {url}]"


def process_artifact(path: Path, session_dir: Path) -> str:
    """Return markdown text extracted from this artifact."""
    ext = path.suffix.lower()
    header = f"\n## Input: `{path.name}` ({ext or 'no ext'})\n\n"

    if ext in (".md", ".markdown", ".txt"):
        text = read_text(path)
        # Also expand any URLs inside the text
        urls_lark = LARK_URL_RE.findall(text)
        urls_gdocs = GDOCS_URL_RE.findall(text)
        expansions = []
        for u in urls_lark:
            log(session_dir, f"fetching lark: {u}")
            expansions.append(fetch_lark(u, session_dir))
        for u in urls_gdocs:
            log(session_dir, f"fetching gdocs: {u}")
            expansions.append(fetch_gdocs(u))
        return header + text + ("\n\n" + "\n\n".join(expansions) if expansions else "")

    if ext == ".pdf":
        log(session_dir, f"pdf: {path.name}")
        return header + extract_pdf(path)

    if ext in (".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp"):
        log(session_dir, f"image: {path.name}")
        return header + extract_image(path)

    if ext in (".wav", ".mp3", ".m4a", ".ogg", ".flac", ".aac"):
        log(session_dir, f"audio: {path.name}")
        return header + extract_audio(path)

    if ext == ".jsonl":
        lines = [json.dumps(json.loads(l), ensure_ascii=False)
                 for l in read_text(path).splitlines() if l.strip()]
        return header + "\n".join(f"- {l}" for l in lines)

    if ext == ".url":
        url = read_text(path).strip()
        if LARK_URL_RE.match(url):
            return header + fetch_lark(url, session_dir)
        if GDOCS_URL_RE.match(url):
            return header + fetch_gdocs(url)
        return header + f"URL: {url}\n[unknown URL type]"

    log(session_dir, f"unknown: {path.name} (ext={ext})")
    return header + f"[unsupported format {ext}; file preserved in input/]"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("session_dir")
    ap.add_argument("--force", action="store_true",
                   help="re-ingest even if normalized.md exists")
    args = ap.parse_args()

    sd = Path(args.session_dir)
    if not sd.is_dir():
        print(f"error: {sd} not a directory", file=sys.stderr)
        sys.exit(2)
    input_dir = sd / "input"
    normalized = sd / "normalized.md"

    if normalized.exists() and not args.force:
        print(f"normalized.md exists; use --force to re-ingest", file=sys.stderr)
        return

    if not input_dir.exists() or not any(input_dir.iterdir()):
        print(f"warn: no files in {input_dir}", file=sys.stderr)
        return

    parts = []
    parts.append(f"# Normalized input — {sd.name}\n")
    parts.append(f"_Ingested at {datetime.now().astimezone().isoformat(timespec='seconds')}_\n")

    for p in sorted(input_dir.iterdir()):
        if not p.is_file() or p.name.startswith("."):
            continue
        parts.append(process_artifact(p, sd))

    normalized.write_text("\n".join(parts))
    print(f"wrote {normalized}")


if __name__ == "__main__":
    main()
