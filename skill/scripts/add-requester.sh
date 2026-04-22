#!/bin/bash
# add-requester.sh — register a Requester user, linked to a Responder
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${REVIEW_AGENT_ROOT:-$HOME/.review-agent}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'

usage() {
  cat <<EOF >&2
Usage: $(basename "$0") <requester_open_id> [--name <text>] [--responder <ou_>] \
                       [--approve-pairing] [--no-pairing-check]

  requester_open_id        Lark open_id of the Requester (briefer)
  --name <text>            Display name
  --responder <ou_>        Lark open_id of the Responder this Requester reviews against
                           (v0: defaults to the sole Responder; explicit only needed if --force used in add-responder)
  --approve-pairing        Run 'hermes pairing approve' for this open_id
  --no-pairing-check       Skip pairing status check
EOF
  exit 1
}

if [ $# -lt 1 ]; then usage; fi

REQUESTER_OPEN_ID="$1"; shift
NAME=""
RESPONDER_OPEN_ID=""
AUTO_APPROVE=0
SKIP_PAIRING=0

while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --responder) RESPONDER_OPEN_ID="$2"; shift 2 ;;
    --approve-pairing) AUTO_APPROVE=1; shift ;;
    --no-pairing-check) SKIP_PAIRING=1; shift ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

if [ ! -d "$ROOT/users" ]; then
  echo -e "${RED}error:${NC} review-agent not initialized. Run setup.sh first." >&2
  exit 2
fi

# Default responder = the sole user with Responder role
if [ -z "$RESPONDER_OPEN_ID" ]; then
  RESPONDER_OPEN_ID=$(python3 - "$ROOT" <<'PYEOF'
import json, os, sys
root = sys.argv[1]
udir = os.path.join(root, "users")
candidates = []
for u in os.listdir(udir):
    mp = os.path.join(udir, u, "meta.json")
    if os.path.exists(mp):
        try:
            m = json.load(open(mp))
            if "Responder" in m.get("roles", []):
                candidates.append(u)
        except: pass
if len(candidates) == 1:
    print(candidates[0])
elif len(candidates) > 1:
    print("AMBIGUOUS:" + ",".join(candidates))
else:
    print("NONE")
PYEOF
)
  if [[ "$RESPONDER_OPEN_ID" == AMBIGUOUS:* ]]; then
    echo -e "${RED}error:${NC} multiple Responders exist (v0 should not have this state); pass --responder <ou_>" >&2
    echo "  candidates: ${RESPONDER_OPEN_ID#AMBIGUOUS:}" >&2
    exit 2
  fi
  if [ "$RESPONDER_OPEN_ID" = "NONE" ]; then
    echo -e "${RED}error:${NC} no Responder exists. Run add-responder.sh or setup.sh first." >&2
    exit 2
  fi
fi

# Verify the Responder exists
if [ ! -d "$ROOT/users/$RESPONDER_OPEN_ID" ]; then
  echo -e "${RED}error:${NC} Responder $RESPONDER_OPEN_ID not registered" >&2
  exit 2
fi

REQUESTER_DIR="$ROOT/users/$REQUESTER_OPEN_ID"
echo -e "${GREEN}Adding Requester${NC}"
echo "  open_id   : $REQUESTER_OPEN_ID"
echo "  name      : ${NAME:-<none>}"
echo "  responder : $RESPONDER_OPEN_ID"

mkdir -p "$REQUESTER_DIR/sessions"

cat > "$REQUESTER_DIR/meta.json" <<EOF
{
  "open_id": "$REQUESTER_OPEN_ID",
  "display_name": "$NAME",
  "roles": ["Requester"],
  "responder": "$RESPONDER_OPEN_ID",
  "channel": "feishu",
  "runtime": "hermes",
  "created_at": "$(date -Iseconds)"
}
EOF

# owner.json for portability (per feedback_no_hardcode_owner)
RESPONDER_NAME=$(python3 -c "
import json
m = json.load(open('$ROOT/users/$RESPONDER_OPEN_ID/meta.json'))
print(m.get('display_name') or 'Responder')
")
cat > "$REQUESTER_DIR/owner.json" <<EOF
{
  "responder_open_id": "$RESPONDER_OPEN_ID",
  "responder_name": "$RESPONDER_NAME",
  "requester_open_id": "$REQUESTER_OPEN_ID",
  "requester_name": "$NAME",
  "review_agent_root": "$ROOT",
  "skill_dir": "$SKILL_DIR",
  "runtime": "hermes"
}
EOF

echo -e "${GREEN}  ✓ user dir created${NC}"

# hermes pairing
if [ $SKIP_PAIRING -eq 0 ] && command -v hermes >/dev/null 2>&1; then
  PAIRED=$(hermes pairing list 2>&1 | grep -E "feishu\s+$REQUESTER_OPEN_ID" || true)
  if [ -n "$PAIRED" ]; then
    echo -e "${GREEN}  ✓ already paired${NC}"
  else
    echo -e "${YELLOW}  ! not yet paired${NC}"
    if [ $AUTO_APPROVE -eq 1 ]; then
      echo "    attempting 'hermes pairing approve'..."
      hermes pairing approve "$REQUESTER_OPEN_ID" 2>&1 | head -3 \
        && echo -e "${GREEN}    ✓ approved${NC}" \
        || echo -e "${YELLOW}    approve failed; briefer may need to DM bot first${NC}"
    else
      echo "    have the requester DM the Lark bot once, then run:"
      echo "      hermes pairing approve $REQUESTER_OPEN_ID"
    fi
  fi
fi

echo
echo -e "${GREEN}Requester registered.${NC}"
