# Phase 07 Brief — Telegram Interface

- **Date:** 2026-09-09
- **Phase:** 07 — Telegram Interface
- **Author:** the Phase 07 context
- **Status:** Accepted, self-ratified under ADR-017
- **Previous handover:** [`06-ai-cli-access-handover.md`](06-ai-cli-access-handover.md)

## 0. Governance note

Under ADR-017 there is no Project Planning context to ratify this brief. It is written and committed
**before implementation begins**. Sixth consecutive phase to do so.

### Three scope decisions taken with the owner before writing

Asked and answered on 2026-09-09:

1. **A native systemd service, not a container.** A dedicated unprivileged account plus systemd
   hardening directives. Docker remains available for workloads that genuinely need it; a small
   deterministic poller is not one, and systemd's directives express ADR-011 more directly than an
   image would.
2. **Read-only status commands.** Report only, change nothing. The bot needs no privilege beyond
   reading its own metrics, so a compromise leaks information but cannot act. Phase 08 owns the
   executor and escalation pattern; designing privilege escalation inside a phase whose roadmap
   entry says "keep it unprivileged" would be working against the brief.
3. **Python.** 3.14.4 and `venv` are already installed. No new runtime, no new apt source, and it is
   the natural base for the Phase 08 router work.

## 1. Purpose

Six phases in, the reference node is well built and **does nothing for the owner**. This is the
first phase that produces something used rather than something owned.

It also carries three firsts that make it more consequential than its size suggests:

- **The first long-running service this project has written.** Everything so far has been installed
  or configured; this is code that runs unattended and restarts at boot.
- **The first live secret since the repository became public.** A bot token is a bearer credential:
  anyone holding it *is* the bot. Phase 04 made a committed secret a disclosure rather than an
  amendable mistake (ADR-021).
- **The first genuine test of ADR-011.** Privilege separation has been an accepted principle since
  bootstrap and has never had a service to apply to. It does now.

There is a fourth reason, inherited verbatim from Phase 06 and not negotiable here:

> The Phase 07 Telegram process must run as a separate unprivileged account, with no access to
> `/home/aleix`, either OAuth file, `sudo`, or the Docker group, and must remain deterministic
> rather than invoking the AI CLIs directly.

`aleix` holds passworded `sudo` and root-equivalent Docker-group access. Nothing in this phase may
inherit that.

### 1.1 This phase is lockout-class, and the reason is not obvious

`docs/standards/safe-changes-headless.md` lists under **Boot**: *"anything
`WantedBy=multi-user.target`"*. A bot service enabled to start at boot is exactly that.

The realistic risk is low — a failing bot unit does not normally prevent boot. But the standard's
central argument is that **most lockouts come from not noticing a safety step applied**, and a unit
with a careless `After=`/`Requires=` or a `Restart=always` tight loop can absolutely degrade a boot
on a machine with no console. So it gets the procedure, not a shrug:

- `preflight.sh` from the MacBook before enabling anything at boot;
- two sessions, counted with `w`;
- `systemd-analyze verify` before `systemctl enable`;
- **a reboot test**, because "it starts when I start it" is not the same claim as "it starts at
  boot", and this is the first phase where the difference matters.

## 2. Starting state

Verified from live output on 2026-09-09 at phase start.

### The node

| Fact | Value |
|---|---|
| OS / kernel | Ubuntu 26.04.1 LTS (`resolute`), `7.0.0-31-generic` |
| Health | `running`; **0** failed units |
| Root filesystem | 232 G, 8.9 G used (5 %), 212 G available |
| **Python** | **3.14.4**, with `venv` available. `pip3` is **not** on `PATH` |
| Node.js / npm | **Not installed** |
| Docker | 29.8.0, Compose v5.5.1 — available, deliberately unused by this phase |
| Human accounts | **`aleix` (1000) only.** No service accounts exist yet |
| AI CLIs | Claude Code 2.1.236, Codex 0.153.4 — owned by `aleix`, **out of bounds here** |

### Listening sockets — the baseline this phase must not change

```text
0.0.0.0:22        and  [::]:22                    sshd
127.0.0.53:53     and  127.0.0.54:53              systemd-resolved (loopback)
100.71.62.71:36121                                tailscaled
[fd7a:115c:a1e0::…]:57273                         tailscaled (IPv6)
```

**`:22` is the only port reachable off-box.** Long polling means the bot opens *outbound*
connections only, so **this list must be byte-identical at phase close**. A new listener is a
finding, not a feature.

## 3. Learning objectives

By the end the owner should be able to explain:

1. **Why a Telegram bot needs no inbound port.** Long polling is an outbound HTTPS request the
   server holds open. There is no webhook, no port forward, no public address — which is the only
   reason this is safe on a node with no firewall.
