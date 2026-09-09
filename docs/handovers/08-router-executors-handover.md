# Phase 08 Handover — Router & Executors

- **Date:** 2026-09-09
- **From:** Phase 08 phase context
- **To:** Phase 09 — Voice
- **Brief:** [`08-router-executors.md`](08-router-executors.md), committed before implementation as `0d2ff86` per ADR-017

## Outcome

**Complete.** All twelve functional objectives met. The service account gained
**nothing** and can perform one privileged action, proved end-to-end after a
reboot with two independent audit records.

## What the next phase inherits

> Read this first. Under ADR-017 there is no planning context to reconcile any of
> it; if it is not written here, it is lost.

### 1. How to add an executor — you should not need to touch the router

```python
router.register(Executor(
    name="/transcribe",
    capability=Capability.READ,        # or PRIVILEGED
    handler=my_handler,                # (args: list[str]) -> str
    summary="shown in /help",
))
```

That is the whole contract. The authorisation check lives in `Router.dispatch()`
and nowhere else, so a new executor **cannot** be unprotected by accident.
`/help` is generated from the registry, so it updates itself.

**If Phase 09 finds itself editing `dispatch()`, something has gone wrong** —
either the capability model needs a new level (an ADR), or the executor is doing
too much.

Current registry: `/status`, `/disk`, `/uptime` (READ), `/restart` (PRIVILEGED),
`/model` (UNAVAILABLE), `/help` (READ, generated). `/start` is an alias.

### 2. ⚠️ The credential question is still open, and it is now yours

Phase 06 raised it. Phase 07 did not touch it. Phase 08 **deliberately did not
answer it**, and built the interface so that answering it is a small change:

> Whether personal, subscription-backed CLIs are technically supported and
> appropriate for **unattended executor use**.

`/model` is registered and returns an explanation rather than an error. Wiring
`claude -p` would work today and cost nothing — **which is exactly why the
decision must be made deliberately rather than by default.**

ADR-008 authorises subscription-backed **interactive** access. It is silent on
unattended use, and whether automating a personal Claude Pro or ChatGPT
subscription behind a service is within either provider's terms is **not
something this project has established.** That is an unknown, not a formality.

**Phase 09 needs a real model call** (transcription) and must decide on the
merits — subscription, paid API key, or a local model — and record it as an ADR
with the costs. **It must not be resolved by copying a personal OAuth credential
to a service account because it works interactively.** `homelab-bot` provably
cannot read either credential file today; keep it that way.

### 3. The exact escalation grant, and that widening it is a decision

| Fact | Value |
|---|---|
| Mechanism | **polkit**, `/etc/polkit-1/rules.d/50-homelab-bot.rules` |
| Scope | one user (`homelab-bot`), one unit (`chrony.service`), one verb (`restart`) |
| sudoers entries | **zero** |
| `id homelab-bot` | `uid=999 gid=982 groups=982` — **byte-identical to phase start** |
| Second gate | `/etc/homelab-telegram-bot/restart-allowlist`, checked inside the bot |
| Proved denied | `ssh.service`, `tailscaled.service`, `systemd-networkd.service` |

**Why polkit and not sudo, because Phase 09 will be tempted by sudo:**

```console
$ setpriv --no-new-privs sudo -n true
sudo: The "no new privileges" flag is set, which prevents sudo from running as root.
```

The unit sets `NoNewPrivileges=yes`. `sudo` is setuid and is refused outright.
**Using sudo means removing the hardening in order to add the escalation.** polkit
decides inside PID 1, so the flag stays on. It is also safer to get wrong: a
malformed polkit rule **denies**; a malformed sudoers file **breaks `sudo`** on a
node with no console.

**Two gates, in two processes, neither trusting the other.** Adding a unit to the
bot's allowlist grants nothing without a matching polkit rule, and vice versa.
Keep it that way — and never add a unit whose loss costs access to the machine.

### 4. The audit trail's shape — and polkit is not part of it for grants

Two independent records. Correlate on timestamp:

```text
20:00:37  homelab-telegram-bot:  user <id>: /restart chrony
20:00:37  homelab-telegram-bot:  restart chrony.service: ok
20:00:37  systemd[1]:            Stopping chrony.service ...
20:00:37  systemd[1]:            Started chrony.service ...
```

