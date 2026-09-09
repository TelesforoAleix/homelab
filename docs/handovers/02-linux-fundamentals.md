# Phase 02 Brief — Linux Fundamentals

- **Date:** 2026-09-09
- **Phase:** 02 — Linux Fundamentals
- **Author:** the Phase 02 context
- **Status:** Accepted, self-ratified under ADR-017
- **Previous handover:** [`03-remote-access-handover.md`](03-remote-access-handover.md)

## 0. Governance note

Under ADR-017 there is no Project Planning context to ratify this brief. It is written and committed
**before implementation begins**, which is the first of the three compensating controls that ADR-017
makes mandatory. Its value is as a specification; a brief written afterwards would be a narrative.

### Sequencing note

Phase 02 is being run **after** Phase 03, by the owner's decision of 2026-09-09. Phase numbers are
stable, so this phase keeps the number 02 and the file name `02-linux-fundamentals.md`. The
consequence for scope is significant and is treated as a feature, not an inconvenience:

- Phase 02 is carried out over key-based SSH with a stable `homelab` alias, not password login.
- Phase 03 exercised roughly half this phase's syllabus for real, under pressure, with two genuine
  failures. That is better teaching material than anything this phase could invent.
- **The console is gone.** Every exercise in this phase has to be designed around that.

### Two scope decisions taken with the owner before writing

Asked and answered on 2026-09-09, because both materially change what gets built:

1. **Deliverable shape:** a written guide **plus hands-on exercises that are actually run**, with
   anything capable of removing access rehearsed on a disposable sandbox rather than on the real
   account or the real services. Not documentation-only; not full hands-on including networking.
2. **Shell tooling:** install a **small, justified set** — `tree`, `ncdu`, `ripgrep` — each of which
   earns its place inside a specific exercise. Not the fuller comfort set (`fzf`, `bat`), and not
   nothing.

## 1. Purpose

Phase 01 installed the operating system and Phase 03 made it reachable. Neither taught the owner to
**operate** it. Every phase from 04 onward assumes a person who can read a permission bit, find out
why a service will not start, tell a full disk from a full inode table, and search a journal without
guessing.

This phase exists to close that gap, and to leave behind two durable things:

- a guide that explains Linux as this project actually uses it, not as a textbook covers it; and
- an operating standard for making changes on a machine with **no console**, which is now the
  single most consequential fact about the reference node.

The second is arguably worth more than the first. Phase 01 and Phase 03 both sequenced their
dangerous steps around a monitor being available. From here on, nothing can.

## 2. Starting state

Verified from live output on 2026-09-09 at phase start, over `ssh homelab`.

### Server

| Fact | Value |
|---|---|
| Host | `homelab`, Lenovo ThinkCentre M700 Tiny |
| OS | Ubuntu 26.04.1 LTS, kernel `7.0.0-31-generic` |
| systemd | 259 (259.5-0ubuntu3.4) |
| Shell | GNU bash 5.3.9(1), `/bin/bash` for `aleix` |
| Health | `systemctl is-system-running` → `running`; **0** failed units |
| Running services | 23 |
| Timers | 16 |
| Journal on disk | 24 MB |
| Pending package upgrades | 0 |
| Groups defined | 62 |
| Human users (UID ≥ 1000) | exactly one — `aleix` (1000) |
| `aleix` groups | `aleix adm cdrom sudo dip plugdev users lxd` |
| `sudo` | **Requires a password.** No `NOPASSWD` |
| Root filesystem | `/dev/mapper/ubuntu--vg-ubuntu--lv`, 232 G, 7.8 G used (4 %) |
| Listening | `:22` (v4+v6), `tailscaled` on the tailnet addresses, `systemd-resolved` on loopback |
| Console | **None.** All DRM connectors `disconnected` |
| Access | `ssh homelab` (Tailscale, primary) · `ssh homelab-lan` → `192.168.1.57` (LAN, fallback) |
| Authentication | Public key only — no passwords, no keyboard-interactive, no root login (ADR-018) |

