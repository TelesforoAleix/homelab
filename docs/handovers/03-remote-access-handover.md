# Phase 03 Handover — Remote Access

- **Date:** 2026-09-09
- **From:** Phase 03 phase context
- **To:** Phase 02 — Linux Fundamentals (the deferred next phase)
- **Brief:** [`03-remote-access.md`](03-remote-access.md), committed before implementation per ADR-017

## Outcome

**Complete.** All ten functional objectives met and validated from live output. Phase 01's principal
open risk — SSH password authentication — is **closed**.

## What the next phase inherits

> The section to read first. Under ADR-017 there is no planning context to reconcile any of this; if
> it is not written here, it is lost.

### 1. The console is gone. Your recovery options have changed.

**This is the most important sentence in this handover.** The monitor, keyboard and DisplayPort→HDMI
cable have been physically removed. All six DRM connectors report `disconnected`.

Phase 01 and Phase 03 both treated the attached console as the ultimate fallback, and both sequenced
their dangerous steps around it. **Phase 02 does not have that.** A change that breaks networking,
`sshd`, or the Wi-Fi link is no longer a walk to the monitor — it is a physical reattachment of a
monitor and a cable that are now in a drawer.

Concretely, before touching networking, `sshd`, `netplan`, users, `sudoers`, or anything that runs at
boot:

- keep a second SSH session open, since established connections survive configuration changes;
- prefer `reload` to `restart`, and validate before applying (`sshd -t`, `netplan try`);
- remember there are **two** independent routes in, and they fail independently:
  `ssh homelab` (Tailscale) and `ssh homelab-lan` (LAN). Losing Wi-Fi loses both.

### 2. Verified starting state

Captured 2026-09-09 after the headless reboot, from live output.

| Fact | Value |
|---|---|
| Host | `homelab`, Lenovo M700 Tiny |
| OS | Ubuntu Server 26.04.1 LTS, kernel 7.0.0-31-generic |
| **Primary access** | `ssh homelab` → MagicDNS over Tailscale, arriving from the MacBook's `100.x` address |
| **Fallback access** | `ssh homelab-lan` → `192.168.1.57` on the LAN |
| **Authentication** | **Public key only.** Passwords, keyboard-interactive and root login all refused |
| Key | Ed25519, passphrase-protected, in the MacBook's login keychain. `~/.ssh/id_ed25519_homelab` |
| Tailnet address | `100.71.62.71` (v4), `fd7a:115c:a1e0::c01:3ed6` (v6) |
| Node key expiry | **Disabled** (ADR-019) |
| Tailscale | 1.102.3 on both machines; `tailscaled` active and enabled |
| VS Code | Remote SSH 0.124.0, `~/.vscode-server` present on the node |
| `sudo` | Requires a password. No `NOPASSWD`. Every privileged step needs the owner |
| Console | **None.** All DRM connectors `disconnected` |
| Boot | 25.8s cold, headless, to reachable |
| Health | `systemctl is-system-running` → `running`, no failed units |

Re-verify at any time:

```bash
scp scripts/server/verify-remote-access.sh homelab:/tmp/
ssh homelab
sudo bash /tmp/verify-remote-access.sh
```

`scripts/server/verify-install.sh` still captures the Phase 01 base system and is unchanged.

### 3. Open risks, and who closes them

| Risk | Closed by |
|---|---|
| ~~SSH password authentication~~ | **Closed by this phase** (ADR-018) |
| **Single SSH key.** Losing the MacBook's private key means losing remote access, and there is no console. A backup key or a recovery path is the mitigation | Phase 13 |
| No firewall. Port 22 is open on the LAN and answers | Phase 13 |
| No encryption at rest (ADR-015); Wi-Fi passphrase cleartext on an unencrypted disk | Phase 13 — **but Phase 10 must revisit ADR-015 first** |
| 2016 firmware; CPU-level exposure mitigated by `intel-microcode`, platform-level not | Phase 13, low priority |
| Wi-Fi is the only network link; losing it loses both access routes at once | Not owned by any phase yet. Ethernet is available (`eno1`, unused) |

### 4. Unsatisfied controls

- **ADR-016's DHCP reservation is now formally superseded**, not merely unmet. ADR-019 records that
  tailnet identity replaces LAN address stability, and does so better — a reservation would only ever
  have been stable on one network. ADR-016 is otherwise unaffected; Wi-Fi remains the reference link.
