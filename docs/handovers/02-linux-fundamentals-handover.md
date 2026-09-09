# Phase 02 Handover — Linux Fundamentals

- **Date:** 2026-09-09
- **From:** Phase 02 phase context
- **To:** Phase 04 — Git & GitHub Fundamentals
- **Brief:** [`02-linux-fundamentals.md`](02-linux-fundamentals.md), committed before implementation per ADR-017

## Outcome

**Complete.** All eight functional objectives met, every validation check run against live output.
The node ends the phase in exactly the access posture it started in.

## What the next phase inherits

> Read this section first. Under ADR-017 there is no planning context to reconcile any of it; if it
> is not written here, it is lost.

### 1. There is now a standard you are obliged to follow

[`docs/standards/safe-changes-headless.md`](../standards/safe-changes-headless.md), adopted as
[ADR-020](../decisions/ADR-020-change-safety-headless.md), and referenced from `AGENTS.md`'s
operating rules — so you inherit it by reading a file you are already required to read.

It binds **every phase from 02 onward**, not just this one. A change is *lockout-class* if it touches
network, remote access, authentication, boot, or the admin account. Classification is the control;
the checklist only helps once you have noticed it applies.

**Phase 04 is low-risk** — it changes the repository, not the node — so you will probably not need
the procedure. **Phase 05 will.** Docker rewrites `iptables` rules and creates bridge interfaces, on
a machine reachable only over the network. Phase 13 is worse: a firewall is the most lockout-prone
change in the whole roadmap.

`scripts/macos/preflight.sh` mechanises the machine-checkable parts. It runs on the MacBook
deliberately — a script on the server is inside the thing it is meant to be testing.

### 2. Verified end state

Captured 2026-09-09 at phase close, from live output.

| Fact | Value |
|---|---|
| Host | `homelab`, Lenovo M700 Tiny |
| OS / kernel | Ubuntu 26.04.1 LTS, `7.0.0-31-generic` |
| systemd / bash / tmux | 259 / 5.3.9(1) / 3.6 |
| Primary access | `ssh homelab` → MagicDNS over Tailscale |
| Fallback access | `ssh homelab-lan` → `192.168.1.57` |
| **Authentication** | **`Permission denied (publickey)`** — asked of the running server, not of `sshd -T` |
| Both routes | Verified with `BatchMode=yes`; both succeed |
| Health | `systemctl is-system-running` → `running`; **0** failed units |
| Listening | `:22` only off-box; everything else on loopback or the tailnet — **identical to phase start** |
| `aleix` | `uid=1000 … 4(adm),24(cdrom),27(sudo),30(dip),46(plugdev),100(users),101(lxd)` — **byte-identical to phase start** |
| Human users | Still exactly one |
| Root filesystem | 232 G, 4% used, 1% inodes |
| `sudo` | Still requires a password. No `NOPASSWD` |
| Console | **None.** All DRM connectors `disconnected` |
| New packages | `tree` 2.3.1-1, `ncdu` 1.22-1build1, `ripgrep` 15.1.0-1ubuntu1 |

### 3. The sandbox is gone, and here is the proof

Phase 02 created a disposable `labuser`, `labgroup`, `/srv/lab` and `homelab-lab.service`, exercised
them, and removed them. Verified four ways:

```text
$ bash lab-sandbox.sh status
  user absent · group absent · directory absent · unit absent
$ getent passwd labuser   → exit 2
$ getent group labgroup   → exit 2
$ ls -ld /srv/lab         → No such file or directory
$ systemctl --failed --no-legend | wc -l → 0
```

Nothing from this phase persists on the node except three diagnostic packages.

### 4. Open risks, and who closes them

Unchanged by this phase unless noted.

| Risk | Owner |
|---|---|
| **Single SSH key, no backup, no console.** Still the most consequential item | Phase 13 |
| No firewall; `:22` open on the LAN and answering | Phase 13 |
| No encryption at rest (ADR-015); Wi-Fi passphrase cleartext | Phase 13 — **Phase 10 must revisit ADR-015 first** |
| Node key expiry deliberately disabled (ADR-019) | Phase 13 must revisit on its merits |
| Wi-Fi is a single point of failure for **both** access routes; `eno1` present, unused | Not owned by any phase |
| 2016 firmware | Phase 13, low priority |
| **New:** the volume group has no free extents — storage cannot be grown by `lvextend` | Not owned by any phase |

**ADR-020 does not close the lockout risk.** It makes lockout-class changes recoverable *while
remote access still works*. If remote access is lost, the answer is still the drawer. Phase 13 owns
the actual recovery path.

### 5. What Phase 02 did NOT teach — do not assume it

The phase classified every exercise by blast radius, and **Tier 3 was studied by reading, not by
changing**. That was a deliberate deferral, not a claim of coverage:

