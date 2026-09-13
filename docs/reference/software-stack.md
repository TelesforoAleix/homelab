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
| Git (server) | **Active** | 2.53.0 | Yes since Phase 18.2 | Phase 01 base tooling. **All five repositories are cloned on the node** at `/srv/homelab` inside the encrypted volume (Phase 18.2, 2026-09-12), with SSH remotes and the node's own key `~aleix/.ssh/id_ed25519_github` (owner-account key; `Host github.com` block in `~aleix/.ssh/config`). The Phase 04 "not cloned on the node" decision is superseded by ADR-038 |
| PyYAML (server) | **Active** | 6.0.3 (`python3-yaml 6.0.3-1build1`) | Yes — the Workbench's only dependency (`PyYAML>=6.0`) | Was already installed as a dependency of `netplan.io`; Phase 18.2 marked it `apt-mark manual` so an autoremove cannot take it. No `pip`, no venv |
| Factory Workbench (server) | **Active** | Factory `2e82f51`; `factory-ops` `66283c2` | Phase 18.2 deliverable (ADR-036, ADR-038) | `homelab-workbench.service`, `User=aleix`, `NoNewPrivileges`, `1.3 OK`. `python3 -m workbench.cli --project /srv/homelab/projects/factory serve` with `PYTHONPATH=/srv/homelab/factory` (no `WorkingDirectory=` — see the standard). Binds `127.0.0.1:8765` only; reached via `ssh homelab-workbench`. Tied to the volume: skipped while locked, started by unlock. Writes `ops/` records and never commits |
| GitHub CLI (`gh`) | **Active** | 2.90.0 | No, but used for PRs/releases | Phase 04. Homebrew. Token in the macOS keyring with `gist`, `read:org`, `repo`, `workflow` scopes — **never in the repository** |
| gitleaks | **Active** | 8.30.1 | No | Phase 04. Homebrew. Independent cross-check on `scan-history.sh`. **Scans diffs, so it skips merge commits** — 34 of 38 on 2026-09-09 |
| OpenSSH client (MacBook) | **Active** | OpenSSH_9.9p2, LibreSSL 3.3.6 | Ships with macOS | Ed25519 key, passphrase in the login keychain (ADR-018) |
| Tailscale (server) | **Active** | 1.102.3 | Chosen remote-access approach (ADR-005) | Installed 2026-09-09 from the `resolute` repository, re-verified that day. MagicDNS primary route; node key expiry disabled (ADR-019). |
| Tailscale (MacBook) | **Active** | 1.102.3 | Same tailnet | Homebrew cask `tailscale-app`. Same version as the server. |
| VS Code Remote SSH | **Active** | extension 0.124.0 (`remote-ssh-edit` 0.87.0, `remote-explorer` 0.5.0) | Development workflow (ADR-004) | Connects via the `homelab` alias in `~/.ssh/config` (the forward-free one — `homelab-workbench` carries the tunnel); bootstraps `~/.vscode-server` on the node. Since Phase 18.2 the editing path is Remote SSH into `/srv/homelab/...`. |
| Docker Engine / CLI | **Active** | 29.8.0, build 88096ef | Core container runtime (ADR-022) | Phase 05. Installed from Docker's official apt repository with `signed-by`; rootful daemon. Containers should run as non-root and published ports must bind an explicit interface. |
| Docker Compose plugin | **Active** | v5.5.1 | Compose file workflow (ADR-022) | Phase 05. Used for committed service definitions instead of long `docker run` lines living only in shell history. |
| Docker Buildx plugin | **Active** | Installed with Docker 29.8.0 | No | Phase 05 package set from Docker's repository. |
| containerd | **Active** | v2.3.5, commit 1294c24a7da8e5a793ed378161673abe94118892 | Docker dependency | Installed as Docker's `containerd.io` package; no conflicting distribution `containerd` was installed. |
| Python | **Active** | 3.14.4 | Runtime for the Telegram bot | Phase 07. Ships with Ubuntu. **Standard library only** — the bot introduces no third-party package, so there is no dependency to audit or upgrade |
| polkit | **Active** | 127 | Escalation mechanism (ADR-024) | Phase 08. Ships with Ubuntu. Grants `homelab-bot` one action, scoped to one user/unit/verb. Chosen over `sudo`, which `NoNewPrivileges=yes` refuses outright. **Logs denials but not grants** |
| Telegram status bot | **Active** | — | First user-facing interface (ADR-009) | Phase 07. Native systemd unit as `homelab-bot`; long polling, so **no listening socket**; `systemd-analyze security` 1.3 OK (ADR-023) |
| Model helper service | **Active** | — | Phase 09 credential boundary (ADR-025) | Phase 09. Socket-activated, `Accept=yes` (one process per connection), runs as `aleix` because it must reach the OAuth credentials the bot cannot. Access control is the socket's group/mode, not code. `MemoryDenyWriteExecute`, `RestrictNamespaces` and `SystemCallFilter` are deliberately **not** set — reasons in the unit |
| Claude model via CLI | **Active** | `haiku` (`claude-haiku-4-5-20251001`) on Claude Code 2.1.236 | Cheapest Claude tier (ADR-025) | Phase 09. The `haiku` alias is **undocumented in `--help`** (which lists `fable`, `opus`, `sonnet`) but works. Invoked with `--tools ""` and `--strict-mcp-config`; tool suppression verified with a canary file. Exhaustion wording: `You've hit your session limit · resets 11pm (UTC)` |
| Codex model via CLI | **Active** | `gpt-5.6-luna` on Codex CLI 0.153.4 | Cheapest Codex tier (ADR-025) | Phase 09. The subscription's mini tier — the CLI's own catalogue records it as the replacement for GPT-5.4 Mini. `gpt-5.4-mini` is in that catalogue but **rejected on a ChatGPT account**. Needs `--skip-git-repo-check`, `--ephemeral`, `-o FILE` and a closed stdin (`codex exec` appends piped stdin to the prompt) |
| Node.js | Planned | — | Likely runtime/tooling | Deliberately not installed for Phase 06; both AI CLIs use native binaries |
| Claude Code CLI (server) | **Active** | 2.1.236, stable channel | Initial AI tool (ADR-008) | Phase 06. Native user-scoped install under `/home/aleix`; subscription OAuth reports Claude Pro. `claude doctor` confirmed native install and automatic updates enabled on the stable channel. Interactive operator command, not a service. |
| OpenAI Codex CLI (server) | **Active** | 0.153.4 | Initial AI tool (ADR-008) | Phase 06. Native user-scoped install under `/home/aleix`; authenticated with ChatGPT device authorization. Interactive operator command, not a service. |
| OpenAI Codex CLI (MacBook) | **Active** | 0.153.4 standalone | Administration workstation | Phase 06 replaced a broken npm `0.118.0` installation whose platform executable was missing. |
| Bubblewrap | **Active** | 0.11.1-1ubuntu0.1 | Codex Linux sandbox prerequisite | Phase 06. Ubuntu package; works with the distribution's AppArmor profile while unprivileged user namespaces remain restricted. |
| netplan | **Active** | 1.2-1ubuntu5 | Ships with Ubuntu Server | Declares the Wi-Fi link (ADR-016). Config at `/etc/netplan/00-installer-config.yaml`, mode `0600`. |
| tmux | **Active** | 3.6 | No, but strongly advised | Ships with Ubuntu Server. Anything long-running on this node belongs in a tmux session: both access routes share one Wi-Fi adapter, and a dropped link mid-`apt` can leave dpkg half-configured. |
| tree | **Active** | 2.3.1-1 | No | Phase 02. Directory structure at a glance where repeated `ls` gets tedious. |
| ncdu | **Active** | 1.22-1build1 | No | Phase 02. Interactive drill-down for "where has the disk gone", far faster than `du \| sort`. |
| ripgrep | **Active** | 15.1.0-1ubuntu1 | No | Phase 02. Fast content search; respects `.gitignore` in a repository, which matters from Phase 04. |
| wpasupplicant | **Active** | 2:2.11-0ubuntu5 | Required for Wi-Fi under `systemd-networkd` | Confirmed active and enabled; without it the networkd renderer cannot drive a wireless link |
| ufw | **Active** | ships with Ubuntu | Host firewall (2026-09-10) | Phase 13 adds a `DOCKER-USER` block in `/etc/ufw/after{,6}.rules` via `scripts/server/apply-docker-user-rules.sh`. `apply-firewall.sh` resets ufw and erases it — run the DOCKER-USER script after. |
| systemd-creds (TPM2) | **Active** | systemd 259; TPM 2.0 (Intel PTT) | Bot token sealed at rest (Phase 13 §6.6, ADR-046 amendment) | `--with-key=tpm2 --tpm2-pcrs=""`; loaded by bot, notifier, watchdog via `LoadCredentialEncrypted=`. Proved across a reboot and a power-cycle. |
| age (MacBook) | **Active** | v1.3.2 | Encrypts the backup and the recovery SSH key on the card | Phase 18; Phase 13 uses it for `recovery-key/id_ed25519_homelab_recovery.age`. |
| mokutil / efibootmgr | **Active** | ship with Ubuntu | Secure Boot state and EFI boot order (read in the audit) | Phase 13: Secure Boot enabled; PXE entries removed from `BootOrder` via the firmware. |
| Tailscale ACL | **Active** | policy v2 (`grants`) | Device-level boundary in front of sshd (Phase 13 §6.7) | `config/tailscale/acl.hujson`; members → node tcp/22 only; Tailscale SSH not used (ADR-019). |

## Version rule

Use **Tested with X** unless compatibility genuinely requires an exact version. Verify current installation guidance in the phase that introduces each tool.

A pinned artefact is not automatically a requirement. ADR-014 pins an exact ISO and checksum so the
reference build can be reproduced byte-for-byte and so the download script can refuse an unverified
file — but the hard requirement remains "Ubuntu Server LTS in standard support". Where a pin exists
for reproducibility rather than compatibility, say so explicitly in the Notes column.
