# Hardware Reference

## Canonical node

Verified in **Phase 01 Part A** on 2026-09-08 from Windows Task Manager, before the disk was erased.

| Field | Value | Confidence/state |
|---|---|---|
| Model | Lenovo ThinkCentre M700 Tiny | Confirmed |
| CPU | Intel Core i5-6600T @ 2.70 GHz (Skylake, 35 W) | Confirmed — Part A |
| CPU cores/threads | 4 / 4 | Confirmed — Part A |
| CPU virtualization | VT-x, VT-d and EPT supported by the CPU; **enabled in firmware 2026-09-08** | ✅ Done in Phase 01 Part D. `lscpu` → `Virtualization: VT-x`; `vmx` on all 8 threads |
| RAM | 8 GB DDR4 SO-DIMM @ 2133 MHz | Confirmed — Part A |
| RAM module layout | **1 × 8 GB in ChannelA-DIMM0; ChannelB-DIMM0 empty** | **Resolved** — confirmed by `dmidecode` |
| RAM module part | Samsung `M471A1K43BB0-CPB`, DDR4-2133 | Confirmed by `dmidecode` |
| Storage | Samsung `MZ7TY256HDHP-000L7`, SATA SSD | Confirmed — Part A |
| Storage capacity | 256 GB nominal / ~239 GiB usable | Confirmed — Part A |
| Wi-Fi | **Intel Dual Band Wireless-AC 8260**, 802.11ac | **Resolved** — Part A |
| Bluetooth | Present | Confirmed |
| Wireless interface name | `wlp1s0` | Confirmed from installed system |
| Ethernet interface | `eno1` — present, DOWN (unused, ADR-016) | Confirmed from installed system |
| BIOS/firmware | LENOVO **FWKT63A**, release date **2016-12-08** | Confirmed from installer probe |
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

## RAM upgrade path

**Now resolved.** The node has one 8 GB DDR4-2133 SO-DIMM and one free slot.

| Path | Result | Status |
|---|---|---|
| Add one 8 GB SO-DIMM | 16 GB | **Planned reference path** |
| Add one 16 GB SO-DIMM | 24 GB | Optional future path if pricing favours it |
| Replace both | 32 GB | Not required; the board's two slots are the binding limit |

**No RAM upgrade is required before or during Phase 01.** 8 GB comfortably exceeds Ubuntu Server's
1.5 GB minimum, and the upgrade should be driven by observed pressure from real services rather than
by reaching a round number.

The installed module is a **Samsung `M471A1K43BB0-CPB`** (8 GB DDR4-2133). Sourcing an identical
part for the empty ChannelB slot would give a matched pair, which is the least surprising upgrade —
though matching is a convenience, not a requirement.

Practical notes for when an upgrade does happen:

- The CPU supports DDR4-2133 as its maximum speed, so a faster module will simply run at 2133 MHz.
- Matching the existing module's speed avoids surprises; capacities need not match.
- Mixed capacities (8 GB + 16 GB) run in flex mode — part dual-channel, part single-channel. This is
  normal and not a fault.
- The CPU's own limit is 64 GB, but the M700 Tiny has two SO-DIMM slots, so 32 GB is the practical
  platform ceiling.

## Swap

| Property | Value |
|---|---|
| Type | Swapfile, `/swap.img` |
| Size | 4 GB |
| In use | 0 B at first measurement (RAM 542 MB / 7.1 GB used) |

**Decision: accept the installer default** (closes the open item in Phase 01 brief §6). 4 GB against
8 GB of RAM is a reasonable ratio, and a *file* rather than a partition can be resized later without
disturbing the disk layout — which complements the LVM choice in ADR-015.

No tuning applied. `vm.swappiness` remains at the distribution default of 60, which is more eager to
swap than a server typically wants. That is worth revisiting only if real memory pressure appears —
likely Phase 05, when containers arrive — rather than pre-emptively.

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
