#!/bin/bash
# install-openclaw.sh — one-shot install of review-agent v2.2 into openclaw.
#
# Two phases:
#   A. Install files (reversible, always runs)
#       - $OC_HOME/.openclaw/skills/review-agent/            (shared skill)
#       - $OC_HOME/.openclaw/workspace/templates/review-agent/  (per-peer template)
#       - $OC_HOME/.openclaw/review-agent/responder-profile.md  (global profile)
#   B. Enable (opt-in prompt)
#       - Patch openclaw.json: dynamicAgentCreation, admin → main binding,
#                              sandbox.docker.binds collision auto-fix
#       - Seed Admin/Responder identity into workspace-template/owner.json
#       - Install peer-workspace seeder watcher (systemd / launchd / nohup)
#       - Clear stale peer session caches
#       - Restart openclaw gateway
#
# Auto-detects: macOS vs linux, root vs user, system vs user systemd, and
# whether openclaw runs as a dedicated user (e.g. 'openclaw' on the
# DigitalOcean droplet image). All paths and service installs adapt.
#
# Safe to re-run. No hermes required.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ADMIN_OID=""; ADMIN_NAME=""; RESPONDER_NAME=""
TARGET_USER=""
MODE="full"   # full | install-only | enable-only
SKIP_RESTART=0
SKIP_WATCHER=0

while [ $# -gt 0 ]; do
  case "$1" in
    --admin-open-id)  ADMIN_OID="$2"; shift 2 ;;
    --admin-name)     ADMIN_NAME="$2"; shift 2 ;;
    --responder-name) RESPONDER_NAME="$2"; shift 2 ;;
    --target-user)    TARGET_USER="$2"; shift 2 ;;
    --install-only)   MODE="install-only"; shift ;;
    --enable-only)    MODE="enable-only"; shift ;;
    --skip-restart)   SKIP_RESTART=1; shift ;;
    --skip-watcher)   SKIP_WATCHER=1; shift ;;
    -h|--help)
      sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1"; exit 1 ;;
  esac
done
ORIGINAL_ADMIN_OID="$ADMIN_OID"

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
banner() {
  echo; echo -e "${BLUE}════════════════════════════════════════${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}════════════════════════════════════════${NC}"
}

# ─── detect target user + their HOME ───
# When run as root with a dedicated 'openclaw' user, target it (VPS image).
# Otherwise target current user.
if [ -z "$TARGET_USER" ]; then
  if [ "$(id -u)" = "0" ] && id openclaw >/dev/null 2>&1; then
    TARGET_USER="openclaw"
  else
    TARGET_USER="$(whoami)"
  fi
fi

if [ "$TARGET_USER" = "$(whoami)" ]; then
  OC_HOME="$HOME"
  RUN_AS=""
else
  OC_HOME=$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6)
  if [ -z "$OC_HOME" ]; then
    echo "error: user '$TARGET_USER' not found"; exit 2
  fi
  RUN_AS="sudo -u $TARGET_USER -H"
fi

SKILL_DST="$OC_HOME/.openclaw/skills/review-agent"
TEMPLATE_DST="$OC_HOME/.openclaw/workspace/templates/review-agent"
GLOBAL_RA_DIR="$OC_HOME/.openclaw/review-agent"

# Helpers to write/copy as the target user
oc_run() { if [ -n "$RUN_AS" ]; then $RUN_AS "$@"; else "$@"; fi; }
oc_write() { local path="$1"; local mode="${2:-644}"
  if [ -n "$RUN_AS" ]; then sudo install -m "$mode" -o "$TARGET_USER" -g "$TARGET_USER" /dev/stdin "$path"
  else install -m "$mode" /dev/stdin "$path"; fi; }

