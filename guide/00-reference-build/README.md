# 00 — Reference Build

## Machine

**Lenovo ThinkCentre M700 Tiny**

Known configuration at repository bootstrap:

| Component | Reference build |
|---|---|
| CPU | Intel Core i5-6600T |
| CPU topology | 4 cores / 4 threads |
| RAM | 32 GB DDR4-2133 (2 × 16 GB) — 8 GB at purchase, upgraded 2026-09-14 ([`00.1-ram-upgrade`](../00.1-ram-upgrade/README.md)) |
| RAM layout | Not yet verified |
| Storage | 256 GB SSD |
| Networking | Built-in Wi-Fi; wired capability to be validated/used as appropriate |
| Bluetooth | Present |
| Purchase condition | Used |
| Purchase price | 700 DKK |

## Intended role

The M700 is an **always-on orchestration and infrastructure server**.

It is expected to run services such as:

- SSH / remote administration
- Git working tree
- Docker / Compose
- Telegram interface
- routing/executor services
- databases when justified
- knowledge/indexing services when justified
- monitoring and automation later

It is not intended to be the project's primary local-LLM machine.

## Development model

The MacBook Pro remains the primary keyboard/screen/development interface. The M700 becomes the headless execution environment.

## Planned OS

Ubuntu Server LTS.

## RAM strategy

The reference node started at 8 GB (one module, one slot free — inspected in Phase 01 Part A) and
was taken to **32 GB, the two-slot platform ceiling**, in Phase 00.1 on 2026-09-14 — see
[`guide/00.1-ram-upgrade/`](../00.1-ram-upgrade/README.md) for the procedure and the reasoning.
The planning position had been 16 GB as a sensible working target and 24 GB if pricing favoured it.

The rule stands even though the reference build did not follow it to the letter: do not buy upgrades
merely to reach a round specification. The 32 GB choice was made on the cost of *opening a headless
machine twice*, not on measured pressure — and that trade-off is recorded, not hidden.
