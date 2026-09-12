# Current Architecture

**State:** Phases 01–09, 12, 18, 18.1, 18.2 and 20.0 complete — the reference node runs Ubuntu Server, is
administered remotely over Tailscale with key-only SSH, and has Docker Engine/Compose plus two
subscription-authenticated AI operator CLIs. **The monitor and keyboard are detached**; the node runs
headless, with a console available on demand — the connectors are present and console login is tested
(Phase 18, ADR-041). **Encryption at rest is executed** (Phase 18.1, 2026-09-12): root is shrunk and
stays unencrypted by decision (ADR-046); a separate LUKS2 volume holds knowledge and project content,
unlocked over SSH after boot (ADR-037). **The node reports its own recovery** (Phase 12, 2026-09-12): a
once-per-boot timer sends downtime, clean-versus-unplanned classification and the volume's lock
state to Telegram, and `OnFailure=` on the bot, the model helper and the watchdog itself pages the
owner when a unit dies — with no daemon, no listening socket, and no path to a model.

**The four layers live on the node** (Phase 18.2, 2026-09-12): `homelab`, `factory`, `brain`,
`projects/oncla` and `projects/factory` are clones inside the encrypted volume at `/srv/homelab`,
owned `aleix:aleix`, and the **Factory Workbench runs there as `homelab-workbench.service`**, bound to
`127.0.0.1:8765`, reached from the MacBook only through `ssh homelab-workbench`'s `LocalForward`.
The MacBook is a client and a terminal; nothing runs from its clones. The node holds one new secret —
an SSH key to GitHub with write access to the three private repositories — and one new listening
socket, on loopback. ADR-038 §5's rule is now the measured statement: **seven sockets, seven names.**

**`Interface → Router → Executor → Model` now exists as code**, not as a diagram. Phase 07 built the
Interface; Phase 08 built the Router and the Executors; Phase 09 connected the model.

The way it was connected is the architectural point. `homelab-bot` provably cannot read either AI
credential and **still cannot** — so the model call happens in a separate service running as
`aleix`, which the bot asks over a UNIX socket. The credential never moves. The bot gained no group,
no sudoers entry and no read access to `/home/aleix`, and the machine gained no listening socket
(ADR-025). **That last property changes under ADR-038**, which adds loopback-bound endpoints for the
harness and Workbench; the rule becomes *every listening socket is accounted for and bound to a stated
interface*, and the bot remains outbound-only.

The node performs exactly one privileged action, and the account that performs it gained nothing:
`id homelab-bot` is byte-identical to Phase 07 and there are zero sudoers entries.

Phase 02 changed nothing here, which its brief predicted: it taught the architecture rather than
altering it. Its only lasting change to the node is three diagnostic packages. What it *did* add is
a constraint on how this architecture may be changed from now on —
[`docs/standards/safe-changes-headless.md`](../standards/safe-changes-headless.md) (ADR-020,
superseded by ADR-041).

## Physical roles

```text
MacBook Pro  —  development / administration interface
    │  Ed25519 key, passphrase in the login keychain (ADR-018)
    │  VS Code Remote SSH over the same "homelab" alias, into /srv/homelab/...
    │
    ├── ssh homelab      → MagicDNS over Tailscale     ← primary; scripts, scp, VS Code
    │                      WireGuard mesh (ADR-005, ADR-019)
    │
    ├── ssh homelab-workbench → same host, plus LocalForward 127.0.0.1:8765
    │                      the ONLY door to the Workbench (ADR-038 §2; Phase 18.2)
    │
    └── ssh homelab-lan  → 192.168.1.57 on the LAN     ← fallback
                           kept as a network-independent path; the console is a
                           separate, physical recovery route, available on demand (ADR-041)
    ▼
Lenovo ThinkCentre M700 Tiny  —  "homelab"
    Ubuntu Server 26.04.1 LTS, kernel 7.0.0-31-generic
    UEFI boot · LVM, root 64 GB unencrypted by decision (ADR-046) ·
    LUKS2 data volume 128 GB at /srv/homelab, unlocked over SSH (ADR-037,
    executed Phase 18.1) · 43.42 GB left free in the volume group
    Wi-Fi wlp1s0, 2.4 GHz (ADR-016) · eno1 present, unused
    SSH: publickey only. No passwords, no root login (ADR-018)
    Docker Engine 29.8.0 + Compose v5.5.1, rootful (ADR-022)
    Claude Code 2.1.236 + Codex CLI 0.153.4, interactive only (ADR-008)
    homelab-telegram-bot.service — read-only status bot (ADR-023)
        runs as homelab-bot (uid 999), no shell, no home, no privileged group
        long polling: OUTBOUND HTTPS only, no listening socket
        systemd-analyze security: 1.3 OK
    homelab-watchdog.timer → .service — once per boot, 90 s after boot (Phase 12)
        runs as homelab-bot; reads the previous boot's journal and findmnt;
        sends one of four literal messages via homelab-notify.sh; OUTBOUND HTTPS only
        RestrictAddressFamilies has no AF_UNIX: the model helper is unreachable at the kernel
    homelab-notify@{bot,model-helper,watchdog,workbench}.service — OnFailure= targets, same account,
        same LoadCredential= token grant; homelab-notify@ itself has no OnFailure= (recursion guard)
    /srv/homelab (LUKS2, unlocked over SSH) — aleix:aleix 0750 (Phase 18.2)
        homelab/ factory/ brain/ projects/oncla/ projects/factory/ — clones, SSH remotes
        ~aleix/.ssh/id_ed25519_github — the node's GitHub key, NOT in the backup
    homelab-workbench.service — the Factory Workbench (Phase 18.2, ADR-036, ADR-038)
        runs as aleix under NoNewPrivileges; ProtectSystem=strict + ReadWritePaths=/srv/homelab
        ConditionPathIsMountPoint= / PartOf= / WantedBy=homelab-data.target — the canary
        LISTENS on 127.0.0.1:8765 only; no AF_UNIX; systemd-analyze security: 1.3 OK
    NO MONITOR, NO KEYBOARD — all DRM connectors report disconnected
    Cold-boots headless to a reachable state in ~26 seconds
```

