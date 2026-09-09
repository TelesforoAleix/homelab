#!/usr/bin/env bash
#
# verify-telegram-bot.sh -- prove the Phase 07 bot's security posture.
#
# Run on:  the Ubuntu server. Use sudo for the complete report.
# Usage:   sudo bash /tmp/verify-telegram-bot.sh
# Phase:   07. See docs/handovers/07-telegram.md, ADR-023.
#
# WHAT THIS IS FOR
#
#   The unit file DECLARES a security posture. This checks the RUNNING system,
#   because a directive that failed to apply is silent -- Phase 03 shipped a
#   correct sshd config to a daemon that never re-read it, and Phase 05 found a
#   scanner class that had never executed. Declarations are not evidence.
#
#   Every isolation claim below is tested by ATTEMPTING the thing and capturing
#   the refusal, not by reading a directive and believing it.
#
# SAFE TO PASTE
#
#   Never prints the bot token, the tailnet name, or a MAC address. It reports
#   metadata -- modes, owners, whether a read succeeded -- never contents.

set -uo pipefail        # not -e: a failing check must be reported, not abort

SVC_USER="homelab-bot"
UNIT="homelab-telegram-bot.service"
CONF_DIR="/etc/homelab-telegram-bot"
APP_DIR="/opt/homelab-telegram-bot"

FAIL=0; WARN=0
ok()   { printf '  ok    %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; FAIL=$((FAIL+1)); }
warn() { printf '  warn  %s\n' "$*"; WARN=$((WARN+1)); }
sec()  { printf '\n--- %s ---\n' "$*"; }

redact() {
  sed -E -e 's/\b([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b/<mac>/g' \
         -e 's/\b[a-zA-Z0-9][a-zA-Z0-9-]*\.ts\.net\b/<tailnet>.ts.net/g' \
         -e 's#bot[0-9]{6,}:[A-Za-z0-9_-]{20,}#bot<redacted-token>#g'
}

printf '\n=== Telegram bot posture ===\n'

# --------------------------------------------------------------------------
sec "service account"
if id "$SVC_USER" >/dev/null 2>&1; then
  UID_OF="$(id -u "$SVC_USER")"
  [ "$UID_OF" -lt 1000 ] && ok "$SVC_USER is a system account (uid $UID_OF)" \
                         || bad "$SVC_USER has uid $UID_OF (>=1000, looks human)"
  SH="$(getent passwd "$SVC_USER" | cut -d: -f7)"
  case "$SH" in */nologin|*/false) ok "login shell is $SH" ;; *) bad "interactive shell: $SH" ;; esac
  HOME_OF="$(getent passwd "$SVC_USER" | cut -d: -f6)"
  [ -d "$HOME_OF" ] && warn "home directory exists: $HOME_OF" || ok "no home directory ($HOME_OF)"
  GROUPS_OF="$(id -nG "$SVC_USER")"
  ok "groups: $GROUPS_OF"
  for g in sudo docker adm wheel; do
    echo "$GROUPS_OF" | tr ' ' '\n' | grep -qx "$g" && bad "IS IN '$g' -- root-equivalent, defeats the sandbox" \
                                                    || ok "not in '$g'"
  done
else
  bad "$SVC_USER does not exist"
fi

# --------------------------------------------------------------------------
sec "isolation, tested by attempting it"
if [ "$(id -u)" -eq 0 ] && id "$SVC_USER" >/dev/null 2>&1; then
  # Each of these MUST fail. A success is a finding.
  try_read() {
    local desc="$1" path="$2"
    if sudo -n -u "$SVC_USER" test -r "$path" 2>/dev/null; then
      bad "$SVC_USER CAN read $desc ($path)"
    else
      ok "$SVC_USER cannot read $desc"
    fi
  }
  try_read "the admin home directory" /home/aleix
  try_read "the Claude OAuth credential" /home/aleix/.claude/.credentials.json
  try_read "the Codex OAuth credential" /home/aleix/.codex/auth.json
  try_read "the Docker socket" /var/run/docker.sock
  try_read "the bot token file" "$CONF_DIR/token"
  if sudo -n -u "$SVC_USER" test -w "$APP_DIR/bot.py" 2>/dev/null; then
    bad "$SVC_USER can WRITE its own code ($APP_DIR/bot.py)"
  else
    ok "$SVC_USER cannot modify its own code"
  fi
else
  warn "not root -- skipped the isolation probes (run with sudo for these)"
fi

# --------------------------------------------------------------------------
sec "file permissions"
#
# UNKNOWN IS NOT A FAILURE, AND IT IS NOT A PASS.
#
# $CONF_DIR is 0750 root:homelab-bot, so an unprivileged caller cannot even
# traverse it. An earlier version of this script reported
# "FAIL: token does not exist" while the bot was happily authenticating with
# that very token -- it had confused "I cannot see it" with "it is not there".
#
# That is the fifth time this project has hit a check that answers confidently
# without being able to answer at all, after sshd -T, `who`, the blob scanner's
# binary test, and its private-key pattern. scripts/README.md has carried the
# rule since Phase 02 and this script still broke it. So the privilege is
# checked FIRST, and anything unknowable says so.
IS_ROOT=0; [ "$(id -u)" -eq 0 ] && IS_ROOT=1
if [ "$IS_ROOT" -eq 0 ] && ! test -x "$CONF_DIR"; then
  warn "cannot traverse $CONF_DIR as $(id -un) -- config checks are UNKNOWN, not failed"
  warn "re-run with sudo for the token, allowlist and journal checks"
  CONF_READABLE=0