- **Phase 01's ISO checksum was never confirmed.** Unchanged by this phase. Nothing depends on it.
- **`verify-remote-access.sh` section 3 needs root.** Run it under `sudo` for a complete report;
  without it the effective-configuration block is skipped. Section 1 is the authoritative check and
  works unprivileged.

### 5. Must not be silently inherited

- **Tailscale is a new third-party dependency.** Its coordination server brokers connections and
  holds node identity and public keys; traffic is end-to-end WireGuard. ADR-005 chose it before any
  implementation existed; ADR-019 records what that actually means now that it is running.
- **Node key expiry is disabled, deliberately.** A real security control switched off for
  availability, because a lapsed key silently removes a console-less machine from the tailnet.
  `verify-remote-access.sh` warns if it is ever re-enabled. **Phase 13 must revisit it on its
  merits**, not inherit it as a default.
- **Tailscale SSH was declined**, keeping OpenSSH keys as the authentication mechanism. Reasonable to
  revisit in Phase 13 with ACLs in scope; it is not a decision to reverse casually, since it changes
  where SSH authentication lives.
- **The `10-` prefix on the sshd drop-in is a security control**, not housekeeping. `sshd` takes the
  **first** value it sees for a keyword, and Ubuntu's `50-cloud-init.conf` sets
  `PasswordAuthentication yes`. Renumbering the file above `50-` silently re-enables passwords.
- **Applying sshd configuration requires `systemctl reload ssh`.** Ubuntu's `ssh.socket` uses
  `Accept=no`, so one long-running daemon serves every connection using the config it parsed at
  start. `sshd -T` will not tell you the daemon is stale. See ADR-018.

### 6. Ground already covered — build on it, don't repeat it

Phase 03 exercised more of the Phase 02 syllabus for real, on top of what Phase 01 left. Together
they are the best teaching material available, and re-teaching them from zero would waste it.

| Phase 02 topic | Met in Phase 01 | Met again in Phase 03 |
|---|---|---|
| Permissions & ownership | `chmod 600` on netplan; the `chown root:root` escalation lesson | `~/.ssh` 700 / `authorized_keys` 600 and *why*; `install -o root -g root -m 0600`; a real file-mode claim that turned out to be wrong |
| Processes & services | systemd units, `enable --now`, socket activation, `systemctl --failed` | `Accept=no` vs `Accept=yes`; `ExecReload`; `KillMode=process`; reload vs restart; `systemctl show -p` for unit properties |
| Packages | `apt update`/`full-upgrade`/`autoremove` | Third-party apt repositories, `signed-by=` keyrings, verifying a repo publishes for your codename |
| Configuration files | netplan | Drop-in directories, `Include`, and **first-match-wins** ordering as a control |
| Logs & diagnosis | `journalctl -u`, reading installer logs | Diagnosing a stale daemon by comparing timestamps rather than re-reading config |
| Shell workflow | Diagnosing a hung command as waiting-on-input | `set -e` semantics in `&&` lists; why `BatchMode=yes` makes a test proof rather than encouragement |
| Networking | netplan, `networkctl`, DHCP, interface naming | Overlay networking, CGNAT address space, DNS via MagicDNS, `known_hosts` keyed by name |

Two specific worked examples worth building a lesson around, because both are cases where **the
obvious check agreed with us and was wrong**:

1. `sshd -T` reporting `passwordauthentication no` while the server still accepted passwords.
2. A verification script reporting a correctly-reloaded daemon as stale, because it compared against
   the wrong systemd timestamp.

### 7. Phase 02 must write and commit its own brief first

`docs/handovers/02-linux-fundamentals.md`, from `docs/templates/phase-brief-template.md`, committed
**before** implementation (ADR-017). Nobody else will write it.

Phase 02's brief should state whether the deliverable is documentation, exercises, or repository
artifacts, and — given the console is gone — how it intends to practise things like user
administration and networking without risking access.

## What was implemented

The reference node is administered entirely remotely. `ssh homelab` from the MacBook reaches it over
a WireGuard mesh by a name that does not depend on the LAN address, authenticated by an Ed25519 key
whose private half never left the laptop. The server refuses passwords, keyboard-interactive
authentication and root login outright. VS Code edits files on it directly. It has no monitor.

## Final architecture/state

