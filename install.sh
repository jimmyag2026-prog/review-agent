#!/bin/bash
# install.sh — install review-agent skill into a hermes environment.
#
# Two-phase design:
#
#   Phase A (always runs): prerequisite check + copy skill files to
#                          ~/.hermes/skills/productivity/review-agent/.
#                          Reversible. Does not change main-agent behavior.
#
#   Phase B (opt-in, prompted): configure Admin + Responder, then wire the
#                               skill up (patch ~/.hermes/config.yaml + install
#                               orchestrator SOP into MEMORY.md). From this
#                               point the main agent starts routing Lark DMs
#                               through review-agent.
#
# Flags:
#   --enable-only            skip phase A, run phase B on existing install
#   --install-only           run phase A only, skip the enable prompt
#   --admin-open-id <ou_>    non-interactive enable (implies enable phase)
#   --admin-name <text>
#   --responder-open-id <ou_>
#   --responder-name <text>
#   --skip-hermes-restart    suppress restart reminder
#
# Safe to re-run: every phase is idempotent.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ADMIN_OID=""
ADMIN_NAME=""
RESPONDER_OID=""
RESPONDER_NAME=""
SKIP_RESTART=0
MODE="full"   # full | install-only | enable-only

while [ $# -gt 0 ]; do
  case "$1" in
    --admin-open-id) ADMIN_OID="$2"; shift 2 ;;
    --admin-name) ADMIN_NAME="$2"; shift 2 ;;
    --responder-open-id) RESPONDER_OID="$2"; shift 2 ;;
    --responder-name) RESPONDER_NAME="$2"; shift 2 ;;
    --skip-hermes-restart) SKIP_RESTART=1; shift ;;
    --install-only) MODE="install-only"; shift ;;
    --enable-only) MODE="enable-only"; shift ;;
    -h|--help)
      sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "unknown option: $1"; exit 1 ;;
  esac
done

# Remember whether --admin-open-id came from the CLI (→ non-interactive mode
# for end-of-Phase-B prompts).
ORIGINAL_ADMIN_OID="$ADMIN_OID"

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

banner() {
  echo
  echo -e "${BLUE}════════════════════════════════════════${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}════════════════════════════════════════${NC}"
}

SKILL_DST="$HOME/.hermes/skills/productivity/review-agent"
ROOT="${REVIEW_AGENT_ROOT:-$HOME/.review-agent}"

