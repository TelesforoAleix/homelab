# Service Security Baseline

**Status:** Standard. Written by Phase 13 under [ADR-043](../decisions/ADR-043-cross-cutting-contracts.md)
as the enforcement of ADR-038 (loopback, every socket accounted for), ADR-046 (credentials on
root) and ADR-022 (accounts). Not itself an ADR: those decisions already exist; this is what a unit
has to look like to comply with them.
**Applies to:** every systemd unit this project installs on the node, from Phase 15.0's first unit
onward, and to every runbook an owner runs with `sudo`. Existing units were brought to it in Phase
13 or carry a written waiver.

The node runs a handful of small services and one sudo-capable human. A new unit is measured
against this page on the day it is written, not at the next hardening phase. Where a rule cannot be
met, the unit says so **in the unit file**, as a `# WHY` comment next to the directive it waives —
the repository's existing idiom — so the waiver travels with the thing it excuses.

## 1. The baseline table — what "normal" scores on this node

`systemd-analyze security <unit>` measured on Ubuntu 26.04.1, systemd 259.5, 2026-09-12, after
Phase 13 S2. Only `.service` units can be scored; timers, sockets and targets refuse.

| Unit | Runs as | Score | Waivers carried in the unit |
|---|---|---|---|
| `homelab-telegram-bot.service` | `homelab-bot` | **1.3** | none needed |
| `homelab-watchdog.service` | `homelab-bot` | **1.3** | none needed |
| `homelab-notify@.service` | `homelab-bot` | **1.3** | none needed |
| `homelab-workbench.service` | `aleix` | **1.3** | `User=aleix` (writes must stay commit-able by the owner — ADR-047) |
| `homelab-model-helper@.service` | `aleix` | **3.8** | `User=aleix` + `ProtectHome` unset (its purpose is the OAuth files); `MemoryDenyWriteExecute` (Node JIT); `RestrictNamespaces` (codex's own sandbox); `SystemCallFilter` (SIGSYS on the Claude CLI, OBSERVED) |
| `wifi-powersave-off.service` | root | **5.1** | root + `CAP_NET_ADMIN` (netlink); no syscall filter on a boot oneshot |

For scale, the vendor units on the same node: `ssh.service` 9.6, `tailscaled` 9.6, `docker` 9.6,
`polkit` 1.2. The score counts sandbox directives; it is not a risk score, and a root daemon that
must configure the network will always be high. The threshold below applies to **this project's
units**, not to the distribution's.

## 2. The threshold

**A new unit scores ≤ 2.0, or every finding above that is waived with a `# WHY`.** The hardening
set that reaches 1.3 for a Python service is proved on this node (Python 3.14.4) and is in
`config/systemd/homelab-workbench.service` — read it as the reference, but **copy the contract, not
the file** (see §5 on volume-dependent units). In outline:

```ini
User=<its own account>          # §3
NoNewPrivileges=yes
CapabilityBoundingSet=
AmbientCapabilities=
UMask=0077                      # 0027 if another account must read what it writes, say why
ProtectSystem=strict
ReadWritePaths=<the one path it writes>
ProtectHome=yes                 # waived only for the unit whose purpose is a home directory
PrivateTmp=yes
PrivateDevices=yes
ProtectProc=invisible
ProtectKernelTunables=yes  ProtectKernelModules=yes  ProtectKernelLogs=yes
ProtectControlGroups=yes   ProtectClock=yes          ProtectHostname=yes
RestrictRealtime=yes       RestrictSUIDSGID=yes      LockPersonality=yes
RestrictNamespaces=yes
MemoryDenyWriteExecute=yes      # waived for anything with a JIT (Node, Java, browsers)
RestrictAddressFamilies=AF_INET AF_INET6   # add AF_UNIX only if it opens a local socket, and say which
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources @obsolete @mount @swap @reboot @raw-io @debug @module @cpu-emulation
```

Two measured limits of that set, so nobody re-derives them: `SystemCallFilter=@system-service` **kills
the Claude CLI with SIGSYS** (`exit=-31`, 2026-09-12) — do not put it on anything that spawns the
AI CLIs; and `RestrictAddressFamilies=AF_NETLINK` alone starves `if_nametoindex()`, so a unit that
runs `iw`/`ip` needs `AF_UNIX AF_INET` beside it.

Record the score in the phase's guide when the unit lands, and again whenever the unit changes.

## 3. The account rule

**One account per trust boundary. Never `aleix` for a service unless the unit's `# WHY` says why.**
`aleix` is the sudo-capable administrator and a member of `docker` (root-equivalent, ADR-022); a
service running as `aleix` inherits the ability to read the OAuth credentials, the GitHub key and
everything the owner can read. Two units are allowed to, each with a written reason: the model
helper (it *exists* to reach the OAuth files) and the Workbench (its writes into `projects/*/ops/`
must be commit-able by the owner without ownership repair — ADR-047). Both compensate with the
sandbox: the helper cannot see `~/.ssh` (`InaccessiblePaths`), the Workbench cannot see any home
directory (`ProtectHome=yes`) and cannot open a local socket (no `AF_UNIX`).

A service account is a system account (`--system`, no shell, own group), is **never** added to
`docker`, `sudo`, `adm` or `lxd`, and gets its files through `LoadCredential=` and `ReadWritePaths=`,
not through group membership on the admin's directories.

## 4. The credential rule

**Every secret reaches a unit through `LoadCredential=` (or `LoadCredentialEncrypted=`), never
`Environment=`, never a world- or group-readable file, never a command-line argument.** The file
on disk is `root:root 0600` under `/etc/<service>/`; the unit reads `$CREDENTIALS_DIRECTORY/<name>`.
Environment variables leak into `systemctl show`, crash dumps and child processes; credentials do
not.

Every credential on root is a row in ADR-046's table **with its revocation path**, added in the
same commit as the unit that loads it. A credential that is not revocable from the MacBook in
minutes, or that could open the data volume, is not covered by ADR-046's acceptance and needs its
own decision before it lands (ADR-046 §3, revisit trigger 2).

Phase 15.0's paid API key follows the bot token's pattern exactly: `/etc/homelab-<service>/<name>`,
`root:root 0600`, `LoadCredential=`, a table row naming the provider console where it is revoked.
Whether it is additionally sealed with `systemd-creds` (`--with-key=tpm2 --tpm2-pcrs=""`, the Phase
13 pattern) is the phase's choice; the sealing narrows the pulled-disk threat only and adds a TPM
dependency — read ADR-046's amendment before choosing.

## 5. The socket rule

**Loopback binding, refused in code, and a socket-table row — for every listener.** ADR-038 §2:
bind `127.0.0.1` (or a UNIX socket with an owner and mode), refuse anything else in the code
itself, reach it from the MacBook through `ssh -L` on the `homelab-workbench` alias or a second
alias — never on `homelab`. The measured baseline is **seven TCP listeners** (`sshd` ×2,
`systemd-resolved` ×2, `tailscaled` ×2, the Workbench on `127.0.0.1:8765`), re-verified with
`sudo ss -tlnp` at every phase close; an eighth row is a finding until it is named in
`docs/architecture/current-architecture.md`'s socket table.

A listener that must be reachable from another tailnet device (not through SSH) additionally gets
its port added to `config/tailscale/acl.hujson` in the same commit — the ACL is a device-level
boundary in front of sshd and allows **tcp/22 only** today.

**If the unit needs the data volume**, it carries the four directives of
[`volume-dependent-services.md`](volume-dependent-services.md) and none of the paths on the volume
as its *place*; if it *observes* the volume, it carries none of them. That standard, not this one,
decides when a unit runs.

## 6. The firewall rule

Two things every phase that touches the firewall must know:

- **`scripts/server/apply-firewall.sh` resets ufw** (`ufw --force reset`), which restores
  `/etc/ufw/*.rules` to the package defaults and **erases the `DOCKER-USER` block**. Run
  `scripts/server/apply-docker-user-rules.sh` after it, **always**, and check
  `sudo iptables -S DOCKER-USER` shows the eight rules before standing down.
- **ufw does not filter published container ports.** Docker DNATs and forwards them, and
  `DOCKER-FORWARD` accepts before ufw's forward chains run. The `DOCKER-USER` block (drop from
  `wlp1s0`/`eno1`, return for `tailscale0`, `lo`, Docker bridges and established flows) is the
  control; a container that must be reachable binds `127.0.0.1:port:port` regardless.