Present already: `tmux` 3.6, `htop`, `jq`, `git`, `curl`, `vim`, `nano`, `less`.
Absent: `tree`, `ncdu`, `ripgrep`, `bat`, `fzf`.

### A storage constraint that shapes §7

```text
sda  238.5G
├─sda1    1G  /boot/efi
├─sda2    2G  /boot
└─sda3  235.4G
  └─ubuntu--vg-ubuntu--lv  235.4G  /
```

The logical volume already consumes **the entire volume group**. There are no free extents, so the
textbook `lvextend` / `resize2fs` exercise **cannot be performed** on this machine without first
shrinking a mounted root filesystem, which is exactly the kind of operation a console-less node
should never attempt. Storage in this phase is therefore taught by **inspection and by reading the
Phase 01 decision that produced this layout** (ADR-015), with the growth path documented rather than
demonstrated. This is a real limitation and is recorded as one, not worked around.

### Repository

Clean `main` at `5804da6`; Phase 03 merged. Work proceeds on `feature/02-linux-fundamentals`.

## 3. Learning objectives

By the end of this phase the owner should be able to do the following **without looking anything up**
for the first four, and with the project's own cheatsheet for the rest.

1. **Read a permission line.** Given `-rw------- 1 root root … 10-homelab-hardening.conf`, say who
   can read it, who can change it, and why both facts are a security control here.
2. **Find out why a service is not running** — `systemctl status`, then `journalctl -u … -b`, then
   the unit file itself — and know the difference between "failed", "inactive" and "not installed".
3. **Tell the three kinds of "disk full" apart**: bytes (`df -h`), inodes (`df -i`), and a file that
   is deleted but still held open by a process (`lsof`/`/proc`), which `df` and `du` disagree about.
4. **Not lock themselves out.** Recognise, before typing, that a command touches `sshd`, `netplan`,
   `sudoers`, the `aleix` account or something that runs at boot — and apply the standard from §7.4.
5. Navigate the filesystem hierarchy with intent: know why configuration is in `/etc`, why
   `/var/log` grows, what `/proc` and `/sys` actually are, and why `/tmp` is not a safe place to
   leave anything.
6. Explain users, groups, and the difference between *ownership*, *group membership* and *the
   `sudo` group being an ordinary group with an entry in `/etc/sudoers.d`*.
7. Use `apt` deliberately: `update` vs `upgrade` vs `full-upgrade`, what a `.list`/`.sources` file
   and a `signed-by=` keyring do, and how to find out which package owns a file.
8. Read processes: `ps`, `top`/`htop`, load average vs CPU percentage, what a zombie is and why it
   is usually harmless.
9. Query the journal like a database rather than scrolling it — by unit, by boot, by priority, by
   time window — and know where journald's retention limits are set.
10. Work comfortably in `tmux`: detach, reattach, and understand **why a long-running command on a
    remote host belongs in a session that survives the connection dropping.**

Each objective maps to at least one exercise in §7 and at least one check in §8. An objective with
no check is a wish, not an objective.

## 4. Functional objectives

What must actually work by the end of the phase.

1. `guide/02-linux-fundamentals/README.md` exists, follows `docs/templates/guide-template.md`, and
   teaches from this project's own artifacts — the netplan file, the sshd drop-in, the Wi-Fi
   power-save unit, the Tailscale repository entry — rather than from invented examples.
2. `docs/reference/linux-command-reference.md` exists: the commands this project actually uses,
   grouped by the question they answer, each with a one-line "why you would run this".
3. `docs/standards/safe-changes-headless.md` exists and is referenced from `AGENTS.md`'s operating
   rules, so future phases inherit it as a standard rather than as prose in a handover.
4. `scripts/server/lab-sandbox.sh` creates and tears down a disposable practice environment — a
   throwaway user, group and scratch directory — and **refuses** to operate on `aleix`, `root`, any
   UID below 1000, or any member of the `sudo` group.
