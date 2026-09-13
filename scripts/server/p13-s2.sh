#!/usr/bin/env bash
#
# Phase 13 S2 -- the node-side steps that are not sshd or the firewall.
#
# Run on:  the Ubuntu server, as root
# Usage:   sudo bash /tmp/p13/p13-s2.sh <tmout|helper|helper-nofilter|wifi|lxd> [--undo]
# Phase:   13 -- Security hardening. Runbook: guide/13-security-hardening/s2-runbook.md
#
# Every subcommand prints what it is about to do, backs up the file it replaces
# as <file>.bak-<date>, applies, and prints the check that decides it. Nothing
# waits for input. `--undo` restores the backup and re-applies. The files come
# from /tmp/p13/, copied there by the runbook from config/ in the repository.

set -euo pipefail
STAMP="$(date +%Y-%m-%d)"
SRC=/tmp/p13
say() { printf '  %s\n' "$*"; }
die() { printf '\n  ERROR: %s\n\n' "$*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || die "run with sudo"

backup() { # never overwrite an earlier backup from the same day (a second round would lose the original)
  if [ -f "$1" ]; then [ -f "$1.bak-$STAMP" ] && say "backup exists: $1.bak-$STAMP (kept)" || { cp -p "$1" "$1.bak-$STAMP"; say "backup: $1.bak-$STAMP"; }; else say "no existing $1 (nothing to back up)"; fi; }
restore() { [ -f "$1.bak-$STAMP" ] || die "no backup $1.bak-$STAMP"; cp -p "$1.bak-$STAMP" "$1"; say "restored $1"; }

cmd="${1:-}"; undo="${2:-}"
case "$cmd" in

tmout)
  F=/etc/profile.d/homelab-console-timeout.sh
  if [ "$undo" = --undo ]; then say "removing $F"; rm -f "$F"; exit 0; fi
  say "about to: install $F (tty-only TMOUT=900); SSH sessions unaffected"
  [ -f "$SRC/homelab-console-timeout.sh" ] || die "copy config/profile.d/homelab-console-timeout.sh to $SRC first"
  install -o root -g root -m 0644 "$SRC/homelab-console-timeout.sh" "$F"
  bash -n "$F" && say "syntax ok"
  say "check (from this SSH session, expect 'unset' -- the guard must NOT fire on a pts):"
  bash -lc 'echo "TMOUT=${TMOUT:-unset}"'
  say "the positive half (a tty login ends after 15 min) is proved at the box in S3." ;;

helper|helper-nofilter)
  U=/etc/systemd/system/homelab-model-helper@.service
  if [ "$undo" = --undo ]; then restore "$U"; systemctl daemon-reload; say "daemon-reload done; next connection uses the restored unit"; exit 0; fi
  [ -f "$SRC/homelab-model-helper@.service" ] || die "copy config/systemd/homelab-model-helper@.service to $SRC first"
  tmp="$(mktemp -d)/homelab-model-helper@.service"; cp "$SRC/homelab-model-helper@.service" "$tmp"   # verify needs the real name
  if [ "$cmd" = helper-nofilter ]; then
    say "about to: install the hardened helper unit WITHOUT the two SystemCallFilter lines (bisect round, brief 6.12)"
    sed -i '/^SystemCallFilter=/d' "$tmp"
  else
    say "about to: install the hardened helper unit (InaccessiblePaths ~/.ssh, native ABI; the syscall filter was removed after S2 -- see the unit)"
  fi
  say "no restart: the socket stays up; instances are per-connection, so the next /ask uses the new unit"
  backup "$U"
  systemd-analyze verify "$tmp" 2>&1 | sed 's/^/    /' || true
  install -o root -g root -m 0644 "$tmp" "$U"; rm -rf "$(dirname "$tmp")"
  systemctl daemon-reload
  say "installed. socket still: $(systemctl is-active homelab-model-helper.socket)"
  say "score (offline, from the file):"
  systemd-analyze security --no-pager --offline=true "$U" 2>/dev/null | tail -1 | sed 's/^/    /'
  say "the decisive check is the key being unreadable INSIDE the sandbox; the runbook runs it via systemd-run" ;;

wifi)
  U=/etc/systemd/system/wifi-powersave-off.service
  if [ "$undo" = --undo ]; then restore "$U"; systemctl daemon-reload; systemctl restart wifi-powersave-off; iw dev wlp1s0 get power_save; exit 0; fi
  [ -f "$SRC/wifi-powersave-off.service" ] || die "copy config/systemd/wifi-powersave-off.service to $SRC first"
  say "about to: install the bounded wifi-powersave-off unit, daemon-reload, RESTART it, and read power_save"
  say "this touches the only network path. Second idle session open? (the runbook says so.)"
  backup "$U"
  systemd-analyze verify "$SRC/wifi-powersave-off.service" 2>&1 | sed 's/^/    /' || true
  install -o root -g root -m 0644 "$SRC/wifi-powersave-off.service" "$U"
  systemctl daemon-reload
  if systemctl restart wifi-powersave-off && [ "$(systemctl is-active wifi-powersave-off)" = active ] \
     && iw dev wlp1s0 get power_save | grep -q 'off'; then
    say "is-active: active"; iw dev wlp1s0 get power_save | sed 's/^/    /'
    systemd-analyze security --no-pager wifi-powersave-off.service | tail -1 | sed 's/^/    /'
  else
    say "FAILED -- reverting immediately (power-save on is how the node went dark before)"
    journalctl -u wifi-powersave-off -n 10 --no-pager | sed 's/^/    /' || true
    restore "$U"; systemctl daemon-reload; systemctl restart wifi-powersave-off || true
    iw dev wlp1s0 get power_save | sed 's/^/    /'; die "reverted; record the journal lines above"
  fi ;;

lxd)
  if [ "$undo" = --undo ]; then say "re-adding aleix to lxd"; gpasswd -a aleix lxd; exit 0; fi
  say "about to: remove aleix from the lxd group (root-equivalent, installer default, unused)"
  say "LXD snap present? $(snap list lxd 2>/dev/null | tail -n +2 | awk '{print $1" "$2}' || echo no)"
  getent group lxd | grep -q aleix || { say "aleix is not in lxd; nothing to do"; exit 0; }
  gpasswd -d aleix lxd
  say "now: $(getent group lxd)"
  say "takes effect at next login: verify with 'id' in a THIRD, fresh SSH session; this one still shows lxd" ;;

*) die "usage: $0 <tmout|helper|helper-nofilter|wifi|lxd> [--undo]" ;;
esac
