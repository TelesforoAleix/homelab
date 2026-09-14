# Current Architecture

**State:** Phases 01–09, 12, 13, 15.0, 18, 18.1, 18.2, 20.0 and 23.0 complete — the reference node runs Ubuntu Server, is
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
socket, on loopback. ADR-038 §5's rule is now the measured statement: ~~seven sockets, seven names~~
**eight sockets, eight names** (Phase 23.0, 2026-09-13).

**The endpoint exists** (Phase 23.0, 2026-09-13): `homelab-harness.service`, its own account, on
`127.0.0.1:8766` — the eighth socket. Layer 1 attaches origin and refuses identity claims in the body
by name; layer 2 classifies deterministically (`question` served; `task`, `command`, `unclassifiable`
refused with the reason); layer 9 forwards a question to the model helper with `role` as the only
routing key and writes one content-free audit line to `/var/lib/homelab-harness/audit.jsonl` on root.
It reaches the helper as a member of **`homelab-model`**, the group that now owns the helper's socket
(ADR-048: `aleix:homelab-model:0660`, members `homelab-bot,homelab-harness`). The Workbench is its
first client through the `homelab` adapter (`factory`), and **the adapter interface is proved** —
the same project run on the fake and on `homelab` differs only in `Result` fields. Up after a locked
boot; score 1.3; `client` is a label, not an identity, until 23.3.

**The security boundary is written down and measured** (Phase 13, 2026-09-13). From the outside in:
**Tailscale ACL** (only a tailnet member's device may reach the node, and only on tcp/22 —
`config/tailscale/acl.hujson`) → **ufw** (default deny; `tailscale0` and the WireGuard port only) +
**`DOCKER-USER`** (a published container port is dropped from `wlp1s0`/`eno1` before Docker accepts
it) → **sshd** (key-only, `AllowUsers aleix`, `MaxAuthTries 3`, no X11, no agent forwarding; two
authorised keys — the MacBook's and a recovery key whose private half lives `age`-encrypted on the
card) → **`aleix`** (sudo, `docker`; no longer `lxd`) → **the units**, each scored and each waiver a
`# WHY` in the unit: bot / watchdog / notifier / Workbench 1.3, model helper 3.8 (it cannot see
`~/.ssh`), `wifi-powersave-off` 5.1 (`CAP_NET_ADMIN` only). **At the box:** a BIOS supervisor
password, boot order locked to the internal disk, PXE off, Secure Boot on, a 15-minute console
timeout on tty logins only. **On disk:** the bot token is sealed to the TPM2 (no PCRs) and loaded by
the bot, the notifier and the watchdog — proved across a real reboot and a cord-pull; the plaintext
lives in the password manager. What each control does and does not protect is in ADR-046's
amendment: the TPM seal narrows a pulled disk, the BIOS password a USB boot, and nothing protects
the running machine. The Workbench's boundary is its sandbox, not an account (ADR-047). The
standard every later unit meets on day one is
[`docs/standards/service-security-baseline.md`](../standards/service-security-baseline.md).

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
    i5-6600T · 32 GB DDR4-2133, 2 × 16 GB dual-channel (Phase 00.1, 2026-09-14; was 8 GB)
    Ubuntu Server 26.04.1 LTS, kernel 7.0.0-31-generic
    UEFI boot · LVM, root 64 GB unencrypted by decision (ADR-046) ·
    LUKS2 data volume 128 GB at /srv/homelab, unlocked over SSH (ADR-037,
    executed Phase 18.1) · 43.42 GB left free in the volume group
    Wi-Fi wlp1s0, 5 GHz as observed 2026-09-14 — 2.4 GHz at install (ADR-016) · eno1 present, unused
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
    homelab-notify@{bot,model-helper,watchdog,workbench,harness}.service — OnFailure= targets, same account,
        same LoadCredential= token grant; homelab-notify@ itself has no OnFailure= (recursion guard)
    /srv/homelab (LUKS2, unlocked over SSH) — aleix:aleix 0750 (Phase 18.2)
        homelab/ factory/ brain/ projects/oncla/ projects/factory/ — clones, SSH remotes
        ~aleix/.ssh/id_ed25519_github — the node's GitHub key, NOT in the backup
    homelab-workbench.service — the Factory Workbench (Phase 18.2, ADR-036, ADR-038)
        runs as aleix under NoNewPrivileges; ProtectSystem=strict + ReadWritePaths=/srv/homelab
        ConditionPathIsMountPoint= / PartOf= / WantedBy=homelab-data.target — the canary
        LISTENS on 127.0.0.1:8765 only; no AF_UNIX; systemd-analyze security: 1.3 OK
        its `homelab` adapter POSTs to the harness below (Phase 23.0)
    homelab-harness.service — the endpoint, layers 1/2/9 (Phase 23.0, ADR-048)
        runs as homelab-harness (uid 995), no shell, no home, groups: own + homelab-model
        StateDirectory on ROOT (audit.jsonl, no content); WantedBy=multi-user.target — up while locked
        LISTENS on 127.0.0.1:8766 only; AF_UNIX for the helper's socket (# WHY); score 1.3 OK
        ──socket──▶ homelab-model-helper as one more capped consumer; holds no credential
    homelab-model-helper@ — the provider tree since Phase 15.1 (ADR-033 §3):
        claude/haiku, codex/mini — subscription CLIs, unmetered, count-capped (limits.py)
        gateway/luna (route `utility` only), gateway/sol (unrouted) — METERED, OUTBOUND HTTPS to
            ai-gateway.vercel.sh, pinned to the OpenAI serving provider on every request
        credential: /etc/homelab-model-helper/gateway-key root:root 0600 → LoadCredential=gateway-key
            (drop-in; score 3.8 unchanged); bot, harness and homelab-agent all denied; revocable in one click
        ledger: /var/lib/homelab-model-helper/spend.json aleix:aleix 0600 — the spend governor (spend.py):
            8 rolling windows (hour/day/week/month × attended/unattended), reserve-at-max before egress,
            settle-at-actual after, FAILS CLOSED when unreadable; proved on the node, reconciled to 9 decimals
        /spend (Telegram, owner) reads it through op: spend; nothing else reads it over the wire
    homelab-agent (uid 994) — the executor agent's OPERATOR account (Phase 13.1, ADR-049)
        /bin/bash, no password, own group only, runs no unit, holds no credential
        reached by its own key + `ssh homelab-agent` (BatchMode, no tty); sshd AllowUsers aleix homelab-agent
        /etc/sudoers.d/homelab-agent: a NOPASSWD LIST (172 entries; sudo-rs matches arguments exactly) —
        seven homelab-* units × nine verbs, journal/sockets/status reads, two named .json configs from
        /tmp/homelab-agent/, two named ledgers (cp -p), data-volume.sh status; every lockout-class
        binary and credential path denied by name. `sudo -l -U homelab-agent` is the truth
    NO MONITOR, NO KEYBOARD — all DRM connectors report disconnected
    Cold-boots headless to a reachable state in ~26 seconds
