# Phase 13 Brief — Security hardening

- **Phase:** 13 — Security hardening
- **Written:** 2026-09-12
- **Status:** Brief, committed before implementation per ADR-017
- **Predecessors:** Phase 18.2 (migration to the server), complete 2026-09-12 —
  [`18.2-migration-to-the-server-handover.md`](18.2-migration-to-the-server-handover.md) §What the
  next phase inherits → Phase 13 (seven numbered items); Phase 18.1 —
  [`18.1-encryption-execution-handover.md`](18.1-encryption-execution-handover.md) §Phase 13; Phase 18
  — [`18-foundations-handover.md`](18-foundations-handover.md) open items 4–5; Phase 03 debts listed
  under *Phase 13* in `ROADMAP.md`; `docs/reference/project-state.md` §Security debt (every bullet
  that names Phase 13).
- **Successors:** Phase 15.0 (model registry — the first API keys with money behind them land on the
  node), Phase 23.0 (the endpoint — inherits the account model and the socket baseline decided here),
  Phase 14 (backup — inherits whatever this phase adds to root or the volume); §16 states what each
  must not silently inherit.

## 1. Purpose

Every phase since 03 has added something to the node and accepted a security consequence "for now",
addressed by name to Phase 13. There are now eleven such items across four handovers and the
project-state debt list. This phase goes through them **one by one** and, for each, does one of three
things: closes it, narrows it with a recorded control, or declines it with a written reason. Nothing
is inherited silently past this phase — that is the whole point of running it.

It is promoted to next (ADR-045 running order amended in `3c70478`) because 18.2 changed what the
node *is*: it runs a web application, holds a passphrase-less key with push access to three
repositories, and serves them as the sudo-capable admin account. The next two phases raise the
stakes — 15.0 puts paid API keys on the node; 23.0 makes the node reachable *as a system*. Both build
on the account model, the credential handling and the socket baseline. Deciding those now costs one
phase; deciding them after 15.0 and 23.0 exist means re-doing their unit files and validation tables.

The phase adds no capability. Its deliverable is a node whose documents describe it truthfully, a
written security baseline every later unit is measured against, and a handover that says exactly
what residual risk 15.0 and 23.0 are building on.

**Out of scope, by decision:** encrypting root (ADR-046 rejects it; a reinstall), moving Docker's
`data-root` unless §6.4 finds the trigger has fired, redesigning the Telegram bot's allowlists,
anything in `factory` or `factory-ops` (Workbench code is Factory's), Tailscale SSH (declined in
ADR-019; re-evaluated in §6.7 as a question, not as work).

## 2. Starting state

Verified on `main` at `0d9aa6e`; the node-side facts are those OBSERVED in the 18.2 handover on
2026-09-12 and must be re-observed in S1, not assumed.

**The node.** Lenovo M700, Ubuntu 26.04, Wi-Fi only (`eno1` is a permanent dead end — never propose
it). Reached over Tailscale; sshd key-only, `PermitRootLogin no`, `aleix` the only human account.
`ufw` default-deny inbound, allows `tailscale0` and Tailscale's UDP port (applied out of phase
2026-09-10). Console attached and login-tested (ADR-041) — the recovery path exists.

**Accounts.** `aleix` (sudo, `docker` group — root-equivalent, accepted in ADR-022 for the sole
administrator), `homelab-bot` (system account: bot, watchdog, notifier). The Workbench and the model
helper run as `aleix`.

**Units (seven listening sockets, each named — 18.2 handover item 1):** `homelab-telegram-bot`,
`homelab-watchdog.timer/.service`, `homelab-notify@`, `homelab-model-helper.socket/@.service`,
`homelab-workbench` (+ `onfailure.conf` drop-in), `homelab-data.target`, `wifi-powersave-off`.
`systemd-analyze security` has been run on **one** unit (Workbench, 1.3) and the bot's set was proven
on Python 3.14.4; the others have never had a score recorded.