- **The bot's log** — requesting user, executor, arguments, outcome, and refusals.
- **systemd's log (PID 1)** — the action *happening*, not an intention to perform
  it. Different process, different failure mode.

**polkit logs denials but not grants.** Measured: a rule-based `YES` produces
zero journal lines, and a `polkit.log()` call is filtered at the default log
level. Do not rely on it for approvals.

Phase 12's automation should **extend these two records rather than invent a
third**.

### 5. Two Phase 07 properties were traded, deliberately

Both are real losses and are recorded rather than glossed:

- **The bot now forks.** `/restart` execs `systemctl`, so "the bot never forks a
  process" no longer holds. What replaces it: `NoNewPrivileges` retained, empty
  `CapabilityBoundingSet`, and authority that lives entirely outside the process.
- **`AF_UNIX` is permitted**, because `systemctl` reaches PID 1 over a UNIX
  socket. Checked rather than assumed: this does **not** open the Docker socket,
  which is `root:docker 0660` to an account in no group but its own.

Exposure level is **unchanged at 1.3 OK**, and listeners are **unchanged at 6**.

### 6. Open risks carried forward

| Risk | Owner |
|---|---|
| **The node still has no backup of any kind** | Phase 13 — **and Phase 09 adds the first data worth losing** |
| **No alerting.** If the bot dies at 3am nothing says so; bounded logging means a quiet journal ≠ healthy | Phase 13 |
| Single SSH key, no backup, no console | Phase 13 |
| No firewall; `:22` open on the LAN | Phase 13 |
| No encryption at rest (ADR-015) | Phase 13 — **Phase 10 must revisit ADR-015 first** |
| `aleix` in the `docker` group — root-equivalent, no password | ADR-022 |
| Volume group has no free extents | Not owned |
| IPv4/IPv6 `FORWARD` asymmetry | Phase 13 must not assume symmetry |
| Wi-Fi single point of failure for **both** routes; `eno1` unused | Not owned |
| Telegram is a third party; all messages transit and are stored there | **Phase 09 — voice notes are more sensitive than uptime figures** |
| **New:** one thing can now change the system. Small, scoped, proved — but Phase 07's "a compromise cannot act" no longer holds | ADR-024 |

**Phase 09 should think hard about the Telegram row.** Uptime figures transiting
a third party is one risk assessment; voice recordings of the owner is a
different one, and it deserves its own paragraph in that brief rather than
inheriting this one.

## Validation performed

All eighteen checks from the brief's §8.

| Check | Result |
|---|---|
| `preflight.sh`, two sessions | ✅ 0 failed |
| Escalation installed with validation | ✅ scope, braces, polkit load errors all checked before use |
| **Grant works** | ✅ `chrony` restarted; `ActiveEnterTimestamp` moved |
| **Grant does not extend** | ✅ `ssh`, `tailscaled`, `systemd-networkd` all **DENIED by polkit**, asserted on the reason |
| Grant is scoped | ✅ one user, one unit, one verb; **0 sudoers entries** |
| READ executors unchanged | ✅ `/status`, `/disk`, `/uptime` behave as Phase 07 |
| `/help` generated from registry | ✅ six executors with capability markers |
| **Privileged refused for non-privileged user** | ✅ distinguishable from "unknown command" |
| **Second gate independent of polkit** | ✅ `/restart ssh` refused by the bot before `systemctl` ran |
| Both audit records exist, no secrets | ✅ bot + systemd, correlating at 20:00:37 |
| Model executor inert and honest | ✅ explains the licensing decision |
| **`id homelab-bot` unchanged** | ✅ byte-identical |
| **`ss -tln` unchanged** | ✅ 6 |
| Exposure | ✅ still **1.3 OK** after `AF_UNIX` |
| Failing executor does not kill the service | ✅ 0 restarts |
| **Reboot test** | ✅ 24.4s boot; service enabled+active, **0 restarts**; correct config loaded |
| **Grant survives reboot** | ✅ proved end-to-end from Telegram after boot |
| Health, checked last | ✅ `running`, 0 failed |

## Problems / failures / lessons

Five, in [`docs/build-log/2026-09-09-phase-08-router-executors.md`](../build-log/2026-09-09-phase-08-router-executors.md).
Three generalise:

1. **The brief specified a mechanism the runtime forbids** (`sudo` vs
   `NoNewPrivileges`). Second consecutive phase, after `ProcSubset=pid`. *A brief
   is written against documentation; documentation describes what a mechanism
   does, not what this machine will permit.*
2. **A test prompted the admin instead of testing the account**, and printed `ok`
   when nobody answered — asking a human to restart `tailscaled` on a
   console-less node, and reporting a pass for the wrong reason. Fixed with
   `--no-ask-password` *and* by asserting on the reason.
3. **The same mistake again, four minutes later**, in an ad-hoc command:
   `setpriv` failed with `Operation not permitted` and that error was read as a
   negative result about a security property. Seventh instance in the project.
   *The structural defences in `scan-history.sh` and `verify-telegram-bot.sh`
   held — the failure moved to the one place they had never been applied.*

> **Any command whose output you will act on is a check**, including the
> throwaway one typed at a terminal. That is where the belief actually forms, and
> it is the least reviewed code in the project.

Also: **polkit does not log grants**, only denials — an audit claim I made and
had to correct by measurement.

## Deviations from phase brief

1. **polkit instead of the specified sudoers rule.** Forced by
   `NoNewPrivileges`, and an improvement: its failure mode is denial rather than
   losing `sudo`. polkit was among the mechanisms the owner approved.
2. **`AF_UNIX` added to `RestrictAddressFamilies`.** Required for `systemctl` to
   reach PID 1. Not anticipated by the brief.
3. **The privileged executor forks**, contrary to the Phase 07 property the brief
   assumed would hold.
4. **The audit trail's second record is systemd's, not polkit's.** The brief said
   polkit would log every decision. It does not.

## ADRs

| ADR | Status | Note |
|---|---|---|
| **ADR-024 — router/executor architecture and the escalation boundary** | **Accepted** | Registry routing; capability levels; two allowlists; polkit over sudo with the reasoning; the model executor registered and inert |
| ADR-006 / ADR-007 / ADR-011 | **Implemented** | First phase in which all three are code rather than principle |
| ADR-008 | Referenced | Why `/model` is inert |
| ADR-020 / ADR-023 | Referenced | Console-less change safety; the Phase 07 service extended |

## Tested versions

| Component | Version |
|---|---|
| Python | 3.14.4 — standard library only, still no third-party package |
| polkit | 127 |
| systemd | 259 |

`NoNewPrivileges` blocking `sudo` reproduces on any systemd with the directive;
polkit JS rules need polkit ≥ 0.106.

## Costs

**0 DKK**, explicit zero. No new services, no API calls, no subscriptions — the
model executor is deliberately unwired, so nothing is billed. Running total
unchanged at **899 DKK (~121 EUR)** plus the existing AI subscriptions.

## Recommended roadmap changes

Actioned directly, since ADR-017 leaves no recipient:

1. **Phase 08 marked complete** in `ROADMAP.md`, with the inert model executor
   stated inline so Phase 09 cannot assume it is wired.
2. **Phase 09 must resolve the unattended-credential question** and record it as
   an ADR with costs.
3. **Phase 09 must reassess the Telegram third-party risk for voice**, rather
   than inheriting the assessment made for uptime figures.

No phase renumbering required.

## Definition of Done

- [x] Functional objective works — all twelve in §4 of the brief
- [x] Configuration/setup is reproducible — router, executors, polkit rule and
      allowlists all deployed from committed files, `scp`'d with SHA256 verified
- [x] Validation/tests have passed — all eighteen checks, with captured output
- [x] Important security implications were considered — the escalation boundary
      proved in both directions, by attempting what must fail
- [x] Relevant repository files are committed
- [x] Human-facing guide is updated — `guide/08-router-executors/README.md`
- [x] Project/internal documentation is updated, including the architecture document
- [x] ADRs created or updated — ADR-024 accepted
- [x] Actual costs recorded — explicit 0 DKK
- [x] Problems, failed approaches and lessons recorded — five, three of them mine,
      including making the same error twice within minutes
- [x] Tested versions recorded
- [x] No unexplained critical AI-generated component remains — the router's
      authorisation check is commented as the single boundary it is
- [x] `main` represents a known-working state — after `--no-ff` merge
- [x] System reports no failed units and no degraded state — checked **last**,
      after the reboot
- [x] Structured handover written, stating what Phase 09 inherits