2. **What a bot token actually is.** Not a password with a user behind it: a bearer credential.
   Whoever holds it is the bot, from anywhere, with no second factor.
3. **Why an allowlist is mandatory rather than optional.** Any Telegram user who finds the bot can
   message it. Without an allowlist the "read-only status" bot reports this machine's state to
   strangers.
4. **What systemd hardening directives actually do** — `ProtectHome`, `ProtectSystem=strict`,
   `NoNewPrivileges`, `PrivateTmp`, `RestrictAddressFamilies`, `SystemCallFilter` — and how to
   verify them on the **running** unit rather than trusting the file.
5. **The difference between a service account and a human account**: no shell, no home, no groups,
   no login.
6. **Why `systemctl start` working is not evidence that boot works.**
7. **How to keep a secret out of logs**, and why journald is a place secrets go to live forever.

## 4. Functional objectives

1. A dedicated **unprivileged service account** exists: no login shell, no password, **not** in
   `sudo`, **not** in `docker`, and with no read access to `/home/aleix`.
2. The bot runs under **systemd** as that account, enabled at boot, with a restart policy that
   backs off rather than looping.
3. **Long polling only.** No inbound port. `ss -tln` byte-identical to §2.
4. **The token never enters the repository, this conversation, or a shell history.** Stored on the
   node at mode `0600`, owned by the service account, loaded by systemd.
5. **An allowlist of permitted Telegram user IDs.** Anyone not on it receives a refusal and no data.
6. Read-only commands, deterministic, no AI: at minimum `/status`, `/disk`, `/uptime`, `/help`.
7. Hardening **verified on the running unit** — `systemd-analyze security` and direct probes, not a
   reading of the unit file.
8. **Isolation proved, not asserted**: the service account demonstrably cannot read `/home/aleix`,
   either OAuth file, or the Docker socket.
9. The bot survives **Telegram being unreachable** without crash-looping or spamming the journal.
10. **No token in the journal**, proved by searching it.
11. **A reboot test**: the service comes back automatically, and both SSH routes still work
    afterwards.
12. Everything reproducible from the repository — the bot, the unit, and the account creation.

## 5. Decisions already fixed

| Source | Constraint |
|---|---|
| **ADR-009** | Telegram is the first interface; begin with simple deterministic commands. |
| **ADR-011** | Bot/router services run unprivileged. Escalation is explicit and auditable, never ambient. |
| **ADR-020** | Applies — a unit `WantedBy=multi-user.target` is boot-class (§1.1). |
| **ADR-021** | The repository is public. A committed token is a disclosure; rotation comes before history rewriting. |
| **ADR-022** | If anything is ever published, it names an interface. Nothing should be published here. |
| **Phase 06 handover §2** | Not a service identity. No access to `/home/aleix`, the OAuth files, `sudo`, or the docker group. Deterministic, not CLI-invoking. |
| **`AGENTS.md`** | No Redis/Postgres/queues/gateways because they are common. A status bot needs none. |
| Owner's standing rule | Never commit secrets or MAC addresses. |

## 6. Decisions still open

To be resolved inside the phase and recorded:

1. **Dependency or no dependency.** `python-telegram-bot` is the obvious library, but long polling
   is one HTTPS GET in a loop and the standard library can do it with **zero** third-party code.
   Given `AGENTS.md`'s preference for minimal comprehensible implementations, and that this is a
   learning phase, the presumption is **stdlib only** — decide on the evidence and record it.
2. **How systemd supplies the token** — `LoadCredential=` (kernel keyring-backed, not in the
   environment, not visible in `/proc/PID/environ`) versus `EnvironmentFile=`. Presumption:
   **`LoadCredential`**, because an environment variable is readable by anything that can read the
   process's environ and tends to leak into crash dumps and logs.
3. **Whether the service account gets a home directory at all.** Presumption: no.
4. **The exact command set** beyond the four required.
5. **Whether a `venv` is needed** if the answer to (1) is stdlib-only. Probably not.
6. **How the allowlist is configured** — file, unit environment, or embedded. It is not a secret,
   but it is deployment-specific, so it should not be hardcoded in committed source.

## 7. Implementation scope

### 7.1 The service account

Created by a committed, guarded script, in the manner of `lab-sandbox.sh`: refusing to touch a real
account, refusing to grant `sudo` or `docker`, and verifying the result from the account database
rather than from a command's exit status.

Shape: system account, `--shell /usr/sbin/nologin`, no password, no home (or a mode-`0700` state
directory owned by it, if state proves necessary).

### 7.2 The bot

Deterministic Python, committed to the repository, readable by someone who must be able to modify it
safely. Long polling, no inbound socket. Every command answerable from the host's own state.