```text
MacBook Pro  —  Ed25519 key, passphrase in login keychain (ADR-018)
    │           VS Code Remote SSH 0.124.0 over the same alias
    │
    ├── ssh homelab      → MagicDNS / Tailscale 1.102.3   ← primary
    │                      arrives from 100.69.244.33
    │
    └── ssh homelab-lan  → 192.168.1.57 on the LAN        ← fallback
    ▼
homelab — Lenovo M700 Tiny
    Ubuntu Server 26.04.1 LTS, kernel 7.0.0-31-generic
    SSH: publickey only. No passwords. No root login.
    Tailscale 100.71.62.71, node key expiry disabled
    NO CONSOLE — all DRM connectors disconnected
    Cold-boots headless to reachable in 25.8s
```

`docs/architecture/current-architecture.md` updated accordingly.

## Validation performed

Full results in the two build-log entries. Summary of the checks that mattered:

| Check | Result |
|---|---|
| Key login, `BatchMode=yes` | Succeeds — no password fallback possible |
| **Server's advertised methods** | `Permission denied (publickey)` — password absent |
| Effective config | `passwordauthentication no`, `kbdinteractiveauthentication no`, `permitrootlogin no`, `authenticationmethods publickey` |
| Route in use | `ssh homelab` arrives from the MacBook's tailnet address |
| Host key on the new name | Matches the fingerprint already trusted for the LAN address |
| Key expiry | `none` |
| VS Code Remote SSH | `~/.vscode-server`, 3 processes |
| **Headless cold boot** | Reachable on the first poll, no physical interaction |
| **Console removed** | All six DRM connectors `disconnected` |
| System health | `running`, no failed units — re-checked *after* the headless reboot |
| File integrity in transit | SHA256 identical on both machines |

## Files changed

- `docs/handovers/03-remote-access.md` — brief; this handover
- `docs/decisions/ADR-018-ssh-access-policy.md`, `ADR-019-tailscale-tailnet-configuration.md`
- `config/ssh/10-homelab-hardening.conf`, `homelab.ssh-config.example`, `README.md`
- `scripts/server/apply-ssh-hardening.sh`, `install-tailscale.sh`, `verify-remote-access.sh`
- `guide/03-remote-access/README.md`
- `docs/build-log/2026-09-09-phase-03-ssh-keys.md`, `2026-09-09-phase-03-tailscale-headless.md`
- `docs/reference/{project-state,software-stack,costs}.md`
- `docs/architecture/current-architecture.md`
- `.gitignore`, `ROADMAP.md`, `CHANGELOG.md`, `guide/README.md`, `config/README.md`, `scripts/README.md`

`MANIFEST.md` is deliberately untouched: it records the original bootstrap package (57 files) and
lists no Phase 01 artifacts either, so it is a historical record rather than a live inventory.

## ADRs

| ADR | Status | Note |
|---|---|---|
| ADR-018 — SSH access policy | **Accepted** | Key-only. Records the drop-in ordering rule and the reload requirement as controls |
| ADR-019 — Tailscale tailnet configuration | **Accepted** | Identity, MagicDNS, key expiry disabled, Tailscale SSH declined. **Supersedes ADR-016's DHCP-reservation control** |
| ADR-005 — Tailscale | Accepted, unchanged | Its open item — "capabilities/pricing must be verified when implemented" — is now closed by ADR-019 |
| ADR-016 — Wi-Fi link | Accepted, one control superseded | Wi-Fi remains the reference link |

## Tested versions

| Component | Version |
|---|---|
| OpenSSH server | OpenSSH_10.2p1 Ubuntu-2ubuntu3.6 (OpenSSL 3.5.5) |
| OpenSSH client (macOS) | OpenSSH_9.9p2, LibreSSL 3.3.6 |
| Tailscale (Ubuntu, `resolute` repo) | 1.102.3 |
| Tailscale (macOS, cask `tailscale-app`) | 1.102.3 |
| VS Code Remote SSH | 0.124.0 (`remote-ssh-edit` 0.87.0, `remote-explorer` 0.5.0) |
| Ubuntu Server / kernel | 26.04.1 LTS / 7.0.0-31-generic |

## Security notes

**Introduced:** key-only SSH; keyboard-interactive disabled; `PermitRootLogin no`;
`AuthenticationMethods publickey`; passphrase-protected private key held only on the MacBook;
`0600 root:root` on the drop-in; overlay networking removing any need to expose port 22; key
patterns in `.gitignore`; a verifier that probes the running server rather than trusting its config.

**Remaining:** single key with no backup (Phase 13); no firewall (Phase 13); no encryption at rest
(ADR-015, Phase 10 revisit trigger, Phase 13 hardening); 2016 firmware (Phase 13); node key expiry
deliberately disabled (Phase 13 revisit); Wi-Fi as a single point of network failure.

