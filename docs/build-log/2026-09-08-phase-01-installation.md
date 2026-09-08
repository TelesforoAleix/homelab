# Build Log — Phase 01 Installation (Parts B–F)

- **Date:** 2026-09-08
- **Phase:** 01 — Ubuntu Server
- **Branch:** `feature/01-ubuntu-server`
- **Status:** Complete — all Definition of Done validation passed

## Starting state

Phase 00 closed. Firmware configured in Part D (virtualization enabled, `After Power Loss → Power
On`, UEFI preserved). Installation USB prepared. The M700 still held its original Windows install.

## Objective

Install Ubuntu Server, verify the result from live output, and prove the machine behaves as an
always-on node rather than a computer that happens to be switched on.

## Actions taken

1. Booted the installer, configured Wi-Fi, installed with guided whole-disk LVM and no encryption.
2. First boot: full package upgrade, extended the root logical volume, installed `dmidecode`/`iw`.
3. Installed the Wi-Fi power-save systemd unit from the repository.
4. Captured state with `scripts/server/verify-install.sh`.
5. Ran the unattended AC power-loss recovery test.
6. Diagnosed and fixed a failed boot unit found by the post-test health check.

## Validation

| Check | Result |
|---|---|
| Release | Ubuntu 26.04.1 LTS, codename `resolute` — matches ADR-014 |
| Kernel | 7.0.0-31-generic |
| LVM | `ubuntu-vg` fully allocated, `VFree 0` after extension |
| Root filesystem | 232 GB, 214 GB available |
| Windows removed | No NTFS/BitLocker partitions found |
| UEFI boot | `sda1` FAT32 mounted at `/boot/efi` |
| RAM layout | `dmidecode`: 8 GB Samsung `M471A1K43BB0-CPB` in ChannelA-DIMM0; ChannelB empty |
| CPU virtualization | `Virtualization: VT-x` — confirms the Part D firmware change |
| Wi-Fi | `wlp1s0` associated, −55 dBm, power save off |
| netplan permissions | `0600`, set by the installer |
| SSH | `ssh.socket` enabled; reachable from the MacBook |
| Automatic updates | `unattended-upgrades` active, `apt-daily-upgrade.timer` scheduled |
| **Power-loss recovery** | **PASSED** — see below |
| System health | `systemctl is-system-running` → `running` |
| Boot time | 23.0s total, 4.4s userspace |

### The unattended AC power-loss recovery test

Power cable pulled with no monitor interaction, restored, power button **not** pressed. All four
required criteria held:

1. booted with no physical interaction;
2. rejoined Wi-Fi unattended — and on the same address;
3. SSH started by itself;
4. reachable from the MacBook.

Passed on the first attempt.

## Problems / failed approaches

**1. "An error occurred during installation" — benign, but only provably so after reading the log.**

- *Assumption:* an installer error means a broken install.
- *What happened:* the message appeared, yet the system installed and booted correctly. The log
  showed a single traceback: `checking for snap update failed`, an `HTTPError: 500` from snapd when
  subiquity asked whether a newer version of **itself** was available. It ran before Wi-Fi was
  configured, so there was no network to reach the snap store. The next log line reads
  `finish: subiquity/Refresh/check_for_update: SUCCESS` — handled and non-fatal by design.
- *What we learned:* installer error text does not distinguish "your install is broken" from "an
  optional pre-flight step failed". The log does. The `subiquity-server-info.log` (11 KB) is far more
  useful than the debug log (251 KB) for this.
- *What changed:* nothing in the system. Recorded so the same message does not cause alarm later.

**2. Guided LVM allocated 100 GB of a 235 GB volume group.**

Predicted in the guide, and it happened exactly as described. Fixed live with `lvextend` +
`resize2fs` — no unmount, no reboot. This was ADR-015's LVM choice paying for itself within an hour
of the decision.

**3. The terminal split pasted commands at ~65 characters — three times.**

- *Assumption:* commands could be given at any reasonable length.
- *What happened:* long lines arrived broken in two. `grep PATTERN` + a filename on the next line
  left `grep` reading from the keyboard and appearing to hang; the next line was executed as a
  command, producing a misleading `Permission denied`. Worst case, a `sudo tee … <<'UNIT'`
  here-document lost its `<<'UNIT'`, so `tee` consumed the unit file's contents as stdin and wrote a
  corrupt file.
