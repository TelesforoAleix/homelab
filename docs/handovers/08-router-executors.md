# Phase 08 Brief — Router & Executors

- **Date:** 2026-09-09
- **Phase:** 08 — Router & Executors
- **Author:** the Phase 08 context
- **Status:** Accepted, self-ratified under ADR-017
- **Previous handover:** [`07-telegram-handover.md`](07-telegram-handover.md)

## 0. Governance note

Under ADR-017 there is no Project Planning context to ratify this brief. It is written and committed
**before implementation begins**. Seventh consecutive phase to do so.

### Three scope decisions taken with the owner before writing

Asked and answered on 2026-09-09:

1. **The model executor is an interface, not a connection.** The abstraction is built and registered;
   no credential is wired to it. ADR-008 authorises subscription-backed *interactive* access and says
   nothing about unattended use, and the roadmap says routing stays deterministic initially. Phase 09
   needs real transcription and is the natural place to settle the credential question on its merits.
2. **One narrowly-scoped privileged action**, through an auditable mechanism rather than by widening
   the service account. ADR-011 explicitly anticipates "controlled executors/escalation", and an
   escalation boundary that is never crossed has never been tested.
3. **The router lives in the bot process.** One service, one unit, one account. ADR-006 says build
   the simple flow manually before frameworks; the layering can be clean in code without being
   separate processes, and this preserves Phase 07's verified security properties exactly.

## 1. Purpose

Phase 07 built an interface. This phase builds the **structure behind it**, and it is the first
phase whose deliverable is an abstraction rather than a thing that runs.

Three reasons it matters more than a refactor:

- **ADR-011 has never been tested.** "Run bot/router services unprivileged and introduce controlled
  executors/escalation for operations that genuinely require additional permissions" has been an
  accepted principle since bootstrap. Phase 07 satisfied the first half by having nothing to
  escalate. This phase is the first to need the second half.
- **ADR-006 and ADR-007 become real or they do not.** "Build interface → router → executor manually
  before frameworks" and "define model access behind replaceable executors" are shapes on paper
  until something is actually shaped that way.
- **Everything after this inherits the pattern.** Phase 09 adds a transcription executor, Phase 10 a
  knowledge executor, Phase 12 automation. If the boundary is wrong here, it is wrong four times.

### 1.1 This phase is lockout-class, and unlike Phase 07 the risk is real

Phase 07 was boot-class because it added a unit `WantedBy=multi-user.target` — technically in
ADR-020's table, realistically low risk.

This phase touches **`/etc/sudoers.d/`**, which is in the standard's **Authentication** row. That is
different in kind:

> **A malformed sudoers file can break `sudo` entirely.** Not degrade it — break it. On a machine
> with no console, where the admin account's only escalation path is `sudo`, that is the most direct
> route to an unrecoverable state this project has yet had.

The standard already names the control (§4 of `safe-changes-headless.md`):

```bash
sudo visudo -c -f /etc/sudoers.d/homelab-bot
```

`visudo` refuses to install a file that would lock out `sudo`. **Never edit a sudoers file with a
plain editor, and never write one with `install` or a heredoc without validating it first.** This
brief makes that a functional objective rather than a footnote, and the phase also keeps a second
session open with a working `sudo` throughout.

## 2. Starting state

Verified from live output on 2026-09-09 at phase start.

### The node

| Fact | Value |
|---|---|
| OS / kernel | Ubuntu 26.04.1 LTS, `7.0.0-31-generic` |
| Health | `running`; **0** failed units |
| Boot | 24.4s |
| Root filesystem | 8.9 G used, 212 G available (5 %) |
| Python | 3.14.4, standard library only in use |
| Listening | **6 sockets; `:22` only off-box** |
| Docker | 29.8.0, 0 containers, 0 images |

### The service this phase modifies

