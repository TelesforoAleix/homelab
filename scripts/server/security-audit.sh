#!/usr/bin/env bash
#
# Phase 13 S1 -- read-only security audit of the node.
#
# Run on:  the Ubuntu server, as aleix
# Usage:   scp scripts/server/security-audit.sh homelab:/tmp/ && ssh homelab bash /tmp/security-audit.sh
#          or paste it into a `ssh homelab` session:  bash /tmp/security-audit.sh 2>&1 | tee /tmp/s1-audit.txt
# Phase:   13 -- Security hardening. Brief: docs/handovers/13-security-hardening.md §7.1.
#
# WHAT THIS IS
# ------------
# Every command brief §7.1 names for Stage 1, grouped so the owner runs them in one
# sitting and pastes one output back. It CHANGES NOTHING. Every block prints what it is
# about to collect before it runs (brief §6.3 / §9: no silent pause, no hidden prompt).
#
# sudo is needed for some blocks (ss -p, sshd -T, ufw, iptables, luksDump, apt). The
# script asks for the sudo password ONCE, up front, at a visible prompt, and refreshes
# the timestamp afterwards so no later block can stall waiting for it while the owner
# is typing something else -- which is how 18.2's password exposure happened.
#
# It is written to be re-run at every later phase close: blocks A and I are ADR-046's
# own three checks, block C is the socket baseline, block B the per-unit scores.

set -u   # not -e: a missing tool must print a note and keep going, not abort the audit

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
note() { printf -- '-- %s\n' "$*"; }
run()  { printf '$ %s\n' "$*"; "$@" 2>&1 || note "exit $?"; }
have() { command -v "$1" >/dev/null 2>&1; }

say "Phase 13 S1 audit -- read-only. Host, kernel, date."
run hostname
run uname -r
run date -u +%FT%TZ
run cat /etc/os-release
run systemctl --version

say "sudo: you will be asked for your password ONCE, at this visible prompt."
sudo -v || { note "sudo not granted; privileged blocks will print 'exit 1'"; }

# ---------------------------------------------------------------------------------
say "BLOCK 0 -- who is logged in (utmp is gone on systemd 259: use w, not who)"
run w -h

# ---------------------------------------------------------------------------------
say "BLOCK A -- ADR-046 check 1: LUKS keyslots are passphrase-only; crypttab key field is 'none'"
run sudo cryptsetup luksDump /dev/ubuntu-vg/data
run cat /etc/crypttab

say "BLOCK A -- ADR-046 check 2: no key-file / keyfile on root for the data volume (expect no output)"
run sudo grep -rl 'key-file\|keyfile' /etc/crypttab /etc/systemd/system /usr/local/sbin
note "ADR-046 check 3 (credential table complete) is a reading exercise; block I lists what is on root."

# ---------------------------------------------------------------------------------
say "BLOCK B -- systemd units: inventory, then a security score and the sandbox facts for each"
run systemctl list-units --all --no-pager 'homelab-*' 'wifi-*' 'ssh*' 'docker*' 'tailscaled*' 'unattended-upgrades*'
run systemctl list-unit-files --no-pager 'homelab-*' 'wifi-*'

PROPS=User,Group,DynamicUser,NoNewPrivileges,ProtectHome,ProtectSystem,ReadWritePaths,RestrictAddressFamilies,MemoryDenyWriteExecute,LoadCredential,LoadCredentialEncrypted,RequiresMountsFor,Requires,Wants,After,PartOf,ConditionPathIsMountPoint,WorkingDirectory,UMask,CapabilityBoundingSet,SystemCallFilter,OnFailure,FragmentPath,DropInPaths

# Instantiated units can be analysed live; templates need a concrete instance or --offline.
for u in homelab-telegram-bot.service homelab-watchdog.service homelab-watchdog.timer \
         homelab-workbench.service wifi-powersave-off.service homelab-model-helper.socket \
         homelab-data.target; do
  say "BLOCK B -- $u"
  run systemd-analyze security --no-pager "$u"
  run systemctl show -p "$PROPS" "$u"
done

for t in homelab-model-helper@.service homelab-notify@.service; do
  say "BLOCK B -- template $t (offline analysis of the unit file; live instance if one exists)"
  f="/etc/systemd/system/$t"
  run systemd-analyze security --no-pager --offline=true "$f"
  run systemctl show -p "$PROPS" "$t"
  inst=$(systemctl list-units --all --no-legend --plain "${t%@.service}@*" 2>/dev/null | awk '{print $1}' | head -1)
  if [ -n "${inst:-}" ]; then run systemd-analyze security --no-pager "$inst"; else note "no live instance of $t right now (expected)"; fi
  run ls -la "/etc/systemd/system/$t.d/" 2>/dev/null || note "no drop-in dir for $t"
done

say "BLOCK B -- the notifier's OnFailure wiring and the volume-dependent negative clause (standard §4)"
run systemctl show -p After,Requires,Wants,PartOf,ConditionPathIsMountPoint --value homelab-watchdog.service
run systemctl show -p After,Requires,Wants,PartOf,ConditionPathIsMountPoint --value homelab-notify@.service
run systemctl show -p RequiresMountsFor,Requires --value homelab-workbench.service

say "BLOCK B -- the whole system, for context (scores for every unit systemd knows)"
run systemd-analyze security --no-pager

# ---------------------------------------------------------------------------------
say "BLOCK C -- socket baseline: brief expects seven, each named (18.2 handover item 1)"
run sudo ss -tlnp
run sudo ss -ulnp
run ip -br addr