- **No networking changes were practised.** `netplan`, `systemd-networkd`, Wi-Fi — read only.
- **No `sudoers` editing.** `visudo` is documented; it was not used.
- **No firewalling, no `ufw`, no `iptables`.**
- **No backup or restore of anything.** The project still has no backup story at all.
- **No LVM growth**, because the volume group has no free extents.
- **No PAM, GRUB or fstab changes.**

If a later phase needs one of these, it is learning it for the first time, under real conditions.
Budget for that rather than assuming the fundamentals phase covered it.

### 6. Decisions that must not be silently inherited

- **The three-tier classification is a security control**, not a teaching device. Tier 3 exists
  because the cost of getting netplan wrong is now physical.
- **`preflight.sh` lives in `scripts/macos/` on purpose.** Moving it server-side would quietly break
  the only check that proves a *new* connection can arrive.
- **The `10-` prefix on the sshd drop-in is still a security control** (inherited from Phase 03, and
  now a worked example in the guide). Renumbering it above `50-` re-enables passwords.
- **`systemctl reload ssh` is still required** for sshd configuration to take effect. Also inherited,
  also now a worked example.
- **Baseline tooling deliberately has no ADR.** Three packages with stated reasons live in
  `software-stack.md`. If a later phase adds tools by the dozen, that judgement should be revisited.
- **The sudo-group guard in `lab-sandbox.sh` is untested.** See §8.

### 7. Ground covered — build on it

| Topic | Worked example now available |
|---|---|
| Permissions | `0600 root:root` on the sshd drop-in, proved by `cat` failing as `aleix`; setgid shown by one command producing two different groups |
| Users & groups | A real account created, exercised and destroyed, with the guard rails tested |
| Services | `Accept=no`, `ExecReload`, `KillMode=process`, `Type=oneshot`, `static`, `Drop-In:`, `status=203/EXEC`, `reset-failed` |
| Packages | `apt policy` separating Ubuntu from Tailscale; `signed-by=` as the control; `dpkg -S` |
| Logs | `journalctl` by unit, boot, priority and window; the node's *normal* error noise identified |
| Storage | Bytes vs inodes vs deleted-but-open files; the LVM stack; no free extents |
| Networking | Four links read; `ss -tlnp` as the honest answer to "what is exposed" |
| Shell | Exit status, redirection, `set -e` in `&&` lists |
| tmux | Proved to survive disconnection across three separate SSH connections |

### 8. Phase 04 must write and commit its own brief first

`docs/handovers/04-git-github.md`, from `docs/templates/phase-brief-template.md`, committed
**before** implementation (ADR-017). Nobody else will write it.

Two specific things for Phase 04 to decide, because this phase bumped into both:

1. **The repository has no remote.** Nothing has ever been pushed. Phase 04 is where that becomes a
   real decision — public or private, owner and name, and what the license is. `project-state.md`
   lists both as known unknowns.
2. **This repository is intended to become public.** Phase 03 already had to tighten what gets
   committed after a tailnet suffix and an account email leaked into repo-bound output. Before a
   first push, Phase 04 should scan the **whole history**, not just the working tree — a secret
   removed in a later commit is still in the history.

## What was implemented

A guide that teaches Linux from this machine's own files; an operator command reference grouped by
the question being asked; a change-safety standard with an ADR behind it; two scripts, both run on
the real machine; and three diagnostic packages. The node was left as it was found.

## Validation performed

| Check | Result |
|---|---|
| Permissions read and enforced | `-rw------- root:root`; `cat` as `aleix` → `Permission denied` |
| Disk triage | Bytes 4%, inodes 1%, deleted-but-open file shown in `/proc/*/fd` |
| Journal querying | `-u`, `-b`, `-p err`, `--since`, `--list-boots` all returned output |
| Package provenance | `pkgs.tailscale.com/…/resolute` vs `archive.ubuntu.com` |
| Socket semantics | `Accept=no`; `ExecReload` = `sshd -t` then `kill -HUP` |
| Tooling | `tree v2.3.1`, `ncdu 1.22`, `ripgrep 15.1.0` |
| **Sandbox create guards** | All three refusals fired |
| **Sandbox delete guard** | Refused a tampered account **and destroyed nothing** — unit and directory still present afterwards |
| Sandbox teardown | Absent four ways (§3) |
| Deliberate unit breakage | `203/EXEC`, diagnosed from `status` + `journalctl`, repaired, `--failed` → 0 |
| **tmux survives disconnection** | Job kept running across three separate SSH connections |
| `preflight.sh` | Both routes, session count, health, disk, Wi-Fi, tailnet |
| Access posture | `Permission denied (publickey)` — asked of the running server |
| `aleix` unchanged | Byte-identical to phase start |
| No new exposure | `ss -tln` identical to phase start |
| System health | `running`, 0 failed units — checked **last** |

## Problems / failures / lessons

Seven recorded across the two build-log entries. The four that matter beyond this phase:

- **`who` reports zero sessions and exits 0.** systemd 257 removed utmp support; Ubuntu 26.04 ships
  259, so `/run/utmp` does not exist. It was being used for the most important check in the new
  standard. **A check that fails by returning "nothing" is more dangerous than one that errors** —
  the same shape as Phase 03's `sshd -T`. Checks now report *unknown* rather than *zero*.