| Fact | Value |
|---|---|
| Unit | `homelab-telegram-bot.service` — active, enabled, **0 restarts** |
| Account | `homelab-bot` uid 999, `nologin`, no home, groups: **`homelab-bot` only** |
| Hardening | `systemd-analyze security` → **1.3 OK** |
| Code | `/opt/homelab-telegram-bot/bot.py`, `root:root 0644` — the service cannot modify it |
| Token | `/etc/homelab-telegram-bot/token`, `root:root 0600` — the service **cannot read it** |
| Allowlist | `/etc/homelab-telegram-bot/allowlist`, 1 id |
| Exposure | Long polling; **no listening socket** |

### Candidate escalation targets

Running services, filtered against ADR-020's lockout table. **Excluded** because restarting them
could cost access: `ssh`, `tailscaled`, `systemd-networkd`, `systemd-resolved`,
`netplan-wpa-wlp1s0`, `wpa_supplicant`, `systemd-logind`, `dbus`, `polkit`.

**Proposed target: `chrony.service`.** It is real (time sync genuinely matters — certificate
validation and log correlation both depend on it), safe to restart, observably successful via
`chronyc tracking`, and in none of the lockout categories. Final choice is §6.1.

## 3. Learning objectives

By the end the owner should be able to explain:

1. **What a router actually is** — a lookup from a parsed request to a named capability, and why
   making it a table rather than a chain of `if` statements is what allows Phase 09 and 10 to add
   executors without touching it.
2. **Why executors declare a capability level**, and why the check happens in the router rather than
   inside each executor.
3. **The difference between authentication and authorisation**, made concrete by two allowlists: who
   may talk to the bot at all, and who may invoke a privileged executor.
4. **How a scoped `sudoers` rule works** — exact command, no wildcards — and why a wildcard in a
   sudoers rule is usually a full root grant in disguise.
5. **What an audit trail is for**, and why two independent records (sudo's and the bot's) are worth
   more than one.
6. **Why the model executor is registered but unavailable**, and why "we could just call the CLI"
   is a licensing question before it is a technical one.

## 4. Functional objectives

1. An explicit **router**: a registry mapping command → executor, with no command dispatch logic
   outside it.
2. **At least three executors registered**, of at least two capability levels — satisfying the
   roadmap's "multiple executors" without inventing work.
3. A **capability check in the router**, before invocation, so an executor cannot be reached by a
   user not entitled to its level.
4. **Two allowlists**: `allowlist` (may use the bot) and `privileged-allowlist` (may invoke
   privileged executors). The second must be a subset, enforced.
5. **One privileged executor**: restart a service named in an explicit restart allowlist.
6. A **`/etc/sudoers.d/` rule scoped to exactly one command**, no wildcards, installed **only after
   `visudo -c` validates it**.
7. **An audit trail with two independent records** — sudo's own log and the bot's, each naming the
   requesting user, the executor and the outcome.
8. A **model executor interface**, registered and reporting itself **unavailable**, with no
   credential wired. Invoking it returns a clear explanation, not an error.
9. **The service account gains no group and no new file access.** `id homelab-bot` byte-identical to
   phase start.
10. `ss -tln` byte-identical to phase start — still no listening socket.
11. **`sudo` still works for `aleix`**, proved from a new session after the sudoers change.
12. Hardening unchanged or improved; exposure level still ≤ 1.3.

## 5. Decisions already fixed

| Source | Constraint |
|---|---|
| **ADR-006** | Build interface → router → executor manually before frameworks. No agent framework. |
| **ADR-007** | Model access behind replaceable executors; nothing hard-coded around one provider. |
| **ADR-011** | Services unprivileged; escalation explicit and auditable, never ambient. |
| **ADR-008** | Subscription-backed **interactive** access. It does **not** authorise unattended use, API keys, credential export, or paid overage. |
| **ADR-020** | Applies — `/etc/sudoers.d/` is authentication-class (§1.1). |
| **ADR-023** | Long polling, no listening socket, allowlist before dispatch, `LoadCredential` for secrets. |
| **Phase 07 handover** | Do not widen `homelab-bot`. If escalation is needed, design an executor with an auditable boundary. |
| **`AGENTS.md`** | No queues, brokers or gateways because they are common. A router is a dict, not a message bus. |