# ---------------------------------------------------------------------------------
say "BLOCK D -- sshd effective configuration (what sshd would conclude from the files now)"
run sudo sshd -T
run ls -la /etc/ssh/sshd_config.d/
run systemctl show ssh.service -p ActiveEnterTimestamp,StateChangeTimestamp
run systemctl is-enabled ssh.socket ssh.service
run cat /home/aleix/.ssh/authorized_keys

# ---------------------------------------------------------------------------------
say "BLOCK E -- firewall: ufw, Docker's chains, IPv6 FORWARD policy"
run sudo ufw status verbose
run sudo iptables -S DOCKER-USER
run sudo iptables -S FORWARD
run sudo ip6tables -S FORWARD
run sudo iptables -S INPUT
run sudo ip6tables -S INPUT
run sudo iptables -t nat -S DOCKER
run sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding

# ---------------------------------------------------------------------------------
say "BLOCK F -- Docker: inventory and daemon configuration"
run docker system df
run docker ps -a
run docker network ls
run cat /etc/docker/daemon.json
run docker info --format '{{.DockerRootDir}} rootless={{.SecurityOptions}}'
run systemctl is-enabled docker.service docker.socket containerd.service

# ---------------------------------------------------------------------------------
say "BLOCK G -- TPM2 availability for systemd-creds (brief §6.6, condition 1 of 3)"
run systemd-creds has-tpm2
run ls -la /dev/tpm0 /dev/tpmrm0
run systemctl show -p LoadCredential,LoadCredentialEncrypted --value homelab-telegram-bot.service
run sudo ls -la /etc/homelab-telegram-bot/

# ---------------------------------------------------------------------------------
say "BLOCK H -- unattended-upgrades and reboot policy (brief §6.10)"
run apt-config dump APT::Periodic
run systemctl is-enabled unattended-upgrades
run systemctl is-active unattended-upgrades
run grep -nE 'Automatic-Reboot|Allowed-Origins|"\$\{distro_id\}' /etc/apt/apt.conf.d/50unattended-upgrades
run grep -nvE '^\s*(//|$)' /etc/apt/apt.conf.d/50unattended-upgrades
run cat /etc/apt/apt.conf.d/20auto-upgrades
run ls /var/run/reboot-required /var/run/reboot-required.pkgs

# ---------------------------------------------------------------------------------
say "BLOCK I -- credentials and keys on root (ADR-046 check 3 material; GitHub key hygiene, §6.2)"
run ls -la /home/aleix/.ssh
run stat -c '%a %U:%G %n' /home/aleix/.ssh/id_ed25519_github /home/aleix/.ssh/config /home/aleix/.ssh/authorized_keys
run grep -c '^Host github.com' /home/aleix/.ssh/config
run grep -nvE '^\s*(#|$)' /home/aleix/.ssh/config
run ssh -G github.com
note "(only the identity / identitiesonly lines matter; the rest is defaults)"
run ssh-keygen -lf /home/aleix/.ssh/id_ed25519_github.pub
run ls -la /home/aleix/.claude/.credentials.json /home/aleix/.codex/auth.json
run sudo ls -la /etc/netplan/
run sudo ls -la /var/lib/tailscale/
run sudo find /etc /root /home /var/lib/tailscale /usr/local -xdev -type f \( -name '*.pem' -o -name '*.key' -o -name 'id_*' -o -name '*token*' -o -name '*secret*' -o -name '*.credentials*' -o -name 'auth.json' \) 2>/dev/null
note "(anything above not in ADR-046's table is a finding)"

# ---------------------------------------------------------------------------------
say "BLOCK J -- accounts, groups, sudoers, console"
run id aleix
run id homelab-bot
run getent group docker sudo adm
run awk -F: '$3==0 || $3>=1000 {print $1":"$3":"$7}' /etc/passwd
run sudo ls -la /etc/sudoers.d/
run sudo grep -rnvE '^\s*(#|$)' /etc/sudoers.d/
run ls -la /etc/profile.d/
run grep -rn TMOUT /etc/profile /etc/profile.d/ /etc/bash.bashrc 2>/dev/null
run systemctl is-active getty@tty1
run loginctl list-sessions --no-pager

# ---------------------------------------------------------------------------------
say "BLOCK K -- firmware: Secure Boot state, TPM, boot entries (brief §6.5 -- record, do not change)"
if have mokutil; then run mokutil --sb-state; else note "mokutil not installed; alternative:"; run bootctl status --no-pager; fi
run ls /sys/firmware/efi
run sudo dmesg -t | grep -i 'secure boot' || note "no 'secure boot' line in dmesg"
run cat /sys/class/tpm/tpm0/tpm_version_major
run sudo efibootmgr

# ---------------------------------------------------------------------------------
say "BLOCK L -- Tailscale from the node's side (ACL is read from the MacBook)"
run tailscale status --self --peers=false
run tailscale status --json --peers=false
note "(KeyExpiry / Expired fields: expiry disabled per ADR-019 shows as no expiry)"
run systemctl show -p ExecStart --value tailscaled.service
run cat /etc/default/tailscaled

# ---------------------------------------------------------------------------------
say "BLOCK M -- 18.2 closing check, as the S1 baseline"
run systemctl --failed --no-pager
run systemctl is-system-running
run systemctl is-active homelab-workbench homelab-telegram-bot homelab-watchdog.timer homelab-model-helper.socket
run findmnt /srv/homelab
run sudo vgs
run sudo lvs

say "DONE. Nothing was changed. Paste the whole output back."