5. `scripts/server/preflight.sh` reports whether the preconditions in the §7.4 standard are met
   before a risky change: both access routes reachable, more than one live session, no failed units,
   free space, and the configuration validator for the thing being changed.
6. `tree`, `ncdu` and `ripgrep` are installed, and each appears in an exercise that justifies it.
7. Every exercise in the guide has been **run on the server, with its real output recorded** —
   nothing is written as expected output.
8. The server ends the phase in the same access posture it started in: key-only SSH, both routes
   working, no failed units, `aleix` unchanged, sandbox artifacts removed.

## 5. Decisions already fixed

Accepted ADRs that constrain this phase:

| ADR | Constraint on this phase |
|---|---|
| ADR-003 / ADR-014 | Ubuntu Server 26.04.1 LTS. Teach `apt` and systemd as Ubuntu ships them, not generic Linux |
| ADR-006 | Manual before frameworks. Understand the command before writing the script |
| ADR-011 | Privilege separation. Nothing user-facing runs as root — the sandbox user models this |
| ADR-012 | Progressive automation. Scripts come **after** the manual process is understood |
| ADR-013 | `main` must stay known-working |
| ADR-015 | The disk layout is fixed and unencrypted. Storage is taught, not re-decided |
| ADR-017 | Brief first; handover states what the next phase inherits |
| ADR-018 | **Key-only SSH is a control.** This phase does not modify `sshd`, and its drop-in is a read-only teaching example |
| ADR-019 | Tailscale is the primary route. Node key expiry stays disabled |

### Inherited from the Phase 03 handover — must not be silently ignored

1. **The console is gone.** All six DRM connectors report `disconnected`. This is section 1 of the
   inbound handover and section 7.4 of this brief.
2. **`sudo` needs a password.** Every privileged step in this phase requires the owner at the
   keyboard. Exercises must be short and one per line — the owner's terminal splits pasted lines at
   about 65 characters.
3. **The `10-` prefix on the sshd drop-in is a security control.** It appears in this phase as a
   worked example of first-match-wins ordering, and must be described as a control when it does.
4. **Applying sshd configuration requires `systemctl reload ssh`.** The stale-daemon failure is one
   of this phase's two centrepiece lessons.
5. **Ground already covered** — the handover's §6 table. Build on it. Re-teaching `chmod` from zero
   when the project already has a `chown root:root` escalation story in its build log wastes the
   best material available.
6. **Single SSH key, no backup, no console.** Not this phase's to close (Phase 13), but it is the
   reason §7.4 exists at all.

## 6. Decisions still open

Resolvable inside this phase; anything cross-phase becomes an ADR (ADR-017).

1. **Does the safe-change standard warrant an ADR, or is a `docs/standards/` file enough?**
   Provisional answer: **an ADR**, because it constrains every future phase's method of working, and
   ADR-017's revisit triggers include phases silently contradicting standards. Expected as ADR-020.
2. **Does `scripts/server/preflight.sh` earn its existence?** Only if it checks something a printed
   checklist cannot — specifically, *counting live sessions* and *proving both routes independently*.
   If it degenerates into a checklist that prints itself, it should not be written. Decide during
   implementation and record the decision either way.
3. **Does baseline shell tooling warrant an ADR?** Provisional answer: **no.** Three packages with
   reasons belong in `docs/reference/software-stack.md`. Recorded here so the omission is deliberate.
4. **How much of the guide is theory?** `guide/README.md` warns against becoming a general textbook.
   Rule adopted: a concept is in scope only if it explains something this project has already done or
   will do by Phase 05.
5. **Sandbox user naming and lifetime.** Provisional: `labuser`, created and destroyed within the
   phase, never left on the machine. Confirm at teardown.

## 7. Implementation scope

### 7.1 Deliverable shape

Guide + exercises actually run + four repository artifacts. Not a textbook, and not a transcript.

