#!/usr/bin/env bash
#
# Make ufw's boundary hold for published container ports (DOCKER-USER).
#
# Run on:  the Ubuntu server, as root
# Usage:   sudo bash /tmp/apply-docker-user-rules.sh          # apply, self-revert armed
#          sudo bash /tmp/apply-docker-user-rules.sh --keep   # cancel the self-revert
#          sudo bash /tmp/apply-docker-user-rules.sh --undo   # restore the backups now
# Phase:   13 -- Security hardening, S2, brief §6.4.
#
# WHY THIS EXISTS
# ---------------
# `ufw` filters INPUT. A published container port (-p 8080:80) is DNAT'd and
# then FORWARDed; in the FORWARD chain Docker's own DOCKER-FORWARD accepts the
# packet BEFORE ufw's forward chains are consulted (OBSERVED S1: FORWARD is
# ts-forward -> DOCKER-USER -> DOCKER-FORWARD -> ufw-*). So today a container
# published to 0.0.0.0 is reachable from all 2046 hosts of the shared LAN and
# ufw's "deny (routed)" never sees it.
#
# DOCKER-USER is the hook Docker provides for exactly this: a chain it jumps to
# first and never flushes. The rules below RETURN (let Docker decide) for
# traffic from the tailnet, loopback and Docker's own bridges, and for replies
# to connections a container opened; everything else arriving from a physical
# interface is DROPped.
#
# WHY NOT INSIDE apply-firewall.sh
# --------------------------------
# That script does `ufw --force reset`, which restores /etc/ufw/*.rules to the
# package defaults -- it would erase this block. And this block has to live in
# /etc/ufw/after.rules (and after6.rules) because ufw is what re-applies rules
# after a reboot; a bare `iptables -A DOCKER-USER` would last until the next
# boot and then silently vanish. `:DOCKER-USER - [0:0]` creates the chain if
# Docker has not yet (ufw starts before docker), and Docker adopts it.
#
# SAFETY
# ------
# This touches the FORWARD path only; SSH arrives on INPUT and is unaffected.
# The self-revert is still armed, because "unaffected" is a prediction until a
# fresh `ssh homelab` proves it. Under docs/standards/safe-changes-headless.md:
# second idle session, third fresh connection afterwards.

set -euo pipefail

REVERT_MIN="${REVERT_MIN:-10}"
UNIT="homelab-docker-user-selfrevert"
STAMP="$(date +%Y-%m-%d)"
MARK_BEGIN="# BEGIN homelab DOCKER-USER (Phase 13)"
MARK_END="# END homelab DOCKER-USER (Phase 13)"

die() { printf '\n  ERROR: %s\n\n' "$*" >&2; exit 1; }
say() { printf '  %s\n' "$*"; }
[ "$(id -u)" -eq 0 ] || die "run with sudo"

block4() {
cat <<EOF
$MARK_BEGIN
# Published container ports must not bypass ufw. See
# scripts/server/apply-docker-user-rules.sh in the homelab repository.
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
-A DOCKER-USER -i tailscale0 -j RETURN
-A DOCKER-USER -i lo -j RETURN
-A DOCKER-USER -i docker0 -j RETURN
-A DOCKER-USER -i br-+ -j RETURN
-A DOCKER-USER -i wlp1s0 -j DROP
-A DOCKER-USER -i eno1 -j DROP
-A DOCKER-USER -j RETURN
COMMIT
$MARK_END
EOF
}

strip_block() { # $1 file  -> stdout without our block
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$1"
}

restore() {
  for f in /etc/ufw/after.rules /etc/ufw/after6.rules; do
    if [ -f "$f.bak-$STAMP" ]; then cp -p "$f.bak-$STAMP" "$f"; say "restored $f"; fi
  done
  ufw reload >/dev/null && say "ufw reloaded"
}

case "${1:-}" in
  --keep)
    say "cancelling the self-revert timer; the DOCKER-USER rules stay"
    systemctl stop "${UNIT}.timer" 2>/dev/null || true
    say "kept. Current chain:"; iptables -S DOCKER-USER | sed 's/^/    /'
    exit 0 ;;
  --undo)
    say "restoring /etc/ufw/after.rules and after6.rules from today's backups"
    systemctl stop "${UNIT}.timer" 2>/dev/null || true
    restore; exit 0 ;;
  "") ;;
  *) die "unknown option $1" ;;
esac

say "about to: back up after.rules/after6.rules, append the DOCKER-USER block, arm a ${REVERT_MIN}-minute self-revert, ufw reload"
command -v ufw >/dev/null || die "ufw not installed"
ufw status | grep -q '^Status: active' || die "ufw is not active; apply-firewall.sh first"

for f in /etc/ufw/after.rules /etc/ufw/after6.rules; do
  [ -f "$f" ] || die "$f missing"
  cp -p "$f" "$f.bak-$STAMP"
  say "backup: $f.bak-$STAMP"
done

# Arm the revert BEFORE writing anything.
systemctl stop "${UNIT}.timer" 2>/dev/null || true
systemd-run --quiet --on-active="${REVERT_MIN}min" --unit="$UNIT" \
  /bin/bash -c "cp -p /etc/ufw/after.rules.bak-$STAMP /etc/ufw/after.rules; cp -p /etc/ufw/after6.rules.bak-$STAMP /etc/ufw/after6.rules; /usr/sbin/ufw reload" \
  || die "could not arm the self-revert; nothing changed"
say "self-revert armed: backups restored and ufw reloaded in ${REVERT_MIN} minutes unless --keep"

# Idempotent: strip an older copy of our block, then append the current one.
# ufw requires each file to end with its own COMMIT; ours is a second *filter
# table block appended after it, which iptables-restore accepts.
for f in /etc/ufw/after.rules /etc/ufw/after6.rules; do
  tmp="$(mktemp)"; strip_block "$f" > "$tmp"; printf '\n' >> "$tmp"; block4 >> "$tmp"
  install -o root -g root -m 0640 "$tmp" "$f"; rm -f "$tmp"
  say "written: $f"
done

say "ufw reload (re-reads after.rules; INPUT rules unchanged)"
ufw reload >/dev/null || { say "ufw reload FAILED -- restoring"; restore; die "reverted"; }

printf '\n'
say "iptables -S DOCKER-USER:";  iptables  -S DOCKER-USER | sed 's/^/    /'
say "ip6tables -S DOCKER-USER:"; ip6tables -S DOCKER-USER | sed 's/^/    /'
say "FORWARD policies:"; iptables -S FORWARD | head -1 | sed 's/^/    /'; ip6tables -S FORWARD | head -1 | sed 's/^/    /'

cat <<EOF

  ----------------------------------------------------------------
  NOT FINISHED. The rules WILL REVERT in ${REVERT_MIN} minutes.

  1. From the MacBook, a FRESH connection:   ssh -o BatchMode=yes homelab true; echo \$?
  2. Optional real proof (pulls one small image, removed afterwards):
       see the S2 runbook step 2b.
  3. Only then:   sudo bash /tmp/apply-docker-user-rules.sh --keep
  ----------------------------------------------------------------

EOF