## 6. Decisions still open

1. **The restart target.** `chrony.service` proposed (§2). Confirm against the exclusion list and
   record the reasoning, including what makes a target *unsafe*.
2. **How the privileged allowlist is expressed** — a second file, or a marker in the existing one.
   Presumption: a **second file**, because a format change to the existing allowlist risks
   misparsing an entry into a privilege grant.
3. **Whether the router is a separate module** or a section of `bot.py`. Presumption: a **separate
   module**, so the boundary is visible in the file listing, while staying one process.
4. **What the model executor reports when invoked.** It must be honest about *why* it is
   unavailable — a licensing decision, not a missing feature.
5. **Whether `/help` is generated from the registry.** Presumption: **yes** — a hand-maintained help
   text is how an undocumented command survives.

## 7. Implementation scope

### 7.1 The shape

```text
Telegram update
      │
      ▼
  allowlist check          ← may this user talk to the bot at all?   (Phase 07)
      │
      ▼
  parse: command + args
      │
      ▼
  ROUTER: registry lookup  ← command → executor. A table, not a chain of ifs.
      │
      ▼
  capability check         ← is this user entitled to THIS executor's level?
      │
      ▼
  EXECUTOR                 ← does one thing; declares what it needs
      │
      ▼
  reply + audit record
```

Two checks, not one. Phase 07 had authentication; this adds **authorisation**, and the distinction
is a learning objective rather than an implementation detail.

### 7.2 Executors

| Executor | Capability | Notes |
|---|---|---|
| `status`, `disk`, `uptime` | **READ** | Existing Phase 07 behaviour, moved behind the registry unchanged |
| `restart` | **PRIVILEGED** | One service, from an explicit restart allowlist |
| `model` | **UNAVAILABLE** | Interface registered; no credential wired (ADR-007, ADR-008) |
| `help` | **READ** | Generated from the registry |

### 7.3 The escalation boundary

A single sudoers rule, exact command, no wildcards:

```text
homelab-bot ALL=(root) NOPASSWD: /usr/bin/systemctl restart chrony.service
```

**Why no wildcards.** `systemctl restart *` would let the bot restart `ssh`, `tailscaled` or
`systemd-networkd` — every lockout-class service on the machine. A wildcard in a sudoers rule is
usually a full root grant wearing a disguise, and this is a good place to see why.

Installation sequence, and the order is the control:

1. Write the file to a **temporary path**.
2. `visudo -c -f <tmp>` — refuse to proceed on any error.
3. Install to `/etc/sudoers.d/homelab-bot`, mode **0440**, `root:root`.
4. `visudo -c` again against the whole configuration.
5. **Prove `sudo` still works for `aleix` from a new session** before doing anything else.

The bot invokes it through `sudo -n` with the exact argument vector. If the rule is wrong, `sudo -n`
fails closed and the executor reports it.

### 7.4 The audit trail

Two independent records, because one can be wrong:

- **`sudo`'s own log** — journald records every invocation and its exit status.
- **The bot's log** — requesting Telegram user id, executor name, arguments, outcome.

Neither may contain the token, the allowlist contents, or anything else sensitive. The Phase 07
`redact()` helper stays in force.

### 7.5 What this phase does not build

Recorded so a later phase does not assume oversight: **no queue, no broker, no scheduler, no agent
framework, no plugin discovery, no dynamic executor loading**. The registry is an explicit dict
written by hand. `AGENTS.md` forbids adding infrastructure because it is common, and dynamic loading
would also defeat the capability check.

## 8. Validation / tests