### 7.2 Syllabus, mapped to what already exists

`ROADMAP.md` names ten topics. Each is taught through an artifact this project already owns:

| Topic | Taught through |
|---|---|
| Filesystem hierarchy | Where Phase 01 and 03 put things: `/etc/netplan`, `/etc/ssh/sshd_config.d`, `/etc/apt/sources.list.d`, `/var/log/journal`, `/home/aleix/.ssh` |
| Users & groups | The single real user, the `sudo` group, `/etc/sudoers.d`, and a sandbox user created to model ADR-011 |
| Permissions & ownership | `0600 root:root` on the sshd drop-in and the netplan file — and *why*, including the Phase 01 `chown` escalation |
| Packages | Ubuntu's own repositories vs the Tailscale one added in Phase 03; `signed-by=`; `dpkg -S`; `apt policy` |
| Processes & services | `ssh.socket` with `Accept=no`, the Wi-Fi power-save unit, `unattended-upgrades`, reload vs restart |
| Logs | `journalctl -u ssh`, `-b`, `-p err`, `--since`; retention in `journald.conf`; the 24 MB currently on disk |
| Storage | `lsblk`, `df -h`, `df -i`, LVM's PV/VG/LV layering as Phase 01 created it; the no-free-extents constraint |
| Networking | **Read-only.** `ip -br a`, `ss -tlnp`, `resolvectl`, `networkctl`, reading `50-wifi.yaml` without editing it |
| Shell workflow | Redirection, pipes, exit status, `set -e` semantics as Phase 03 got wrong, quoting |
| `tmux` & tooling | Detach/reattach as the answer to "my SSH dropped mid-upgrade"; `tree`, `ncdu`, `ripgrep` in context |

### 7.3 The three-tier safety model

Every exercise is classified before it is written. This classification is the phase's core method.

**Tier 1 — Free.** Read-only inspection, or writes confined to a scratch directory the sandbox user
owns. Cannot affect access. The large majority of exercises.

**Tier 2 — Sandboxed.** The write side of users, groups, permissions and systemd units — genuinely
practised, but on a disposable `labuser`, a disposable group, and a disposable unit that does
nothing. Never on `aleix`, never on the `sudo` group, never on `ssh`, `tailscaled`, or anything
`WantedBy=multi-user.target` that could fail at boot.

**Tier 3 — Read-only this phase.** `sshd`, `netplan`, `sudoers`, PAM, the bootloader, fstab. Studied
by reading the real files and explaining them. **Not modified.** The learning value of editing
netplan on a console-less node is not worth the cost of getting it wrong, and Phase 13 will have a
better safety net.

An exercise that cannot be placed in a tier does not go in the guide.

### 7.4 The safe-change standard (the phase's most important output)

To be written as `docs/standards/safe-changes-headless.md` and proposed as ADR-020. Draft content:

- **Classify first.** Does this touch network, `sshd`, authentication, or boot? If yes, it is a
  lockout-class change and the rest applies.
- **Two sessions, always.** Open a second SSH session and leave it idle. Established connections
  survive `sshd` configuration changes and restarts; a new connection may not.
- **Prove both routes before, not after.** `ssh homelab` and `ssh homelab-lan` are independent
  above the Wi-Fi link and identical below it. Losing Wi-Fi loses both.
- **Validate before applying.** `sshd -t`, `netplan try` (which auto-reverts), `systemd-analyze
  verify`, `visudo -c`. A validator that exists and is skipped is a self-inflicted wound.