## Deployed

| Component | State |
|---|---|
| Ubuntu Server 26.04.1 LTS | **Active** |
| OpenSSH server (socket-activated) | **Active** — key-only; passwords and root login refused (ADR-018) |
| Tailscale 1.102.3 | **Active** — MagicDNS primary route, node key expiry disabled (ADR-019) |
| ufw (firewall) | **Active** since 2026-09-10 — default deny inbound; allows `tailscale0` and Tailscale's UDP port on `wlp1s0` |
| VS Code Remote SSH | **Active** — `~/.vscode-server` on the node |
| netplan + wpasupplicant (Wi-Fi) | **Active** |
| unattended-upgrades | **Active** |
| Wi-Fi power-save suppression | **Active** — `config/systemd/` |
| Docker Engine / Compose | **Active** — no persistent containers; explicit-interface port publishing required (ADR-022) |
| Claude Code 2.1.236 | **Active** — `aleix`-scoped operator CLI using Claude Pro subscription OAuth; no daemon |
| Codex CLI 0.153.4 | **Active** — `aleix`-scoped operator CLI using Sign in with ChatGPT; no daemon |
| Bubblewrap 0.11.1 | **Active** — Ubuntu package used by the Codex Linux sandbox |
| **Router / executors** | **Active** — registry-based, in the bot process. Six executors at three capability levels; authorisation in one function; two allowlists with privileged enforced as a subset (ADR-024) |
| **Escalation grant** | **Active** — polkit, one user / one unit / one verb, plus a second allowlist inside the bot. Zero sudoers entries; `NoNewPrivileges` retained |
| **Telegram status bot** | **Active** — `homelab-telegram-bot.service`, the project's first service. Read-only, standard library only, never forks a process. Long polling means **no listening socket**; isolation proved by attempted access (ADR-023) |
| **Model helper** | **Active** — `homelab-model-helper.socket` + templated service. Runs as `aleix` because it must reach the credentials the bot cannot; socket-activated, one process per connection, so nothing holds an OAuth token between requests. Access control is the socket's group and mode, not code (ADR-025) |
| **Model executor** | **Active** — `/ask`, two providers with independent usage limits and automatic fallback, cheapest model by default. The model gets **no tools** (verified with a canary), and its output is never dispatched |
| **Encrypted data volume** | **Active, locked at boot** — `ubuntu-vg/data` (LUKS2, 128 GiB) → mapper `homelab-data` → ext4, mounted at `/srv/homelab`. Unlocked manually over SSH via `data-volume.sh unlock`; `noauto` in `/etc/crypttab` and `/etc/fstab` keeps boot from waiting on it (ADR-037, Phase 18.1) |
| **Watchdog / notifier** | **Active** — `homelab-watchdog.timer` (`OnBootSec=90s`, `WantedBy=timers.target`) → `homelab-watchdog.service` (oneshot, `User=homelab-bot`, `SupplementaryGroups=systemd-journal`, `LoadCredential=` on the bot's token, `RestrictAddressFamilies=AF_INET AF_INET6`). Classifies the previous stop from PID 1's journal (`Shutting down.` present → clean, absent → unplanned), computes downtime from `journalctl --list-boots`, reads lock state from `/etc/crypttab` + `findmnt`. `homelab-notify@.service` is the single send primitive and the `OnFailure=` target for the bot (drop-in), the model helper (drop-in) and the watchdog; it has no `OnFailure=` of its own. Three boots observed 2026-09-12: enable, clean reboot, power cut — all reported correctly (Phase 12) |
| **`homelab-data.target` + `homelab-workbench.service`** | **Active pattern** — `ConditionPathIsMountPoint=/srv/homelab`, `PartOf=`/`WantedBy=homelab-data.target`, and **no `WorkingDirectory=` on the volume** (implicit `RequiresMountsFor=` would run before the Condition — found by a false alert, Phase 18.2). A dependent unit started while locked is skipped, not failed; `is-system-running` stays `running` either way. The Workbench is the canary; the 18.1 probe is removed. Contract: `docs/standards/volume-dependent-services.md` |
| **Factory Workbench** | **Active** — `homelab-workbench.service`, `User=aleix`, `python3 -m workbench.cli --project /srv/homelab/projects/factory serve` from `/srv/homelab/factory` via `PYTHONPATH`. Binds `127.0.0.1:8765` only (refused otherwise in `server.py`); reached through `ssh homelab-workbench`; no application login — the OS user is the boundary (ADR-035 §7, ADR-036 §5, ADR-038). `OnFailure=homelab-notify@workbench.service`. Score 1.3 OK. **Writes records into `projects/factory/ops/` and never commits** — the owner commits by hand (Phase 18.2) |
| **The four layers in the volume** | **Active** — five clones at `/srv/homelab/{homelab,factory,brain,projects/oncla,projects/factory}`, SSH remotes, cloned with `~aleix/.ssh/id_ed25519_github` (owner-account key, write to the three private repos; excluded from `backup-node.sh` by design). The MacBook's clones remain as working copies (Phase 18.2) |

## Confirmed architectural direction

```text
Interface  →  Router  →  Executor  →  Tool / Model / Service
```

**Every layer now exists.** A Telegram bot runs as its own unprivileged account, a registry-based
router performs one authorisation check before dispatch, executors do one thing each, and the model
executor reaches a model without the bot holding a credential.

The question Phase 08 left open — whether personal subscription credentials are appropriate for
unattended use, and specifically that it must **not** be resolved by copying an OAuth file to a
service account — was answered by not moving the credential at all:

```text
Telegram → homelab-bot ──socket──▶ homelab-model-helper → Claude / Codex
           (no credential)         (runs as aleix, already has them)
```

Two boundaries hold this together, and neither trusts the other:

- **the socket's group and mode**, enforced by the kernel before the helper process exists;
- **the router's capability check**, which is why `/ask` cannot reach `/restart`.

The licensing question was left open, and the constraint that substituted for an answer — every
model call owner-initiated, in response to a message just sent — **is retired**. ADR-026 lifted it
per provider on 2026-09-10; **ADR-040 retired §9 in full** on 2026-09-11. Autonomous calls are normal
and **budget replaces attribution** as the control. The licensing position is recorded in ADR-040 §3
as an **accepted judgement with its reasoning**, not as resolved.

## Not implemented yet

- knowledge/RAG services (Phase 10)
- ~~automation (Phase 12)~~ — **the scheduler exists** (Phase 12, 2026-09-12) as a systemd timer that
  triggers one oneshot unit; it **cannot reach a model** (`RestrictAddressFamilies` omits `AF_UNIX`)
  until Phase 15.1's governor lands and a new ADR names it a client (ADR-044 §4). Autonomous model
  calls are normal in principle (ADR-040); the budget control that makes them safe does not exist yet
- voice input (Phase 17 — moved out of Phase 09, see `ROADMAP.md`)
- ~~alerting or metrics on any service (nothing reports the bot dying)~~ — **closed by Phase 12**
  (2026-09-12): `OnFailure=` on the bot, the model helper and the watchdog pages Telegram on a real
  crash and not on a clean `stop`; tested with 15 `SIGKILL`s. Metrics remain unbuilt, by scope. The
  one unwatched failure is `homelab-notify@.service`'s own
- narrower filesystem confinement for the model helper — `ReadWritePaths=/home/aleix` is broader
  than it should eventually be, and was deliberately not guessed at (ADR-025)
- ~~any backup of the node (Phase 13)~~ — delivered by Phase 18: a verified, restorable backup
  (`scripts/macos/backup-node.sh`)
- ~~firewall (Phase 13)~~ — `ufw` active since 2026-09-10 (default deny inbound; `tailscale0` plus
  Tailscale's UDP port allowed)
- ~~encryption at rest~~ — **executed** by Phase 18.1 (2026-09-12, ADR-037); root stays unencrypted
  by decision (ADR-046)
- local GPU node (Phase 16)
- the harness endpoint (Phase 23.0) — the Workbench is on loopback and the socket rule is measured;
  the endpoint follows the same shape
- a dedicated Workbench account — it runs as `aleix` under `NoNewPrivileges`; Phase 13 takes or
  declines the upgrade with a reason (Phase 18.2)

Update this document when a phase changes the actually deployed architecture.