1. `preflight.sh` from the MacBook before the sudoers change; two sessions, counted with `w`.
2. **`visudo -c` passes** on the new file before installation, and on the whole configuration after.
3. **`sudo` works for `aleix` from a NEW session** after the change — established sessions prove
   nothing.
4. `/etc/sudoers.d/homelab-bot` is mode `0440`, `root:root`.
5. **The rule is scoped**: `sudo -l -U homelab-bot` lists exactly one command, no wildcard.
6. `status`, `disk`, `uptime`, `help` work as before for an allowlisted user.
7. **`/help` is generated from the registry** — adding an executor changes it without editing text.
8. **A privileged command from a non-privileged allowlisted user is refused**, and the refusal is
   logged and distinguishable from "unknown command".
9. **The privileged executor works** for a privileged user: the target service restarts, proved by
   its unit's `ActiveEnterTimestamp` moving.
10. **The bot cannot restart anything else** — proved by attempting a non-allowlisted service and
    capturing the refusal, at both the executor and the `sudo` layer.
11. **Both audit records exist** for one invocation, and neither contains a secret.
12. The model executor reports itself unavailable with an honest reason; no credential is read.
13. **`id homelab-bot` byte-identical to phase start.**
14. **`ss -tln` byte-identical to phase start.**
15. `systemd-analyze security` still ≤ 1.3.
16. A failing executor does not kill the service — the Phase 07 fault isolation still holds.
17. **Reboot test**: the service returns, and both routes prove from new connections.
18. `systemctl is-system-running` → `running`, 0 failed units — checked **last**.

## 9. Security considerations

### 9.1 The escalation boundary is the whole phase

Everything else is plumbing. The question this phase answers is: *can a service that must remain
unprivileged perform one privileged action without becoming privileged?*

The answer is a scoped sudoers rule, and the properties that make it acceptable:

- **Exactly one command.** No wildcards, no shell, no argument interpolation.
- **The account gains nothing else.** No group, no file access, no capability.
- **It fails closed.** `sudo -n` with a non-matching command is refused by sudo itself, before the
  bot's own check matters.
- **It is auditable twice**, by two systems that do not share a failure mode.

### 9.2 A wildcard would undo all of it

`systemctl restart *` reaches `ssh`, `tailscaled` and `systemd-networkd` — every service whose loss
costs access to this machine. The narrowness is not tidiness; it is the control.

### 9.3 Authorisation is not authentication

Phase 07 proved *who is talking*. It said nothing about *what they may do*, because everything was
read-only. Introducing a privileged action makes that distinction load-bearing, which is why there
are two allowlists and why the second is enforced as a subset — a user cannot be privileged without
first being permitted.

### 9.4 The model executor is deliberately inert

Wiring `claude -p` would work today and cost nothing. It is not done because ADR-008 authorises
interactive subscription use and is silent on unattended use, and because the provider terms for
automated use of a personal subscription are **not something this project has established**. That is
an unknown, not a formality, and the honest response is to build the interface and leave the
credential decision to a phase that needs it.

### 9.5 Nothing new is exposed

No listening socket, no new port, no inbound path. The exposure model from ADR-023 is unchanged, and
validation item 14 checks it rather than assuming it.

### 9.6 The repository is public

The sudoers rule, the router and the executor registry all become public. That is fine — they are
mechanism. The allowlists remain on the node. `scan-history.sh` runs before the push.

## 10. Repository changes expected

