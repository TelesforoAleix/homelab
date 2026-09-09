#!/usr/bin/env bash
#
# install-bot-escalation.sh -- grant the bot exactly one privileged action.
#
# Run on:  the Ubuntu server, as root
# Usage:   sudo bash /tmp/install-bot-escalation.sh install
# Phase:   08. See docs/handovers/08-router-executors.md, ADR-024.
#
# WHAT THIS GRANTS
#
#   homelab-bot may restart chrony.service. Nothing else, by any route.
#
#   One user, one unit, one verb. No wildcards. A wildcard would reach ssh,
#   tailscaled and systemd-networkd -- every service whose loss costs access to
#   this console-less machine.
#
# WHY POLKIT RATHER THAN THE SUDOERS RULE THE BRIEF SPECIFIED
#
#   The unit sets NoNewPrivileges=yes. sudo is setuid and is refused outright
#   under that flag:
#
#     sudo: The "no new privileges" flag is set, which prevents sudo from
#           running as root.
#
#   Using sudo would have required removing the hardening in order to add the
#   escalation. polkit needs no setuid -- the decision happens inside PID 1 --
#   so NoNewPrivileges stays on.
#
#   It is also far safer to get wrong. A malformed sudoers file BREAKS sudo on a
#   node with no console. A malformed polkit rule DENIES. This deviation reduces
#   the phase's lockout risk rather than accepting it.
#
# TWO GATES, DELIBERATELY
#
#   This rule is one of them. The other is a unit allowlist inside the bot. A
#   bug in the bot cannot reach a unit polkit refuses; a mistake in this rule
#   cannot reach a unit the bot's list does not name. Neither trusts the other.

set -euo pipefail

RULE_SRC="/tmp/50-homelab-bot.rules"
RULE_DST="/etc/polkit-1/rules.d/50-homelab-bot.rules"
SVC_USER="homelab-bot"
TARGET_UNIT="chrony.service"
CONF_DIR="/etc/homelab-telegram-bot"

die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
ok()  { printf '  ok   %s\n' "$*"; }
note(){ printf '  --   %s\n' "$*"; }

