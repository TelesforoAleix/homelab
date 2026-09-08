# Hardware Reference

## Canonical node

Verified in **Phase 01 Part A** on 2026-09-08 from Windows Task Manager, before the disk was erased.

| Field | Value | Confidence/state |
|---|---|---|
| Model | Lenovo ThinkCentre M700 Tiny | Confirmed |
| CPU | Intel Core i5-6600T @ 2.70 GHz (Skylake, 35 W) | Confirmed — Part A |
| CPU cores/threads | 4 / 4 | Confirmed — Part A |
| CPU virtualization | VT-x, VT-d and EPT supported by the CPU; **currently disabled in firmware** | To enable in Phase 01 Part D |
| RAM | 8 GB DDR4 SO-DIMM @ 2133 MHz | Confirmed — Part A |
| RAM module layout | **1 × 8 GB — 1 of 2 slots occupied** | **Resolved** — Part A |
| Storage | Samsung `MZ7TY256HDHP-000L7`, SATA SSD | Confirmed — Part A |
| Storage capacity | 256 GB nominal / ~239 GiB usable | Confirmed — Part A |
| Wi-Fi | **Intel Dual Band Wireless-AC 8260**, 802.11ac | **Resolved** — Part A |
| Bluetooth | Present | Confirmed |
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

- ⚠️ **CPU virtualization is disabled in firmware.** The CPU supports it; the setting is off. See
  *Firmware actions* below.

Still outstanding before the disk is erased:

- ⬜ **Essential physical validation** — USB ports, video output, and fan noise under load. These were
  not part of the identification pass. The Phase 00 prerequisite is not closed until they are done.

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

## Firmware actions required before installation

To be performed in Phase 01 Part D, while a monitor and keyboard are still attached:

1. **Enable CPU virtualization (VT-x / VT-d).** Currently disabled.
2. **Set `After Power Loss` to `Power On`.** Required by the Definition of Done.
3. **Preserve UEFI boot mode.** Do not switch to legacy/CSM.

The ordering matters for a practical reason: after this phase the machine is headless, so every
later firmware change means physically reattaching a monitor and keyboard. Make all of them now.

### On CPU virtualization

Enabling it is **not** a requirement for anything currently on the roadmap. Linux containers —
Docker in Phase 05 — use kernel namespaces and cgroups, not hardware virtualization, and run fine
with VT-x disabled. It is being enabled because it is free, because the CPU supports it, and because
the alternative to enabling it now is a physical trip to the machine later if a phase ever wants
KVM/QEMU virtual machines.

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

Practical notes for when an upgrade does happen:

- The CPU supports DDR4-2133 as its maximum speed, so a faster module will simply run at 2133 MHz.
- Matching the existing module's speed avoids surprises; capacities need not match.
- Mixed capacities (8 GB + 16 GB) run in flex mode — part dual-channel, part single-channel. This is
  normal and not a fault.
- The CPU's own limit is 64 GB, but the M700 Tiny has two SO-DIMM slots, so 32 GB is the practical
  platform ceiling.

## Storage capacity note

The drive is sold as 256 GB but reports roughly 239 GB in Windows. Nothing is wrong or missing: the
manufacturer counts decimal gigabytes (10⁹ bytes) while the operating system reports binary
gibibytes (2³⁰ bytes). 256 × 10⁹ bytes ≈ 238.4 GiB. Linux will report the same figure.

## Local AI

Serious local CUDA/LLM experimentation is expected to use a future second node rather than
converting the M700 into a GPU workstation (ADR-002).
