# Software Stack Reference

This file records the actual tested stack as phases are completed. Do not mark planned software as installed.

| Component | State | Tested version | Hard requirement? | Notes |
|---|---|---|---|---|
| Ubuntu Server LTS | **Active** | 26.04.1 LTS (Resolute Raccoon) | **Requires:** Ubuntu Server LTS in standard support. Exact point release **not** required. | Installed 2026-09-08. ISO/checksum pinned in ADR-014 for reproducibility, not as a constraint. |
| Linux kernel | **Active** | 7.0.0-31-generic | Ships with the release | x86_64 |
| systemd | **Active** | 259 | Ships with the release | Socket activation used for SSH |
| intel-microcode | **Active** | 3.20260210.1ubuntu2 | No | Mitigates the 2016-era firmware; see `hardware.md` |
| unattended-upgrades | **Active** | — | No | Enabled; `apt-daily-upgrade.timer` confirmed scheduled |
| OpenSSH server | **Active** | OpenSSH_10.2p1 Ubuntu-2ubuntu3.6 (OpenSSL 3.5.5) | Required for target workflow | Installed Phase 01 via socket activation (`ssh.socket` enabled). **Password auth still on** — key-only auth and hardening are Phase 03. |
| Git | Planned | — | Yes for repository workflow | Fundamentals in Phase 04 |
| Tailscale | Planned | — | Chosen remote-access approach | Phase 03; `resolute` repository confirmed available 2026-09-08 |
| VS Code Remote SSH | Planned | — | Development workflow | Phase 03 |
| Docker Engine | Planned | — | Expected core infrastructure | Phase 05; `resolute` repository confirmed available 2026-09-08 |
| Docker Compose | Planned | — | Expected core infrastructure | Phase 05 |
| Python | Planned | — | Likely runtime/tooling | Version selected when needed |
| Node.js | Planned | — | Likely runtime/tooling | Version selected when needed |
| Claude Code CLI | Planned | — | Initial AI tool | Phase 06 |
| OpenAI Codex CLI | Planned | — | Initial AI tool | Phase 06 |
| Telegram Bot | Planned | — | First remote interface | Phase 07 |
| netplan | **Active** | 1.2-1ubuntu5 | Ships with Ubuntu Server | Declares the Wi-Fi link (ADR-016). Config at `/etc/netplan/00-installer-config.yaml`, mode `0600`. |
| wpasupplicant | **Active** | 2:2.11-0ubuntu5 | Required for Wi-Fi under `systemd-networkd` | Confirmed active and enabled; without it the networkd renderer cannot drive a wireless link |

## Version rule

Use **Tested with X** unless compatibility genuinely requires an exact version. Verify current installation guidance in the phase that introduces each tool.

A pinned artefact is not automatically a requirement. ADR-014 pins an exact ISO and checksum so the
reference build can be reproduced byte-for-byte and so the download script can refuse an unverified
file — but the hard requirement remains "Ubuntu Server LTS in standard support". Where a pin exists
for reproducibility rather than compatibility, say so explicitly in the Notes column.
