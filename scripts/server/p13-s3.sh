#!/usr/bin/env bash
#
# Phase 13 S3 -- node-side steps: the TPM2-sealed bot token (brief §6.6).
#
# Run on:  the Ubuntu server, as root
# Usage:   sudo bash /tmp/p13/p13-s3.sh <creds-check|creds-encrypt|creds-shred|creds-undo|postboot>
# Phase:   13 -- Security hardening. Runbook: guide/13-security-hardening/s3-runbook.md
#
# Every subcommand prints what it is about to do before it does it. Nothing
# waits for input and nothing here ever prints the token.
#
#   creds-check    read-only: TPM2 present, the three units, the plaintext file
#   creds-encrypt  seal the token -> token.cred; install the three drop-ins;
#                  daemon-reload; restart the bot. The PLAINTEXT STAYS until
#                  creds-shred -- rollback is a file removal until then.
#   creds-shred    after the reboot proof only: remove the plaintext token.
#   creds-undo     rollback: drop-ins removed, plaintext restored (from the
#                  sealed copy if this TPM still unseals it -- the usual case --
#                  otherwise from the password manager, by editor), restart.
#   postboot       the checks after a reboot or power-cycle, in one go.

set -euo pipefail
SRC=/tmp/p13
DIR=/etc/homelab-telegram-bot
PLAIN="$DIR/token"
CRED="$DIR/token.cred"
UNITS="homelab-telegram-bot.service homelab-notify@.service homelab-watchdog.service"
say() { printf '  %s\n' "$*"; }
die() { printf '\n  ERROR: %s\n\n' "$*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || die "run with sudo"

case "${1:-}" in

creds-check)
  say "read-only: is condition 1 (TPM2) still true, and what loads the token today"
  systemd-analyze has-tpm2 | sed 's/^/    /'
  for u in $UNITS; do printf '    %-32s LoadCredential=%s  Encrypted=%s\n' "$u" \
    "$(systemctl show -p LoadCredential --value "$u" 2>/dev/null || echo '?')" \
    "$(systemctl show -p LoadCredentialEncrypted --value "$u" 2>/dev/null || echo '?')"; done
  ls -la "$DIR" | sed 's/^/    /'
  say "the token is $(wc -c < "$PLAIN") bytes; it must ALSO be in the password manager before creds-encrypt" ;;

creds-encrypt)
  [ -s "$PLAIN" ] || die "$PLAIN missing or empty"
  for u in $UNITS; do [ -f "$SRC/${u}.d/credential.conf" ] || die "copy config/systemd/${u}.d/credential.conf to $SRC/${u}.d/ first"; done
  say "about to: seal $PLAIN to the TPM2 (no PCRs) as $CRED; install credential.conf for: $UNITS; daemon-reload; restart the bot"
  say "the plaintext is NOT removed by this step"
  systemd-creds encrypt --name=bot-token --with-key=tpm2 --tpm2-pcrs= "$PLAIN" "$CRED"
  chown root:root "$CRED"; chmod 0600 "$CRED"
  say "sealed: $(stat -c '%a %U:%G %s bytes' "$CRED")"
  say "round-trip on this machine (decrypt to memory, compare, print nothing):"
  if systemd-creds decrypt --name=bot-token "$CRED" - | cmp -s - "$PLAIN"; then say "  ok: unseals to the same bytes"; else die "unsealed bytes differ -- nothing installed"; fi
  for u in $UNITS; do
    install -d -o root -g root -m 0755 "/etc/systemd/system/${u}.d"
    install -o root -g root -m 0644 "$SRC/${u}.d/credential.conf" "/etc/systemd/system/${u}.d/credential.conf"
    say "installed /etc/systemd/system/${u}.d/credential.conf"
  done
  systemctl daemon-reload
  for u in $UNITS; do printf '    %-32s LoadCredential=[%s]  Encrypted=%s\n' "$u" \
    "$(systemctl show -p LoadCredential --value "$u")" "$(systemctl show -p LoadCredentialEncrypted --value "$u" | sed 's/:.*//')"; done
  say "restart the bot (the notifier and watchdog are on-demand; they pick the drop-in up when next started)"
  systemctl restart homelab-telegram-bot
  sleep 3
  say "bot: $(systemctl is-active homelab-telegram-bot)"
  journalctl -u homelab-telegram-bot -n 5 --no-pager | sed 's/^/    /'
  say "now send /status to the bot. Then the runbook's real reboot is condition 3." ;;

creds-shred)
  [ -f "$CRED" ] || die "no $CRED -- refusing to remove the only copy"
  systemctl is-active --quiet homelab-telegram-bot || die "bot not active -- do not remove the plaintext now"
  grep -q token.cred "/etc/systemd/system/homelab-telegram-bot.service.d/credential.conf" 2>/dev/null || die "drop-in not installed"
  say "about to: remove the plaintext $PLAIN (the sealed copy and the password manager remain)"
  shred -u "$PLAIN" 2>/dev/null || rm -f "$PLAIN"
  ls -la "$DIR" | sed 's/^/    /'
  say "done. ADR-046's table row for the token now reads: sealed, TPM2, plaintext in the password manager only" ;;

creds-undo)
  say "about to: remove the three drop-ins, restore the plaintext token, daemon-reload, restart the bot"
  for u in $UNITS; do rm -f "/etc/systemd/system/${u}.d/credential.conf"; rmdir "/etc/systemd/system/${u}.d" 2>/dev/null || true; done
  if [ ! -s "$PLAIN" ]; then
    if [ -f "$CRED" ] && systemd-creds decrypt --name=bot-token "$CRED" - > "$PLAIN.tmp" 2>/dev/null; then
      install -o root -g root -m 0600 "$PLAIN.tmp" "$PLAIN"; rm -f "$PLAIN.tmp"; say "plaintext restored from the sealed copy (this TPM still unseals it)"
    else
      rm -f "$PLAIN.tmp"
      say "the TPM cannot unseal the copy. Restore the token from the password manager with an editor:"
      say "    sudo nano $PLAIN     (one line, no trailing newline needed)  then: sudo chmod 0600 $PLAIN"
      say "then re-run: sudo bash $0 creds-undo"
      systemctl daemon-reload; exit 1
    fi
  fi
  systemctl daemon-reload
  systemctl restart homelab-telegram-bot; sleep 3
  say "bot: $(systemctl is-active homelab-telegram-bot)   LoadCredential=$(systemctl show -p LoadCredential --value homelab-telegram-bot | sed 's/:.*//')" ;;

postboot)
  say "post-boot checks (run right after /status answered; then again after unlock)"
  printf '    uptime: '; uptime -p
  printf '    failed: '; systemctl --failed --no-legend | wc -l
  printf '    system: '; systemctl is-system-running || true
  printf '    volume: '; findmnt -n /srv/homelab >/dev/null && echo mounted || echo locked
  for u in homelab-telegram-bot wifi-powersave-off homelab-watchdog.timer homelab-model-helper.socket homelab-workbench; do printf '    %-28s %s\n' "$u" "$(systemctl is-active "$u")"; done
  printf '    wifi:   '; iw dev wlp1s0 get power_save
  printf '    creds:  bot Encrypted=%s\n' "$(systemctl show -p LoadCredentialEncrypted --value homelab-telegram-bot | sed 's/:.*//')"
  printf '    watchdog last run: '; journalctl -u homelab-watchdog -n 1 --no-pager -o cat || true
  printf '    boot order: '; efibootmgr | grep BootOrder ;;

*) die "usage: $0 <creds-check|creds-encrypt|creds-shred|creds-undo|postboot>" ;;
esac