**Credentials on root (ADR-046 table, five rows):** Claude OAuth, Codex OAuth, Telegram bot token
(`LoadCredential=`, `root:root 0600`), Wi-Fi passphrase, Tailscale node identity. **A sixth exists
since 18.2 and is not in the table:** `~aleix/.ssh/id_ed25519_github`, passphrase-less, account-level,
push to `oncla`, `factory-ops`, `brain`. ADR-046's own check 3 says a new credential is added to the
table with its revocation path or the ADR is reopened. That is the first thing this phase owes.

**The volume.** LUKS2 `ubuntu-vg/data` → `/srv/homelab`, `noauto`, unlocked by hand over SSH after
boot, `aleix:aleix 750`. Five clones inside. 43 GiB of the VG deliberately unallocated — never
allocate it. Nothing on root can open the volume (ADR-046 §3) — a property this phase must re-verify
and must not weaken.

**Docker.** Rootful, no userns-remap, `data-root` on root by decision (18.2 brief §6.5), inventory
believed to be zero. Docker and Tailscale both own packet-filtering chains; Docker's DNAT runs before
`ufw`'s `INPUT`, so a published container port would bypass the firewall. ~~IPv4 `FORWARD` is `DROP`,
IPv6 `FORWARD` is `ACCEPT`~~ **Corrected in S1 (OBSERVED 2026-09-12):** both `FORWARD` policies are
already `DROP` — `ufw`'s `deny (routed)` default set them on 2026-09-10; project-state's
"asymmetric" bullet was stale. `DOCKER-USER` exists and is empty; `DOCKER-FORWARD` is consulted
before `ufw`'s forward chains, so the bypass for a *published* port is real and the `DOCKER-USER`
rule below is still the control.

**Physical.** No BIOS password — a USB stick yields root on the installed system in about a minute
(the same path 18.1 used legitimately for rescue). No console idle timeout. The console is the
recovery path, so the box is also a logged-in shell to anyone who walks up to it after the owner.

**Access.** Two SSH aliases by design: `homelab` (forward-free; every script uses it) and
`homelab-workbench` (`LocalForward 127.0.0.1:8765`, `ExitOnForwardFailure yes`). `homelab-lan`
fallback alias untouched. Single Ed25519 client key; backup restored once (Phase 18); Tailscale node
key expiry disabled (ADR-019).

**Governance.** `docs/standards/` holds four standards; `safe-changes-headless.md` (ADR-041) governs
every boot-class and remote-access change in this phase — **a second idle SSH session before touching
sshd, ufw, Tailscale, or anything that runs at boot**. A password exposure happened during 18.2's
validation because a runbook script paused silently while the owner was typing a sudo password;
remediated the same evening, recorded in the guide, not yet a rule.

## 3. Learning objectives

- Reading a systemd unit's effective sandbox (`systemd-analyze security`, `systemctl show`) and
  knowing which findings matter for *this* process and which are noise.
- How Docker's `DOCKER-USER` chain relates to `ufw` and why a host firewall does not control
  published ports by default.
- What a BIOS password, Secure Boot state and a console timeout each do and do not protect.
- `systemd-creds` and TPM2-bound credentials: what they protect against, and the failure mode when
  the TPM state changes.
- Tailscale ACLs as a second, device-level boundary in front of sshd.
- The difference between closing, narrowing and declining a risk, and writing each so a later
  reader can tell which happened.

## 4. Functional objectives

1. Every item addressed to Phase 13 by name in the 18.2, 18.1 and 18 handovers, the roadmap's Phase
   13 entry and `project-state.md` §Security debt has an OBSERVED outcome: closed, narrowed or
   declined with a reason. A table in the guide lists them all with the outcome.
2. `systemd-analyze security` scores recorded for **all service units** on the node (six: the tool
   refuses timers, sockets and targets — S1 correction), with each finding above the unit's stated
   threshold either fixed or explained.
3. ADR-046 revalidated: its three checks run and pass; its credential table gains the GitHub key
   row; its revisit triggers checked and the results recorded in the ADR.
4. A written **service security baseline** in `docs/standards/` that every later unit (15.0's, 23.x's)
   must meet on day one — the hardening set, the account rule, the socket-accounting rule, the
   credential rule, and the "no silent pause in owner scripts" rule.
