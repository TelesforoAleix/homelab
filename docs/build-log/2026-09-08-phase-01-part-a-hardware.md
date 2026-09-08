# Build Log — Phase 01 Part A: Hardware Identification

- **Date:** 2026-09-08
- **Phase:** 01 — Ubuntu Server (Part A)
- **Branch:** `feature/01-ubuntu-server`
- **Status:** Complete — Phase 00 hardware prerequisite closed

## Starting state

The M700 still ran its original Windows installation. Two hardware facts had been open since project
bootstrap and were blocking confident planning:

- the RAM module layout (1×8 GB vs 2×4 GB), which decides the upgrade path;
- the wireless adapter model, which ADR-016 flagged as a risk that could strand the installation with
  no network.

## Objective

Capture the hardware facts that are cheapest to read from Windows, before the disk is erased, and
close the Phase 00 hardware prerequisite.

## Actions taken

Read from Windows Task Manager on the reference node and recorded into
`docs/reference/hardware.md`:

| Item | Result |
|---|---|
| CPU | Intel Core i5-6600T @ 2.70 GHz, 4 cores / 4 logical processors |
| RAM | 8 GB DDR4 SO-DIMM @ 2133 MHz |
| RAM slots | **1 of 2 used — single 8 GB module** |
| Storage | Samsung `MZ7TY256HDHP-000L7` SATA SSD, 256 GB nominal / ~239 GiB usable |
| Wi-Fi | **Intel Dual Band Wireless-AC 8260, 802.11ac** |
| CPU virtualization | **Disabled** in firmware |

## Validation

The hardware facts are confirmed observations. Two claims *derived* from them were checked against
sources rather than assumed:

| Claim | Verified against |
|---|---|
| The AC 8260 uses the in-tree `iwlwifi` driver with `iwlwifi-8000C` firmware | kernel.org iwlwifi wiki |
| That firmware ships in Ubuntu's `linux-firmware` package | Ubuntu package contents search — `iwlwifi-8000C-34.ucode`, `-36.ucode` |
| The i5-6600T supports VT-x, VT-d and EPT; DDR4-2133, 2 channels | Intel ARK, SKU 88189 |

Nothing here is validated *on Linux*. No operating system has been installed, and no software has
been marked as installed or tested anywhere in the repository.

## Problems / failed approaches

**1. CPU virtualization was found disabled — and nobody had thought to check.**

- *Assumption:* the Part A checklist covered the firmware facts that mattered. It listed RAM,
  storage, wireless adapter, CPU model and physical checks.
- *What happened:* Task Manager reported virtualization as Disabled. It was not on the checklist;
  it surfaced incidentally from the same screen that showed the CPU.
- *What we learned:* the checklist was built around *identifying components*, and missed *firmware
  state*. On a machine about to become headless, a wrong firmware setting is far more expensive than
  a wrong inventory entry, because fixing it later means physically reattaching a monitor.
- *What changed:* enabling virtualization was added to the Part D firmware tasks, alongside the
  power-loss and UEFI settings, with the explicit framing that all firmware changes happen in one
  sitting while a monitor is attached.

**2. Looked up the wrong CPU SKU while verifying virtualization support.**

- The first Intel ARK page fetched was for the i5-6500T, not the i5-6600T, and reported plausible
  specifications that would have been easy to accept.
- *Lesson:* neighbouring SKUs in the same family produce believable-looking answers. The SKU number
  (88189 for the i5-6600T) is the thing to check, not the page's general shape.

**3. Part A was initially only half done.**

The identification pass completed, but the essential *physical* validation — USB ports, video
output, fan noise under load — had not been performed. It was recorded as outstanding rather than
quietly assumed to have passed.

> **Resolved later the same day.** The physical checks were completed: USB ports and video output
> work, fan noise is unobtrusive. **Phase 00 hardware prerequisite closed 2026-09-08.**
>
> *Lesson:* separating "identify the components" from "validate they work" was worth doing. The two
> are easy to conflate, and only the second would have caught a dead USB port before the installer
> needed one.

## What we learned

- Both bootstrap-era unknowns took minutes to resolve from Windows Task Manager. The cost of
  deferring them had been much higher than the cost of answering them.
- The ADR-016 risk framing was worth having even though the outcome was benign. The adapter turned
  out to be well supported, but the fallback path was written before that was known — which is the
  point. It stays in the guide, now marked as unlikely to be needed on this hardware and more
  relevant to someone reproducing the build on a different machine.
- "Well supported according to documentation" is not "worked on this machine". The ADR records the
  distinction explicitly rather than closing the risk outright.

## Decisions / ADRs

- No new ADR required.
- **ADR-016** gains a dated *Validation status* section recording the identified adapter and the
  reduced risk, with the fallback path retained unchanged.
- **ADR-015** and **ADR-014** unaffected.

## Costs

**None.** The RAM upgrade is explicitly **not required**: 8 GB is well above Ubuntu Server's 1.5 GB
minimum, and the confirmed free slot means an upgrade to 16 GB stays cheap and available whenever
real services justify it. Recorded as a zero-cost line in `docs/reference/costs.md` so the decision
is visible rather than merely absent.

## Next

1. ~~Complete the outstanding physical checks.~~ Done — Phase 00 closed.
2. ~~Parts B and C — image verification and USB creation.~~ Installation USB reported ready.
3. **Part D firmware:** enable virtualization, set `After Power Loss -> Power On`, preserve UEFI boot.
4. **Parts E and F:** installation, first boot, and the unattended power-loss validation.