```

## Deployed

| Component | State |
|---|---|
| Ubuntu Server 26.04.1 LTS | **Active** |
| OpenSSH server (socket-activated) | **Active** — key-only; passwords and root login refused (ADR-018); `AllowUsers aleix`, `MaxAuthTries 3`, X11 and agent forwarding off (Phase 13); two authorised keys |
| Tailscale 1.102.3 | **Active** — MagicDNS primary route, node key expiry disabled (ADR-019, kept by Phase 13); **ACL: members → node tcp/22 only** (`config/tailscale/acl.hujson`, Phase 13) |
| ufw (firewall) | **Active** since 2026-09-10 — default deny inbound; allows `tailscale0` and Tailscale's UDP port on `wlp1s0`. **`DOCKER-USER`** block in `after{,6}.rules` since 2026-09-12 (Phase 13): published container ports dropped from physical interfaces. `apply-firewall.sh` resets it — run `apply-docker-user-rules.sh` after |
| VS Code Remote SSH | **Active** — `~/.vscode-server` on the node |
| netplan + wpasupplicant (Wi-Fi) | **Active** |
| unattended-upgrades | **Active** — security pockets only; `Automatic-Reboot` off (audited Phase 13); reboots are the owner's |
| Wi-Fi power-save suppression | **Active** — `config/systemd/wifi-powersave-off.service`; root bounded to `CAP_NET_ADMIN`, score 5.1 (Phase 13), proved from cold |
| Docker Engine / Compose | **Active** — no persistent containers; explicit-interface port publishing required (ADR-022) |
| Claude Code 2.1.236 | **Active** — `aleix`-scoped operator CLI using Claude Pro subscription OAuth; no daemon |
| Codex CLI 0.153.4 | **Active** — `aleix`-scoped operator CLI using Sign in with ChatGPT; no daemon |
| Bubblewrap 0.11.1 | **Active** — Ubuntu package used by the Codex Linux sandbox |
| **Router / executors** | **Active** — registry-based, in the bot process. Six executors at three capability levels; authorisation in one function; two allowlists with privileged enforced as a subset (ADR-024) |
| **Escalation grant** | **Active** — polkit, one user / one unit / one verb, plus a second allowlist inside the bot. Zero sudoers entries; `NoNewPrivileges` retained |
| **Telegram status bot** | **Active** — `homelab-telegram-bot.service`, the project's first service. Read-only, standard library only, never forks a process. Long polling means **no listening socket**; isolation proved by attempted access (ADR-023) |
| **Model helper** | **Active** — `homelab-model-helper.socket` + templated service. Runs as `aleix` because it must reach the credentials the bot cannot; **cannot see `~/.ssh`** (`InaccessiblePaths`, Phase 13; score 3.8, syscall filter declined after SIGSYS); socket-activated, one process per connection, so nothing holds an OAuth token between requests. Access control is the socket's group and mode, not code (ADR-025). **Since Phase 23.0 the group is `homelab-model`** (ADR-048): members `homelab-bot`, `homelab-harness`; `getent group homelab-model` is the access list. `RuntimeMaxSec=270` via drop-in (the 15.0 debt) |
| **Metered provider + spend governor** | **Active** — Phase 15.1 (2026-09-13). `GatewayProvider` reaches the Vercel AI Gateway with `urllib`/`ssl` and a key under `LoadCredential=` (`root:root 0600`, not sealed by decision, ADR-046 row 7 — **revoked and replaced end to end**; a deleted key answers 400, not 401). One route, `utility` → `openai/gpt-5.6-luna`; `/ask` and `execution-agent` stay on the subscriptions. The governor (`spend.py`, `spend.json`) reserves at maximum before egress across eight rolling windows, settles at actual usage, keeps attended/unattended apart, persists under `flock`, **fails closed** (twice for real: 403, 400 → settled at maximum). Approved serving providers are an owner-signed list; every request carries `providerOptions.gateway.only`. **Costs are no longer zero: $0.0000422 for the phase**, reconciled to the dashboard to nine decimals. The `homelab-agent` account can replace `config.json` (a ceiling path); the key's $10/week is the backstop |
| **Model executor** | **Active** — `/ask`, two providers with independent usage limits and automatic fallback, cheapest model by default. **Phase 15.0:** models are a registry in root-owned `config.json` (`providers → models`, `routes`, `default_route`); the caller asks by routing key (`role`, absent → `owner-interactive`), unknown key refused; `unattended` eligibility per provider refused before the cap reservation (proved by fixture); an owner floor on every provider; hints (`priority`, `severity`, `complexity`, `summary`) logged, never selecting; any other field refused by name. The model gets **no tools** (verified with a canary), and its output is never dispatched |
| **Encrypted data volume** | **Active, locked at boot** — `ubuntu-vg/data` (LUKS2, 128 GiB) → mapper `homelab-data` → ext4, mounted at `/srv/homelab`. Unlocked manually over SSH via `data-volume.sh unlock`; `noauto` in `/etc/crypttab` and `/etc/fstab` keeps boot from waiting on it (ADR-037, Phase 18.1) |
| **Watchdog / notifier** | **Active** — token via `LoadCredentialEncrypted=` (TPM2-sealed, Phase 13) in both, as in the bot; `homelab-watchdog.timer` (`OnBootSec=90s`, `WantedBy=timers.target`) → `homelab-watchdog.service` (oneshot, `User=homelab-bot`, `SupplementaryGroups=systemd-journal`, `LoadCredential=` on the bot's token, `RestrictAddressFamilies=AF_INET AF_INET6`). Classifies the previous stop from PID 1's journal (`Shutting down.` present → clean, absent → unplanned), computes downtime from `journalctl --list-boots`, reads lock state from `/etc/crypttab` + `findmnt`. `homelab-notify@.service` is the single send primitive and the `OnFailure=` target for the bot (drop-in), the model helper (drop-in) and the watchdog; it has no `OnFailure=` of its own. Three boots observed 2026-09-12: enable, clean reboot, power cut — all reported correctly (Phase 12) |
| **`homelab-data.target` + `homelab-workbench.service`** | **Active pattern** — `ConditionPathIsMountPoint=/srv/homelab`, `PartOf=`/`WantedBy=homelab-data.target`, and **no `WorkingDirectory=` on the volume** (implicit `RequiresMountsFor=` would run before the Condition — found by a false alert, Phase 18.2). A dependent unit started while locked is skipped, not failed; `is-system-running` stays `running` either way. The Workbench is the canary; the 18.1 probe is removed. Contract: `docs/standards/volume-dependent-services.md` |
| **Factory Workbench** | **Active** — `homelab-workbench.service`, `User=aleix`, `python3 -m workbench.cli --project /srv/homelab/projects/factory serve` from `/srv/homelab/factory` via `PYTHONPATH`. Binds `127.0.0.1:8765` only (refused otherwise in `server.py`); reached through `ssh homelab-workbench`; no application login — the OS user is the boundary (ADR-035 §7, ADR-036 §5, ADR-038). `OnFailure=homelab-notify@workbench.service`. Score 1.3 OK. **Writes records into `projects/factory/ops/` and never commits** — the owner commits by hand (Phase 18.2) |
| **Harness — the endpoint** | **Active** — `homelab-harness.service` (Phase 23.0, 2026-09-13), `User=homelab-harness`, `127.0.0.1:8766` only (refused otherwise in code), `StateDirectory=/var/lib/homelab-harness` on root holding `audit.jsonl` — one line per request, **no content** (ids, labels, enums, lengths; proved on the file). `POST /v1/request` with a closed schema; identity fields in the body refused by name; `role` required; a deterministic four-class taxonomy (only `question` is served; `task` → `needs_decomposition` for 23.1). Forwards to the helper as a member of `homelab-model`; hints carried, never selecting. `GET /health/helper` pings the helper without a model call. `OnFailure=homelab-notify@harness.service`. Score **1.3**; `AF_UNIX` the one waiver. **`client` is a declared label, not an identity** (23.3). Up after a locked reboot |
| **Second adapter — `Workbench → homelab`** | **Active, proved** — `factory` `workbench/adapters/homelab.py`, selected by `ops/project.json` `"adapter": "homelab"` (default `fake`); `python3 -m workbench.cli run <item>` is the one action that calls it. The Phase 20.0 §8.1.3 check run locally and on the node: records byte-identical apart from `Result` fields, the adapter name, the request id and the `adapter` key — **the adapter interface is proved** (2026-09-13). `Result` carries no correlation field; the request id reaches the run record out of band (to 23.3) |
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
  until a new ADR names it a client (ADR-044 §4). Autonomous model calls are normal in principle
  (ADR-040); **the budget control that makes them safe exists since Phase 15.1** (the spend
  governor, proved on the node) — what remains is the client decision
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
- ~~the harness endpoint (Phase 23.0)~~ — **built** (2026-09-13): layers 1, 2 and 9 as
  `homelab-harness.service`. Layers 3–4 (23.1), 6 (23.2) and governance (23.3) are not; a `task` is
  refused, not decomposed, and `client` is a label
- a dedicated Workbench account — it runs as `aleix` under `NoNewPrivileges`; Phase 13 takes or
  declines the upgrade with a reason (Phase 18.2)

Update this document when a phase changes the actually deployed architecture.

## Phase 13 additions (2026-09-13)

| Component | State |
|---|---|
| **BIOS supervisor password, Boot Order Lock, PXE off** | **Active** — set at the box; boot proceeds unattended (rows 10–11 observed); password in the password manager only |
| **TPM2-sealed bot token** | **Active** — `/etc/homelab-telegram-bot/token.cred`, `systemd-creds --with-key=tpm2 --tpm2-pcrs=""`; `credential.conf` drop-ins on bot, notifier, watchdog; no plaintext on the node; rollback `p13-s3.sh creds-undo` |
| **Console idle timeout** | **Active** — `/etc/profile.d/homelab-console-timeout.sh`, `TMOUT=900` readonly on `/dev/ttyN` only; SSH unaffected (both halves observed) |
| **Recovery SSH key** | **Active** — second line in `authorized_keys`; private half `age`-encrypted at `homelab-backup/recovery-key/` on the card; never on the node |
| **Tailscale ACL** | **Active** — `config/tailscale/acl.hujson`; a new reachable listener adds its port there in the same commit as its socket-table row |
| **Service security baseline** | **Standard** — `docs/standards/service-security-baseline.md`; scores recorded per unit; 15.0's units meet it on day one |