- **Prefer `reload` to `restart`** where the unit supports it, and know that `reload` is what makes
  a configuration file into a control (Phase 03's stale-daemon lesson).
- **Have the rollback typed out before the change**, in the second session, unexecuted.
- **Verify the running system, not the file you wrote.** Phase 03 shipped a correct configuration to
  a daemon that never re-read it, and `sshd -T` agreed with the file.
- **Know what "recover" means now.** It means reattaching a monitor, a keyboard and a DisplayPort→
  HDMI cable that are in a drawer. Budget accordingly.

### 7.5 Work sequence

- **Part A — Guide skeleton and the safe-change standard.** Written first, because it governs the
  exercises that follow.
- **Part B — Tier 1 exercises.** Filesystem, permissions reading, packages, journal, storage,
  read-only networking. Run and captured.
- **Part C — Tooling.** `tree`, `ncdu`, `ripgrep`; versions recorded; each used in an exercise.
- **Part D — Sandbox.** `lab-sandbox.sh`, then the Tier 2 exercises: create a user and group, set
  ownership and modes, write a trivial systemd unit, start it, break it deliberately, diagnose it
  from the journal alone, fix it, tear the whole thing down.
- **Part E — `preflight.sh`**, or a recorded decision not to write it (§6.2).
- **Part F — Close.** Guide finalised with real output and real failures, build log, ADR-020,
  project docs, handover, merge.

### Explicitly out of scope

- **Any change to `sshd`, `netplan`, `sudoers`, PAM, GRUB or `/etc/fstab`.** Tier 3.
- **Firewalling (`ufw`), `fail2ban`, AppArmor, auditd** — Phase 13.
- **Docker, containers, any service that persists past the phase** — Phase 05.
- **Shell scripting as a discipline** (functions, traps, argument parsing) beyond what the phase's
  own scripts demonstrate. `set -e` semantics are in scope because Phase 03 got them wrong.
- **Ethernet migration**, despite `eno1` sitting unused. Tempting, network-class, and not this
  phase's risk to take.
- **Extending the logical volume.** No free extents (§2). Documented, not demonstrated.
- **Backups.** Phase 13, and genuinely missing — say so rather than improvising one here.

## 8. Validation / tests

Every check produces output that is recorded. Nothing is marked done from expectation.

| # | Check | Passes when |
|---|---|---|
| 1 | Guide exercises were run | Every command block in the guide has real captured output somewhere in the build log |
| 2 | Permission reading | Owner correctly reads the mode/owner of the sshd drop-in and states the control it implements |
| 3 | Service diagnosis | A deliberately broken sandbox unit is diagnosed from `systemctl status` + `journalctl` alone, before the cause is revealed |
| 4 | Disk-full triage | `df -h`, `df -i` and a held-open deleted file are each demonstrated and distinguished |
| 5 | Journal querying | Filters by unit, boot, priority and time window all produce output; retention setting located |
| 6 | Package provenance | `dpkg -S` and `apt policy` correctly identify the origin of a Tailscale binary vs an Ubuntu one |
| 7 | Tooling installed | `tree`, `ncdu`, `rg` all report versions; each appears in an exercise |
| 8 | Sandbox guard rails | `lab-sandbox.sh` **refuses** `aleix`, `root`, a UID < 1000 and a `sudo` member — tested, with output |
| 9 | Sandbox teardown | After teardown: no `labuser` in `getent passwd`, no lab group, no lab unit, no scratch directory |
| 10 | `tmux` survival | A command started in `tmux` survives the SSH connection being closed and is reattached to |
| 11 | Preflight | `preflight.sh` reports both routes, session count and failed units — or its absence is recorded with reasoning |
| 12 | Access posture unchanged | `ssh -o PreferredAuthentications=none homelab` → `Permission denied (publickey)`, exactly as at phase start |
| 13 | `aleix` unchanged | `id aleix` identical to §2 |
| 14 | System health | `systemctl is-system-running` → `running`; `systemctl --failed` → 0 units. **Checked at the end, not the middle** |
| 15 | Both routes | `ssh homelab` and `ssh homelab-lan` both succeed with `BatchMode=yes` |
| 16 | Repo hygiene | No secrets, no tailnet suffix, no account email, no MAC addresses in anything committed |

Check 14 exists because Phase 01 passed every functional test on a quietly degraded machine.

## 9. Security considerations

- **The phase's main risk is self-inflicted lockout.** Mitigated by the three-tier model (§7.3) and
  the standard (§7.4). The tier boundaries are the security control; they are not advisory.
- **Creating a user is a privilege decision.** `labuser` gets no `sudo`, no SSH key, no password, and
  a non-login shell where possible. It exists to be looked at, not to be logged into remotely. This
  is ADR-011 in miniature.
- **Teardown is part of the exercise, not cleanup.** A forgotten practice account with a weak or
  absent password is exactly the kind of thing that survives into production. Check 9 exists for it.
- **`lab-sandbox.sh` must refuse dangerous targets rather than trust its caller.** `userdel -r` on
  the wrong name deletes a home directory. The guard rails are tested (check 8), not asserted.
- **Reading is not free either.** Exercises must never `cat` `/etc/netplan/50-wifi.yaml` into
  anything that gets committed — it holds the Wi-Fi passphrase in cleartext (ADR-016). The guide
  shows `ls -l` and `head -3` of a redacted example instead.
- **Third-party output carries identity.** Phase 03's verifier printed the owner's account email
  into a document meant for the repository. Anything in this phase that captures `tailscale status`,
  `journalctl`, or `ss` output for the repo is redacted **before** it is pasted, not after.
- **No new network exposure.** Nothing in this phase opens a port. `ss -tlnp` at the end must match
  §2.

## 10. Repository changes expected

| Path | Kind | Purpose |
|---|---|---|
| `docs/handovers/02-linux-fundamentals.md` | New | This brief |
| `guide/02-linux-fundamentals/README.md` | New | The guide |
| `docs/reference/linux-command-reference.md` | New | Operator cheatsheet, grouped by question |
| `docs/standards/safe-changes-headless.md` | New | The safe-change standard |
| `docs/decisions/ADR-020-*.md` | New | Change safety on a console-less node |
| `scripts/server/lab-sandbox.sh` | New | Disposable practice environment, with guard rails |
| `scripts/server/preflight.sh` | New (conditional) | Pre-change verification — or a recorded decision not to |
| `docs/build-log/2026-09-09-phase-02-*.md` | New | Real output, real failures |
| `docs/handovers/02-linux-fundamentals-handover.md` | New | Handover to Phase 04 |
| `AGENTS.md` | Modified | Reference the safe-change standard in the operating rules |
| `ROADMAP.md`, `CHANGELOG.md`, `guide/README.md`, `scripts/README.md` | Modified | Index the new material |
| `docs/reference/project-state.md`, `software-stack.md`, `costs.md` | Modified | Operational truth |
| `docs/handovers/README.md`, `docs/decisions/README.md` | Modified | Registers |

`MANIFEST.md` stays untouched — it is the bootstrap record, and lists no Phase 01 or 03 artifacts
either. `docs/architecture/current-architecture.md` is expected to need **no** change: this phase
teaches the architecture rather than altering it. If that turns out to be wrong, it is a scope
warning, not a documentation task.

## 11. Guide documentation required

`guide/02-linux-fundamentals/README.md`, following `docs/templates/guide-template.md`, for a reader
who is comfortable with computers but is not a systems administrator.

Non-negotiable properties:

- **Every example comes from this machine.** No `foo.txt`, no `/path/to/file`.
- **The two Phase 03 failures get a section each**, because both are cases where the obvious check
  agreed with us and was wrong: `sshd -T` reporting a setting the running daemon did not have, and a
  verifier comparing against the wrong systemd timestamp. These teach *how to be wrong carefully*,
  which is the actual subject of the phase.
- **"Reference-build experience" is filled in as the work happens**, not at the end. Phase 01 left
  it empty by design and it was worse for it.
- Concepts pass the §6.4 test: they explain something this project has done, or will do by Phase 05.

## 12. Project documentation required

- `docs/reference/project-state.md` — Phase 02 status, starting state for Phase 04, risk register.
- `docs/reference/software-stack.md` — `tree`, `ncdu`, `ripgrep` with versions and justification.
- `docs/reference/costs.md` — an explicit **0 DKK**, recorded rather than omitted.
- `docs/build-log/` — at least two entries, including every failure. `PROJECT.md` §11.
- `CHANGELOG.md`, `ROADMAP.md`, and the directory READMEs.
- `docs/handovers/02-linux-fundamentals-handover.md`, addressed to **Phase 04 — Git & GitHub
  Fundamentals**.

## 13. ADRs required / possible

| ADR | Subject | Expectation |
|---|---|---|
| **ADR-020** | Change safety policy for a console-less node | **Expected.** Constrains every future phase's method of working, which is precisely what an ADR is for |
| Baseline shell tooling | `tree`, `ncdu`, `ripgrep` | **Not warranted.** Three packages with stated reasons belong in `software-stack.md`. Recorded so the omission is visible |
| ADR-015 | Disk layout | **Referenced, not reopened.** The Phase 10 revisit trigger stands |
| ADR-018 / ADR-019 | SSH and tailnet | **Referenced as teaching material, not modified** |

## 14. Costs

**Expected: 0 DKK.** `tree`, `ncdu` and `ripgrep` are in Ubuntu's own repositories. No new hardware,
no subscription, no paid service. To be recorded as an explicit zero in `docs/reference/costs.md`
rather than left out — an omitted cost is indistinguishable from a forgotten one.

Reference-build running total is expected to stay at **899 DKK (~121 EUR)**.

## 15. Definition of Done

The project-wide checklist from `PROJECT.md` §12, applied literally, item by item.

- [ ] Functional objective works — all eight in §4
- [ ] Configuration/setup is reproducible — scripts run from the repository, not pasted
- [ ] Validation/tests have passed — all sixteen checks in §8, with real output
- [ ] Important security implications were considered — §9, and the tier model held
- [ ] Relevant repository files are committed
- [ ] Human-facing guide is updated — `guide/02-linux-fundamentals/README.md`
- [ ] Project/internal documentation is updated — state, stack, costs, build logs
- [ ] ADRs created or updated — ADR-020 expected
- [ ] Actual costs recorded — explicit 0 DKK
- [ ] Problems, failed approaches and lessons recorded — including any of mine
- [ ] Tested versions recorded — the three new packages, plus what was exercised
- [ ] No unexplained critical AI-generated component remains — both scripts commented for a reader
      who must be able to modify them safely
- [ ] `main` represents a known-working state — after merge of `feature/02-linux-fundamentals`
- [ ] System reports no failed units and no degraded state — **checked at the end**
- [ ] Structured handover written, stating what the next phase inherits

## 16. Return handover requirements

The handover to **Phase 04 — Git & GitHub Fundamentals** must state, explicitly:

1. **What the safe-change standard obliges future phases to do**, with a link, and the fact that
   `AGENTS.md` now points at it. Phase 04 is low-risk; Phase 05 is not.
2. **The verified end state**, from live output — access posture, health, users, tooling versions.
3. **Confirmation that the sandbox is gone**, by name, with the check that proves it.
4. **Open risks carried forward**, unchanged unless this phase changed them: single SSH key with no
   backup and no console; no firewall; no encryption at rest; node key expiry disabled; Wi-Fi as a
   single point of failure for both routes; no free extents in the volume group.
5. **What Phase 02 did *not* teach**, so Phase 04 does not assume it: no networking changes were
   practised, no `sudoers` editing, no firewalling, no backup or restore, and no LVM growth.
6. **Decisions that must not be silently inherited** — in particular that Tier 3 was a deliberate
   deferral of real learning, not a claim that those topics are covered.
7. **Whether `preflight.sh` was written**, and if not, why not.
8. **Every failure**, with what was learned. `PROJECT.md` §11: do not rewrite history to look linear.