5. The socket baseline re-measured (`sudo ss -tlnp`): seven, each named, or the difference explained.
6. The node still passes 18.2's closing check afterwards: no failed units, `running`, Workbench
   active, the volume lock/unlock cycle unchanged, both SSH aliases working concurrently, the bot
   answering `/status`.

## 5. Decisions already fixed

Not reopened here. Where one bites, cite it.

- **ADR-046** — credentials stay on root; nothing on root may open the volume. This phase narrows
  the accepted risk (§4 of the ADR names how) and revalidates; it does not reverse.
- **ADR-038** — everything runs on the node; loopback-only for services; every listening socket
  accounted for and bound to a stated interface.
- **ADR-041 / `safe-changes-headless.md`** — second idle session before boot-class or remote-access
  changes; the console is the recovery path.
- **ADR-043 / `volume-dependent-services.md`** — any unit touched here keeps or gains the contract
  exactly as written; the watchdog, timer and notifier must **not** carry it.
- **ADR-019** — OpenSSH keys are the authentication mechanism, not Tailscale SSH. §6.7 asks whether
  ACLs are added *in front of* that; it does not swap it.
- **ADR-022** — `aleix` in `docker`; never a service account.
- **ADR-018** — sshd key-only, `PermitRootLogin no`. Stays.
- **18.2 §6.2** — the node's GitHub key is account-level, not per-repo deploy keys. This phase may
  narrow its scope (§6.2 below) but does not replace it with a token.
- **The two-alias SSH design** (18.2 handover item 6). Any sshd or client change is tested with
  `ssh -o BatchMode=yes homelab true` *while* a `homelab-workbench` session is open.
- **`eno1` is not an option.** Wi-Fi is the only path.
- The 43 GiB LVM reserve is not allocated by this or any phase without an ADR.
- **The node has no ethernet, the MacBook is a client.** No control here may require the MacBook
  to be present for the node to recover.

## 6. Decisions still open

Each is resolved in execution, recorded in the stage report and the handover, and where marked as
an ADR. Recommendations are the orchestrator's; the executor may overturn any with an OBSERVED
reason.

**6.1 Dedicated account for the Workbench (18.2 handover item 3).** Recommendation: **decline, with
an ADR**, unless S1's audit finds the sandbox leaves a gap. Reasoning: the Workbench never commits or
pushes (18.2 correction `8045856`), so it does not need the key; `ProtectHome=yes` hides
`~aleix/.ssh` and both OAuth files from it; `NoNewPrivileges=yes` closes sudo; `ReadWritePaths=` is
the volume only; `RestrictAddressFamilies` has no `AF_UNIX`. What a compromised Workbench *can* do
today is write anywhere under `/srv/homelab` as `aleix` — all five clones, including the public
`homelab` clone — and read them. A dedicated account would narrow that to `projects/*/ops/` but at
the cost of shared-group write on directories inside git repositories the owner commits from, which
is the classic source of `dubious ownership` and permission drift. 23.0's endpoint runs as its own
account regardless and reaches the Workbench over loopback, so the account question does not block
it. **The ADR records the boundary as the systemd sandbox, names what the account can reach, and
sets the triggers: a second human, an automated client with write access, or the Workbench gaining
commit ability.** If S1 shows the sandbox is weaker than believed (e.g. `ProtectHome` not effective,
or the key readable), take the account instead and say so.

**6.2 The node's GitHub key (18.2 handover item 2).** Recommendation: **keep the account-level key;
add it to ADR-046's table; narrow it in one of two ways, execution chooses:** (a) rotate it to a key
with a **passphrase held by `ssh-agent`** — rejected unless something actually needs unattended push
today (nothing does: Phase 14 will decide how `ops/` gets committed); (b) keep it passphrase-less and
**scope by policy** — GitHub cannot restrict a user key per repository, so the control is the
revocation path plus an audit: `gh api user/keys` from the MacBook lists it by title. Take (b); record
(a) as the change to make if Phase 14 picks unattended push. Verify `0600`, `IdentitiesOnly yes`, one
`Host github.com` block only (the duplicate the owner fixed by hand during 18.2 must be gone).

