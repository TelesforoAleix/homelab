# 00 — Reference Build

## Machine

**Lenovo ThinkCentre M700 Tiny**

Known configuration at repository bootstrap:

| Component | Reference build |
|---|---|
| CPU | Intel Core i5-6600T |
| CPU topology | 4 cores / 4 threads |
| RAM | 8 GB DDR4 |
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

The current 8 GB configuration must be inspected before deciding on an upgrade. The reference planning considers 16 GB a sensible working target, while 24 GB may be attractive if the installed module layout and used-market pricing make it economical.

Do not buy upgrades merely to reach a round specification; measure actual needs as services are added.
