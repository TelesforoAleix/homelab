#!/usr/bin/env bash
#
# Close SSH to the shared LAN, keeping it open on the tailnet.
#
# Run on:  the Ubuntu server, as root
# Usage:   sudo bash /tmp/apply-firewall.sh
# Phase:   security reassessment 2026-09-10. See
#          docs/build-log/2026-09-10-publication-security-review.md §8.
#
# WHY THIS EXISTS
# ---------------
# The node is not on a home LAN. It sits on a shared building network -- a flat
# 192.168.0.0/21, 2046 usable addresses -- occupied by many other tenants'
# devices, whose edge is administered by a third party and can be neither
# audited nor reconfigured by this project. Anything you cannot verify and
# cannot fix earns zero trust.
#
# sshd currently listens on 0.0.0.0:22, so every host on that /21 can reach it.
# Authentication is public-key only (ADR-018), so this is exposure rather than
# vulnerability. It is still an exposed service on a network nobody here
# administers, and Tailscale already provides the access path it duplicates.
#
# WHY A TIMED SELF-REVERT AND NOT JUST `ufw enable`
# -------------------------------------------------
# A firewall change applied over the connection it might break is the classic
# way to lose a remote machine. The revert is armed BEFORE the rules are
# applied, so the failure mode is "the node fixes itself in N minutes" rather
# than "the node is unreachable".
#
# The node does have a console -- unplugged, not absent, with getty@tty1 active
# and the machine in the owner's room. That makes lockout recoverable rather
# than fatal. The self-revert is kept anyway: a control that costs nothing and
# removes a walk across a room is worth having, and the next person to run this
# may not have the machine nearby.
#
# WHAT IS DELIBERATELY NOT DONE
# -----------------------------
# fail2ban. It watches for repeated failed passwords, and this server does not
# accept passwords. Installing it here would add a service and protect nothing.
#
# Docker. ADR-022 records that Docker publishes ports by DNAT BEFORE the host
# INPUT chain, so ufw does not filter published container ports. Docker
# inventory is currently zero, so nothing is affected today -- but any future
# container must bind 127.0.0.1 or the tailnet explicitly. `-p 8080:80` on this
# network publishes to 2046 hosts and ufw will not stop it.
set -euo pipefail

REVERT_MIN="${REVERT_MIN:-10}"
TS_IF="tailscale0"
UNIT="homelab-ufw-selfrevert"

die() { printf '\n  ERROR: %s\n\n' "$*" >&2; exit 1; }
say() { printf '  %s\n' "$*"; }

[ "$(id -u)" -eq 0 ] || die "run with sudo"

# --- Refusals. Each is a reason this change would strand the machine. -------

command -v ufw >/dev/null || die "ufw is not installed"

ip link show "$TS_IF" >/dev/null 2>&1 \
  || die "$TS_IF does not exist. Closing the LAN would leave no way in."

tailscale status >/dev/null 2>&1 \
  || die "tailscale is not up. Closing the LAN would leave no way in."

# If this very session came in over the LAN, applying the rules drops it. That
# is survivable -- the revert fires and the console exists -- but it is better
# to refuse and let the operator reconnect over the tailnet first.
#
# SSH_CLIENT CANNOT BE READ DIRECTLY HERE, and the first version of this script
# died trying. sudo resets the environment, so under `sudo bash script.sh` the
# variable is simply absent -- and with `set -u` that is a hard abort, not a
# graceful skip. The failure was safe, because this block runs before the
# self-revert is armed and before any rule is applied, so nothing had changed.
# It was still a check that could not run.
#
# `who am i` is no help either: it reads utmp, and these sessions leave no utmp
# entry -- it returns empty.
#
# What does work: this script runs as root, so it can read the environment of
# its own ancestors. The user's login shell still has SSH_CLIENT.
detect_client_ip() {
  local pid val
  pid="${PPID:-0}"
  for _ in 1 2 3 4 5 6 7 8; do
    [ -n "$pid" ] && [ "$pid" != "0" ] && [ -r "/proc/$pid/environ" ] || return 1
    val="$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null \
           | sed -n 's/^SSH_CLIENT=//p' | head -1)"
    if [ -n "$val" ]; then printf '%s' "${val%% *}"; return 0; fi
    # /proc/PID/status, not /proc/PID/stat: the latter's second field is the
    # process name in parentheses, and a name containing a space shifts every
    # field after it. status is key/value and cannot be miscounted.
    pid="$(awk '/^PPid:/{print $2}' "/proc/$pid/status" 2>/dev/null)"
  done
  return 1
}