## 7. The runbook rule — no silent pause

**Every step an owner runs with `sudo` prints what it is about to do before it waits for anything.**
No bare `read`, no `pause`, no prompt without a preceding line saying what is being asked and why.
The only thing the owner ever types blind is a password into a `sudo` prompt they can see — never
a token, a passphrase or a key into a script's own prompt (a passphrase goes to `age`'s or
`cryptsetup`'s own visible prompt).

Why this is a rule and not advice: during Phase 18.2's validation a runbook script paused silently
while the owner was typing a sudo password, and the password landed in the transcript. Phase 13's
runbooks were the first written under this rule; the S1 audit asked for `sudo` once, up front, at
a labelled line, and refreshed the timestamp so no later block could stall.

And never put a prompting script behind a buffering pipe — `backup-node.sh | tail` hid the node's
sudo prompt from the owner at Phase 13's own close (`tee` is fine; `tail`, `head`, `less` are not).

Two habits that go with it: a script that changes a file keeps the previous version as
`<file>.bak-<date>` and **never overwrites an existing backup from the same day** (a second round
would otherwise destroy the original); and a `systemd-run` probe that is *meant* to fail passes
`--collect`, or it lingers as a failed unit and turns `is-system-running` to `degraded`.

## 8. The one-screen version

```text
Score ≤ 2.0, or a # WHY per finding, in the unit.        systemd-analyze security <unit>
Own account per boundary. Never aleix without a # WHY.   Never docker/sudo/adm/lxd for a service.
Secrets via LoadCredential=, root:root 0600, ADR-046 row + revocation path, same commit.
Listeners: 127.0.0.1, refused in code, socket-table row. Seven is the baseline. ssh -L to reach.
Volume? volume-dependent-services.md decides when it runs.
apply-firewall.sh resets ufw -> apply-docker-user-rules.sh after it, always.
Owner runbooks: print before you wait. sudo prompt only. .bak-<date>, never overwritten.
Known limits: @system-service kills the Claude CLI; AF_NETLINK alone breaks iw/ip.
```