phase_install() {
  banner "Phase A · Prereq check"
  if ! OPENCLAW_HOME="$OC_HOME" bash "$SCRIPT_DIR/check_prereqs.sh"; then
    echo -e "${RED}→ fix blocking issues above and re-run.${NC}"; exit 2
  fi

  banner "Phase A · Install skill (${SKILL_DST})"
  oc_run mkdir -p "$(dirname "$SKILL_DST")"
  if command -v rsync >/dev/null 2>&1; then
    oc_run rsync -a --delete --exclude=".git" --exclude=".DS_Store" \
          "$REPO_ROOT/skill/" "$SKILL_DST/"
  else
    oc_run rm -rf "$SKILL_DST"; oc_run cp -R "$REPO_ROOT/skill" "$SKILL_DST"
  fi
  oc_run chmod +x "$SKILL_DST"/scripts/*.py 2>/dev/null || true
  echo -e "${GREEN}✓${NC} skill installed"

  banner "Phase A · Install workspace template (${TEMPLATE_DST})"
  oc_run mkdir -p "$(dirname "$TEMPLATE_DST")"
  if command -v rsync >/dev/null 2>&1; then
    oc_run rsync -a --delete --exclude=".git" --exclude=".DS_Store" \
          "$REPO_ROOT/workspace-template/review-agent/" "$TEMPLATE_DST/"
  else
    oc_run rm -rf "$TEMPLATE_DST"; oc_run cp -R "$REPO_ROOT/workspace-template/review-agent" "$TEMPLATE_DST"
  fi
  oc_run rm -f "$TEMPLATE_DST/responder-profile.md.INSTALL_SHOULD_SYMLINK"
  echo -e "${GREEN}✓${NC} template installed"

  banner "Phase A · Global responder profile (${GLOBAL_RA_DIR})"
  oc_run mkdir -p "$GLOBAL_RA_DIR"
  if [ ! -f "$GLOBAL_RA_DIR/responder-profile.md" ]; then
    if [ -f "$REPO_ROOT/skill/references/template/boss_profile.md" ]; then
      oc_run cp "$REPO_ROOT/skill/references/template/boss_profile.md" \
                "$GLOBAL_RA_DIR/responder-profile.md"
      echo -e "${GREEN}✓${NC} seeded responder-profile from default"
    else
      oc_run bash -c "cat > '$GLOBAL_RA_DIR/responder-profile.md' <<'EOF'
# Responder Profile (global)
# Edit to describe the Responder's review standards.
EOF"
      echo -e "${YELLOW}!${NC} wrote placeholder responder-profile"
    fi
  else
    echo -e "${YELLOW}!${NC} responder-profile.md already exists — left as-is"
  fi

  oc_run bash -c "cd '$TEMPLATE_DST' && rm -f responder-profile.md && \
    ln -s '$GLOBAL_RA_DIR/responder-profile.md' responder-profile.md"
  echo -e "${GREEN}✓${NC} template responder-profile.md → global"

  echo
  echo -e "${GREEN}Phase A complete.${NC} Skill files installed; openclaw not yet wired."
}

# ─── Admin open_id discovery (interactive) ───
discover_admin_oid() {
  # Try 1: most recent feishu sender from gateway log
  local LOGFILE
  for cand in \
    "/tmp/openclaw/openclaw-$(date +%Y-%m-%d).log" \
    "$OC_HOME/.openclaw/logs/gateway.log" \
    ; do
    if [ -r "$cand" ]; then LOGFILE="$cand"; break; fi
  done
  # Try journalctl if root
  local recent_oids=""
  if [ -n "${LOGFILE:-}" ]; then
    recent_oids=$(grep -oE 'received message from ou_[a-f0-9]{32}' "$LOGFILE" 2>/dev/null | \
                  grep -oE 'ou_[a-f0-9]{32}' | sort -u | tail -5 || true)
  fi
  if [ -z "$recent_oids" ] && command -v journalctl >/dev/null 2>&1; then
    recent_oids=$(journalctl -u openclaw --no-pager --since "24 hours ago" 2>/dev/null | \
                  grep -oE 'received message from ou_[a-f0-9]{32}' | \
                  grep -oE 'ou_[a-f0-9]{32}' | sort -u | tail -5 || true)
  fi
  if [ -n "$recent_oids" ]; then
    echo "Recent feishu senders (from gateway log):"
    echo "$recent_oids" | sed 's/^/  /'
    echo
    echo "If your open_id is in the list, paste it. Otherwise, send a DM to"
    echo "your bot first (any text), then re-run this script."
  else
    echo "No recent feishu senders found in logs. Two ways to get your open_id:"
    echo "  a) DM your bot a single message (anything), then re-run this script"
    echo "  b) Look up via Lark Open API or your Lark profile (advanced)"
  fi
}

phase_enable() {
  if [ ! -f "$SKILL_DST/SKILL.md" ]; then
    echo -e "${RED}error:${NC} skill not found at $SKILL_DST"
    echo "  run install.sh (without --enable-only) first"
    exit 2
  fi

  NON_INTERACTIVE=0
  [ -n "${ORIGINAL_ADMIN_OID:-}" ] && NON_INTERACTIVE=1

  banner "Phase B · Identify Admin"
  echo "Admin = the person who owns this bot."
  echo "Admin DMs go to the MAIN openclaw agent (chat/admin), not the review subagent."
  echo "Other Lark users (Requesters) get per-peer review-coach subagents."
  echo

  if [ -z "$ADMIN_OID" ]; then
    discover_admin_oid
    echo
    read -rp "Admin's Lark open_id (ou_xxx): " ADMIN_OID
  fi
  if [ -z "$ADMIN_OID" ] || [[ ! "$ADMIN_OID" =~ ^ou_ ]]; then
    echo -e "${RED}error:${NC} open_id required, must start with 'ou_'"; exit 3
  fi

  [ -z "$ADMIN_NAME" ] && read -rp "Admin display name [$TARGET_USER]: " ADMIN_NAME
  [ -z "$ADMIN_NAME" ] && ADMIN_NAME="$TARGET_USER"

  echo
  echo "Responder = the person whose review style the agent simulates."
  echo "(Often the same as Admin, but can differ — e.g. you operate the bot, but"
  echo " the agent reviews proposals as if your CEO were reviewing them.)"
  [ -z "$RESPONDER_NAME" ] && read -rp "Responder name [$ADMIN_NAME]: " RESPONDER_NAME
  [ -z "$RESPONDER_NAME" ] && RESPONDER_NAME="$ADMIN_NAME"

  banner "Phase B · Seed identity into template (${TEMPLATE_DST})"
  oc_run bash -c "cat > '$TEMPLATE_DST/owner.json' <<EOF
{
  \"admin_open_id\": \"$ADMIN_OID\",
  \"admin_display_name\": \"$ADMIN_NAME\",
  \"responder_open_id\": \"$ADMIN_OID\",
  \"responder_name\": \"$RESPONDER_NAME\",
  \"note\": \"openclaw-managed. Re-run install.sh --enable-only to update.\"
}
EOF"
  oc_run rm -f "$TEMPLATE_DST/owner.json.template"
  echo -e "${GREEN}✓${NC} template owner.json seeded"

  # Replace {responder_name} in ALL persona files at template level
  for f in SOUL.md AGENTS.md BOOTSTRAP.md HEARTBEAT.md IDENTITY.md USER.md; do
    [ -f "$TEMPLATE_DST/$f" ] && \
      oc_run sed -i.bak "s|{responder_name}|$RESPONDER_NAME|g" "$TEMPLATE_DST/$f" && \
      oc_run rm -f "$TEMPLATE_DST/$f.bak"
  done
  echo -e "${GREEN}✓${NC} {responder_name} → '$RESPONDER_NAME' in all persona files"

  banner "Phase B · Patch openclaw.json"
  # The patcher does: dynamicAgentCreation + admin→main binding +
  # sandbox.docker.binds auto-clear + legacy cleanup
  if [ -n "$RUN_AS" ]; then
    $RUN_AS python3 "$SCRIPT_DIR/patch_openclaw_json.py" \
      --admin-open-id "$ADMIN_OID" \
      --openclaw-home "$OC_HOME" \
      --clear-bad-binds
  else
    OPENCLAW_HOME="$OC_HOME" python3 "$SCRIPT_DIR/patch_openclaw_json.py" \
      --admin-open-id "$ADMIN_OID" \
      --openclaw-home "$OC_HOME" \
      --clear-bad-binds
  fi

  banner "Phase B · Profile sanity check"
  GPROFILE="$GLOBAL_RA_DIR/responder-profile.md"
  if [ -f "$GPROFILE" ] && [ -f "$SKILL_DST/scripts/check-profile.py" ]; then
    if ! oc_run python3 "$SKILL_DST/scripts/check-profile.py" "$GPROFILE" 2>/dev/null; then
      echo -e "${YELLOW}!${NC} responder-profile has placeholder content."
      echo "    Edit to personalize: vim $GPROFILE"
    fi
  fi

  # ─── Phase B · Install peer-workspace seeder watcher ───
  if [ $SKIP_WATCHER -eq 0 ]; then
    banner "Phase B · Install peer-workspace seeder watcher"
    bash "$SCRIPT_DIR/setup_watcher.sh" --target-user "$TARGET_USER" || \
      echo -e "${YELLOW}!${NC} watcher install had issues — peer subagents may load openclaw default persona"
  else
    echo
    echo -e "${YELLOW}!${NC} --skip-watcher: peer subagents will load openclaw default persona (memorist)"
    echo "    To install later: bash $SCRIPT_DIR/setup_watcher.sh"
  fi

  # ─── Phase B · Clear stale peer session caches (so prompt-cache doesn't stick) ───
  banner "Phase B · Clear stale peer session caches"
  CLEARED=0
  for ad in "$OC_HOME/.openclaw/agents/"feishu-* "$OC_HOME/.openclaw/agents/"wecom-*; do
    [ -d "$ad/sessions" ] || continue
    oc_run bash -c "rm -f '$ad/sessions/'*.jsonl '$ad/sessions/sessions.json' '$ad/sessions/'*.lock 2>/dev/null"
    CLEARED=$((CLEARED+1))
  done
  echo "  ✓ cleared $CLEARED peer agent session cache(s)"

  # ─── Re-seed admin's binding into existing main session if present ───
  # (The admin → main binding written above only takes effect for NEW sessions.
  # If admin already had a peer subagent session, it'll be reused. Clear it.)
  ADMIN_PEER_DIR="$OC_HOME/.openclaw/agents/feishu-${ADMIN_OID}"
  ADMIN_WS="$OC_HOME/.openclaw/workspace-feishu-${ADMIN_OID}"
  if [ -d "$ADMIN_PEER_DIR" ] || [ -d "$ADMIN_WS" ]; then
    echo "  ! admin had a stale peer subagent — removing"
    oc_run rm -rf "$ADMIN_PEER_DIR" "$ADMIN_WS"
  fi

  # ─── Enabled stamp ───
  oc_run mkdir -p "$GLOBAL_RA_DIR"
  oc_run bash -c "cat > '$GLOBAL_RA_DIR/enabled.json' <<EOF
{
  \"enabled_at\": \"$(date -Iseconds)\",
  \"version\": \"$(cat $REPO_ROOT/VERSION 2>/dev/null || echo 'unknown')\",
  \"target_user\": \"$TARGET_USER\",
  \"openclaw_home\": \"$OC_HOME\",
  \"skill_dst\": \"$SKILL_DST\",
  \"template_dst\": \"$TEMPLATE_DST\",
  \"admin_open_id\": \"$ADMIN_OID\",
  \"admin_display_name\": \"$ADMIN_NAME\",
  \"responder_name\": \"$RESPONDER_NAME\"
}
EOF"

  # ─── Restart openclaw ───
  if [ $SKIP_RESTART -eq 0 ]; then
    banner "Phase B · Restart openclaw"
    if [ "$(id -u)" = "0" ] && systemctl is-active openclaw >/dev/null 2>&1; then
      systemctl restart openclaw && \
        echo -e "  ${GREEN}✓${NC} systemd service restarted"
    elif command -v openclaw >/dev/null 2>&1; then
      oc_run openclaw gateway restart 2>&1 | tail -3 && \
        echo -e "  ${GREEN}✓${NC} gateway restarted"
    else
      echo -e "  ${YELLOW}!${NC} restart manually: systemctl restart openclaw  OR  openclaw gateway restart"
    fi
  fi

  banner "Done — review-agent v2.2 ENABLED"
  cat <<EOF

${BLUE}Summary${NC}
  target user:       $TARGET_USER
  openclaw HOME:     $OC_HOME
  Admin:             $ADMIN_NAME ($ADMIN_OID)
                     → routes to MAIN openclaw agent (regular chat)
  Responder name:    $RESPONDER_NAME (agent reviews as if they were reviewing)
  Requesters:        any other Lark user → per-peer review-coach subagent

${BLUE}Verify${NC}
  1. As Admin, DM the bot something like "你是谁".
     Expect: regular openclaw assistant reply (not review-coach).
     Log: gateway should show 'session=agent:main:main'.

  2. As a Requester (a different Lark user, NOT the Admin),
     DM the bot a proposal/PDF/Lark doc URL.
     Expect: review-coach reply with first finding.
     Log: gateway should show 'creating dynamic agent feishu-ou_xxx'
          plus seeder.log: 'seeded .../workspace-feishu-ou_xxx'

${BLUE}Next steps${NC}
  • Personalize the Responder profile (10 min):
       vim $GPROFILE
  • Watch the seeder log:
       tail -F $OC_HOME/.openclaw/seeder.log
  • Watch the openclaw gateway:
       journalctl -u openclaw -f      # if systemd-system
       tail -F $OC_HOME/.openclaw/logs/gateway.log

${BLUE}Channel compatibility${NC}
  ✅ feishu / wecom — full v2 architecture (per-peer subagent)
  ❌ telegram / whatsapp / discord / slack / iMessage — fall back to
     shared-main-agent mode. For those, either:
       - Use bash $REPO_ROOT/scripts/setup-shared-mode.sh (skill on main agent)
       - Or use hermes v1 (https://github.com/jimmyag2026-prog/review-agent)

${BLUE}Self-heal if anything goes wrong${NC}
       bash $REPO_ROOT/scripts/vps-doctor.sh

EOF
}

banner "review-agent v2.2 · install (openclaw)"
echo "  target user: $TARGET_USER  ($([ -n "$RUN_AS" ] && echo "via sudo" || echo "current user"))"
echo "  openclaw HOME: $OC_HOME"

case "$MODE" in
  install-only)
    phase_install
    echo; echo "To enable later:"
    echo "     bash $SCRIPT_DIR/install-openclaw.sh --enable-only"
    ;;
  enable-only) phase_enable ;;
  full)
    phase_install
    if [ -n "${ORIGINAL_ADMIN_OID:-}" ]; then
      phase_enable
    else
      echo
      cat <<'INTRO'
━━━ About review-agent v2 (openclaw) ━━━

Review-agent is a CSW-style pre-meeting coach for Lark. In v2 each Requester
gets their OWN dedicated subagent with isolated context. Admin DMs the main
openclaw agent (chat/management); Requesters get per-peer review subagents.

Three roles:
  • Admin     — you (manage config, talks to MAIN agent)
  • Responder — whose review standards apply (you, by default)
  • Requester — submits drafts (auto-enrolled on first DM)

━━━
INTRO
      read -rp "Enable review-agent now? [y/N] " ENABLE_NOW
      case "${ENABLE_NOW:-N}" in
        y|Y|yes|YES) phase_enable ;;
        *)
          echo
          echo -e "${YELLOW}Skipped.${NC} Skill files installed but openclaw isn't wired yet."
          echo "When ready: bash $SCRIPT_DIR/install-openclaw.sh --enable-only"
          ;;
      esac
    fi
    ;;
esac
