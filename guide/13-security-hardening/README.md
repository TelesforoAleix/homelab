# Phase 13 — Security hardening

> **Work in progress — S1 (audit) complete, nothing on the node changed yet.** This file currently
> holds the S1 observations and the debt table with *proposed* outcomes. Outcomes become final in
> S2–S4; every row will end with OBSERVED evidence or an explicit PREDICTED tag.

Brief: [`docs/handovers/13-security-hardening.md`](../../docs/handovers/13-security-hardening.md).
Audit runbooks: [`scripts/server/security-audit.sh`](../../scripts/server/security-audit.sh) (node,
read-only) and [`scripts/macos/security-audit-macbook.sh`](../../scripts/macos/security-audit-macbook.sh).

## S1 — what was observed (2026-09-12, node at 20:48 UTC; MacBook the same evening)

Ubuntu 26.04.1 LTS, kernel 7.0.0-31-generic, systemd 259.5, Tailscale 1.102.3. Node rebooted at
19:41 UTC that day (18.2's power cut); `systemctl --failed` empty, `is-system-running` → `running`,
Workbench / bot / watchdog timer / model-helper socket all `active`, volume mounted, VG free 43.42 GiB.

### ADR-046's three checks

| # | Check | OBSERVED | Verdict |
|---|---|---|---|
| 1 | `luksDump`: passphrase slots only; crypttab key `none` | Keyslots 0 and 1, both `luks2` argon2id; `Tokens:` empty; `homelab-data /dev/ubuntu-vg/data none luks,noauto,discard` | **PASS** |
| 2 | `grep -rl 'key-file\|keyfile' /etc/crypttab /etc/systemd/system /usr/local/sbin` → nothing | One hit: `/usr/local/sbin/homelab-watchdog.sh` line 71 — a **comment** ("no keyfile path is …") | **PASS in substance, check text wrong.** The ADR's grep needs to skip comments. Amend in S3 |
| 3 | Every credential on root is in the table | `find` over `/etc /root /home /var/lib/tailscale /usr/local`: the five table rows plus `~aleix/.ssh/id_ed25519_github` (0600). Everything else found is public material (fwupd CA certs, `.pub`, `known_hosts`, VS Code server tokenizer files) | **FAIL as written — sixth row missing**, exactly as the brief predicted. Amend in S3 |

### The units — `systemd-analyze security`

Only `.service` units can be scored; the timer, socket and target refuse (`not a service unit`).
Six services, all scored for the first time except the Workbench and bot:

| Unit | User | Score | Notes |
|---|---|---|---|
| `homelab-telegram-bot.service` | `homelab-bot` | **1.3 OK** | `ProtectHome=yes`, `ProtectSystem=strict`, `LoadCredential=`, allow-list syscall filter, MDWE. Residual: `AF_UNIX` allowed (0.1), no `IPAddressDeny` (0.2) |
| `homelab-watchdog.service` | `homelab-bot` | **1.3 OK** | Same set. Negative clause holds: `After=` has no `srv-homelab`, `homelab-data`, `workbench` |
| `homelab-notify@bot.service` (live instance) | `homelab-bot` | **1.3 OK** | Template scored offline 1.3 as well; no drop-in dir (correct — `OnFailure=` drop-ins live on the *callers*) |
| `homelab-workbench.service` | `aleix` | **1.3 OK** | `ProtectHome=yes`, `ProtectSystem=strict`, `ReadWritePaths=/srv/homelab`, `RestrictAddressFamilies=AF_INET AF_INET6` (no `AF_UNIX`), `NoNewPrivileges=yes`, `UMask=0027`. `RequiresMountsFor=` empty; `Requires=` without `srv-homelab.mount` |
| `homelab-model-helper@.service` (template, offline) | `aleix` | **3.9 OK** — *above the 2.0 threshold* | No syscall filter, no `SystemCallArchitectures`, no `MemoryDenyWriteExecute`, no `RestrictNamespaces`, **`ProtectHome` unset with `ReadWritePaths=/home/aleix`**. Zero `# WHY` comments. See open decision 6.12 |
| `wifi-powersave-off.service` | **root** | **9.6 UNSAFE** | Bare `Type=oneshot` running `iw dev wlp1s0 set power_save off` with full capabilities. See open decision 6.13 |

For scale: vendor units on the same node score `ssh.service` 9.6, `tailscaled` 9.6, `docker` 9.6,
`unattended-upgrades` 9.6, `polkit` 1.2. The score measures sandbox directives, not risk; a root
daemon that must configure the network will always score high. The baseline (§6.3) applies the
threshold to *this project's* units only.

### Sockets — the seven, re-measured

`sudo ss -tlnp` → exactly the 18.2 list: `sshd` `0.0.0.0:22` + `[::]:22`; `python3` (Workbench)
`127.0.0.1:8765`; `tailscaled` `100.71.62.71:36121` + `[fd7a:…:3ed6]:57273`; `systemd-resolve`
`127.0.0.54:53` + `127.0.0.53%lo:53`. **Seven, each named. No eighth row.** UDP for the record:
`tailscaled` `41641` on `0.0.0.0`/`[::]` (the ufw-allowed WireGuard port), `chronyd` `323` loopback
only, `systemd-networkd` DHCP client on `wlp1s0`, resolved's two. `docker0` is `DOWN` with `172.17.0.1/16`.

### sshd (`sshd -T`)

`passwordauthentication no` · `kbdinteractiveauthentication no` · `permitrootlogin no` ·
`authenticationmethods publickey` · `pubkeyauthentication yes`. **Not** as the brief wants:
`x11forwarding yes`, `maxauthtries 6`, no `allowusers`, `allowagentforwarding yes`.
`allowtcpforwarding yes` is **required** (the Workbench tunnel). `listenaddress` `0.0.0.0`/`[::]`
(left alone by decision). `ssh.socket` enabled, `ssh.service` disabled — socket activation, so
`reload` semantics per the standard §5. Two drop-ins in `sshd_config.d/`: `10-homelab-hardening.conf`
(Phase 03) and `50-cloud-init.conf`. `authorized_keys`: one line, the MacBook key, comment `homelab`.

### Firewall

`ufw`: active, `deny (incoming), allow (outgoing), deny (routed)`; allows `Anywhere on tailscale0`
and `41641/udp on wlp1s0`, v4 and v6. `iptables -S FORWARD` **and** `ip6tables -S FORWARD` both
`-P FORWARD DROP` — **the IPv6 asymmetry recorded in project-state is already gone** (ufw's
`deny (routed)` set both policies on 2026-09-10). Chain order in `FORWARD`: `ts-forward` →
`DOCKER-USER` (exists, **empty**) → `DOCKER-FORWARD` → ufw chains. `INPUT`: `ts-input` → ufw chains.
`nat DOCKER` chain empty (no published ports). `net.ipv4.ip_forward=1` (Docker), `ipv6 forwarding=0`.
Because `DOCKER-FORWARD` accepts before ufw's forward chains are consulted, a published port
**would** still bypass ufw — the `DOCKER-USER` rule in §6.4 is still the right control; the IPv6
half is already done.

### Docker

`docker system df`: 0 images, 0 containers, 0 volumes, 0 build cache. `docker ps -a` empty. Root
dir `/var/lib/docker`; security options `apparmor, seccomp builtin, cgroupns`; no userns-remap.
`daemon.json` is the log bounds only. `docker.service`, `docker.socket`, `containerd` all enabled.

### TPM2 / firmware / console

`systemd-analyze has-tpm2` (the command `systemd-creds has-tpm2` now redirects to) → **`yes`**, all
of `+firmware +driver +system +subsystem +libraries`. `/dev/tpmrm0` `tss:tss`. TPM major version 2.
**Secure Boot enabled**, kernel in EFI lockdown, Canonical's signing certs loaded. `efibootmgr`:
`BootOrder 0001 (Ubuntu shim), 0007 (UEFI IPv6 PXE, I219-V), 0006 (UEFI IPv4 PXE), 0004 (USB),
0005 (CD/DVD), 0000 (Windows Boot Manager — stale)`; timeout 2 s. No `TMOUT` anywhere in
`/etc/profile*`. `getty@tty1` active.

### unattended-upgrades

Enabled and active. `APT::Periodic::Update-Package-Lists 1`, `Unattended-Upgrade 1`,
`Download-Upgradeable-Packages 0`, `AutocleanInterval 0`. `Allowed-Origins`: the release pocket,
`-security`, ESM apps/infra security; `-updates`, `-proposed`, `-backports` commented out.
`Automatic-Reboot` **commented out → default `false`**. No `/var/run/reboot-required`.

### Credentials and keys

`~aleix/.ssh/id_ed25519_github` `600 aleix:aleix`; `config` `600`, one `Host github.com` block
(`User git`, `IdentityFile`, `IdentitiesOnly yes`) — the 18.2 duplicate is gone; `ssh -G github.com`
selects it with `identitiesonly yes`. Public key comment `homelab node — 2026-09-12`. OAuth files
`0600`. Bot token `/etc/homelab-telegram-bot/token` `root:root 0600`, 47 bytes; the three allowlists
`root:homelab-bot 0640`. `/etc/netplan/*` `0600`; `/var/lib/tailscale` `0700`.
**MacBook:** `gh api user/keys` — **not yet observed** (`gh` lacks `admin:public_key`); deploy keys on
`oncla`, `factory-ops`, `brain`: none.

### Accounts

`aleix`: `adm cdrom sudo dip plugdev users lxd docker`. `homelab-bot` uid 999, own group only. Human
accounts with a shell: `root`, `aleix`. `/etc/sudoers.d/` holds only the README. Two logind sessions
(the owner's SSH). **`lxd` membership** is an installer default and root-equivalent like `docker` —
see open decision 6.14.

### Tailscale

Two devices on the tailnet (MacBook `100.69.244.33`, node `100.71.62.71`), one user. **Policy file
is the stock default:** `{"src":["*"],"dst":["*"],"ip":["*"]}` plus the default Tailscale-SSH
`check` rule (inert: `tailscaled` runs with `FLAGS=""`, no `--ssh`). Key expiry state is not in the
CLI's self JSON; PREDICTED disabled per ADR-019 until read in the admin console.

### The two aliases (MacBook)

With `homelab-workbench` held open (`-N`), `ssh -o BatchMode=yes homelab true` → 0 and the
Workbench answered `HTTP 200` through the tunnel. `ssh -G`: `homelab` has no `localforward`,
`exitonforwardfailure no`; `homelab-workbench` has `localforward [127.0.0.1]:8765`,
`exitonforwardfailure yes`. One client key, in the agent. `age v1.3.2` present.

## The debt table — proposed outcomes (S1; to be finalised)

Sources: **18.2** = 18.2 handover *Phase 13 by name* items 1–7; **18.1** = 18.1 handover §Phase 13;
**18** = Phase 18 handover open items 4–5; **RM** = `ROADMAP.md` Phase 13; **PS** =
`project-state.md` §Security debt. Brief section in the last column.

| # | Item | Source | S1 OBSERVED state | Proposed outcome | § |
|---|---|---|---|---|---|
| 1 | Socket baseline: seven, each named | 18.2 #1 | Seven, identical to the list | **Close** — re-measured; baseline written into the standard | 4.5 |
| 2 | GitHub key on the node, passphrase-less, account-level | 18.2 #2 | `0600`, one `Host` block, `IdentitiesOnly`; not in ADR-046's table; `gh` listing pending | **Narrow (6.2b):** keep, add table row + revocation path, audit by title from the MacBook; record 6.2(a) as Phase 14's change if it picks unattended push | 6.2 |
| 3 | Workbench as `aleix` vs dedicated account | 18.2 #3 | Sandbox exactly as believed: `ProtectHome=yes`, no `AF_UNIX`, `NoNewPrivileges`, RW only `/srv/homelab`; 1.3 | **Decline with ADR-047** — boundary is the sandbox; triggers recorded | 6.1 |
| 4 | Docker `data-root` on root | 18.2 #4 | `/var/lib/docker`, inventory zero, `docker0` down | **Decline (keep)** — trigger has not fired; recorded | 6.4 |
| 5 | BIOS password | 18 #5, 18.1, 18.2 #5 | None; Secure Boot on; PXE ×2, USB, CD entries in boot order; stale Windows entry | **Close (S3, at the box):** supervisor password, boot order locked to disk, network boot off; Secure Boot left on | 6.5 |
| 6 | Console idle timeout | 18.1, 18.2 #5 | No `TMOUT` | **Close (S2):** `TMOUT=900` readonly, tty-guarded, `/etc/profile.d/` | 6.5 |
| 7 | `systemd-creds` TPM2 binding of the bot token | 18.1, 18.2 #5, ADR-046 | `has-tpm2` yes; token `root:root 0600`; Secure Boot on | **Evaluate in S3** — condition 1 holds; 2 and 3 (rollback, real reboot) decide it. Both bot and notifier or neither | 6.6 |
| 8 | ADR-046 revisit triggers as a checklist | 18.1, 18.2 #5 | Checks 1 PASS, 2 PASS-with-defect, 3 FAIL (sixth row) | **Close (S3):** amend ADR — row, check-2 grep, trigger 3 fired, dated re-run | 4.3 |
| 9 | Two SSH aliases keep working | 18.2 #6 | Both work concurrently, tunnel 200 | **Close** — test repeated after every S2 change | §5 |
| 10 | Password exposure → rule | 18.2 #7 | Not yet a rule | **Close (S4):** the no-silent-pause rule in the baseline; S1's own runbook applied it | 6.3 |
| 11 | Single SSH client key | RM, PS | One key in `authorized_keys`, one on the MacBook | **Close (S2):** second Ed25519 pair, `age`-encrypted on the card | 6.8 |
| 12 | Node key expiry disabled | RM, PS | PREDICTED disabled (console read pending) | **Decline (keep disabled)**, revisit if the machine leaves the home | 6.7 |
| 13 | Tailscale SSH declined; ACLs | RM | ACL is allow-all; TS-SSH inert | **Take ACLs (S2, last)**; TS-SSH stays declined; drop the inert `ssh` block from the policy | 6.7 |
| 14 | Firewall + `fail2ban` | RM, PS | ufw done 09-10; `fail2ban` absent; no passwords accepted | **Close firewall (DOCKER-USER); decline `fail2ban`** with reason | 6.4, 6.9 |
| 15 | Docker publishes before ufw `INPUT` | PS | `DOCKER-USER` exists, empty; `DOCKER-FORWARD` before ufw | **Close (S2):** `DOCKER-USER` drop for non-`tailscale0`/non-`lo` via `apply-firewall.sh` | 6.4 |
| 16 | IPv4/IPv6 FORWARD asymmetric | PS | **Both already `DROP`** | **Close — already closed 2026-09-10 by ufw**; project-state corrected; §8 row 6 becomes a re-proof | 6.4 |
| 17 | Rootful Docker, no userns-remap | PS | No container; rootful | **Decline** — nothing to protect; the first phase that ships a container decides (likely 23.x or 15.x) | 6.4 |
| 18 | Docker consumes the root LV | PS | 0 B used | **Narrow:** record; bounded logs already; no action | 6.4 |
| 19 | `aleix` in `docker` | PS, ADR-022 | True | **Decline (accepted, ADR-022)** — restated in the baseline: never a service account | §5 |
| 20 | OAuth credentials in `/home/aleix` | PS, ADR-046 | `0600`; readable by the model helper (by design) | **Decline (ADR-046 §2)** — stays; deferred to 23.3. New: also readable next to the GitHub key → 6.12 | 6.11 |
| 21 | Root not encrypted + cleartext Wi-Fi passphrase | PS | Unchanged; ADR-046 accepted | **Decline (ADR-046)** — out of scope by brief §1 | §1 |
| 22 | sshd audit | brief | `x11forwarding yes`, `maxauthtries 6`, no `AllowUsers`, agent forwarding on | **Narrow (S2):** `AllowUsers aleix`, `MaxAuthTries 3`, `X11Forwarding no`, `AllowAgentForwarding no`; TCP forwarding stays | 6.9 |
| 23 | unattended-upgrades / reboot | brief | Security pockets; `Automatic-Reboot` default false | **Close (record):** no change; optionally make `false` explicit for a reader | 6.10 |
| 24 | Scores for all units | brief 4.2 | Recorded above; two above threshold | **Close (S2):** 6.12 and 6.13 decide the two | 4.2 |

## New open decisions found in S1 (not in brief §6)

**6.12 The model helper can read the GitHub push key.** `homelab-model-helper@.service` runs as
`aleix` with `ReadWritePaths=/home/aleix` and no `ProtectHome=`; since 18.2 that home holds a
passphrase-less key with push to three private repositories. The helper is reachable by anyone
who can open `/run/homelab-model-helper.sock` (`SocketUser=aleix`), and its job is to run the two
AI CLIs on untrusted prompts. Score 3.9, no `# WHY`. **Proposal:** `InaccessiblePaths=-/home/aleix/.ssh`
(it needs `~/.claude` and `~/.codex`, not `~/.ssh`); add `SystemCallArchitectures=native`,
`RestrictNamespaces=yes`, and try the bot's syscall allow-list; **not** `MemoryDenyWriteExecute=`
without a test (the CLIs are Node.js with a JIT). Waive the remaining gap with `# WHY` comments.
Verify with `verify-ai-cli-access.sh`. Not lockout-class.

**6.13 `wifi-powersave-off.service` at 9.6 as root.** It needs `CAP_NET_ADMIN` and `AF_NETLINK`, and
nothing else. **Proposal:** `CapabilityBoundingSet=CAP_NET_ADMIN`, `AmbientCapabilities=CAP_NET_ADMIN`
with `DynamicUser=yes` *or* keep root with `NoNewPrivileges`, `ProtectSystem=strict`,
`ProtectHome=yes`, `PrivateTmp`, `RestrictAddressFamilies=AF_NETLINK`, `SystemCallArchitectures=native`.
It is `WantedBy=multi-user.target` → **boot-class** under the standard (a failing oneshot dirties
`systemctl --failed`, though the link stays up with power-save on). Test with `restart`, then the
next real reboot in S3 proves it.

**6.14 `aleix` is in `lxd`.** Root-equivalent (the daemon runs as root and members control it),
installer default, not decided anywhere. Is LXD installed (`snap list lxd`)? If not: `deluser aleix lxd`
— an admin-account change, so lockout-class in the standard's table, though a group removal cannot
break login. If yes: same treatment as `docker` under ADR-022, stated.

**6.15 EFI boot order has two PXE entries ahead of USB.** `eno1` has no cable, so PXE cannot fire
today; but the BIOS step in 6.5 should disable network boot as well as lock the order, and the stale
`Windows Boot Manager` entry can go (`efibootmgr -b 0000 -B`, or leave — cosmetic). Folded into 6.5's
checklist for the orchestrator to confirm.

**6.16 §8 row 8 (ACL negative test) has no second device.** The tailnet is two devices. Either a
phone joins for one test or the row is PREDICTED and named as debt in the handover.

**6.17 ADR-046 check 2 has a false positive.** Its grep matches its own documentation in the watchdog.
Amend the check to `grep -rhv '^\s*#' … | grep -l …` or narrow the pattern to `key-file=|keyfile=`. S3.

## Corrections to the brief made in S1

- §2, §6.4, §8 row 6: IPv6 `FORWARD` was **already `DROP`** (OBSERVED `ip6tables -S FORWARD` →
  `-P FORWARD DROP`). ufw's `deny (routed)` did it on 2026-09-10; project-state's "asymmetric" bullet
  was stale. The IPv6 half of 6.4 is a re-proof, not a change.
- §4.2 / §8 row 1: "every unit" means every **service** unit — six; the timer, socket and target
  cannot be scored (`systemd-analyze security` refuses non-services).

## Security notes

- The S1 runbook asked for the sudo password once, at a labelled prompt, before any output
  scrolled. No exposure. `systemctl show` on template names (`homelab-notify@.service`) fails — the
  script now uses instances.
- Nothing was changed on the node or the MacBook in S1.