client_ip="$(detect_client_ip || true)"

case "${client_ip:-}" in
  100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*)
    say "this session is on the tailnet ($client_ip). Good." ;;
  "")
    # Report what is true rather than assuming the safe answer. Proceeding is
    # justified by the self-revert, not by a guess about the connection.
    say "connection source: UNKNOWN -- could not read SSH_CLIENT from any"
    say "  ancestor process. Proceeding anyway, because the self-revert below"
    say "  is what protects this change. If this session drops, wait"
    say "  ${REVERT_MIN} minutes and it will come back." ;;
  *)
    die "this session came from $client_ip, which is not the tailnet.
       Reconnect with 'ssh homelab' over Tailscale and re-run, or the
       rules below will drop the connection applying them." ;;
esac

# Cross-check, and a genuine warning rather than a refusal: other sessions may
# be on the LAN even when ours is not. They will be dropped.
lan_sessions="$(ss -tn state established '( sport = :22 )' 2>/dev/null \
  | awk 'NR>1{split($4,a,":"); print a[1]}' \
  | grep -vcE '^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.' || true)"
if [ "${lan_sessions:-0}" -gt 0 ]; then
  say "NOTE: ${lan_sessions} other SSH session(s) are on non-tailnet addresses"
  say "  and will be disconnected. They can reconnect over Tailscale."
fi

# --- Arm the self-revert BEFORE touching anything. -------------------------

systemctl stop "${UNIT}.timer" 2>/dev/null || true
systemd-run --quiet --on-active="${REVERT_MIN}min" --unit="$UNIT" \
  /usr/sbin/ufw --force disable \
  || die "could not arm the self-revert; refusing to change the firewall"
say "self-revert armed: ufw disables itself in ${REVERT_MIN} minutes"

# --- Rules. -----------------------------------------------------------------

ufw --force reset >/dev/null
ufw default deny incoming  >/dev/null
ufw default allow outgoing >/dev/null

# Everything arriving over the tailnet. This is the access path.
ufw allow in on "$TS_IF" >/dev/null

# Tailscale's own UDP port on the physical link. Without this, direct
# peer-to-peer connections fail and traffic falls back to a DERP relay -- still
# working, but slower and dependent on Tailscale's infrastructure.
ufw allow in on wlp1s0 proto udp to any port 41641 >/dev/null

ufw --force enable >/dev/null
say "ufw enabled"

# --- Report what is actually true, not what was intended. ------------------

printf '\n'
ufw status verbose | sed 's/^/  /'
printf '\n'
say "listening sockets now:"
ss -tln | awk 'NR>1{print "    " $4}'

cat <<EOF

  ----------------------------------------------------------------
  NOT FINISHED. The rules are live and WILL REVERT in ${REVERT_MIN} minutes.

  1. Open a NEW terminal and prove access still works:

       ssh homelab

  2. Prove the LAN path is now closed. From the MacBook, on the
     same Wi-Fi, this must now FAIL or hang:

       ssh -o ConnectTimeout=5 homelab-lan

     If it still succeeds, the change did not do what it claims.
     Do not cancel the revert.

  3. Only when BOTH are true, make it permanent:

       sudo systemctl stop ${UNIT}.timer

  If you do nothing, ufw disables itself and the node returns to
  its previous state.
  ----------------------------------------------------------------

EOF