**6.3 Service security baseline — the standard.** Recommendation: **write
`docs/standards/service-security-baseline.md`** as an ADR-043 living spec. Content: the hardening
set proven on Python 3.14.4 (from `homelab-workbench.service`), with `systemd-analyze security` ≤ 2.0
as the threshold for a new unit and each waiver written into the unit as a `# WHY` comment (the
repository's existing idiom); one account per trust boundary, never `aleix` for a service unless the
unit's `# WHY` says so; `LoadCredential=` for every secret, never `Environment=`; loopback binding
and a socket-table row for every listener; volume-dependent pattern by reference; **no interactive
pause, prompt or silent `read` in any script the owner runs with sudo**; every owner runbook step
prints what it is about to do before it waits. Not an ADR — it is the enforcement of ADR-038/043/046,
and those already exist.

**6.4 Docker (`data-root`, rootless/userns-remap, firewall).** Recommendation: **`data-root` stays on
root** — the 18.2 trigger (a container that must hold volume content) has not fired and Docker's
inventory is zero; moving it is the only stage that costs bot downtime and buys nothing measurable
today. Confirm inventory with `docker system df` in S1 and record it. **Rootless/userns-remap:
decline with a reason** — no container runs; the decision has nothing to protect yet and should be
taken by the first phase that ships one (record which phase that is likely to be). **Firewall: take
it.** Add a `DOCKER-USER` rule set that drops anything not from `tailscale0` or loopback, so a future
published port cannot bypass `ufw`; ~~set IPv6 `FORWARD` policy to `DROP` to match IPv4~~ (already `DROP` — S1 correction above;
§8 row 6's second half becomes a re-proof). Through
`scripts/server/apply-firewall.sh` with the timed self-revert that script already has, and under
`safe-changes-headless.md`. Verify from the MacBook that SSH and the tunnel still work.

**6.5 BIOS password and console idle timeout (18 handover item 5; 18.1 → 13).** Recommendation:
**take both.** BIOS: supervisor/administrator password only (not a power-on password — the node must
boot unattended after a power cut, ADR-037 §2); boot order locked to the internal disk; record
whether Secure Boot is on and leave it as found. This is the one step that needs the owner *at the
box*; it can be a separate short session, and it does not need a second SSH session because it does
not touch the running system. Store the BIOS password in the owner's password manager; **it is not
written anywhere in the repository or on the node.** Console: `TMOUT=900` readonly for tty logins
only (`/etc/profile.d/`, guarded on `tty` so SSH sessions are unaffected — a timeout on SSH would
kill the owner's unlock and validation sessions). Record in ADR-046 as trigger 3 firing: the
consequence table narrows.

**6.6 `systemd-creds` TPM2 binding of the bot token (ADR-046's "cheapest narrowing").**
Recommendation: **evaluate in S1, take only if all three hold:** `systemd-creds has-tpm2` reports
yes; a rollback is written and tested (the plaintext token stays in the owner's password manager, and
the runbook to re-encrypt after a firmware change is one command); and the encrypted credential can
be proved to load after a **real reboot** (`LoadCredentialEncrypted=`) — the failure mode is a bot
that comes back silent, which is precisely what ADR-046 §2 exists to prevent. If any of the three
fails, **decline** and write why; the risk it narrows (pulled disk → token) is revocable in minutes
via `@BotFather` anyway. Do the same evaluation for the notifier (`homelab-notify@`), which loads the
same token — both or neither.

**6.7 Tailscale: node key expiry (ADR-019) and ACLs.** Recommendation: **key expiry stays disabled**
— the console now exists (ADR-041) but the owner is not always home, and a lapsed key silently
removes the remote path; the control this trades away is re-authentication, which Tailscale's device
approval covers. Record as *declined, revisit if the machine leaves the home*. **ACLs: take** — a
tailnet policy that allows only the owner's tagged/named devices to reach the node on `22` and
nothing else to reach it at all. Applied in the Tailscale admin console from the MacBook, under
`safe-changes-headless.md` (it is a remote-access change), with the console as fallback. Tailscale
SSH stays declined (ADR-019). Record the policy JSON in `config/tailscale/` — it is not a secret.

**6.8 The single SSH client key (Phase 03 debt).** Recommendation: **close it cheaply** — generate a
second Ed25519 pair on the MacBook, add its public half to `~aleix/.ssh/authorized_keys` on the node
(one line, `restrict`-free), and store the private half `age`-encrypted on the backup card next to
the LUKS header backup (18.1 C6's location). The card is already treated as secret material. Test
the second key once from the MacBook, then remove it from the agent. With the console (ADR-041) and
the restored backup (Phase 18) this is the third leg; record the debt as closed.

**6.9 sshd audit.** Recommendation: **audit, change little.** `sshd -T` captured and read; add
`AllowUsers aleix` and `MaxAuthTries 3` if absent; confirm `PasswordAuthentication no`,
`KbdInteractiveAuthentication no`, `PermitRootLogin no`, `X11Forwarding no`; leave `ListenAddress`
alone (binding to `tailscale0`'s address would race the interface at boot and the `ufw` rule already
filters). Every change via `scripts/server/apply-ssh-hardening.sh`'s existing pattern, second idle
session open, `sshd -t` before reload. `fail2ban`: **decline** — no password authentication, inbound
only from `tailscale0`; there is nothing for it to count.

**6.10 unattended-upgrades and reboot policy.** Recommendation: **audit and record.** Confirm
`unattended-upgrades` is active and what it installs (security pocket only, or all); confirm
`Automatic-Reboot` is **off** — an automatic reboot leaves the volume locked (ADR-037 §4) and the
watchdog already tells the owner when a reboot is *needed*; the reboot is the owner's. If it is on,
turn it off and record why.

**6.11 Everything else that names Phase 13.** `project-state.md` §Security debt is walked bullet by
bullet in S1 and each gets a row in the guide's table. Anything found there that is not in §6.1–6.10
is a new open decision for the stage report, not a silent skip.

## 7. Implementation scope

Four stages. **S1 is read-only on the node.** S2 and S3 change the node and run under
`safe-changes-headless.md`. Nothing here needs the volume locked, and nothing here reboots the node
except the optional proof in 6.6.

**7.1 S1 — Audit (executor drafts; owner runs read-only commands and pastes).** For every unit:
`systemd-analyze security <unit>` and `systemctl show -p User,NoNewPrivileges,ProtectHome,ProtectSystem,ReadWritePaths,RestrictAddressFamilies,LoadCredential,RequiresMountsFor --value <unit>`.
`sudo ss -tlnp`. `sshd -T`. `sudo ufw status verbose`; `sudo iptables -S DOCKER-USER FORWARD`;
`sudo ip6tables -S FORWARD`. `docker system df`; `cat /etc/docker/daemon.json`. ADR-046 checks 1–3
verbatim. `systemd-creds has-tpm2`. `apt-config dump APT::Periodic` and
`/etc/apt/apt.conf.d/50unattended-upgrades` (grep `Automatic-Reboot`). `ls -la ~aleix/.ssh`;
`ssh -G github.com | grep -i identity`; `grep -c 'Host github.com' ~aleix/.ssh/config`.
`mokutil --sb-state`. From the MacBook: `gh api user/keys --jq '.[].title'`; the Tailscale ACL as it
stands. **Output of S1 is the debt table with a proposed outcome per row and the §6 recommendations
confirmed or overturned — before anything is changed.** Orchestrator reviews before S2.

**7.2 S2 — Software controls (one owner session, second idle session open throughout).** In this
order, each verified before the next: sshd (6.9) → firewall (6.4, with the self-revert) → console
timeout (6.5, the `TMOUT` half) → unattended-upgrades (6.10) → second key (6.8) → GitHub key hygiene
(6.2) → Tailscale ACL (6.7, applied last because it is the one applied from outside the node). After
each: `ssh -o BatchMode=yes homelab true` with a `homelab-workbench` session open; `/status` to the
bot. Any unit changes from the S1 audit (raising a score, adding a missing directive) go here too,
each via `systemctl daemon-reload` + restart + `systemctl is-active`, and each unit that gains a
directive gets the `# WHY` comment.

**7.3 S3 — Credentials and the box (may be a separate owner session; part of it is physical).**
6.6 if taken: `systemd-creds encrypt` for the bot token, `LoadCredentialEncrypted=` in the bot and
notifier drop-ins, restart, `/status`, then **a real reboot** and `/status` again from the bot — this
is the proof, and the volume comes back locked, so the unlock is part of the drill. 6.5 BIOS half:
owner at the box, password set, boot order locked; afterwards one full power-cycle to prove the node
boots unattended and reports for duty. 6.1's ADR written here, after S1's sandbox facts are known.
ADR-046 updated: table row, trigger 3 fired, checks re-run.

**7.4 S4 — Documentation and close.** `docs/standards/service-security-baseline.md` (6.3). Guide
`guide/13-security-hardening/README.md` with the debt table (item → source handover → outcome →
OBSERVED evidence). Handover per template addressed to 15.0, 23.0 and 14 by name (§16). Architecture,
project-state (every Phase 13 bullet struck or rewritten), roadmap status block, software-stack,
costs. DoD applied literally. Closing check identical to 18.2's plus the socket count.

**Rollback per stage.** S2: every change is a file under `/etc` with the previous version saved
alongside as `.bak-2026-09-DD` and the self-revert timer for firewall/sshd; the console is the
fallback. S3: the plaintext token in the password manager re-creates `/etc/homelab-telegram-bot/token`
in one step; BIOS password in the password manager. Nothing in this phase is unrecoverable.

## 8. Validation / tests

Each row OBSERVED by the owner on the node (or the MacBook where stated) and pasted; the executor
records verbatim. PREDICTED rows are not accepted at close.

| # | Test | Expected |
|---|---|---|
| 1 | `systemd-analyze security --no-pager` for every unit | Each score recorded; each ≤ threshold or waived with a `# WHY` in the unit |
| 2 | `sudo ss -tlnp` | Seven sockets, each matching the 18.2 list, or the difference explained |
| 3 | `sshd -T \| grep -iE 'passwordauth\|permitroot\|allowusers\|maxauthtries\|kbdinteractive'` | `no`, `no`, `aleix`, `3`, `no` |
| 4 | With a `homelab-workbench` session open: `ssh -o BatchMode=yes homelab true; echo $?` | `0`, and the tunnel session still alive |
| 5 | From the MacBook, second key: `ssh -i <second> -o IdentitiesOnly=yes homelab true` | `0`; then key removed from agent, private half absent from the MacBook's `~/.ssh` |
| 6 | `sudo iptables -S DOCKER-USER`; `sudo ip6tables -S FORWARD \| head -1` | Drop rule for non-`tailscale0`/non-lo present; `-P FORWARD DROP` |
| 7 | From a non-tailnet host or with Tailscale off on the MacBook: `nc -zv -w3 <node LAN IP> 22` | Refused/timeout (already true via ufw — re-proved after the changes) |
| 8 | Tailscale ACL: from the MacBook `tailscale ping homelab` and `ssh homelab true`; from a device not in the allow list (if available) `nc -zv -w3 homelab 22` | Owner device: reachable; other: refused. If no second device, PREDICTED and said so |
| 9 | Console: log in on the tty, wait `TMOUT`+30 s | Session ended; an SSH session left idle the same period is **not** ended |
| 10 | BIOS: reboot, attempt to enter setup | Password prompt; boot proceeds unattended without one |
| 11 | After the BIOS change: full power-cycle | Node boots, bot answers `/status` reporting volume locked; unlock; Workbench active |
| 12 | If 6.6 taken: `systemctl show -p LoadCredentialEncrypted --value homelab-telegram-bot`; then real reboot; `/status` | Value present; bot answers after reboot with no manual step |
| 13 | ADR-046 checks 1–3 | `luksDump` passphrase slots only; grep empty; table has six rows |
| 14 | `grep -c '^Host github.com' ~aleix/.ssh/config`; `stat -c %a ~aleix/.ssh/id_ed25519_github`; from the MacBook `gh api user/keys --jq '.[].title'` | `1`; `600`; title `homelab node — 2026-09-12` present once |
| 15 | `grep -i 'Automatic-Reboot' /etc/apt/apt.conf.d/50unattended-upgrades`; `systemctl is-enabled unattended-upgrades` | `"false"` (or absent); `enabled` |
| 16 | `docker system df` | Zero or recorded inventory; `data-root` unchanged (`/var/lib/docker`) |
| 17 | Lock/unlock cycle: `data-volume.sh lock`, `status`, `unlock`, `status` | Workbench stops with the target and returns; no `OnFailure` fires; no Telegram alert |
| 18 | 18.2 closing check: `systemctl --failed`; `systemctl is-system-running`; `systemctl is-active homelab-workbench` | Empty; `running`; `active` |
| 19 | Backup: `backup-node.sh` then `verify-node-backup.sh` from the MacBook | Passes; new `/etc` files this phase touched are in the manifest; second key's private half and the GitHub key are **absent** |
| 20 | Every `# WHY` comment in units changed this phase | Present for each directive added or waived (read, not run) |

## 9. Security considerations

- **This phase touches remote access three times** (sshd, firewall, Tailscale ACL). Each one under
  `safe-changes-headless.md`: second idle session, self-revert armed, console available. The ACL is
  applied from *outside* the node; a wrong ACL locks the MacBook out while leaving the node fine —
  the console is the fix, and the admin console can be edited from any browser.
- **The BIOS password must be a supervisor password, not a power-on password.** A power-on password
  defeats unattended recovery (ADR-037 §2) and turns every power cut into a walk to the box.
- **A console timeout on SSH sessions would be a regression**: the owner's unlock, validation and
  long-running runbook sessions would be killed. Guard on `tty`.
- **`systemd-creds` is a two-edged control.** It narrows a pulled-disk threat that is already
  revocable in minutes, at the cost of a new failure mode (TPM state change → bot silent) in the one
  component ADR-046 says must always come back. The three conditions in 6.6 are not optional.
- **Nothing on root may become able to open the volume** (ADR-046 §3). No step here adds a keyfile,
  a TPM enrolment of the *volume*, or a scripted passphrase. `systemd-creds` binds the *bot token*,
  not the LUKS key — keep the two clearly separate in the guide, because a reader will conflate them.
- **The second SSH key's private half never lives on the node or in the repository.** Card only,
  `age`-encrypted, like the LUKS header.
- **The BIOS password lives in the password manager only.** Not in the guide, not in a handover, not
  in the ADR.
- **No new secret is committed.** The repository is public; the Tailscale ACL JSON, the firewall
  rules and the `TMOUT` profile snippet are configuration, not secrets, and go in. Anything with a
  key, token or password does not.
- **The sudo-password lesson becomes a rule in this phase** (6.3). Every owner runbook step in S2
  and S3 prints what it is about to do before it waits — this phase's own runbooks are the first test
  of the rule.
- **Do not weaken the two-alias design** to make a test pass. If an sshd change breaks the tunnel
  alias, the change is wrong.

## 10. Repository changes expected

- New: `docs/handovers/13-security-hardening.md` (this), `docs/handovers/13-security-hardening-handover.md`,
  `guide/13-security-hardening/README.md`, `docs/standards/service-security-baseline.md`,
  `config/tailscale/acl.json` (or `.hujson`), `config/profile.d/homelab-console-timeout.sh`,
  `docs/decisions/ADR-047-workbench-account-boundary.md` (6.1; number to be confirmed against
  `docs/decisions/README.md` at the time).
- Modified: `scripts/server/apply-firewall.sh` (DOCKER-USER, IPv6 FORWARD), possibly
  `scripts/server/apply-ssh-hardening.sh` (AllowUsers, MaxAuthTries), unit files and drop-ins that
  gain directives or `# WHY` comments, `config/systemd/homelab-telegram-bot.service.d/` and
  `homelab-notify@.service.d/` if 6.6 is taken, `docs/decisions/ADR-046-…` (table row, trigger 3,
  re-run checks), `scripts/macos/backup-node.sh` + `verify-node-backup.sh` (new `/etc` paths;
  exclusions for the second key if it ever touches the node's `~/.ssh` — it should not),
  `ROADMAP.md`, `docs/reference/project-state.md`, `docs/architecture/current-architecture.md`,
  `docs/reference/software-stack.md`, `docs/reference/costs.md`, `README.md` phase table,
  `docs/handovers/README.md`, `docs/decisions/README.md`, `docs/standards/` index if one exists.

## 11. Guide documentation required

`guide/13-security-hardening/README.md`: what the phase did and why now; **the debt table** (item,
where it was addressed from, outcome, evidence); each control in plain language with what it does
and does not protect (the ADR-046 §4 standard); the physical steps (BIOS) as a checklist; the
`systemd-creds` decision either way with the failure mode explained; the rollback for each control;
Security notes including anything that went wrong during execution (§11 of PROJECT.md — failure
transparency, as 18.2 did with the password exposure).

## 12. Project documentation required

`project-state.md`: every bullet naming Phase 13 struck or rewritten with the outcome and date; the
"Current phase" line. `current-architecture.md`: the security boundary description updated (BIOS,
ACL, DOCKER-USER, TMOUT, second key), the socket table re-dated. `ROADMAP.md`: Phase 13 status
block; sequencing note item struck; 15.0 confirmed next. `software-stack.md`: `age`, `systemd-creds`
if used, Tailscale ACL version. `costs.md`: 0 expected (Tailscale free tier covers ACLs).

## 13. ADRs required / possible

- **Required:** ADR-047 (number to confirm) — the Workbench's trust boundary is the systemd sandbox,
  not a dedicated account; what the account can reach; triggers to revisit (6.1). Required either
  way because 23.0's endpoint design depends on the answer.
- **Required:** ADR-046 **amended, not superseded** — sixth table row, trigger 3 fired (BIOS password
  and/or `systemd-creds`), checks re-run with date.
- **Possible:** an ADR for the Tailscale ACL as a device-level boundary in front of sshd, if the
  executor finds it changes ADR-019's reasoning rather than sitting beside it. Default: record in the
  guide and the standard, no ADR.
- **Not an ADR:** `fail2ban` declined, rootless Docker deferred, key expiry kept disabled — these are
  recorded in the guide table with reasons and in the handover.

## 14. Costs

Expected 0. Tailscale ACLs are on the free tier. `age` is already installed on the MacBook (18.1).
Record actual.

## 15. Definition of Done

PROJECT.md §12 applied literally, item by item, in the handover. Specific to this phase:

- Every item in §6.11's walk has an OBSERVED outcome row — none is "inherited".
- All twenty rows of §8 OBSERVED, or the row says PREDICTED and the handover names it as debt.
- `systemd-analyze security` recorded for every unit.
- ADR-046 checks pass and the table has six rows.
- Both SSH aliases work concurrently after every remote-access change (row 4).
- The node boots unattended after the BIOS change and the bot reports for duty (row 11).
- `docs/standards/service-security-baseline.md` exists and 15.0's brief can cite it.
- No secret in the repository — `git grep` for the BIOS password's shape, the token and key
  material returns nothing (the executor states which patterns were checked).
- The closing check (row 18) pasted by the owner.

## 16. Return handover requirements

Per `docs/templates/` handover template, addressed by name:

**To Phase 15.0 (model registry):** the service security baseline it must meet on day one; where a
paid API key lives (`LoadCredential=` from `/etc/…`, `root:root 0600`, added to ADR-046's table with
its revocation path — the pattern the bot token set); the account it runs as and why (6.1's ADR);
the socket baseline it must not silently extend; whether `systemd-creds` is available to it.

**To Phase 23.0 (the endpoint):** the account decision (ADR-047) and what it means for a process
that reaches the Workbench over loopback; the Tailscale ACL as the outer boundary and how a new
listener is added to it; the `DOCKER-USER` rule if the endpoint is ever containerised; the
socket-table row it owes.

**To Phase 14 (backup):** every new `/etc` path this phase created; the second key's card location
next to the LUKS header; the BIOS password's existence (not value) as a restore-time dependency —
a rebuilt node needs it entered at the box; whether `systemd-creds` encrypted blobs are in the
backup and that they are useless without this machine's TPM (so the plaintext in the password
manager is the real backup).

**Open risks not to be inherited silently:** anything declined in §6 with its reason and revisit
trigger; any §8 row left PREDICTED; the account-level GitHub key's scope if 6.2(b) was taken; the
running machine is still unprotected (ADR-046 §4 — unchanged, restated).

**Failures and lessons** per PROJECT.md §11, including anything that broke remote access and how
the second session or console recovered it.