| Path | Change |
|---|---|
| `docs/handovers/08-router-executors.md` | **This brief** — committed first |
| `services/telegram-bot/router.py` | New — registry, capability check, dispatch |
| `services/telegram-bot/executors.py` | New — the executors, including the inert model interface |
| `services/telegram-bot/bot.py` | Modified — dispatch delegated to the router |
| `services/telegram-bot/privileged-allowlist.example` | New |
| `services/telegram-bot/restart-allowlist.example` | New |
| `config/sudoers.d/homelab-bot` | New — the scoped rule |
| `scripts/server/install-bot-escalation.sh` | New — `visudo`-validated installation |
| `scripts/server/verify-telegram-bot.sh` | Extended — escalation scope and audit checks |
| `guide/08-router-executors/README.md` | New — the phase guide |
| `docs/decisions/ADR-024-…` | New — router/executor architecture and the escalation boundary |
| `docs/build-log/2026-09-09-phase-08-*.md` | New |
| `docs/handovers/08-router-executors-handover.md` | New — addressed to Phase 09 |
| `docs/reference/project-state.md`, `software-stack.md`, `costs.md` | Updated |
| `docs/architecture/current-architecture.md` | **Updated** — the Router and Executor layers now exist |
| `ROADMAP.md`, `CHANGELOG.md`, `docs/handovers/README.md`, `guide/README.md`, `scripts/README.md` | Updated |

## 11. Guide documentation required

`guide/08-router-executors/README.md`:

- Leads with **authentication versus authorisation**, using the two allowlists.
- Shows the scoped sudoers rule and explains **why a wildcard would undo the whole design**.
- Explains why the model executor is registered but inert — a licensing decision, not a gap.
- Records the reference-build experience, including what went wrong.

## 12. Project documentation required

As listed. **`current-architecture.md` needs real revision**: `Interface → Router → Executor` has
been aspirational since bootstrap and two of the three layers will exist.

## 13. ADRs required / possible

| ADR | Status | Subject |
|---|---|---|
| **ADR-024 — router/executor architecture and the escalation boundary** | **Required** | Registry-based routing; capability levels; two allowlists; scoped sudoers over group membership; the model executor registered but unwired, and why. Records rejected alternatives including widening the service account and wiring subscription CLIs. |
| Unattended AI credentials | **Not this phase** | Carried to Phase 09, which needs transcription and must decide on its merits. |

## 14. Costs

**Expected: 0 DKK.** No new services, no API calls, no subscriptions. The model executor is
deliberately unwired, so no usage is billed. Running total unchanged.

## 15. Definition of Done

From `PROJECT.md` §12, applied **literally, item by item**:

- [ ] Functional objective works — all twelve in §4
- [ ] Configuration/setup is reproducible — router, executors, sudoers rule all from committed files
- [ ] Validation/tests have passed — all eighteen checks in §8, with captured output
- [ ] Important security implications were considered — §9; the escalation boundary proved by
      attempting what must fail
- [ ] Relevant repository files are committed
- [ ] Human-facing guide is updated
- [ ] Project/internal documentation is updated, including the architecture document
- [ ] ADRs created or updated — ADR-024
- [ ] Actual costs recorded — explicit zero
- [ ] Problems, failed approaches and lessons recorded, including my own errors
- [ ] Tested versions recorded
- [ ] No unexplained critical AI-generated component remains
- [ ] `main` represents a known-working state — after `--no-ff` merge
- [ ] System reports no failed units and no degraded state — checked **last**, after the reboot test
- [ ] Structured handover written, stating what Phase 09 inherits

## 16. Return handover requirements

Addressed to **Phase 09 — Voice**, and must state:

1. **How to add an executor** — the registry entry, the capability level, and where the checks
   happen. Phase 09 adds a transcription executor and should not need to modify the router.
2. **The unresolved credential question**, inherited from Phase 06 and deliberately not answered
   here. Phase 09 needs a real model call and must decide on its merits — subscription, API key, or
   local — and record it as an ADR. **It must not be resolved by copying a personal OAuth file to a
   service account.**
3. **The exact escalation grant**, and that widening it is a decision, not a convenience.
4. **The audit trail's shape**, so Phase 12's automation extends it rather than inventing a second.
5. **Open risks carried forward**, plus anything this phase adds — in particular that the node still
   has no backup and no alerting, and that Phase 09 will add the first *data* worth losing.
