# Software Stack Reference

This file records the actual tested stack as phases are completed. Do not mark planned software as installed.

| Component | State | Tested version | Hard requirement? | Notes |
|---|---|---|---|---|
| Ubuntu Server LTS | Planned | — | Project standard | Phase 01; target pinned to 26.04.1 LTS by ADR-014. Record the real version from `scripts/server/verify-install.sh` once installed. |
| OpenSSH | Planned | — | Required for target workflow | Installed during Phase 01; key-only auth and hardening deferred to Phase 03 |
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
| netplan | Planned | — | Ships with Ubuntu Server | Declares the Wi-Fi link (ADR-016) |
| wpasupplicant | Planned | — | Required for Wi-Fi under `systemd-networkd` | Without it the networkd renderer cannot drive a wireless link |

## Version rule

Use **Tested with X** unless compatibility genuinely requires an exact version. Verify current installation guidance in the phase that introduces each tool.
