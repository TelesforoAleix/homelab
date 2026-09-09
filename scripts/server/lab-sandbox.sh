#!/usr/bin/env bash
#
# lab-sandbox.sh — a disposable practice environment for Phase 02 exercises.
#
# WHY THIS EXISTS
# ---------------
# Phase 02 teaches the *write* side of users, groups, permissions and systemd
# units. Practising those on a real account, on a machine with no console, is
# how people lock themselves out. So the exercises run against a throwaway user,
# a throwaway group, a throwaway directory and a throwaway unit — all of which
# this script creates and, more importantly, removes again.
#
# The teardown is not cleanup. A forgotten practice account with no password is
# exactly the kind of thing that survives into production, and Phase 02's
# validation check 9 exists to prove it is gone.
#
# THE GUARD RAILS ARE THE POINT
# -----------------------------
# `userdel -r` on the wrong name deletes somebody's home directory. This script
# therefore refuses to operate on anything it did not create:
#
#   * setup   refuses root, refuses any UID below 1000, refuses an existing
#             account, and refuses any member of the `sudo` group.
#   * teardown refuses any account whose GECOS comment does not carry the
#             marker string below. If this script did not create it, this
#             script will not delete it.
#
# The names are overridable so the guards can actually be tested:
#
#   LAB_USER=aleix sudo -E bash lab-sandbox.sh setup     # must refuse
#
# USAGE
#   sudo bash lab-sandbox.sh setup
#   sudo bash lab-sandbox.sh status
#   sudo bash lab-sandbox.sh teardown
#
set -euo pipefail

LAB_USER="${LAB_USER:-labuser}"
LAB_GROUP="${LAB_GROUP:-labgroup}"
LAB_DIR="${LAB_DIR:-/srv/lab}"
LAB_UNIT="${LAB_UNIT:-homelab-lab.service}"

# The marker that makes teardown safe. Only accounts carrying it can be removed.
MARKER="homelab phase-02 lab sandbox (disposable)"

say()  { printf '%s\n' "$*"; }
ok()   { printf '  ok   %s\n' "$*"; }
info() { printf '  ..   %s\n' "$*"; }
die()  { printf 'REFUSED: %s\n' "$*" >&2; exit 1; }

need_root() {
  [ "$(id -u)" -eq 0 ] || die "run this with sudo — it creates and deletes users"
}

# ---------------------------------------------------------------------------
# Guard rails.
# ---------------------------------------------------------------------------

# Refuse to CREATE anything that could collide with a real account.
guard_create() {
  local u="$1"

  case "$u" in
    root|aleix) die "'$u' is a real account. This script never touches it." ;;
    '')         die "empty username" ;;
  esac

  if id "$u" >/dev/null 2>&1; then
    local uid
    uid="$(id -u "$u")"
    # An existing account might be a system account, or the operator's own.
    # Either way it is not ours to reuse.
    die "'$u' already exists (uid $uid). This script only creates new accounts."
  fi

  # Belt and braces: if someone points LAB_USER at a sudoer via a different
  # spelling, the group check catches it before we do anything.
  if id -nG "$u" 2>/dev/null | tr ' ' '\n' | grep -qx sudo; then
    die "'$u' is a member of the sudo group"
  fi
}

# Refuse to DELETE anything this script did not create.
guard_delete() {
  local u="$1"

  case "$u" in
    root|aleix) die "'$u' is a real account. This script never deletes it." ;;
  esac

  id "$u" >/dev/null 2>&1 || { info "user '$u' is already absent"; return 1; }

  local uid comment
  uid="$(id -u "$u")"
  [ "$uid" -ge 1000 ] || die "'$u' has uid $uid — below 1000 means a system account"

  if id -nG "$u" | tr ' ' '\n' | grep -qx sudo; then
    die "'$u' is a member of the sudo group"
  fi

  # The decisive check: did we create it?
  comment="$(getent passwd "$u" | cut -d: -f5)"
  [ "$comment" = "$MARKER" ] || \
    die "'$u' does not carry the sandbox marker — this script did not create it"

  return 0
}