**The allowlist is checked before any handler runs**, not inside each one — a single choke point,
so a new command cannot accidentally be unprotected.

### 7.3 The unit

Hardened. At minimum: `User=`/`Group=`, `NoNewPrivileges=yes`, `ProtectSystem=strict`,
`ProtectHome=yes`, `PrivateTmp=yes`, `PrivateDevices=yes`, `ProtectKernelTunables=yes`,
`ProtectControlGroups=yes`, `RestrictAddressFamilies=AF_INET AF_INET6`,
`RestrictNamespaces=yes`, `LockPersonality=yes`, `MemoryDenyWriteExecute=yes`,
`SystemCallFilter=@system-service`, `CapabilityBoundingSet=` (empty), and a backoff restart policy.

**Verified with `systemd-analyze security`**, and the score recorded. Note the Phase 02 lesson:
`systemd-analyze verify` walks the whole dependency closure and will report warnings from unrelated
units, so a clean unit can look broken.

### 7.4 The token

**It must never be typed into this conversation.** Phase 06 recorded a one-time Claude authorization
code entering the agent transcript, and named the fix: paste credentials only into the waiting
terminal. That applies here with more force, because a bot token is long-lived rather than one-time.

The owner creates the bot with BotFather and installs the token on the node directly. The repository
carries the *mechanism* and an example file with a placeholder — never the value.

### 7.5 Validation ordering

The reboot test comes **after** everything else passes and after `preflight.sh`, because it is the
one step that could leave the machine in a state nobody is watching.

## 8. Validation / tests

1. Service account exists with no shell, no password, and is in neither `sudo` nor `docker`.
2. The account **cannot** read `/home/aleix`, either OAuth file, or `/var/run/docker.sock` — proved
   by attempting it as that user and capturing the refusal.
3. `systemd-analyze verify` on the unit before enabling it.
4. `systemd-analyze security` score recorded, and the exposure level noted.
5. Hardening probed on the **running** service, not read from the file.
6. Bot answers `/status`, `/disk`, `/uptime`, `/help` correctly to an allowlisted user.
7. **A non-allowlisted user receives a refusal and no host data.** Tested, not assumed.
8. **`ss -tln` byte-identical to §2** — no new listener.
9. Outbound-only confirmed: the bot's connections are established outbound HTTPS.
10. Token file mode `0600`, owned by the service account, and **not** readable by `aleix`.
11. **`journalctl -u <unit> | grep <token>` returns nothing** — proved with the real token, on the
    node, never printed into this conversation.
12. `git log -S` and `scan-history.sh` confirm the token is absent from the repository and history.
13. Telegram unreachable: the service degrades gracefully, backs off, and does not flood the journal.
14. `systemctl restart` recovers cleanly.
15. **Reboot test**: the unit comes back enabled and running without intervention.
16. **Both SSH routes prove after the reboot**, from genuinely new connections.
17. `systemctl is-system-running` → `running`, 0 failed units — checked **last**.
18. `id aleix` unchanged from phase start.

## 9. Security considerations

### 9.1 A bot token is a bearer credential

Anyone holding it *is* the bot: they can read its messages and post as it, from anywhere, with no
second factor. It is closer to a private key than to a password.

Consequences: never in the repository, never in this conversation, never in a shell history, never
in an environment variable if `LoadCredential` will do, and never in the journal. If it is ever
exposed, **revoke it with BotFather first** — that is rotation, and it comes before any attempt to
clean up wherever it leaked (ADR-021).

### 9.2 Anyone can message a Telegram bot

Bots are discoverable and there is no approval step. Without an allowlist, a "harmless read-only
status bot" publishes this machine's disk usage, uptime and service list to whoever finds it. **The
allowlist is the primary access control**, and it is checked once, before dispatch, so a future
command cannot be added unprotected by accident.

### 9.3 Telegram is a third party

Every message and response transits Telegram's infrastructure and is stored there. That is
acceptable for uptime and disk figures. It is a reason not to extend this bot toward anything
sensitive without revisiting the decision — a note for Phases 08 and 10, not a constraint to solve
here.

### 9.4 Outbound-only is what makes this safe

There is still no firewall. The bot is acceptable on this node *specifically because* long polling
opens no listening socket. **If any future phase moves to webhooks, that changes the exposure model
completely** and requires its own ADR — a webhook needs an inbound, publicly reachable HTTPS
endpoint, which this node does not have and should not acquire casually.

### 9.5 The service account must not become a second `aleix`

The temptation in later phases will be to give it "just a bit" of access — the docker group to
restart a container, a sudo rule to read a log. ADR-011 exists to make that explicit rather than
ambient. Phase 08 owns the executor pattern; **this phase must not pre-empt it by widening the
account**.