[ "${1:-}" = "install" ] || { printf 'usage: sudo bash %s install\n' "$0" >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || die "must run as root"
ok "running as root"

SESSIONS="$(w -h 2>/dev/null | awk '$2 ~ /^pts\//' | wc -l | tr -d ' ')"
WLINES="$(w -h 2>/dev/null | wc -l | tr -d ' ')"
if [ "${WLINES:-0}" -eq 0 ]; then
  note "cannot determine session count -- check manually with: w"
elif [ "${SESSIONS:-0}" -lt 2 ]; then
  die "only ${SESSIONS} interactive session(s). This changes authorisation policy
on a node with no console (ADR-020). Open a second session and leave it idle."
else
  ok "${SESSIONS} interactive sessions -- one can stay idle as the way back"
fi

id "$SVC_USER" >/dev/null 2>&1 || die "user '$SVC_USER' does not exist"
systemctl list-unit-files "$TARGET_UNIT" >/dev/null 2>&1 || die "$TARGET_UNIT is not a known unit"
ok "$SVC_USER and $TARGET_UNIT both exist"

[ -f "$RULE_SRC" ] || die "$RULE_SRC not found. scp it from config/polkit/ first."

# --- Sanity checks on the rule before installing --------------------------
#
# polkit has no `visudo -c`. It does not need one, because a broken rule denies
# rather than locks out -- but a rule that silently never matches is its own
# waste of an afternoon, so check the obvious shapes here.

grep -q 'polkit.addRule' "$RULE_SRC" || die "rule contains no polkit.addRule()"
grep -q "subject.user == \"$SVC_USER\"" "$RULE_SRC" || die "rule does not scope to $SVC_USER"
grep -q "\"$TARGET_UNIT\"" "$RULE_SRC" || die "rule does not name $TARGET_UNIT"
if grep -qE '\*|action\.id\s*==\s*"org\.freedesktop\.systemd1\.manage-units"\s*\)\s*\{?\s*$' "$RULE_SRC"; then
  grep -q 'action.lookup("unit")' "$RULE_SRC" || die "rule matches the action without scoping the unit -- refusing"
fi
ok "rule is scoped to one user, one unit, one verb"

OPEN="$(tr -cd '{' < "$RULE_SRC" | wc -c)"; CLOSE="$(tr -cd '}' < "$RULE_SRC" | wc -c)"
[ "$OPEN" = "$CLOSE" ] || die "unbalanced braces in the rule ($OPEN open, $CLOSE close)"
ok "braces balanced ($OPEN/$CLOSE)"

# --- Install --------------------------------------------------------------

install -m 0644 -o root -g root "$RULE_SRC" "$RULE_DST"
ok "installed $RULE_DST"

# polkitd watches rules.d and reloads on its own. Give it a moment, then look
# for parse errors -- polkit reports a broken rule in the journal and then
# ignores the file, which is a silent denial rather than a visible failure.
sleep 2
if journalctl -u polkit --since "30 seconds ago" --no-pager 2>/dev/null | grep -qiE 'error|failed to (load|compile)'; then
  printf '\n--- polkit journal ---\n'
  journalctl -u polkit --since "30 seconds ago" --no-pager | tail -10 | sed 's/^/  /'
  die "polkit reported an error loading the rules. The rule is NOT in effect."
fi
ok "polkit loaded the rules with no reported error"

# --- The second gate: the bot's own unit allowlist -------------------------

install -d -m 0750 -o root -g "$SVC_USER" "$CONF_DIR"
if [ ! -f "$CONF_DIR/restart-allowlist" ]; then
  printf '# Units the bot may restart. One per line.\n# Second gate; polkit is the first.\n%s\n' "$TARGET_UNIT" \
    > "$CONF_DIR/restart-allowlist"
  chmod 0640 "$CONF_DIR/restart-allowlist"; chown root:"$SVC_USER" "$CONF_DIR/restart-allowlist"
  ok "created $CONF_DIR/restart-allowlist with $TARGET_UNIT"
else
  ok "$CONF_DIR/restart-allowlist already exists -- left untouched"
fi

if [ ! -f "$CONF_DIR/privileged-allowlist" ]; then
  printf '# Telegram user ids permitted to invoke PRIVILEGED commands.\n# Must be a SUBSET of allowlist. Empty means nobody may escalate.\n' \
    > "$CONF_DIR/privileged-allowlist"
  chmod 0640 "$CONF_DIR/privileged-allowlist"; chown root:"$SVC_USER" "$CONF_DIR/privileged-allowlist"
  note "created EMPTY $CONF_DIR/privileged-allowlist -- nobody may escalate yet"
else
  ok "$CONF_DIR/privileged-allowlist already exists -- left untouched"
fi

# --- Prove it, both directions --------------------------------------------

printf '\n--- proving the grant works (as %s) ---\n' "$SVC_USER"
BEFORE="$(systemctl show -p ActiveEnterTimestamp --value "$TARGET_UNIT")"
if setpriv --reuid="$SVC_USER" --regid="$SVC_USER" --clear-groups --no-new-privs \
     /usr/bin/systemctl restart "$TARGET_UNIT" 2>&1 | sed 's/^/  /'; then
  AFTER="$(systemctl show -p ActiveEnterTimestamp --value "$TARGET_UNIT")"
  if [ "$BEFORE" != "$AFTER" ]; then
    ok "$TARGET_UNIT restarted (ActiveEnterTimestamp moved)"
  else
    die "systemctl returned success but $TARGET_UNIT did not restart"
  fi
else
  die "$SVC_USER could not restart $TARGET_UNIT -- the grant is not working"
fi

printf '\n--- proving it does NOT extend (as %s) ---\n' "$SVC_USER"
for forbidden in ssh.service tailscaled.service systemd-networkd.service; do
  if setpriv --reuid="$SVC_USER" --regid="$SVC_USER" --clear-groups --no-new-privs \
       /usr/bin/systemctl restart "$forbidden" >/dev/null 2>&1; then
    die "SECURITY FAILURE: $SVC_USER restarted $forbidden. Remove $RULE_DST now."
  fi
  ok "$SVC_USER cannot restart $forbidden"
done

cat <<'NEXT'

=== NEXT ===

  Nobody can escalate yet: the privileged allowlist is empty, which is the
  correct default. To authorise yourself:

      sudoedit /etc/homelab-telegram-bot/privileged-allowlist

  Add your numeric Telegram id -- the same one already in `allowlist`. The bot
  refuses to start if a privileged id is not also in the main allowlist.

  Then:
      sudo systemctl restart homelab-telegram-bot
      journalctl -u homelab-telegram-bot -n 5

  And from Telegram:  /help   then   /restart chrony
NEXT
