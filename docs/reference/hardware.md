# Hardware Reference

## Canonical node

Verified in **Phase 01 Part A** on 2026-09-08 from Windows Task Manager, before the disk was erased.

| Field | Value | Confidence/state |
|---|---|---|
| Model | Lenovo ThinkCentre M700 Tiny | Confirmed |
| CPU | Intel Core i5-6600T @ 2.70 GHz (Skylake, 35 W) | Confirmed — Part A |
| CPU cores/threads | 4 / 4 | Confirmed — Part A |
| CPU virtualization | VT-x, VT-d and EPT supported by the CPU; **enabled in firmware 2026-09-08** | ✅ Done in Phase 01 Part D. `lscpu` → `Virtualization: VT-x`; `vmx` on all 8 threads |
| RAM | **32 GB DDR4 SO-DIMM @ 2133 MT/s** (was 8 GB until 2026-09-14) | **Upgraded in Phase 00.1, 2026-09-14** — `MemTotal 31701556 kB`, `free` 30 GiB |
| RAM module layout | **2 × 16 GB — ChannelA-DIMM0 and ChannelB-DIMM0, both populated** (dual-channel, identical dual-rank modules) | Confirmed by `dmidecode -t 17` after the upgrade |
| RAM module part | Kingston ValueRAM `KVR26S19D8/16` × 2 (firmware reports Kingston `99U5663-007.A00G`), DDR4-2666 2Rx8 1.2 V, **configured at 2133 MT/s** — the i5-6600T's ceiling | Confirmed by `dmidecode`; stability: `memtester 20G 1` all tests `ok`, no MCE/EDAC |
| RAM — previous module | Samsung `M471A1K43BB0-CPB` 8 GB DDR4-2133, removed 2026-09-14, **kept as a spare** | Was the sole module from purchase to Phase 00.1 |
| Storage | Samsung `MZ7TY256HDHP-000L7`, SATA SSD | Confirmed — Part A |
| Storage capacity | 256 GB nominal / ~239 GiB usable | Confirmed — Part A |
| Wi-Fi | **Intel Dual Band Wireless-AC 8260**, 802.11ac | **Resolved** — Part A |
| Bluetooth | Present | Confirmed |
| Wireless interface name | `wlp1s0` | Confirmed from installed system |
| Ethernet interface | `eno1` — present, DOWN (unused, ADR-016) | Confirmed from installed system |
| BIOS/firmware | LENOVO **FWKT63A**, release date **2016-12-08** | Confirmed from installer probe |
| TPM | **Version 2.0** at `/dev/tpm0` + `/dev/tpmrm0` | **Changed 2026-09-10.** Was a discrete TPM **1.2**; the firmware offers `TCG Security Device: Firmware TPM` (Intel PTT) and it was switched. Confirmed by `tpm_version_major` = 2, the appearance of `/dev/tpmrm0` (a 2.0-only device), the disappearance of the 1.2-only attributes `pubek`/`owned`/`temp_deactivated`, and `ppi` becoming present. **Cost: firmware POST rose 10.97s → 13.81s** (+2.8s), which is the fTPM initialising. **Two prerequisites remain before it can unlock a LUKS volume** — see the Phase 18 brief §2.1 |
| Secure Boot | **Enabled** | Confirmed 2026-09-10 — `mokutil --sb-state` |
| Purchase price | 700 DKK | Confirmed |
| Target OS | Ubuntu Server 26.04.1 LTS | **Planned — not installed** |
| Primary role | Orchestration / infrastructure | Accepted decision (ADR-002) |

## Part A verification status (2026-09-08)

**Source:** Windows Task Manager on the reference node, prior to installation.

Resolved:

- ✅ **RAM module layout** — previously an open Phase 00 unknown. Confirmed as a single 8 GB module
  with one slot free.
- ✅ **Wi-Fi adapter model** — previously tracked as a Phase 01 risk under ADR-016. Confirmed as an
  Intel Dual Band Wireless-AC 8260.
- ✅ CPU model and core count, matching prior records.
- ✅ Storage device model and capacity.

Newly discovered:

- ~~⚠️ **CPU virtualization is disabled in firmware.**~~ ✅ **Enabled 2026-09-08** during Phase 01
  Part D. Recorded here as discovered-then-resolved rather than deleted (`PROJECT.md` §11).

Also validated:

- ✅ **Essential physical validation** — USB ports, video output and fan noise all checked. Fan noise
  is unobtrusive, which matters for a machine that will live in a home rather than a rack. A monitor,
  keyboard and mouse are attached and stay attached until the machine goes headless in Phase 03.

> **Phase 00 hardware prerequisite: CLOSED** (2026-09-08).

## Linux support assessment

Assessed on 2026-09-08 against the confirmed hardware. Nothing here is validated on the running
system yet — it is a pre-installation risk assessment, not a test result.

