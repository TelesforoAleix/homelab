#!/usr/bin/env bash
#
# Install the Home Lab sshd hardening drop-in, safely.
#
# Run on:  the Ubuntu server, as root
# Usage:   sudo bash /tmp/apply-ssh-hardening.sh
# Phase:   03 (Remote Access). See docs/handovers/03-remote-access.md, ADR-018.
#
# Why this is a script and not four commands in the guide
# -------------------------------------------------------
# Disabling password authentication is the one change that can lock you out of
# a headless machine permanently. Three things go wrong in practice:
#
#   1. installing a file that does not parse;
#   2. disabling passwords when no working key is installed;
#   3. believing the change is live when it is not.
#
# This script reverts (1), refuses (2), and handles (3) explicitly.
#
# On (3), which cost this phase a wrong turn worth recording
# ----------------------------------------------------------
# Ubuntu 26.04 enables ssh.socket, and it is tempting to conclude that sshd is
# started per connection and therefore re-reads its configuration every time.
# That is true of inetd-style socket activation (Accept=yes, sshd -i). Ubuntu
# does NOT do that:
#
#     ssh.socket:   Accept=no
#     ssh.service:  ExecStart=/usr/sbin/sshd -D $SSHD_OPTS
#
# With Accept=no, systemd holds port 22, starts ONE long-running sshd on the
# first connection, and hands it the listening socket. Every later connection
# is a fork of that daemon, inheriting the configuration it parsed at start.
#
# So a drop-in written at 12:28 has no effect at all on a daemon started at
# 08:01. `sshd -T` still reports the new values — it re-parses the files on the
# spot — which makes this genuinely deceptive: the configuration check agrees
# with you while the running server does not. The observable truth is what the
# server advertises to a client:
#
#     ssh -o PreferredAuthentications=none user@host
#     -> Permission denied (publickey,password)   <- password STILL accepted
#     -> Permission denied (publickey)            <- actually disabled
#
# Hence the reload below, and hence the guide checks from a second terminal
# rather than trusting sshd -T alone.

set -euo pipefail

SRC="${1:-/tmp/10-homelab-hardening.conf}"
DEST_DIR="/etc/ssh/sshd_config.d"
DEST="$DEST_DIR/10-homelab-hardening.conf"

die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
ok()  { printf '  ok   %s\n' "$*"; }

printf '\n=== Home Lab: apply SSH hardening ===\n\n'

# --- Preconditions --------------------------------------------------------

[ "$(id -u)" -eq 0 ] || die "must run as root (use: sudo bash $0)"
ok "running as root"

[ -f "$SRC" ] || die "source file not found: $SRC
Copy it from the repository first:
  scp config/ssh/10-homelab-hardening.conf homelab:/tmp/"
ok "source file present: $SRC"

[ -d "$DEST_DIR" ] || die "$DEST_DIR does not exist"
ok "destination directory exists"

# --- Refuse to lock the operator out --------------------------------------
#
# SUDO_USER is the account that invoked sudo, i.e. the human. Checking root's
# authorized_keys would be useless: this drop-in sets PermitRootLogin no, so
# root cannot log in regardless.

ADMIN="${SUDO_USER:-}"
[ -n "$ADMIN" ] || die "cannot determine the invoking user (SUDO_USER unset).
Run via sudo from your normal account, not from a root shell."

ADMIN_HOME="$(getent passwd "$ADMIN" | cut -d: -f6)"
AK="$ADMIN_HOME/.ssh/authorized_keys"

[ -s "$AK" ] || die "$AK is missing or empty.
This file is about to disable password authentication. Without a working key
for '$ADMIN' that would lock you out of this machine. Install your key first:
  ssh-copy-id -i ~/.ssh/id_ed25519_homelab.pub $ADMIN@<server>"

KEYCOUNT="$(grep -c -E '^[^#[:space:]]' "$AK" || true)"
[ "$KEYCOUNT" -ge 1 ] || die "$AK contains no usable key entries"
ok "$ADMIN has $KEYCOUNT authorized key(s) installed"

