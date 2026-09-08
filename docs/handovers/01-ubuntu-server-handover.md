# Phase 01 Handover — Ubuntu Server

- **Date:** 2026-09-08
- **From:** Phase 01 working context
- **To:** Project Planning
- **Brief:** [`01-ubuntu-server.md`](01-ubuntu-server.md) (ratified 2026-09-08, six amendments, all reconciled)

## Outcome

**Complete.** Every applicable Definition of Done item is satisfied, including the unattended AC
power-loss recovery test, which passed on the first attempt.

## What was implemented

The reference node runs Ubuntu Server 26.04.1 LTS, installed on whole-disk LVM without encryption,
networked over Wi-Fi, reachable over SSH from the MacBook, and able to return to service unattended
after a power cut. Windows is entirely removed.

## Final architecture/state

```text
MacBook Pro  ──ssh(password)──►  homelab / 192.168.1.57  (Lenovo M700 Tiny)
                                 Ubuntu Server 26.04.1 LTS, kernel 7.0.0-31
                                 UEFI · LVM (no FDE) · 232 GB root
                                 Wi-Fi wlp1s0 (2.4 GHz) · eno1 unused
                                 boots unattended in 23s after power loss
```

First phase in which a deliberately deployed component exists;
`docs/architecture/current-architecture.md` updated accordingly.

## Validation performed

| Check | Result |
|---|---|
| Release / kernel | Ubuntu 26.04.1 LTS `resolute` / 7.0.0-31-generic |
| Windows removed | No NTFS or BitLocker partitions |
| UEFI boot | ESP present at `/boot/efi` |
| LVM | Fully allocated, `VFree 0`; root 232 GB, 214 GB free |
| RAM layout | 1 × 8 GB Samsung `M471A1K43BB0-CPB`, ChannelB empty |
| CPU virtualization | `VT-x` present — confirms the firmware change |
| Wi-Fi | Associated at −55 dBm, power save off, reconnects unattended |
| SSH | `ssh.socket` enabled; reachable from the MacBook |
| Automatic security updates | Active and scheduled |
| **Power-loss recovery** | **Passed all four criteria** |
| System health | `running` (after fixing a failed unit — see Problems) |
| Boot time | 23.0s, down from ~145s |

## Files changed

- `guide/01-ubuntu-server/README.md` — full phase guide
- `docs/handovers/01-ubuntu-server.md` — brief; this handover
- `docs/decisions/ADR-014`, `ADR-015`, `ADR-016`
- `scripts/macos/download-ubuntu-iso.sh`, `write-ubuntu-usb.sh`
- `scripts/server/verify-install.sh`
- `config/systemd/wifi-powersave-off.service`
- `config/netplan/99-eno1-optional.yaml`, `50-wifi.example.yaml`
- `docs/reference/{hardware,software-stack,project-state,costs}.md`
- `docs/build-log/` — three entries
- `ROADMAP.md`, `PROJECT.md`, `CHANGELOG.md`

## Guide updates

The guide was written before the install and then **corrected five times by using it**:

1. Wi-Fi power-save unit ships as a repo file instead of a here-document.
2. netplan permissions are a verification, not a fix; filename corrected.
3. New section: the `systemd-networkd-wait-online` boot delay.
4. `chown root:root` added after moving files into system directories.
5. Power-loss test clarified — the monitor may stay attached; it forbids interaction, not a display.

## Project documentation updates

`hardware.md` (fully verified, plus firmware age and wireless characteristics), `software-stack.md`
(Planned → Active with tested versions), `project-state.md`, `costs.md`, three build-log entries,
`current-architecture.md`.

## ADRs

| ADR | Status | Note |
|---|---|---|
| ADR-014 — Ubuntu release | Accepted | *Requires* any supported LTS; *Tested with* 26.04.1. Validated. |
| ADR-015 — LVM, no FDE | Accepted | Validated: LVM allowed a live root resize within the hour. |
| ADR-016 — Wi-Fi initial link | Accepted | Validated by the power-loss test. One control unsatisfied — see below. |

No new ADR required.

## Tested versions

| Component | Version |
|---|---|
| Ubuntu Server | 26.04.1 LTS (Resolute Raccoon) |
| Linux kernel | 7.0.0-31-generic |
| OpenSSH server | OpenSSH_10.2p1 Ubuntu-2ubuntu3.6 (OpenSSL 3.5.5) |
| systemd | 259 |
| netplan | 1.2-1ubuntu5 |
| wpasupplicant | 2:2.11-0ubuntu5 |
| intel-microcode | 3.20260210.1ubuntu2 |

