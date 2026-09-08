# Hardware Reference

## Canonical node

| Field | Value | Confidence/state |
|---|---|---|
| Model | Lenovo ThinkCentre M700 Tiny | Confirmed |
| CPU | Intel Core i5-6600T | Confirmed |
| CPU cores/threads | 4 / 4 | Confirmed |
| RAM | 8 GB DDR4 | Confirmed |
| RAM module layout | Unknown: 1×8 GB or 2×4 GB | To inspect |
| Storage | 256 GB SSD | Confirmed |
| Wi-Fi | Present | Confirmed |
| Bluetooth | Present | Confirmed |
| Purchase price | 700 DKK | Confirmed |
| Target OS | Ubuntu Server LTS | Planned |
| Primary role | Orchestration / infrastructure | Accepted decision |

## Upgrade direction

Do not purchase RAM solely based on target numbers. Inspect installed modules first.

Planning assumptions:

- 16 GB is a sensible working target for the reference orchestration node.
- 24 GB may be economical if the machine contains a reusable 8 GB module and a low-cost 16 GB SO-DIMM is available.
- 32 GB is not currently required.

## Local AI

Serious local CUDA/LLM experimentation is expected to use a future second node rather than converting the M700 into a GPU workstation.