# --- Install --------------------------------------------------------------
#
# Keep any existing file so a re-run is reversible.

if [ -f "$DEST" ]; then
  BACKUP="$DEST.bak.$(date +%Y%m%d%H%M%S)"
  cp -p "$DEST" "$BACKUP"
  ok "existing file backed up to $BACKUP"
else
  BACKUP=""
fi

install -o root -g root -m 0600 "$SRC" "$DEST"
ok "installed $DEST (root:root, 0600)"

# `install` sets ownership and mode in one step, which is why this script does
# not repeat Phase 01's mistake of an scp'd file left owned by a normal user.
# A file that root parses but a non-root user can rewrite is a privilege
# escalation path.

# --- Validate, and revert if invalid --------------------------------------
#
# sshd -t parses the whole configuration, including every drop-in, and prints
# nothing when it is valid. Because of socket activation the new file is
# already live at this point, so a failure here must be undone immediately
# rather than reported and left in place.

if ! sshd -t 2>/tmp/sshd-test.err; then
  printf '\n  !! sshd -t REJECTED the configuration:\n\n'
  sed 's/^/     /' /tmp/sshd-test.err
  rm -f "$DEST"
  if [ -n "$BACKUP" ]; then
    mv "$BACKUP" "$DEST"
    printf '\n  reverted to the previous file. '
  else
    printf '\n  removed the new file. '
  fi
  printf 'SSH is unchanged; you are not locked out.\n\n'
  exit 1
fi
ok "sshd -t accepted the configuration"

# Written as an `if` rather than `[ -n "$BACKUP" ] && rm -f "$BACKUP"`.
# The one-liner is actually safe here — `set -e` ignores a failing command that
# is not the last in an AND list — but it is NOT safe as the final line of a
# script or function, where the list's non-zero status becomes the exit status.
# The `if` form behaves the same wherever it is moved to, so it is the one
# worth having the habit of.
if [ -n "$BACKUP" ]; then
  rm -f "$BACKUP"
fi

# --- Report what sshd actually resolved -----------------------------------
#
# This is the only trustworthy check. The file says what we asked for; sshd -T
# says what sshd concluded after reading every drop-in in order. They differ
# whenever the first-match-wins rule bites.

printf '\nEffective configuration (sshd -T — what sshd actually resolved):\n\n'
sshd -T | grep -E '^(passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|permitrootlogin|authenticationmethods) ' | sed 's/^/  /'

printf '\nDrop-ins now present, in the order sshd reads them:\n\n'
ls -1 "$DEST_DIR"/*.conf | sed 's/^/  /'

# --- Make it actually take effect -----------------------------------------
#
# See the note at the top: the running sshd parsed its configuration when it
# started and will not notice this file on its own. Reload, do not restart.
#
#   ExecReload=/usr/sbin/sshd -t          <- validates again before acting
#   ExecReload=/bin/kill -HUP $MAINPID    <- sshd re-execs and re-reads config
#
# and ssh.service sets KillMode=process, so established sessions survive. A
# restart is heavier and needlessly risks the connection you are typing into.

STARTED_BEFORE="$(systemctl show ssh.service -p ActiveEnterTimestamp --value)"
printf '\nReloading sshd...\n'
systemctl reload ssh
ok "reload issued (sshd re-execs and re-reads its configuration)"

MAINPID="$(systemctl show ssh.service -p MainPID --value)"
printf '  daemon: PID %s, service active since %s\n' "$MAINPID" "$STARTED_BEFORE"

printf '\nDone. Established sessions, including this one, are unaffected.\n\n'
printf 'Now prove it from ANOTHER terminal. sshd -T is NOT sufficient evidence:\n'
printf '  key login still works:\n'
printf '    ssh homelab true\n'
printf '  the server no longer offers passwords (expect "publickey" alone):\n'
printf '    ssh -o PreferredAuthentications=none homelab true\n\n'
