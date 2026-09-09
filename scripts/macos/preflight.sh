#!/usr/bin/env bash
#
# preflight.sh — check the safety preconditions before a lockout-class change.
#
# Run this on the MacBook, from the repository, before touching networking,
# sshd, authentication, or anything that runs at boot on the reference node.
#
#   bash scripts/macos/preflight.sh
#   bash scripts/macos/preflight.sh --check sshd     # also validate sshd config
#
# WHY THIS RUNS ON THE MAC AND NOT ON THE SERVER
# ----------------------------------------------
# The Phase 02 brief placed this in scripts/server/. That was wrong, and the
# reason is section 7 of docs/standards/safe-changes-headless.md: the question
# that matters is not "does the server think it is reachable" but "can a new
# connection actually arrive". A script running on the server cannot answer
# that. It is inside the thing it is supposed to be testing.
#
# So the route checks happen here, arriving the way a real user does, and the
# host-side checks are gathered over SSH.
#
# WHAT THIS CANNOT DO
# -------------------
# It cannot tell you whether the change you are about to make is lockout-class.
# That judgement is the actual control (ADR-020); this script only mechanises
# the parts a machine can check. A green result is permission to proceed
# carefully, not permission to stop thinking.
#
set -uo pipefail          # deliberately NOT -e: a failing check must be
                          # reported, not abort the report.

PRIMARY="${PRIMARY_HOST:-homelab}"
FALLBACK="${FALLBACK_HOST:-homelab-lan}"
CHECK=""

while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,30p' "$0"; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

FAIL=0
WARN=0

pass() { printf '  \033[32mok\033[0m    %s\n' "$*"; }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$*"; WARN=$((WARN+1)); }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; FAIL=$((FAIL+1)); }
head2() { printf '\n%s\n' "$*"; }

printf 'Preflight — safe-changes-headless.md (ADR-020)\n'
printf 'Reference node has no console. Recovery is physical.\n'

# ---------------------------------------------------------------------------
# 1. Both routes, proved from outside, the way a real connection arrives.
#
# BatchMode=yes forbids every interactive fallback, so a success here is proof
# rather than encouragement. Without it, a passing check could just mean the
# ssh client was about to ask for a password.
# ---------------------------------------------------------------------------
head2 "1. Access routes"

route_ok() {
  ssh -o BatchMode=yes -o ConnectTimeout=8 "$1" true 2>/dev/null
}

if route_ok "$PRIMARY"; then
  pass "$PRIMARY (Tailscale) reachable"
  PRIMARY_UP=1
else
  fail "$PRIMARY (Tailscale) NOT reachable"
  PRIMARY_UP=0
fi

if route_ok "$FALLBACK"; then
  pass "$FALLBACK (LAN) reachable"
  FALLBACK_UP=1
else
  fail "$FALLBACK (LAN) NOT reachable"
  FALLBACK_UP=0
fi

if [ "$PRIMARY_UP" -eq 0 ] && [ "$FALLBACK_UP" -eq 0 ]; then
  fail "no route in at all — stop here, there is nothing to be careful with"
  printf '\nAborting: cannot inspect the host.\n'
  exit 1
fi

HOST="$PRIMARY"; [ "$PRIMARY_UP" -eq 1 ] || HOST="$FALLBACK"

if [ "$PRIMARY_UP" -eq 1 ] && [ "$FALLBACK_UP" -eq 1 ]; then
  pass "both routes up — you have a spare"
else
  warn "only one route up. A lockout-class change now has no spare route."
fi

# Both routes share one Wi-Fi adapter, so "two routes" is less independence
# than it looks. Say so every time rather than letting it be forgotten.
warn "both routes run over wlp1s0 — losing Wi-Fi loses both (eno1 unused)"

# ---------------------------------------------------------------------------
# 2. Host-side state. One SSH round trip, not five.
# ---------------------------------------------------------------------------
head2 "2. Host state"

