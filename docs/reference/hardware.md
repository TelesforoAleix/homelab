# Hardware Reference

## Canonical node

| Field | Value | Confidence/state |
|---|---|---|
| Model | Lenovo ThinkCentre M700 Tiny | Confirmed |
| CPU | Intel Core i5-6600T | Confirmed |
| CPU cores/threads | 4 / 4 | Confirmed |
| RAM | 8 GB DDR4 | Confirmed |
| RAM module layout | Unknown: 1×8 GB or 2×4 GB | To inspect — Phase 01 Part A |
| Storage | 256 GB SSD | Confirmed |
| Wi-Fi | Present | Confirmed |
| Wi-Fi adapter model | **Unknown** | To inspect — Phase 01 Part A; determines whether the Ubuntu installer can see the card (ADR-016) |
| Bluetooth | Present | Confirmed |
| Purchase price | 700 DKK | Confirmed |
| Target OS | Ubuntu Server 26.04.1 LTS | Planned — pinned by ADR-014, not yet installed |
| Primary role | Orchestration / infrastructure | Accepted decision |

## Upgrade direction

Do not purchase RAM solely based on target numbers. Inspect installed modules first.

Planning assumptions:

- 16 GB is a sensible working target for the reference orchestration node.
- 24 GB may be economical if the machine contains a reusable 8 GB module and a low-cost 16 GB SO-DIMM is available.
- 32 GB is not currently required.

## Local AI

Serious local CUDA/LLM experimentation is expected to use a future second node rather than converting the M700 into a GPU workstation.

## Verification status

Nothing in the table above has yet been confirmed from the running Ubuntu system, because the
operating system has not been installed. Two fields are open:

- **RAM module layout** — decides whether a spare SO-DIMM slot exists, and therefore the upgrade
  path. Read it from Windows before erasing the disk (Phase 01 Part A), or afterwards with
  `sudo dmidecode -t memory`.
- **Wi-Fi adapter model** — a Phase 01 risk rather than a curiosity. ADR-016 makes Wi-Fi the only
  network link, so an unsupported card blocks the install.

Once Ubuntu is installed, populate this file from `scripts/server/verify-install.sh` output rather
than from memory, per `docs/standards/documentation.md`.