else
  CONF_READABLE=1
fi

check_file() {
  local path="$1" want_mode="$2" want_own="$3"
  if [ ! -e "$path" ] && [ "$CONF_READABLE" -eq 0 ] && case "$path" in "$CONF_DIR"/*) true ;; *) false ;; esac; then
    warn "$path: UNKNOWN (no permission to look)"
    return
  fi
  if [ -e "$path" ]; then
    local got; got="$(stat -c '%a %U:%G' "$path" 2>/dev/null)"
    if [ -z "$got" ]; then warn "$path: UNKNOWN (cannot stat)"; return; fi
    [ "$got" = "$want_mode $want_own" ] && ok "$path is $got" \
                                        || bad "$path is $got, expected $want_mode $want_own"
  else
    bad "$path does not exist"
  fi
}
check_file "$CONF_DIR/token" 600 root:root
check_file "$APP_DIR/bot.py" 644 root:root

if [ "$CONF_READABLE" -eq 1 ] && [ -f "$CONF_DIR/token" ]; then
  [ -s "$CONF_DIR/token" ] && ok "token file is non-empty (value not shown)" \
                           || warn "token file is EMPTY -- the bot cannot authenticate"
fi
if [ "$CONF_READABLE" -eq 1 ] && [ -f "$CONF_DIR/allowlist" ]; then
  N="$(grep -cE '^[[:space:]]*[0-9]+' "$CONF_DIR/allowlist" 2>/dev/null || echo 0)"
  [ "$N" -gt 0 ] && ok "allowlist holds $N id(s) (ids not shown)" \
                 || bad "allowlist has no ids -- the bot refuses to start, by design"
fi

# --------------------------------------------------------------------------
sec "unit state"
systemctl is-enabled "$UNIT" >/dev/null 2>&1 && ok "enabled: $(systemctl is-enabled "$UNIT")" \
                                             || warn "not enabled: $(systemctl is-enabled "$UNIT" 2>&1)"
if systemctl is-active --quiet "$UNIT"; then
  ok "active: running"
  MAINPID="$(systemctl show -p MainPID --value "$UNIT")"
  ok "main pid $MAINPID, running as $(ps -o user= -p "$MAINPID" 2>/dev/null | tr -d ' ')"
else
  warn "not active: $(systemctl is-active "$UNIT" 2>&1)"
  MAINPID=""
fi

# --------------------------------------------------------------------------
sec "hardening, read from the RUNNING service"
for d in NoNewPrivileges ProtectHome ProtectSystem PrivateTmp RestrictAddressFamilies \
         MemoryDenyWriteExecute LockPersonality RestrictNamespaces CapabilityBoundingSet; do
  printf '  %-26s %s\n' "$d" "$(systemctl show -p "$d" --value "$UNIT" 2>/dev/null)"
done
SCORE="$(systemd-analyze security "$UNIT" 2>/dev/null | tail -1)"
[ -n "$SCORE" ] && printf '  %s\n' "$SCORE"

# --------------------------------------------------------------------------
sec "network exposure"
echo "  listening sockets on this host:"
ss -tln | tail -n +2 | redact | sed 's/^/    /'
if [ -n "$MAINPID" ]; then
  # The listener claim is safe to make unprivileged for a different reason:
  # `ss -tln` shows every listening socket on the host regardless of owner, so
  # comparing the full list against the known baseline is conclusive even
  # without pid attribution.
  BASELINE=6
  LISTEN_TOTAL="$(ss -tln | tail -n +2 | wc -l | tr -d ' ')"
  if [ "$LISTEN_TOTAL" -eq "$BASELINE" ]; then
    ok "$LISTEN_TOTAL listening sockets, matching the pre-Phase-07 baseline -- the bot added none"
  else
    bad "$LISTEN_TOTAL listening sockets, baseline was $BASELINE -- investigate the difference"
  fi
  # Same trap as the config files: ss cannot see another user's sockets
  # unprivileged, so a zero here means "cannot see", not "none exist".
  if [ "$IS_ROOT" -eq 1 ]; then
    OUT_N="$(ss -tnp 2>/dev/null | grep -c "pid=$MAINPID," || true)"
    ok "outbound connections owned by the bot: ${OUT_N:-0}"
  else
    warn "outbound connection count: UNKNOWN (ss needs root to attribute sockets)"
  fi
fi

# --------------------------------------------------------------------------
sec "token containment in the journal"
if [ "$(id -u)" -eq 0 ] && [ -s "$CONF_DIR/token" ]; then
  TOK="$(cat "$CONF_DIR/token")"
  # The token is used only as a search needle here, and never printed.
  if journalctl -u "$UNIT" --no-pager 2>/dev/null | grep -qF -- "$TOK"; then
    bad "THE TOKEN APPEARS IN THE JOURNAL. Revoke it with BotFather now."
  else
    ok "token does not appear in the unit's journal"
  fi
  unset TOK
else
  warn "not root or token empty -- skipped the journal containment check"
fi

# --------------------------------------------------------------------------
sec "host health"
ok "system state: $(systemctl is-system-running 2>&1)"
F="$(systemctl --failed --no-legend | wc -l | tr -d ' ')"
[ "$F" -eq 0 ] && ok "no failed units" || bad "$F failed unit(s)"

sec "result"
if [ "$FAIL" -eq 0 ]; then
  printf '  ok    %s check(s) need attention, 0 failures\n' "$WARN"
  exit 0
fi
printf '  FAIL  %s failure(s), %s warning(s)\n' "$FAIL" "$WARN"
exit 1