- **A guard that fires after the first destructive step is not a guard, it is a report.**
  `lab-sandbox.sh` deleted the unit before validating the account. Found by reading the code path,
  fixed by validating before acting, and the test now checks *what was not destroyed*.
- **`systemd-analyze verify` reports the whole dependency closure**, so a clean unit can look broken.
- **Automation on this node stops at the `sudo` boundary.** Second phase running in which every
  privileged step had to be handed to the owner.

Two of my own errors are recorded rather than quietly corrected: the brief specified `preflight.sh`
for the wrong machine, and it named `/etc/netplan/50-wifi.yaml`, which does not exist — that is the
name of the redacted example in this repository, and the brief was written from the repo rather than
from the machine.

## Deviations from phase brief

1. **`preflight.sh` moved from `scripts/server/` to `scripts/macos/`.** The check that matters is
   whether a *new* connection can arrive, and a script on the server cannot answer that.
2. **The brief's §6.2 asked whether `preflight.sh` earns its existence.** Answer: **yes** — it counts
   interactive sessions and proves both routes from outside, neither of which a printed checklist can
   do. Its limits are stated in its own header.
3. **Storage was taught by inspection**, as the brief anticipated, because the volume group has no
   free extents.
4. **The sudo-group guard could not be tested.** Recorded as untested rather than counted as passing.

## Open issues / technical debt

- **`lab-sandbox.sh`'s sudo-group guard is untested.** `aleix` is the only sudo member and the
  by-name check fires first, so the branch is unreachable without manufacturing a second sudoer —
  an authentication-class change ADR-020 says not to make for convenience.
- **No backup story exists**, for the repository or the node. Increasingly conspicuous.
- **The volume group has no free extents.** Growing storage means adding a disk.
- **`vm.swappiness` still 60** (inherited from Phase 01; Phase 05 trigger).
- **`eno1` still unused**, so both access routes still share one Wi-Fi adapter.
- **2.4 GHz / 802.11n on an 802.11ac-capable adapter** (inherited from Phase 01).

## ADRs

| ADR | Status | Note |
|---|---|---|
| ADR-020 — change safety on a console-less node | **Accepted** | Binds every phase from 02 onward; referenced from `AGENTS.md` |
| ADR-011 — privilege separation | Referenced | The sandbox user is it in miniature |
| ADR-015 / 016 / 018 / 019 | Referenced as teaching material, unmodified | |

## Tested versions

| Component | Version |
|---|---|
| Ubuntu Server / kernel | 26.04.1 LTS (`resolute`) / 7.0.0-31-generic |
| systemd | 259 (259.5-0ubuntu3.4) |
| bash | 5.3.9(1)-release |
| tmux | 3.6 |
| lsof | 4.99.4 |
| tree | 2.3.1-1 |
| ncdu | 1.22-1build1 |
| ripgrep | 15.1.0-1ubuntu1 |

Nothing is version-critical **except** the `who`/utmp behaviour, which needs systemd ≥ 257 to
reproduce.

## Costs

**0 DKK**, recorded as an explicit zero. All three packages are in Ubuntu's own repositories
(1,671 kB). Reference-build running total unchanged at **899 DKK (~121 EUR)**.

## Recommended roadmap changes

Actioned directly, since ADR-017 leaves no recipient:

1. **Phase 02 marked complete** in `ROADMAP.md`, with what it deliberately did not teach listed
   inline so later phases cannot assume it.
2. **The no-free-extents constraint** added to the risk register in `project-state.md`.
3. **Phase 05 should apply ADR-020 explicitly.** Docker rewrites firewall rules and creates bridge
   interfaces on a console-less machine; that is lockout-class by the standard's own definition.

No phase renumbering required.

## Definition of Done

- [x] Functional objective works — all eight in §4 of the brief
- [x] Configuration/setup is reproducible — both scripts run from the repository, transferred by
      `scp` with SHA256 verified on both sides, never pasted
- [x] Validation/tests have passed — every check above, with captured output
- [x] Important security implications were considered — the tier model held; no new exposure
- [x] Relevant repository files are committed
- [x] Human-facing guide is updated — `guide/02-linux-fundamentals/README.md`
- [x] Project/internal documentation is updated — state, stack, costs, roadmap, changelog, two build logs
- [x] ADRs created or updated — ADR-020 accepted; tooling ADR deliberately declined and recorded
- [x] Actual costs recorded — explicit 0 DKK
- [x] Problems, failed approaches and lessons recorded — seven, including two of my own errors and
      one guard recorded as untested
- [x] Tested versions recorded
- [x] No unexplained critical AI-generated component remains — both scripts commented for a reader
      who must be able to modify them safely
- [x] `main` represents a known-working state — after merge of `feature/02-linux-fundamentals`
- [x] System reports no failed units and no degraded state — verified **last**, after teardown
- [x] Structured handover written, stating what the next phase inherits