### 9.6 The repository is public

The bot's source, the unit and the account script all become public on merge. That is fine and
intended — they contain mechanism, not credentials. The example environment file carries a
placeholder, and `scan-history.sh` runs before the push.

## 10. Repository changes expected

| Path | Change |
|---|---|
| `docs/handovers/07-telegram.md` | **This brief** — committed first |
| `services/telegram-bot/` | The bot source, its example config, and a README |
| `config/systemd/homelab-telegram-bot.service` | The hardened unit |
| `scripts/server/install-telegram-bot.sh` | Guarded account creation and deployment |
| `scripts/server/verify-telegram-bot.sh` | Posture verification, safe to paste |
| `guide/07-telegram/README.md` | The phase guide |
| `guide/README.md`, `scripts/README.md` | Index entries |
| `docs/reference/project-state.md` | Phase 07 status; new service; new risks |
| `docs/reference/software-stack.md` | Python → Active with tested version |
| `docs/reference/costs.md` | Phase 07 — expected explicit zero |
| `docs/decisions/ADR-023-…` | Telegram bot service design (§13) |
| `docs/build-log/2026-09-09-phase-07-*.md` | Problems, failures, lessons |
| `docs/handovers/07-telegram-handover.md` | Addressed to Phase 08 |
| `ROADMAP.md`, `CHANGELOG.md`, `docs/handovers/README.md` | Phase 07 complete |

## 11. Guide documentation required

`guide/07-telegram/README.md`, following Phases 01–06:

- Leads with **why there is no inbound port**, since that is what makes this safe here.
- Explains the token as a bearer credential, and where it must never go.
- Shows the hardening directives with their **verified** effect, not their intent.
- Records the reference-build experience, including what went wrong.

## 12. Project documentation required

As listed in §10. `software-stack.md` records Python 3.14.4 as tested and states whether any
third-party dependency was introduced. `project-state.md` records the first service account and the
first long-running service.

## 13. ADRs required / possible

| ADR | Status | Subject |
|---|---|---|
| **ADR-023 — Telegram bot service design** | **Required** | Native systemd over container; dedicated unprivileged account; long polling over webhooks; allowlist as primary access control; `LoadCredential` over environment; read-only scope with escalation deferred to Phase 08. Records the rejected alternatives. |
| Executor / escalation pattern | **Not this phase** | Phase 08. This brief hands it §9.5 as an inherited constraint. |

## 14. Costs

**Expected: 0 DKK.** Telegram bots are free. No new hardware, no subscription, no paid service.
Running total expected to remain unchanged.

## 15. Definition of Done

From `PROJECT.md` §12, applied **literally, item by item**:

- [ ] Functional objective works — all twelve in §4
- [ ] Configuration/setup is reproducible — account, unit and bot all deployed from committed files
- [ ] Validation/tests have passed — all eighteen checks in §8, with captured output
- [ ] Important security implications were considered — §9, allowlist and isolation proved
- [ ] Relevant repository files are committed
- [ ] Human-facing guide is updated — `guide/07-telegram/README.md`
- [ ] Project/internal documentation is updated
- [ ] ADRs created or updated — ADR-023
- [ ] Actual costs recorded — explicit zero
- [ ] Problems, failed approaches and lessons recorded, including my own errors
- [ ] Tested versions recorded — Python, and any dependency
- [ ] No unexplained critical AI-generated component remains — the bot is commented for a reader who
      must be able to modify it safely
- [ ] `main` represents a known-working state — after `--no-ff` merge
- [ ] System reports no failed units and no degraded state — checked **last**, after the reboot test
- [ ] Structured handover written, stating what Phase 08 inherits

## 16. Return handover requirements

Addressed to **Phase 08 — Router & Executors**, and must state:

1. **The service account's exact privileges**, and that widening it is Phase 08's decision to make
   deliberately rather than inherit.
2. **The escalation design**, if any was sketched — as a proposal, clearly marked as unbuilt.
3. **That the bot is deterministic and calls no AI**, plus Phase 06's unresolved question of whether
   personal subscription CLIs may ever back an unattended executor. Phase 08 owns that.
4. **The exposure model**: outbound-only long polling, no listener, no firewall. And that moving to
   webhooks would change it completely and needs its own ADR.
5. **Where the token lives and how it is supplied**, without the value.
6. **The reboot-test result**, since Phase 08 will add more units to the same boot.
7. **Open risks carried forward** — no node backup, single SSH key, `eno1` unused, no free extents,
   `aleix` in the docker group, IPv4/IPv6 forwarding asymmetry — plus anything this phase adds.