- *What we learned:* an apparently hung command is usually one waiting on input. `Ctrl+C` returning
  the prompt instantly proves it was waiting, not working — a much better diagnostic than guessing
  that a 4-core machine is "slow".
- *What changed:* two things. Commands are kept short. More importantly, **configuration that
  belongs in the repository is now copied from the repository** rather than typed at a prompt:
  `config/systemd/wifi-powersave-off.service` and `config/netplan/99-eno1-optional.yaml` are files,
  `scp`'d into place. That is more reproducible, reviewable, and immune to terminal behaviour.

**4. `systemd-networkd-wait-online` failed on every boot, costing two minutes.**

- *Assumption:* a machine that boots and answers SSH is healthy.
- *What happened:* `systemctl is-system-running` reported **`degraded`**. `networkctl` showed the
  unused Ethernet port `eno1` at `no-carrier / configuring`, and `wait-online` waits for *every*
  managed link. Journal timestamps show the full 120-second timeout on both boots. Anything ordered
  `After=network-online.target` — including this project's own Wi-Fi power-save unit — started that
  late.
- *What we learned:* "reachable over SSH" is not a health check. This defect was completely invisible
  from the outside and would have persisted indefinitely. The Definition of Done asking for
  `systemctl is-system-running` is what caught it.
- *What changed:* `config/netplan/99-eno1-optional.yaml` marks the interface `optional: true`. Boot
  time fell from roughly 145 seconds to **23.0 seconds**, and the system now reports `running`.

**5. The guide's own instructions created a privilege-escalation risk.**

- *Assumption:* `sudo mv` into a system directory is sufficient.
- *What happened:* `scp` copies as the invoking user and `sudo mv` **preserves that ownership**, so
  `/etc/systemd/system/wifi-powersave-off.service` ended up owned by `aleix`, not `root`. systemd
  executes unit files as root.
- *What we learned:* a file that a non-root user can rewrite, which root then executes, is a
  privilege-escalation path. Not exploitable here — the owner is the only user and already
  sudo-capable — but the instruction was wrong and would be dangerous on a multi-user host.
- *What changed:* `chown root:root` added to the guide and to both config files' embedded
  instructions, and `verify-install.sh` now actively reports any non-root-owned file in
  `/etc/netplan` and `/etc/systemd/system` so this class of error is caught rather than noticed.

**6. `verify-install.sh` reported SSH misleadingly.**

It printed `ssh … enabled=disabled` without checking `ssh.socket`. Modern Ubuntu uses socket
activation, so that output is normal — but read literally it says SSH will not survive a reboot.
The script now checks `ssh.socket` and explains socket activation inline. A bug found only by using
the tool for real.

**7. The netplan `chmod` was unnecessary.**

The 26.04.1 installer already writes `/etc/netplan/00-installer-config.yaml` as `0600`. The guide
taught this as a fix; it is now a **verification**, with the filename corrected — the guide had
claimed `50-cloud-init.yaml`.

**8. The DHCP reservation could not be made.**

No router administration access. Recorded as an unsatisfied ADR-016 control rather than dropped. A
static address was rejected (the DHCP pool boundaries on this `/21` are unknown, so a conflict was
a real risk) and mDNS was rejected as solving a problem that has not occurred. Tailscale in Phase 03
supersedes it. Notably, the address survived the power-cut test unchanged.

## What we learned

- The most valuable checks were the ones that looked redundant. SSH worked, the machine was
  reachable, and it still had a failed unit and a two-minute boot penalty.
- Writing the guide before the install was worth it: the LVM under-allocation and the keyboard-layout
  trap were both predicted and both mattered. But **using** the guide found five defects in it that
  no amount of pre-writing would have surfaced.
- Configuration belongs in files, not in pasted commands. That principle emerged from a terminal
  quirk, but it is the correct engineering answer regardless.

## Decisions / ADRs

- ADR-014, ADR-015, ADR-016 — all **Accepted**, all validated in practice.
- ADR-016 gains an unsatisfied-control record for the DHCP reservation.
- No new ADR required. Local decisions (hostname, username, Secure Boot, swap) recorded in
  `docs/reference/project-state.md`.

## Costs

**None.** Ubuntu Server is free; the install reused existing hardware. No RAM upgrade was required —
Part A confirmed a free DIMM slot, and the base system uses 542 MB of 7.1 GB.

## Next

Phase 02 (Linux Fundamentals) and Phase 03 (Remote Access). Phase 03 closes this phase's principal
open risk: SSH password authentication.
