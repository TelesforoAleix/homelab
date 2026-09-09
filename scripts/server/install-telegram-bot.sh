#!/usr/bin/env bash
#
# install-telegram-bot.sh -- deploy the Phase 07 Telegram status bot.
#
# Run on:  the Ubuntu server, as root
# Usage:   sudo bash /tmp/install-telegram-bot.sh install
# Phase:   07. See docs/handovers/07-telegram.md, ADR-023.
#
# THIS IS LOCKOUT-CLASS, FOR A NON-OBVIOUS REASON
#
#   docs/standards/safe-changes-headless.md lists under Boot: "anything
#   WantedBy=multi-user.target". This installs exactly that.
#
#   The realistic risk is low -- a failing bot does not normally stop a boot.
#   But the standard's argument is that lockouts come from not NOTICING a
#   safety step applied, and a unit with a careless Requires= or a tight
#   restart loop can degrade a boot on a machine with no console. So this
#   script checks for a way back, and validates the unit before enabling it.
#
# WHAT IT DELIBERATELY DOES NOT DO
#
#   - It does not enable or start the service. The token has to be installed
#     first, by a human, on this machine. Starting a bot with a placeholder
#     token would produce a confusing authentication failure instead of an
#     obvious missing-token error.
#   - It does not ask for, accept, or transport the token. The token is typed
#     into this machine directly. Phase 06 recorded a one-time authorization
#     code reaching an agent transcript; a bot token is long-lived, so the same
#     mistake would be worse.
#   - It never adds the service account to sudo or docker, and refuses to
#     proceed if something else already has.

set -euo pipefail

SVC_USER="homelab-bot"
SVC_GROUP="homelab-bot"
APP_DIR="/opt/homelab-telegram-bot"
CONF_DIR="/etc/homelab-telegram-bot"
UNIT="/etc/systemd/system/homelab-telegram-bot.service"
STAGE="/tmp/telegram-bot-stage"

die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
ok()  { printf '  ok   %s\n' "$*"; }
note(){ printf '  --   %s\n' "$*"; }

[ "${1:-}" = "install" ] || {
  printf 'usage: sudo bash %s install\n' "$0" >&2
  printf '\nThe explicit argument is deliberate: this installs a unit that\n' >&2
  printf 'starts at boot on a machine with no console.\n' >&2
  exit 2
}

printf '\n=== Home Lab: install the Telegram status bot ===\n\n'
[ "$(id -u)" -eq 0 ] || die "must run as root (use: sudo bash $0 install)"
ok "running as root"

# Counted with `w`, never `who`: /run/utmp does not exist on systemd 259.
SESSIONS="$(w -h 2>/dev/null | awk '$2 ~ /^pts\//' | wc -l | tr -d ' ')"
WLINES="$(w -h 2>/dev/null | wc -l | tr -d ' ')"
if [ "${WLINES:-0}" -eq 0 ]; then
  note "cannot determine session count -- check manually with: w"
elif [ "${SESSIONS:-0}" -lt 2 ]; then
  die "only ${SESSIONS} interactive session(s). This installs a boot-time unit,
which the standard classifies as lockout-class (ADR-020). Open a second
session and leave it idle."
else
  ok "${SESSIONS} interactive sessions -- one can stay idle as the way back"
fi

for f in bot.py router.py executors.py model_client.py homelab-telegram-bot.service allowlist.example; do
  [ -f "$STAGE/$f" ] || die "$STAGE/$f not found. scp the staging directory from the repository first."
done
ok "staged files present"

# --- Service account -----------------------------------------------------
#
# A system account: no login shell, no password, no home directory. It owns
# nothing and can log in nowhere. ADR-011 in its simplest form.

if id "$SVC_USER" >/dev/null 2>&1; then
  EXISTING_UID="$(id -u "$SVC_USER")"
  [ "$EXISTING_UID" -lt 1000 ] || die "'$SVC_USER' exists with uid $EXISTING_UID (>=1000).
That looks like a human account. Refusing to reuse it."
  ok "service account already exists (uid $EXISTING_UID)"
else
  useradd --system --no-create-home --home-dir /nonexistent \
          --shell /usr/sbin/nologin --user-group "$SVC_USER"
  ok "created system account $SVC_USER (uid $(id -u "$SVC_USER"))"
fi

# Guard, checked every run rather than only at creation: this account must
# never hold sudo or docker. Docker-group membership is root-equivalent
# (ADR-022) and would make every hardening directive below pointless.
for grp in sudo docker adm; do
  if id -nG "$SVC_USER" | tr ' ' '\n' | grep -qx "$grp"; then
    die "'$SVC_USER' is in the '$grp' group. That defeats the entire point of
this service account. Remove it before continuing:  gpasswd -d $SVC_USER $grp"
  fi
done
ok "service account is in no privileged group"