## Security notes

Controls introduced: unprivileged sudo-capable admin user, no direct root login
(`permitrootlogin prohibit-password`), automatic security updates verified active, netplan config at
`0600`, root-owned system files, `intel-microcode` confirmed active.

**Risks carried into Phase 03:**

1. **SSH password authentication is enabled.** The phase's principal open risk, time-boxed to
   Phase 03. Do not port-forward SSH from the router before then.

**Risks carried into Phase 13:**

2. **No encryption at rest** (ADR-015). Compounds with the cleartext Wi-Fi passphrase. Phase 10 must
   not silently inherit this — see the ADR's revisit trigger.
3. **Firmware from 2016** (`FWKT63A`). CPU-level exposure is mitigated by `intel-microcode`;
   platform-level fixes are not. Low priority for a LAN node behind NAT.
4. **No firewall.** UFW is Phase 13.

## Costs

**199 DKK (~27 EUR)**, one-time: a DisplayPort→HDMI cable, required to attach a monitor for the
installation. The M700 Tiny outputs DisplayPort while most monitors take HDMI.

No recurring or usage-based cost. The USB stick was reused (0 DKK) and no RAM upgrade was required
(0 DKK) — both recorded explicitly in `costs.md` so the decisions are visible rather than merely
absent. Reference-build running total: **899 DKK (~121 EUR)**.

## Problems / failures / lessons

Eight recorded in `docs/build-log/2026-09-08-phase-01-installation.md`. The three that matter to
Project Planning:

- **A healthy-looking machine was degraded.** SSH worked and the machine was reachable while a boot
  unit failed and every startup wasted two minutes. Only `systemctl is-system-running` caught it.
  **Recommendation: make a system-health assertion a standing Definition of Done item**, not a
  Phase 01 detail.
- **The guide's own instructions created a privilege-escalation risk** by omitting `chown root:root`
  after `scp` + `sudo mv`. Fixed, and `verify-install.sh` now detects it.
- **Configuration belongs in the repository, not in pasted commands.** Forced by a terminal quirk,
  but correct regardless — and it is the pattern later phases should follow.

## Deviations from phase brief

1. **DHCP reservation not made** — no router admin access. Recorded as an unsatisfied ADR-016
   control, with static-IP and mDNS alternatives considered and rejected with reasons. Superseded by
   Tailscale in Phase 03. The address survived the power cut unchanged.
2. **ISO checksum verification not confirmed in-session.** The USB was prepared independently of
   `scripts/macos/download-ubuntu-iso.sh`, and whether the checksum was verified was never
   established. The install completed and the system is correct, which is strong evidence of image
   integrity, but the formal check is unconfirmed. Recorded rather than assumed.

## Open issues / technical debt

- SSH password authentication (Phase 03).
- Wi-Fi runs on 2.4 GHz/802.11n though the adapter supports 5 GHz/802.11ac. Not a problem at −55 dBm;
  first thing to check if the link ever proves unreliable.
- `vm.swappiness` left at the default 60, which is eager for a server. Revisit if Phase 05 creates
  memory pressure.
- No LAN address stability guarantee until Tailscale.

## Recommended roadmap changes

1. **Add a system-health check to the project-wide Definition of Done** in `PROJECT.md` — something
   equivalent to "the system reports no failed units". This phase demonstrates that functional tests
   pass on a degraded machine.
2. **Phase 03 should not cite Tailscale's Ubuntu documentation** — it still references Noble 24.04
   and has no 26.04 page. The `resolute` package repository is the authoritative source. See ADR-014.
3. **Phase 10 must explicitly revisit ADR-015.** Converting to encryption at rest after the fact
   generally means a reinstall, so the decision should be made before the Second Brain holds real
   data, not after.

No phase renumbering or re-sequencing is required.

## Definition of Done

- [x] Functional objective works
- [x] Reproducible
- [x] Validated/tested
- [x] Security considered
- [x] Repository updated
- [x] Guide updated
- [x] Project docs updated
- [x] ADRs handled
- [x] Costs recorded — 199 DKK, DisplayPort→HDMI cable
- [x] Failures/lessons recorded
- [x] Tested versions recorded
- [x] Critical AI-generated components understood
- [x] `main` known-working — `feature/01-ubuntu-server` merged 2026-09-08
- [x] Handover returned to Project Planning