**Do not port-forward SSH.** Unchanged from Phase 01, and now unnecessary.

## Costs

**0 DKK.** Tailscale's Personal plan covers this tailnet including MagicDNS and disabling key
expiry. Verified at implementation as ADR-005 required, and recorded as an explicit zero.

Reference-build running total unchanged at **899 DKK (~121 EUR)**. The Phase 01 DisplayPort→HDMI
cable became redundant at Part F; it is not re-recorded, but the guide notes that someone installing
headless from the start may not need it at all.

## Problems / failures / lessons

Five recorded across the two build-log entries. The three that matter beyond this phase:

- **`sshd -T` agreed with us while the running server disagreed.** Ubuntu's `ssh.socket` uses
  `Accept=no`, so one long-running daemon serves every connection using the config it read at start.
  A configuration file is not a control until the process holding it has re-read it. This is now
  encoded in ADR-018, in the apply script, and in the verifier.
- **A verifier is worth more than a configurator.** `apply-ssh-hardening.sh` ran correctly and still
  left the system wrong, because it validated the file rather than the server.
- **Redaction has to be designed before the first report, not after.** The verification script
  printed the owner's account email into a document whose own footer says to paste it into the
  repository. Anything that prints third-party output should assume that output contains identity.

Also recorded: the key pair was first generated on the server by mistake, because a leading `!` is
bash's negation operator and the command ran without complaint; and two errors of mine in this
repository's own material, both corrected in place rather than dropped.

## Deviations from phase brief

1. **The brief said MagicDNS names and tailnet addresses were safe to commit. They are not.** The
   tailnet suffix is a globally unique identifier tied to the owner's account, and this repository is
   intended to become public. Tightened: committed material says `<tailnet>` and `<account>`, the
   verification script redacts both, and the real name lives only in the owner's uncommitted
   `~/.ssh/config`. The `100.x` addresses are kept, being unroutable CGNAT space.
2. **The brief assumed `sudo` could be driven non-interactively.** It cannot — there is no
   `NOPASSWD` — so every privileged step was performed by the owner. Worth knowing for later phases:
   automation on this node currently stops at the `sudo` boundary.
3. **`verify-install.sh` was listed as likely to need updating. It did not.** Its Phase 01
   assumptions still hold; the new posture is covered by a companion script instead of by changing a
   working one.

## Open issues / technical debt

- **Single SSH key, no backup, no console.** The most consequential item on this list.
- `verify-remote-access.sh` needs `sudo` for a complete report.
- Wi-Fi remains a single point of failure for *both* access routes. `eno1` is present and unused.
- 2.4 GHz / 802.11n on an adapter that supports 5 GHz / 802.11ac (inherited from Phase 01).
- `vm.swappiness` still 60 (inherited from Phase 01; Phase 05 trigger).
- Tailscale ACLs, tags, subnet routes and exit nodes all unconfigured — deliberately out of scope.

## Recommended roadmap changes

Actioned directly, since ADR-017 leaves no recipient:

1. **Phase 02 marked deferred-not-skipped** in `ROADMAP.md`, with the sequencing reasoning recorded.
2. **Phase 13's scope should include a backup SSH key or recovery path.** Noted in the Phase 13
   roadmap entry — it is new debt this phase created by removing the console.
3. **Phase 13 must revisit two ADR-019 decisions**: Tailscale SSH, and disabled node key expiry.

No phase renumbering required.

## Definition of Done

- [x] Functional objective works — all ten, each with live output
- [x] Reproducible — three scripts and two config artifacts, applied from the repository
- [x] Validated/tested — all fourteen brief checks, re-run after the headless reboot
- [x] Security considered — the phase *is* a security change; risks and trade-offs recorded
- [x] Repository updated
- [x] Guide updated — `guide/03-remote-access/README.md`, including what went wrong
- [x] Project docs updated — state, stack, costs, architecture, two build logs
- [x] ADRs handled — ADR-018, ADR-019, ADR-016 control superseded, ADR-005 open item closed
- [x] Costs recorded — explicit 0 DKK
- [x] Failures/lessons recorded — five, including two of my own errors
- [x] Tested versions recorded
- [x] Critical AI-generated components understood — all three scripts commented line by line
- [x] `main` known-working — after merge of `feature/03-remote-access`
- [x] System reports no failed units / not degraded — verified **after** the headless reboot
- [x] Handover written, stating what the next phase inherits
