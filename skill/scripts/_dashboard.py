#!/usr/bin/env python3
"""Rebuild the review-agent dashboard from on-disk users/<id>/sessions/<id>/ state."""
import json
import sys
from pathlib import Path
from datetime import datetime


def load_meta(p):
    if not p.exists(): return None
    try: return json.load(open(p))
    except json.JSONDecodeError: return None


def main(root):
    root = Path(root)
    udir = root / "users"
    user_rows = []
    active = []
    closed = []

    if udir.exists():
        for u in sorted(udir.iterdir()):
            if not u.is_dir(): continue
            um = load_meta(u / "meta.json")
            if not um: continue
            uname = um.get("display_name") or um.get("open_id") or u.name
            roles = um.get("roles", [])
            sd = u / "sessions"
            a = c = 0
            if sd.is_dir():
                for s in sorted(sd.iterdir()):
                    if not s.is_dir(): continue
                    sm = load_meta(s / "meta.json")
                    if not sm: continue
                    row = {
                        "session_id": sm.get("session_id", s.name),
                        "requester": uname if "Requester" in roles else "",
                        "requester_oid": u.name,
                        "responder_oid": sm.get("responder_open_id", ""),
                        "subject": sm.get("subject", ""),
                        "round": sm.get("round", 0),
                        "status": sm.get("status", "?"),
                        "last_activity": sm.get("last_activity_at", ""),
                        "termination": sm.get("termination", ""),
                        "closed_at": sm.get("closed_at", ""),
                    }
                    if sm.get("status") == "closed":
                        closed.append(row); c += 1
                    else:
                        active.append(row); a += 1
            user_rows.append({
                "open_id": u.name,
                "name": uname,
                "roles": ",".join(roles),
                "active": a,
                "closed": c,
            })

    closed.sort(key=lambda r: r.get("closed_at", ""), reverse=True)
    active.sort(key=lambda r: r.get("last_activity", ""), reverse=True)

    out = []
    out.append("# Review Agent Dashboard")
    out.append("")
    out.append(f"_Last refreshed: {datetime.now().astimezone().isoformat(timespec='seconds')}_")
    out.append("")
    out.append("## Users")
    out.append("")
    out.append("| open_id | name | roles | active | closed |")
    out.append("|---|---|---|---|---|")
    if user_rows:
        for r in user_rows:
            out.append(f"| `{r['open_id']}` | {r['name']} | {r['roles']} | {r['active']} | {r['closed']} |")
    else:
        out.append("| _(none)_ | | | | |")
    out.append("")
    out.append("## Active sessions")
    out.append("")
    out.append("| session_id | requester | responder | subject | round | status | last_activity |")
    out.append("|---|---|---|---|---|---|---|")
    if active:
        for r in active:
            out.append(f"| `{r['session_id']}` | {r['requester']} | `{r['responder_oid'][:12]}…` | {r['subject']} | {r['round']} | {r['status']} | {r['last_activity']} |")
    else:
        out.append("| _(none)_ | | | | | | |")
    out.append("")
    out.append("## Closed sessions (last 10)")
    out.append("")
    out.append("| session_id | requester | subject | termination | closed_at |")
    out.append("|---|---|---|---|---|")
    if closed:
        for r in closed[:10]:
            out.append(f"| `{r['session_id']}` | {r['requester']} | {r['subject']} | {r['termination']} | {r['closed_at']} |")
    else:
        out.append("| _(none)_ | | | | |")
    out.append("")
    out.append(f"_Source: {root}/users/*/sessions/_")

    print("\n".join(out))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else str(Path.home() / ".review-agent"))