# ──────────────────────────────────────────────
# Phase A — install files
# ──────────────────────────────────────────────
phase_install() {
  banner "Phase A · Prerequisite check"
  if ! bash "$SCRIPT_DIR/install/check_prereqs.sh"; then
    echo -e "${RED}→ fix blocking issues above and re-run.${NC}"
    exit 2
  fi

  banner "Phase A · Install skill files"
  mkdir -p "$(dirname "$SKILL_DST")"

  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --exclude=".git" --exclude=".DS_Store" \
          "$SCRIPT_DIR/skill/" "$SKILL_DST/"
  else
    rm -rf "$SKILL_DST"
    cp -R "$SCRIPT_DIR/skill" "$SKILL_DST"
  fi
  chmod +x "$SKILL_DST"/scripts/*.sh "$SKILL_DST"/scripts/*.py 2>/dev/null || true
  echo -e "${GREEN}✓${NC} installed to $SKILL_DST"

  if hermes skills list --source local 2>&1 | grep -q "review-agent"; then
    echo -e "${GREEN}✓${NC} hermes recognizes review-agent"
  else
    echo -e "${YELLOW}!${NC} hermes doesn't list review-agent yet — may need gateway restart"
  fi

  echo
  echo -e "${GREEN}Skill files installed but NOT yet enabled.${NC}"
  echo "The main agent will not route Lark DMs through review-agent until you enable it."
}

# ──────────────────────────────────────────────
# Phase B — configure admin/responder, then wire up
# ──────────────────────────────────────────────
phase_enable() {
  # Verify files are present (guard for --enable-only on a fresh box)
  if [ ! -f "$SKILL_DST/SKILL.md" ]; then
    echo -e "${RED}error:${NC} skill files not found at $SKILL_DST"
    echo "  run 'bash install.sh' first (without --enable-only)."
    exit 2
  fi

  banner "Phase B · Configure Admin + Responder"
  echo "review-agent needs at least one Admin + one Responder before it can run."
  echo "(Admin = you, the person who runs the agent. Responder = the person whose"
  echo " review standards are applied. Default: same Lark account plays both roles.)"
  echo

  if [ -z "$ADMIN_OID" ]; then
    echo "Tip: run 'hermes pairing list' to see your Lark open_id (the feishu row)."
    echo
    hermes pairing list 2>&1 | grep feishu || echo "  (no feishu pairings yet — DM your bot once first)"
    echo
    read -rp "Admin Lark open_id (starts with 'ou_'): " ADMIN_OID
  fi

  if [ -z "$ADMIN_OID" ] || [[ ! "$ADMIN_OID" =~ ^ou_ ]]; then
    echo -e "${RED}error:${NC} Admin open_id required, must start with 'ou_'"
    exit 3
  fi

  [ -z "$ADMIN_NAME" ] && read -rp "Admin display name (leave blank for '$USER'): " ADMIN_NAME
  [ -z "$ADMIN_NAME" ] && ADMIN_NAME="$USER"

  if [ -z "$RESPONDER_OID" ]; then
    echo
    read -rp "Responder Lark open_id (blank = same as Admin): " RESPONDER_OID
  fi
  if [ -n "$RESPONDER_OID" ] && [[ ! "$RESPONDER_OID" =~ ^ou_ ]]; then
    echo -e "${RED}error:${NC} Responder open_id must start with 'ou_' (or leave blank)"
    exit 3
  fi
  if [ -n "$RESPONDER_OID" ] && [ -z "$RESPONDER_NAME" ]; then
    read -rp "Responder display name: " RESPONDER_NAME
  fi

  SETUP_ARGS=(--admin-open-id "$ADMIN_OID" --admin-name "$ADMIN_NAME")
  [ -n "$RESPONDER_OID" ]  && SETUP_ARGS+=(--responder-open-id "$RESPONDER_OID")
  [ -n "$RESPONDER_NAME" ] && SETUP_ARGS+=(--responder-name "$RESPONDER_NAME")

  bash "$SKILL_DST/scripts/setup.sh" "${SETUP_ARGS[@]}"

  banner "Phase B · Patch hermes config (feishu MINIMAL display tier)"
  python3 "$SCRIPT_DIR/install/patch_hermes_config.py"

  banner "Phase B · Install orchestrator SOP into MEMORY.md"
  python3 "$SCRIPT_DIR/install/patch_memory_sop.py"

  banner "Phase B · Lark app scope check"
  # Non-blocking: reports per-scope status. Soft-fail if creds or network miss.
  python3 "$SCRIPT_DIR/install/check_lark_scopes.py" || true

  # Stamp enable state for scripts + uninstall tooling to check
  mkdir -p "$ROOT"
  cat > "$ROOT/enabled.json" <<EOF
{
  "enabled_at": "$(date -Iseconds)",
  "skill_dst": "$SKILL_DST",
  "admin_open_id": "$ADMIN_OID"
}
EOF
  echo -e "${GREEN}✓${NC} wrote $ROOT/enabled.json"

  # Check for unfilled profile placeholders — warn, don't block
  RESPONDER_CHECK_OID="${RESPONDER_OID:-$ADMIN_OID}"
  PROFILE_PATH="$ROOT/users/$RESPONDER_CHECK_OID/profile.md"
  if [ -f "$PROFILE_PATH" ]; then
    banner "Phase B · Profile sanity check"
    if ! python3 "$SKILL_DST/scripts/check-profile.py" "$PROFILE_PATH"; then
      echo
      echo -e "${YELLOW}!${NC} The profile above still has template placeholders."
      echo "  The agent will run with the built-in default, but reviews will be generic"
      echo "  until you personalize these lines."
    fi
  fi

  banner "Done — review-agent ENABLED"

  # Determine non-interactive mode: if admin was passed on CLI, assume the
  # caller wants everything to just finish without prompts.
  NON_INTERACTIVE=0
  [ -n "${ORIGINAL_ADMIN_OID:-}" ] && NON_INTERACTIVE=1

  # ── Prompt 1: restart hermes gateway ──
  if [ $SKIP_RESTART -eq 0 ]; then
    RESTART_CMD=""
    if [ "$(uname)" = "Darwin" ] && command -v hermes >/dev/null 2>&1; then
      RESTART_CMD="hermes gateway restart"
    elif command -v systemctl >/dev/null 2>&1 && systemctl --user is-enabled hermes-gateway >/dev/null 2>&1; then
      RESTART_CMD="systemctl --user restart hermes-gateway"
    elif command -v hermes >/dev/null 2>&1; then
      RESTART_CMD="hermes gateway restart"
    fi

    if [ -n "$RESTART_CMD" ] && [ $NON_INTERACTIVE -eq 0 ]; then
      echo
      read -rp "Restart hermes gateway now (runs: $RESTART_CMD)? [Y/n] " ANS
      case "${ANS:-Y}" in
        n|N|no|NO) echo "  skipped. Remember to run '$RESTART_CMD' before the first review." ;;
        *)
          echo "  running: $RESTART_CMD"
          if $RESTART_CMD 2>&1 | tail -3; then
            echo -e "  ${GREEN}✓${NC} gateway restarted"
          else
            echo -e "  ${YELLOW}!${NC} restart reported errors — check with: hermes gateway status"
          fi
          ;;
      esac
    elif [ -n "$RESTART_CMD" ]; then
      echo
      echo "! Don't forget to restart the gateway: $RESTART_CMD"
    fi
  fi

  # ── Prompt 2: add first Requester ──
  if [ $NON_INTERACTIVE -eq 0 ]; then
    echo
    read -rp "Add your first Requester now (the person whose drafts you'll review)? [y/N] " ANS
    case "${ANS:-N}" in
      y|Y|yes|YES)
        echo
        echo "Tip: if the Requester has DM'd your bot, run 'hermes pairing list' in another terminal to see their open_id."
        read -rp "  Requester Lark open_id (starts with 'ou_'): " REQ_OID
        if [ -z "$REQ_OID" ] || [[ ! "$REQ_OID" =~ ^ou_ ]]; then
          echo -e "  ${YELLOW}!${NC} skipping — open_id must start with 'ou_'"
        else
          read -rp "  Requester display name: " REQ_NAME
          REQ_ARGS=("$REQ_OID")
          [ -n "$REQ_NAME" ] && REQ_ARGS+=(--name "$REQ_NAME")
          REQ_ARGS+=(--approve-pairing)
          bash "$SKILL_DST/scripts/add-requester.sh" "${REQ_ARGS[@]}" || true
        fi
        ;;
      *) : ;;
    esac
  fi

  # ── Final guidance (always printed) ──
  cat <<EOF

${YELLOW}What's next:${NC}

1. ${BLUE}Personalize your Responder profile${NC} (10 min of real work — bad defaults = generic reviews):
     vim $ROOT/users/$ADMIN_OID/profile.md

2. ${BLUE}(Optional) Edit agent behavior style${NC}:
     vim $ROOT/admin_style.md

3. ${BLUE}Add more Requesters${NC} anytime:
     bash $SKILL_DST/scripts/add-requester.sh <requester_ou_xxx> --name "Name"

4. ${BLUE}Watch session progress${NC} in the dashboard:
     bash $SKILL_DST/scripts/dashboard-web.sh --open

${BLUE}Reference${NC}: https://github.com/jimmyag2026-prog/review-agent

EOF
}

# ──────────────────────────────────────────────
# Dispatch
# ──────────────────────────────────────────────
banner "review-agent · install"

case "$MODE" in
  install-only)
    phase_install
    echo
    echo "To enable later (configure admin + patch hermes config + install SOP):"
    echo "     bash $SCRIPT_DIR/install.sh --enable-only"
    echo
    ;;

  enable-only)
    phase_enable
    ;;

  full)
    phase_install

    # If admin flag was passed on CLI → enable non-interactively.
    # Otherwise → prompt.
    if [ -n "$ADMIN_OID" ]; then
      phase_enable
    else
      echo
      read -rp "Enable review-agent now? This will configure Admin/Responder, patch ~/.hermes/config.yaml, and install the routing SOP into MEMORY.md. [y/N] " ENABLE_NOW
      case "${ENABLE_NOW:-N}" in
        y|Y|yes|YES)
          phase_enable
          ;;
        *)
          echo
          echo -e "${YELLOW}Skipped enable step.${NC}  Skill files are in place but dormant."
          echo "When you're ready to activate:"
          echo "     bash $SCRIPT_DIR/install.sh --enable-only"
          echo
          echo "Until then the main agent will NOT route Lark DMs through review-agent."
          echo
          ;;
      esac
    fi
    ;;
esac
