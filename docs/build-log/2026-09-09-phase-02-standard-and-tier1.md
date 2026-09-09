# Build Log — Phase 02 Parts A–B: the safe-change standard, and reading the system

- **Date:** 2026-09-09
- **Phase:** 02 — Linux Fundamentals
- **Branch:** `feature/02-linux-fundamentals`
- **Status:** Complete

## Starting state

`main` at `5804da6`, Phase 03 merged. The reference node running Ubuntu 26.04.1 LTS, kernel
7.0.0-31-generic, systemd 259, reachable only over SSH with keys, **no console attached**, health
`running` with 0 failed units, 0 pending package upgrades, and exactly one human user.

## Objective

Parts A and B of the phase: adopt an operating standard for making changes on a machine with no
console, and work through the read-only (Tier 1) half of the syllabus capturing real output.

## Actions taken

1. **Read the inbound handover, `PROJECT.md` §12–13, ADR-017, the templates and `ROADMAP.md`.**
   Confirmed Phase 02 keeps its number despite running third.

2. **Asked the owner two scope questions before writing the brief**, both of which change what gets
   built: deliverable shape (guide + exercises actually run, versus documentation-only or full
   hands-on including networking), and whether to install shell tooling. Answers: guide + safe
   hands-on exercises; a small justified toolset.

3. **Captured the starting state from live output** rather than from the previous handover, which is
   how the volume-group constraint below was found.

4. **Wrote and committed the brief** as `6ddf2a5`, before any implementation existed, per ADR-017.

5. **Wrote `docs/standards/safe-changes-headless.md` and ADR-020**, and referenced the standard from
   `AGENTS.md` so future phase contexts inherit it by reading a file they must already read.

6. **Wrote `scripts/macos/preflight.sh`** and `scripts/server/lab-sandbox.sh`. Copied the sandbox
   script to the node with `scp` and verified SHA256 on both sides
   (`5b8ec1ed14de5cb657bec4fa908a0e8232e4238ae0707b907b252744c6a4ff10`) — configuration and scripts
   are transferred, never pasted.

7. **Ran the Tier 1 exercises** over `ssh homelab`: filesystem layout, permission reading, package
   provenance, socket/service semantics, journal querying, storage triage, read-only networking,
   process inspection, shell semantics, and tmux survival.

## Validation

| Check | Result |
|---|---|
| Modes on the sshd drop-ins | `-rw------- root:root` on both — matching ADR-018, not the `0644` Phase 03 first documented |
| Mode actually enforces | `cat` as `aleix` → `Permission denied` |
| First-match-wins evidence | `50-cloud-init.conf` is 27 bytes = exactly `PasswordAuthentication yes` |
| Bytes vs inodes | 4% / 1% — independent budgets, both captured |
| Deleted-but-open file | 200 MB invisible to `du`, visible as `/proc/3113/fd/9 -> …/big.bin (deleted)` |
| Journal queries | `-u`, `-b`, `-p err`, `--since`, `--list-boots` all returned output; 24 MB persistent |
| Package provenance | `apt policy` separated `pkgs.tailscale.com/…/resolute` from `archive.ubuntu.com` |
| Socket semantics | `Accept=no`; `ExecReload` = `sshd -t` then `kill -HUP $MAINPID`; `KillMode=process` |
| Networking, read-only | 4 links; `eno1` `no-carrier`; `tailscale0` `unmanaged`; only `:22` reachable off-box |
| `set -e` in `&&` lists | Reproduced both halves: non-final link ignored, bare command aborts |
| **tmux survives disconnection** | Job started in a detached session kept ticking across **three separate SSH connections** — `tick 6` on the second, `tick 11` on the third |
| `preflight.sh` end to end | Both routes ok, 2 interactive sessions, health running, 0 failed units |

## Problems / failed approaches

### 1. `who` reports zero sessions on a machine carrying six, and exits 0

The most important check in `preflight.sh` is whether a second session is held open, since an
established connection survives a broken `sshd` and a new one may not. Implemented as `who | wc -l`.

It returned `0` — with `w` simultaneously reporting `6 users`.

```text
$ who ; echo $?
0
$ ls -l /run/utmp
ls: cannot access '/run/utmp': No such file or directory
$ systemctl --version | head -1
systemd 259 (259.5-0ubuntu3.4)
```

