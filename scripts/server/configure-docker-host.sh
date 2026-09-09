#!/usr/bin/env bash
#
# configure-docker-host.sh -- the two host changes Phase 05 makes after Docker
# is installed.
#
# Run on:  the Ubuntu server, as root
# Usage:   sudo bash /tmp/configure-docker-host.sh apply
# Phase:   05. See docs/handovers/05-docker.md, ADR-022.
#
# TWO CHANGES, ONE OF WHICH IS LOCKOUT-CLASS BY THE STANDARD'S OWN DEFINITION
#
#   1. vm.swappiness 60 -> 10, via a sysctl drop-in. Ordinary work.
#
#   2. Add the admin user to the `docker` group.
#
#      docs/standards/safe-changes-headless.md lists "the admin account --
#      aleix, its shell, home directory, groups, or UID" as lockout-class.
#      Adding a supplementary group is about as benign as a change to that
#      account gets -- but the standard's whole argument is that
#      classification is the control, and that most lockouts come from not
#      NOTICING a safety step applied. So it gets checked rather than waved
#      through, and this script refuses to run without a way back.
#
#      What it actually means, recorded rather than glossed: the docker group
#      can start a container that mounts the host filesystem. It is therefore
#      equivalent to root -- and unlike sudo, it has no password prompt. It
#      grants the admin no capability they did not already have via sudo; it
#      removes the gate in front of it. That is a real trade and ADR-022
#      records it as one.
#
#      It must never be granted to a service account (ADR-011).

set -euo pipefail

SYSCTL_SRC="/tmp/99-homelab-swappiness.conf"
SYSCTL_DST="/etc/sysctl.d/99-homelab-swappiness.conf"
TARGET_USER="${SUDO_USER:-aleix}"

die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
ok()  { printf '  ok   %s\n' "$*"; }
note(){ printf '  --   %s\n' "$*"; }

[ "${1:-}" = "apply" ] || { printf 'usage: sudo bash %s apply\n' "$0" >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || die "must run as root (use: sudo bash $0 apply)"
ok "running as root"

# Counted with `w`, never `who` -- /run/utmp does not exist on systemd 259.
SESSIONS="$(w -h 2>/dev/null | awk '$2 ~ /^pts\//' | wc -l | tr -d ' ')"
WLINES="$(w -h 2>/dev/null | wc -l | tr -d ' ')"
if [ "${WLINES:-0}" -eq 0 ]; then
  note "cannot determine session count -- check manually with: w"
elif [ "${SESSIONS:-0}" -lt 2 ]; then
  die "only ${SESSIONS} interactive session(s). This touches the admin
account's groups, which the standard classifies as lockout-class (ADR-020)."
else
  ok "${SESSIONS} interactive sessions -- one can stay idle as the way back"
fi

printf '\n--- 1. vm.swappiness ---\n'
BEFORE_SW="$(sysctl -n vm.swappiness)"
ok "current vm.swappiness = $BEFORE_SW"

[ -f "$SYSCTL_SRC" ] || die "$SYSCTL_SRC not found. scp it from the repository:
  config/sysctl/99-homelab-swappiness.conf
Configuration that belongs in the repository is transferred, never pasted."

install -m 0644 -o root -g root "$SYSCTL_SRC" "$SYSCTL_DST"
ok "installed $SYSCTL_DST"

sysctl -p "$SYSCTL_DST" >/dev/null
AFTER_SW="$(sysctl -n vm.swappiness)"
[ "$AFTER_SW" = "10" ] || die "vm.swappiness is $AFTER_SW, expected 10"
ok "vm.swappiness now $AFTER_SW (was $BEFORE_SW)"

printf '\n--- 2. docker group membership ---\n'
getent group docker >/dev/null || die "group 'docker' does not exist -- is Docker installed?"
id "$TARGET_USER" >/dev/null 2>&1 || die "user '$TARGET_USER' does not exist"

printf '  before: '; id "$TARGET_USER"

if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx docker; then
  note "$TARGET_USER is already in the docker group -- nothing to do"
else
  usermod -aG docker "$TARGET_USER"
  ok "added $TARGET_USER to the docker group"
fi

printf '  after:  '; id "$TARGET_USER"

# Verify the group database, not the command's exit status.
id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx docker \
  || die "verification failed: $TARGET_USER is not in the docker group"
ok "verified from the group database"

# Confirm nothing else about the account moved. A change to the admin account
# should change exactly one thing, and you should be able to say so.
printf '\n--- 3. what did NOT change ---\n'
printf '  shell:  %s\n' "$(getent passwd "$TARGET_USER" | cut -d: -f7)"
printf '  home:   %s\n' "$(getent passwd "$TARGET_USER" | cut -d: -f6)"
printf '  uid:    %s\n' "$(id -u "$TARGET_USER")"
printf '  sudo:   %s\n' "$(id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx sudo && echo 'still present' || echo 'MISSING -- INVESTIGATE')"

cat <<'NEXT'

=== NEXT ===

  Group membership applies to NEW logins only. An existing session keeps the
  groups it was given at login -- so reconnect before expecting `docker ps`
  to work without sudo, and do not conclude it failed until you have.

  Verify from a fresh connection:
    ssh homelab 'id; docker ps'
NEXT