SHELL_OF="$(getent passwd "$SVC_USER" | cut -d: -f7)"
case "$SHELL_OF" in
  */nologin|*/false) ok "login shell is $SHELL_OF" ;;
  *) die "'$SVC_USER' has an interactive shell ($SHELL_OF). Refusing." ;;
esac

# --- Application ---------------------------------------------------------
#
# Root-owned and read-only to the service. The bot cannot modify its own code,
# so a compromise cannot persist by rewriting it.

install -d -m 0755 -o root -g root "$APP_DIR"
# model_client.py added in Phase 09. It is the ONLY part of the model feature
# that runs as this service account: it opens a UNIX socket and speaks JSON.
# The credentials, the CLIs and the caps are all on the far side of that socket,
# in homelab-model-helper, which runs as the owner.
for mod in bot.py router.py executors.py model_client.py; do
  install -m 0644 -o root -g root "$STAGE/$mod" "$APP_DIR/$mod"
done
ok "installed bot.py, router.py, executors.py, model_client.py (root-owned, not writable by $SVC_USER)"

# --- Does systemd actually accept the unit? ------------------------------
#
# Added in Phase 09, which found that Phase 07 put StartLimitIntervalSec in
# [Service], where systemd IGNORES it and carries on with its 10s default. The
# unit loaded, the service ran, and the restart-loop protection was never
# capable of firing. Nothing in the install output said so.
#
# A misplaced or misspelled directive is silent by design: systemd logs a note
# and applies the rest. So ask it, every install, and print what it says.
VOUT=$(systemd-analyze verify "$STAGE/homelab-telegram-bot.service" 2>&1 \
         | grep -F 'homelab-telegram-bot.service' || true)
if [ -n "$VOUT" ]; then
  note "systemd-analyze verify has complaints about the unit:"
  printf '%s\n' "$VOUT" | sed 's/^/       /'
  note "a directive systemd ignores is not a directive. Fix these."
else
  ok "systemd-analyze verify accepts the unit with no complaint"
fi

# --- Configuration -------------------------------------------------------

install -d -m 0750 -o root -g "$SVC_GROUP" "$CONF_DIR"

if [ ! -f "$CONF_DIR/allowlist" ]; then
  install -m 0640 -o root -g "$SVC_GROUP" "$STAGE/allowlist.example" "$CONF_DIR/allowlist"
  note "created $CONF_DIR/allowlist from the example -- IT HAS NO IDS YET"
  note "the bot will refuse to start until you add one (that is deliberate)"
else
  ok "$CONF_DIR/allowlist already exists -- left untouched"
fi

# The token file is root:root 0600. The SERVICE ACCOUNT CANNOT READ IT.
# systemd reads it as root during unit start and hands the service a private
# copy via LoadCredential. So a compromise of the bot process does not yield
# the file on disk.
if [ ! -f "$CONF_DIR/token" ]; then
  install -m 0600 -o root -g root /dev/null "$CONF_DIR/token"
  note "created empty $CONF_DIR/token -- you must fill it in by hand"
else
  chmod 0600 "$CONF_DIR/token"; chown root:root "$CONF_DIR/token"
  ok "$CONF_DIR/token exists; permissions reasserted as root:root 0600"
fi

# --- Unit ----------------------------------------------------------------

install -m 0644 -o root -g root "$STAGE/homelab-telegram-bot.service" "$UNIT"
systemctl daemon-reload
ok "installed $UNIT"

# Validate BEFORE enabling. Note the Phase 02 lesson: systemd-analyze verify
# walks the whole dependency closure, so warnings about unrelated units are
# expected and are not this unit's fault.
printf '\n--- systemd-analyze verify (closure warnings are normal) ---\n'
systemd-analyze verify "$UNIT" 2>&1 | sed 's/^/  /' || true

printf '\n--- systemd-analyze security ---\n'
systemd-analyze security homelab-telegram-bot.service 2>&1 | tail -3 | sed 's/^/  /' || true

cat <<'NEXT'

=== NOT ENABLED YET. Two things remain, and both are yours. ===

  1. Put the BotFather token into the file, ON THIS MACHINE. Never paste it
     into a chat window, an agent conversation, or a shell command that lands
     in history.

       sudo systemd-creds --help >/dev/null   # (informational)
       sudoedit /etc/homelab-telegram-bot/token

     Paste the token as the only line. Save. It stays root:root 0600, and the
     service account cannot read it -- systemd hands the service a copy.

  2. Add your numeric Telegram user id to the allowlist.

       sudoedit /etc/homelab-telegram-bot/allowlist

     Do not know your id? Start the bot, message it, then read:
       journalctl -u homelab-telegram-bot -n 20
     It logs the refused id without revealing anything else.

  Then, and only then:

       sudo systemctl enable --now homelab-telegram-bot
       systemctl status homelab-telegram-bot
NEXT
