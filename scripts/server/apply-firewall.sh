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
# The node is not on a home LAN. Its Wi-Fi is shared across 40-50 rooms on a
# flat 192.168.0.0/21 -- 2046 usable addresses -- behind a router the owner does
# not control, whose management interface is reachable from the internet and
# which answers SSH with OpenSSH 7.0.
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
client_ip="${SSH_CLIENT%% *}"
case "$client_ip" in
  100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*|"")
    say "this session is on the tailnet (or local). Good." ;;
  *)
    die "this session came from $client_ip, which is not the tailnet.
       Reconnect with 'ssh homelab' over Tailscale and re-run, or the
       rules below will drop the connection applying them." ;;
esac

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