| Component | Expected Linux support | Basis |
|---|---|---|
| Intel Wireless-AC 8260 | **Well supported.** Uses the in-tree `iwlwifi` driver with `iwlwifi-8000C` firmware. Ubuntu's `linux-firmware` package ships `iwlwifi-8000C-34.ucode` and `-36.ucode`, and that package is present on the Server installer image. | kernel.org iwlwifi wiki; Ubuntu `linux-firmware` package contents |
| Samsung SATA SSD | Standard AHCI SATA device; no special driver needed. | Generic |
| Intel HD Graphics 530 | Irrelevant to a headless server beyond console output. | Generic |

**Effect on ADR-016.** The identified adapter is a mainstream Intel part with a long-standing in-tree
driver and packaged firmware, so the specific risk that *the installer cannot see the wireless card*
is now **substantially reduced**. The documented fallback path is retained — it costs nothing to keep
and covers the case where reality disagrees — but it is now unlikely to be needed.

## Firmware actions — ✅ completed in Phase 01 Part D (2026-09-08)

All three were performed while a monitor and keyboard were still attached, and all three are
verified from live output.

| # | Action | Verified by |
|---|---|---|
| 1 | **Enable CPU virtualization (VT-x / VT-d)** | `lscpu` → `Virtualization: VT-x`; `vmx` present on all 8 threads. Re-confirmed 2026-09-09 |
| 2 | **Set `After Power Loss` to `Power On`** | Phase 01's unattended power-loss recovery test passed all four criteria |
| 3 | **Preserve UEFI boot mode** | ESP present at `/boot/efi`; no legacy/CSM |

The ordering mattered for a practical reason, and that reason has now fully arrived: **the machine is
headless and the monitor, keyboard and cable have been removed** (Phase 03). Any further firmware
change means physically reattaching all three. There is no known outstanding firmware task — and if
one appears, budget a physical trip for it.

### On CPU virtualization

It was **not** a requirement for anything on the roadmap. Linux containers — Docker in Phase 05 —
use kernel namespaces and cgroups, not hardware virtualization, and run fine with VT-x disabled. It
was enabled because it was free, because the CPU supports it, and because the alternative was a
physical trip to the machine later if a phase ever wanted KVM/QEMU virtual machines.

That reasoning has aged well. The console is now gone, so the trip that was hypothetical in Phase 01
would today mean reattaching hardware from a drawer.

## RAM upgrade — ✅ done in Phase 00.1 (2026-09-14)

**History.** The node shipped with one 8 GB DDR4-2133 SO-DIMM (Samsung `M471A1K43BB0-CPB`) in
ChannelA-DIMM0 and ChannelB-DIMM0 empty. This section used to say the "planned reference path" was
adding one 8 GB module for 16 GB, that 32 GB was "not required", and that the upgrade "should be
driven by observed pressure from real services rather than by reaching a round number". Kept here
as the reasoning it was (`PROJECT.md` §11); what actually happened is below.

**What was done.** Both slots populated with **2 × 16 GB Kingston ValueRAM `KVR26S19D8/16`**
(DDR4-2666, 2Rx8, 260-pin, 1.2 V, non-ECC, unbuffered); the 8 GB module removed and kept as a
spare. Cost 700 DKK. The owner chose the platform ceiling in one step rather than 16 GB now and a
second trip into the box later — the two-slot limit makes any later step a *replacement*, not an
addition, and the box is headless and lives in a cupboard. That is a judgement about the cost of
opening the machine, not a measurement of memory pressure: at the time of the upgrade the node used
under 1 GiB of its 7.1 GiB.

**As the firmware reports it** (`dmidecode -t 16,17`, 2026-09-14 19:49 UTC):

| Slot | Module | Reported |
|---|---|---|
| ChannelA-DIMM0 (BANK 0) | Kingston `99U5663-007.A00G`, serial 11161410 | 16 GB, DDR4, SODIMM, Rank 2, Speed 2133 MT/s, Configured 2133 MT/s, 1.2 V |
| ChannelB-DIMM0 (BANK 2) | Kingston `99U5663-007.A00G`, serial 10107215 | 16 GB, DDR4, SODIMM, Rank 2, Speed 2133 MT/s, Configured 2133 MT/s, 1.2 V |
| Physical array | | Maximum Capacity 32 GB, Number Of Devices 2, Error Correction None |

Three things worth knowing when reading that:

- **2666 on the box, 2133 in the machine — correct.** The i5-6600T's memory controller supports
  DDR4-2133 as its maximum; a faster JEDEC module runs at the controller's speed. This BIOS reports
  `Speed: 2133` (the running speed) rather than the module's SPD maximum, so the 2666 rating is
  visible only on the label.
- **Dual-channel has no field.** `dmidecode` reports slots, not channel mode. Two identical modules
  in `ChannelA-DIMM0` and `ChannelB-DIMM0` on a Skylake controller is symmetric dual-channel; the
  locators are the evidence.
- **`99U5663-007.A00G`** is Kingston's internal part code; it is what `KVR26S19D8/16` reports.

**Verified by:** `free -h` 30 GiB / `MemTotal 31701556 kB`; `memtester 20G 1` — all 16 tests `ok`,
2 h 07 min, run from the console (see below); `journalctl -k` free of MCE/EDAC/memory-error lines
before and after; `systemctl is-system-running` → `running`, no failed units; boot, Wi-Fi, the
watchdog notice, the data-volume unlock and every service back as before. Build log:
[`2026-09-14-phase-00.1-ram-upgrade.md`](../build-log/2026-09-14-phase-00.1-ram-upgrade.md).