**Cause:** `who` reads `/run/utmp`. systemd 257 removed utmp support and Ubuntu 26.04 ships
systemd 259, so the file does not exist. `who` finds nothing and reports nothing, successfully.

**Fix:** count sessions with `w -h | awk '$2 ~ /^pts\//'`, which falls back to logind and filters to
sessions holding a pseudo-terminal — so the script's own non-TTY connection is correctly excluded.
The script now also reports **unknown** rather than **zero** when `w` produces no rows at all.

Two failed intermediate attempts are worth recording. First I raised the threshold to `> 1` on the
theory that the script's own connection was being counted — wrong, and it would have hidden the bug
behind a plausible number. Then I opened a backgrounded `ssh -tt … sleep 45` to force a TTY and
re-ran the check, which still reported 0; only then did I look at `/run/utmp`.

This is the same failure shape as Phase 03's `sshd -T`: **a check that answered an adjacent question
and agreed with us.** It is now recorded in the standard itself, since it was aimed squarely at that
document's most important step.

### 2. The brief specified `preflight.sh` for the wrong machine

Placed in `scripts/server/`. Writing it made the error plain: the question is whether a *new*
connection can arrive, and a script on the server is inside the thing being tested. Moved to
`scripts/macos/`; route checks now run from outside, host state is gathered in one SSH round trip.

### 3. The brief named a netplan file that does not exist

`/etc/netplan/50-wifi.yaml`. The real files are `00-installer-config.yaml` and
`99-eno1-optional.yaml`. `50-wifi.example.yaml` is the **repository's redacted example**, and the
brief was written from the repository rather than from the machine. Harmless, and a precise little
demonstration of how documentation drifts away from reality.

### 4. `systemd-analyze verify` reported warnings from an unrelated unit

`systemd-analyze verify ssh.service` printed deprecation warnings about `xfs_scrub_all.service` and
`system-xfs_scrub.slice`. `verify` walks the dependency closure, not just the named unit. Not a
fault, but a clean unit can look broken if you do not read the filename on each line.

### 5. The volume group has no free extents

```text
└─sda3                    235.4G part LVM2_member
  └─ubuntu--vg-ubuntu--lv 235.4G lvm  ext4  /
```

The root LV consumes the entire VG, so the textbook `lvextend`/`resize2fs` exercise is impossible
here without shrinking a mounted root filesystem — the exact class of operation a console-less node
must not attempt. Recorded as a limitation of the reference build. Phase 01 used the whole disk,
which is defensible for a single-purpose node but removes the main benefit people install LVM for.

### 6. `tree`, `ncdu` and `ripgrep` needed the owner

No `NOPASSWD` on this node. Second phase running in which every privileged step has to be handed
over; worth stating for later phases that automation here stops at the `sudo` boundary.

## What we learned

- **A configuration file is not a control until the process holding it has re-read it** — carried
  forward from Phase 03 and now written into a standard rather than a handover.
- **A check that fails by returning "nothing" is more dangerous than one that errors.** Both of this
  project's worst diagnostic failures — `sshd -T` and now `who` — returned confident, plausible,
  wrong answers rather than complaining.
- **Long-stable tools do change.** `who` has behaved consistently for fifty years and is wrong on
  this machine.
- **`ss -tlnp` is the honest answer to "what is exposed."** Firewall rules are a claim about intent;
  the listening socket list is what is actually true.
- The node's *normal* error noise — three cosmetic kernel messages about 2016 firmware and an unused
  Bluetooth radio — is worth knowing, so a fourth stands out.

## Decisions / ADRs

- **ADR-020 — Change safety policy for a console-less node.** Accepted. Adopts
  `docs/standards/safe-changes-headless.md` as binding on every phase from 02 onward.
- Baseline shell tooling was considered for an ADR and deliberately **not** given one — three
  packages with stated reasons belong in `software-stack.md`. Recorded so the omission is visible.

## Costs

**None.** All three tools are in Ubuntu's own repositories.

## Next

Parts C–D: install the tooling, test the sandbox guard rails, run the Tier 2 exercises, and tear the
sandbox down. All require the owner's `sudo`.
