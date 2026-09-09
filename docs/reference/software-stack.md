# Software Stack Reference

This file records the actual tested stack as phases are completed. Do not mark planned software as installed.

| Component | State | Tested version | Hard requirement? | Notes |
|---|---|---|---|---|
| Ubuntu Server LTS | **Active** | 26.04.1 LTS (Resolute Raccoon) | **Requires:** Ubuntu Server LTS in standard support. Exact point release **not** required. | Installed 2026-09-08. ISO/checksum pinned in ADR-014 for reproducibility, not as a constraint. |
| Linux kernel | **Active** | 7.0.0-31-generic | Ships with the release | x86_64 |
| systemd | **Active** | 259 | Ships with the release | Socket activation used for SSH |
| intel-microcode | **Active** | 3.20260210.1ubuntu2 | No | Mitigates the 2016-era firmware; see `hardware.md` |
| unattended-upgrades | **Active** | — | No | Enabled; `apt-daily-upgrade.timer` confirmed scheduled |
| OpenSSH server | **Active** | OpenSSH_10.2p1 Ubuntu-2ubuntu3.6 (OpenSSL 3.5.5) | Required for target workflow | Installed Phase 01 via socket activation (`ssh.socket` enabled). **Key-only since Phase 03** (ADR-018): passwords and keyboard-interactive disabled, `PermitRootLogin no`. Note `ssh.socket` uses `Accept=no`, so config changes need `systemctl reload ssh`. |
| Git (MacBook) | **Active** | 2.39.5 (Apple Git-154) | Yes for repository workflow | Phase 04. Ships with macOS/Xcode CLT and is **behind upstream git** — relevant if a later phase needs a newer feature. Not a constraint today. |
| Git (server) | **Active** | — | No | Present from Phase 01 base tooling; the repository is **not** cloned on the node (Phase 04 decision) |
| GitHub CLI (`gh`) | **Active** | 2.90.0 | No, but used for PRs/releases | Phase 04. Homebrew. Token in the macOS keyring with `gist`, `read:org`, `repo`, `workflow` scopes — **never in the repository** |
| gitleaks | **Active** | 8.30.1 | No | Phase 04. Homebrew. Independent cross-check on `scan-history.sh`. **Scans diffs, so it skips merge commits** — 34 of 38 on 2026-09-09 |
| OpenSSH client (MacBook) | **Active** | OpenSSH_9.9p2, LibreSSL 3.3.6 | Ships with macOS | Ed25519 key, passphrase in the login keychain (ADR-018) |
| Tailscale (server) | **Active** | 1.102.3 | Chosen remote-access approach (ADR-005) | Installed 2026-09-09 from the `resolute` repository, re-verified that day. MagicDNS primary route; node key expiry disabled (ADR-019). |
| Tailscale (MacBook) | **Active** | 1.102.3 | Same tailnet | Homebrew cask `tailscale-app`. Same version as the server. |
| VS Code Remote SSH | **Active** | extension 0.124.0 (`remote-ssh-edit` 0.87.0, `remote-explorer` 0.5.0) | Development workflow (ADR-004) | Connects via the `homelab` alias in `~/.ssh/config`; bootstraps `~/.vscode-server` on the node. |
| Docker Engine / CLI | **Active** | 29.8.0, build 88096ef | Core container runtime (ADR-022) | Phase 05. Installed from Docker's official apt repository with `signed-by`; rootful daemon. Containers should run as non-root and published ports must bind an explicit interface. |
| Docker Compose plugin | **Active** | v5.5.1 | Compose file workflow (ADR-022) | Phase 05. Used for committed service definitions instead of long `docker run` lines living only in shell history. |
| Docker Buildx plugin | **Active** | Installed with Docker 29.8.0 | No | Phase 05 package set from Docker's repository. |
| containerd | **Active** | v2.3.5, commit 1294c24a7da8e5a793ed378161673abe94118892 | Docker dependency | Installed as Docker's `containerd.io` package; no conflicting distribution `containerd` was installed. |
| Python | Planned | — | Likely runtime/tooling | Version selected when needed |
| Node.js | Planned | — | Likely runtime/tooling | Version selected when needed |
| Claude Code CLI | Planned | — | Initial AI tool | Phase 06 |
| OpenAI Codex CLI | Planned | — | Initial AI tool | Phase 06 |
| Telegram Bot | Planned | — | First remote interface | Phase 07 |
| netplan | **Active** | 1.2-1ubuntu5 | Ships with Ubuntu Server | Declares the Wi-Fi link (ADR-016). Config at `/etc/netplan/00-installer-config.yaml`, mode `0600`. |
| tmux | **Active** | 3.6 | No, but strongly advised | Ships with Ubuntu Server. Anything long-running on this node belongs in a tmux session: both access routes share one Wi-Fi adapter, and a dropped link mid-`apt` can leave dpkg half-configured. |
| tree | **Active** | 2.3.1-1 | No | Phase 02. Directory structure at a glance where repeated `ls` gets tedious. |
| ncdu | **Active** | 1.22-1build1 | No | Phase 02. Interactive drill-down for "where has the disk gone", far faster than `du \| sort`. |
| ripgrep | **Active** | 15.1.0-1ubuntu1 | No | Phase 02. Fast content search; respects `.gitignore` in a repository, which matters from Phase 04. |
| wpasupplicant | **Active** | 2:2.11-0ubuntu5 | Required for Wi-Fi under `systemd-networkd` | Confirmed active and enabled; without it the networkd renderer cannot drive a wireless link |

## Version rule

Use **Tested with X** unless compatibility genuinely requires an exact version. Verify current installation guidance in the phase that introduces each tool.

A pinned artefact is not automatically a requirement. ADR-014 pins an exact ISO and checksum so the
reference build can be reproduced byte-for-byte and so the download script can refuse an unverified
file — but the hard requirement remains "Ubuntu Server LTS in standard support". Where a pin exists
for reproducibility rather than compatibility, say so explicitly in the Notes column.