REMOTE="$(ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST" '
  # NOT `who`. On Ubuntu 26.04 (systemd 259) /run/utmp does not exist --
  # systemd 257 removed utmp support -- so `who` prints nothing and exits 0.
  # A silent wrong answer is worse than an error, which is the whole subject
  # of this standard. `w` falls back to logind and still reports correctly.
  echo "SESSIONS=$(w -h 2>/dev/null | awk "\$2 ~ /^pts\//" | wc -l)"
  echo "WLINES=$(w -h 2>/dev/null | wc -l)"
  echo "STATE=$(systemctl is-system-running 2>/dev/null)"
  echo "FAILED=$(systemctl --failed --no-legend 2>/dev/null | wc -l)"
  echo "DISKPCT=$(df --output=pcent / | tail -1 | tr -dc 0-9)"
  echo "INODEPCT=$(df --output=ipcent / | tail -1 | tr -dc 0-9)"
  echo "WIFI=$(cat /sys/class/net/wlp1s0/operstate 2>/dev/null)"
  echo "TS=$(tailscale status --self=true --peers=false 2>/dev/null | head -1 | awk "{print \$1}")"
' 2>/dev/null)"

if [ -z "$REMOTE" ]; then
  fail "could not gather host state over $HOST"
else
  eval "$REMOTE"

  # The most important check in the file. An established session survives an
  # sshd misconfiguration; a new connection may not.
  #
  # We count only sessions holding a pseudo-terminal (pts/N). This script
  # connects without one (`ssh host command`), so its own connection is not
  # counted -- which is what we want: the number reported is the number of
  # real interactive sessions the operator is holding open.
  #
  # If `w` produced no rows at all, we do not know the answer. Say so, rather
  # than reporting zero and being confidently wrong.
  if [ "${WLINES:-0}" -eq 0 ]; then
    warn "cannot determine session count on this host — check manually with: w"
  else
    case "${SESSIONS:-0}" in
      0) fail "no interactive sessions. Open two: one to work in, one to leave idle." ;;
      1) fail "only 1 interactive session. Open a second and leave it idle." ;;
      *) pass "$SESSIONS interactive sessions — one can stay idle as the way back" ;;
    esac
  fi

  case "${STATE:-}" in
    running)  pass "systemctl is-system-running → running" ;;
    degraded) fail "system is DEGRADED — fix that before adding a change on top" ;;
    *)        warn "systemctl is-system-running → ${STATE:-unknown}" ;;
  esac

  if [ "${FAILED:-1}" -eq 0 ]; then
    pass "no failed units"
  else
    fail "$FAILED failed unit(s) — investigate before changing anything else"
  fi

  # Bytes and inodes are different failure modes and fail independently.
  [ "${DISKPCT:-100}"  -lt 85 ] && pass "root filesystem ${DISKPCT}% full"  || warn "root filesystem ${DISKPCT}% full"
  [ "${INODEPCT:-100}" -lt 85 ] && pass "root inodes ${INODEPCT}% used"     || warn "root inodes ${INODEPCT}% used"

  [ "${WIFI:-}" = "up" ] && pass "wlp1s0 operstate up" || fail "wlp1s0 operstate ${WIFI:-unknown}"
  [ -n "${TS:-}" ] && pass "tailscale self: $TS" || warn "tailscale status unavailable"
fi

# ---------------------------------------------------------------------------
# 3. Optional: run the validator for the thing being changed.
# ---------------------------------------------------------------------------
if [ -n "$CHECK" ]; then
  head2 "3. Validator: $CHECK"
  case "$CHECK" in
    sshd)
      # Needs root, so this one requires the owner at the keyboard.
      printf '  run on the host:  sudo sshd -t && echo valid\n'
      printf '  silence means well-formed. It does NOT mean your key still works.\n'
      ;;
    netplan)
      printf '  run on the host:  sudo netplan try\n'
      printf '  applies, then auto-reverts after 120s unless you confirm.\n'
      ;;
    sudoers)
      printf '  run on the host:  sudo visudo -c\n'
      ;;
    *)
      warn "no validator known for '$CHECK' — sshd, netplan, sudoers"
      ;;
  esac
fi

# ---------------------------------------------------------------------------
head2 "Before you proceed"
cat <<'REMINDER'
  - Is this change lockout-class?  network / sshd / auth / boot / admin account
  - Is the rollback typed out, unexecuted, in the second session?
  - Can you use reload instead of restart?
  - After the change: open a THIRD fresh connection before closing the second.
REMINDER

printf '\n%s\n' "----------------------------------------------"
if [ "$FAIL" -gt 0 ]; then
  printf 'RESULT: %d failed, %d warnings — do not make a lockout-class change.\n' "$FAIL" "$WARN"
  exit 1
fi
printf 'RESULT: 0 failed, %d warnings — preconditions met.\n' "$WARN"
printf 'This does not make the change safe. It makes it recoverable.\n'