# ---------------------------------------------------------------------------
# setup
# ---------------------------------------------------------------------------
do_setup() {
  need_root
  guard_create "$LAB_USER"

  say "Creating the Phase 02 sandbox."

  # The group first, so the user can be created directly into it.
  if getent group "$LAB_GROUP" >/dev/null; then
    info "group '$LAB_GROUP' already exists"
  else
    groupadd "$LAB_GROUP"
    ok "group '$LAB_GROUP' created (gid $(getent group "$LAB_GROUP" | cut -d: -f3))"
  fi

  # --shell /usr/sbin/nologin  : this account is to be looked at, not logged into.
  # --no-create-home           : its working area is $LAB_DIR, which we own and can delete.
  # (no password is set at all, so password login is impossible, not merely hard)
  # ADR-011 in miniature: an unprivileged account with the least it needs.
  useradd \
    --gid "$LAB_GROUP" \
    --shell /usr/sbin/nologin \
    --no-create-home \
    --comment "$MARKER" \
    "$LAB_USER"
  ok "user '$LAB_USER' created (uid $(id -u "$LAB_USER"), no password, nologin shell)"

  # 2770: rwx for owner, rwx for group, nothing for others, plus the setgid bit.
  # setgid on a directory means new files inherit the DIRECTORY's group rather
  # than the creating user's primary group — the standard way to make a shared
  # working area actually work. Exercise 6 in the guide demonstrates it.
  mkdir -p "$LAB_DIR"
  chown "$LAB_USER:$LAB_GROUP" "$LAB_DIR"
  chmod 2770 "$LAB_DIR"
  ok "directory '$LAB_DIR' created  $(stat -c '%A %U:%G' "$LAB_DIR")"

  # A deliberately trivial unit. It is Type=oneshot and does nothing useful:
  # its entire purpose is to be broken on purpose in exercise 8 and diagnosed
  # from the journal alone. Note what it is NOT:
  #   - not enabled  (so it can never affect boot)
  #   - no WantedBy  (so `systemctl enable` would refuse anyway)
  #   - runs as the unprivileged sandbox user, never as root
  cat > "/etc/systemd/system/$LAB_UNIT" <<UNIT
[Unit]
Description=Home Lab Phase 02 practice unit (disposable)
Documentation=file://$LAB_DIR

[Service]
Type=oneshot
User=$LAB_USER
Group=$LAB_GROUP
WorkingDirectory=$LAB_DIR
ExecStart=/usr/bin/env bash -c 'echo "practice unit ran at \$(date -Is)" >> $LAB_DIR/unit.log'

# Deliberately no [Install] section. This unit cannot be enabled, so it can
# never run at boot, so it can never contribute to a boot failure.
UNIT
  chmod 0644 "/etc/systemd/system/$LAB_UNIT"
  systemctl daemon-reload
  ok "unit '$LAB_UNIT' installed (not enabled — it cannot run at boot)"

  say ""
  say "Sandbox ready. Nothing here can affect access or boot."
  say "Tear it down with:  sudo bash $0 teardown"
}

# ---------------------------------------------------------------------------
# status
# ---------------------------------------------------------------------------
do_status() {
  say "Phase 02 sandbox status"
  say ""

  if id "$LAB_USER" >/dev/null 2>&1; then
    say "  user      $(getent passwd "$LAB_USER")"
    say "  groups    $(id -nG "$LAB_USER")"
  else
    say "  user      absent"
  fi

  getent group "$LAB_GROUP" >/dev/null \
    && say "  group     $(getent group "$LAB_GROUP")" \
    || say "  group     absent"

  [ -d "$LAB_DIR" ] \
    && say "  directory $(stat -c '%A %U:%G %n' "$LAB_DIR")" \
    || say "  directory absent"

  [ -f "/etc/systemd/system/$LAB_UNIT" ] \
    && say "  unit      present — $(systemctl is-enabled "$LAB_UNIT" 2>&1), $(systemctl is-active "$LAB_UNIT" 2>&1)" \
    || say "  unit      absent"
}

# ---------------------------------------------------------------------------
# teardown
# ---------------------------------------------------------------------------
do_teardown() {
  need_root

  say "Removing the Phase 02 sandbox."

  # The unit goes first: never delete a user an active service is running as.
  if [ -f "/etc/systemd/system/$LAB_UNIT" ]; then
    systemctl stop "$LAB_UNIT" 2>/dev/null || true
    rm -f "/etc/systemd/system/$LAB_UNIT"
    systemctl daemon-reload
    # Clears the record of a unit that no longer exists on disk.
    systemctl reset-failed "$LAB_UNIT" 2>/dev/null || true
    ok "unit '$LAB_UNIT' removed"
  else
    info "unit already absent"
  fi

  # guard_delete returns non-zero (without dying) when the user is simply not
  # there, so this `if` distinguishes "nothing to do" from "refused".
  if guard_delete "$LAB_USER"; then
    userdel "$LAB_USER"
    ok "user '$LAB_USER' removed"
  fi

  if getent group "$LAB_GROUP" >/dev/null; then
    groupdel "$LAB_GROUP"
    ok "group '$LAB_GROUP' removed"
  else
    info "group already absent"
  fi

  # Only remove the directory if it is the one we made, at the path we chose.
  # Refusing to rm -rf an arbitrary LAB_DIR is worth the two extra lines.
  case "$LAB_DIR" in
    /srv/lab|/srv/lab/*)
      if [ -d "$LAB_DIR" ]; then
        rm -rf "$LAB_DIR"
        ok "directory '$LAB_DIR' removed"
      else
        info "directory already absent"
      fi
      ;;
    *)
      say "  !!   '$LAB_DIR' is not under /srv/lab — remove it yourself if you meant to"
      ;;
  esac

  say ""
  say "Verify with:  bash $0 status"
}

case "${1:-}" in
  setup)    do_setup ;;
  status)   do_status ;;
  teardown) do_teardown ;;
  *)
    say "usage: $0 {setup|status|teardown}"
    say ""
    say "  setup     create the disposable user, group, directory and unit"
    say "  status    show what currently exists"
    say "  teardown  remove all of it (refuses anything it did not create)"
    exit 2
    ;;
esac