**Two operational facts learned on the way:**

1. **A memory-stress test is a network outage on this node.** `memtester` locking most of RAM made
   the DHCP renewal fail; the shared building network issues **3-minute leases**
   (`LIFETIME=3min`, `T1=1min 30s`), so `systemd-networkd` dropped the address within a lease
   lifetime and the node was unreachable on both routes until the test ended. Run such tests from
   the console. The Wi-Fi association itself held throughout.
2. **The firmware POST took 17.0 s on the first boot with the new modules** (memory training)
   against 5.7 s on the boot before. Expect a slower first POST after any memory change.

**Opening the machine.** Lenovo HMM (M700/M900/M900x Tiny) ch. 9: the SO-DIMM slots are **under the
2.5-inch storage-drive bracket**. Cover screw at the rear → slide the cover forward, lift → bracket
screw, slide, lift (the front Wi-Fi antenna cable may need to come off the card and *must* go back:
it is the node's only network path) → modules → reverse. The cover is a slide-and-hook fit: set it
down well forward of closed with the rear lip *under* the rear panel edge, then slide it back. Set
down too far back it jams a few millimetres short; do not force it.

## Swap

| Property | Value |
|---|---|
| Type | Swapfile, `/swap.img` |
| Size | 4 GB |
| In use | 0 B at first measurement (RAM 542 MB / 7.1 GB used); still 0 B after the 32 GB upgrade |

**Decision: accept the installer default** (closes the open item in Phase 01 brief §6). 4 GB against
8 GB of RAM is a reasonable ratio, and a *file* rather than a partition can be resized later without
disturbing the disk layout — which complements the LVM choice in ADR-015.

**Revisited 2026-09-14 (Phase 00.1), unchanged.** Against 32 GB the 4 GB swapfile is small as a
proportion, but swap on this node is a safety margin, not a memory extension: it has never been
touched, and `vm.swappiness` is 10 (Phase 05). Resizing it would be work with no observed need.

No tuning applied at the time. `vm.swappiness` was at the distribution default of 60; Phase 05
lowered it to 10 when Docker arrived.

## Storage capacity note

The drive is sold as 256 GB but reports roughly 239 GB in Windows. Nothing is wrong or missing: the
manufacturer counts decimal gigabytes (10⁹ bytes) while the operating system reports binary
gibibytes (2³⁰ bytes). 256 × 10⁹ bytes ≈ 238.4 GiB. Linux will report the same figure.

## Wireless link — observed characteristics

Measured on the running system, 2026-09-08:

| Property | Value |
|---|---|
| Band | **2.4 GHz** (2412 MHz, channel 1) |
| Rate | rx 117 Mbit/s / tx 144.4 Mbit/s (802.11n rates) |
| Signal | −55 dBm (good) |

The Intel AC 8260 is a dual-band 802.11ac adapter, but the link came up on **2.4 GHz using 802.11n**,
not 5 GHz/802.11ac. Signal quality is good and throughput is far beyond anything this node's
workload needs, so this is **not a problem to fix** — but it is worth knowing:

- 2.4 GHz is more congested, and channel 1 is among the busiest.
- 5 GHz would offer higher throughput and less interference, at shorter range.

If the link ever proves unreliable — the risk ADR-016 actually cares about — the band is the first
thing to examine, before deeper causes.

**Observed 2026-09-14 (Phase 00.1):** the link was on **5 GHz** (5220 MHz, VHT 80 MHz, rx 292.5 /
tx 866.7 Mbit/s, −57 to −60 dBm) on every check that day, before and after the upgrade. The band
choice is the access point's and has evidently changed since 2026-09-08; nothing on the node was
altered to cause it.

## Firmware age — open security observation

The node's BIOS is **FWKT63A, dated 2016-12-08**, and has never been updated. It therefore predates
the January 2018 Spectre/Meltdown disclosures and carries no corrected CPU microcode.

**Mitigation confirmed (2026-09-08).** `intel-microcode` version `3.20260210.1ubuntu2` is installed
and active — microcode dated February 2026, loaded at boot independently of the firmware. `needrestart`
also reports the processor microcode as up to date. The CPU-level Spectre/Meltdown-class issues are
therefore addressed in software despite the firmware's age.

**Residual gap.** Microcode does not cover firmware-level fixes — platform mitigations, Intel ME
updates, and any Lenovo-specific fixes issued since 2016. This remains a **Phase 13 hardening item**,
now lower priority than it first appeared. When it is revisited, the trade-off is:

1. Do nothing further — `intel-microcode` already handles the CPU-level exposure.
2. Flash a newer Lenovo BIOS — closes the firmware-level gap, but a failed flash on the project's
   only node is a genuinely bad outcome, and this machine has no redundancy. Not to be done casually,
   and arguably not worth it for a home LAN node behind NAT.

## Local AI

Serious local CUDA/LLM experimentation is expected to use a future second node rather than
converting the M700 into a GPU workstation (ADR-002).
