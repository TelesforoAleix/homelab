# Phase 07 Handover — Telegram Interface

- **Date:** 2026-09-09
- **From:** Phase 07 phase context
- **To:** Phase 08 — Router & Executors
- **Brief:** [`07-telegram.md`](07-telegram.md), committed before implementation as `54a33d2` per ADR-017

## Outcome

**Complete.** All twelve functional objectives met. The verifier passes with
**0 failures and 0 warnings**, and the reboot test passed with zero restarts.

The node now does something for its owner for the first time.

## What the next phase inherits

> Read this first. Under ADR-017 there is no planning context to reconcile any of
> it; if it is not written here, it is lost.

### 1. The service account, and the fact that widening it is your decision

| Fact | Value |
|---|---|
| Account | `homelab-bot`, uid **999**, system account |
| Shell | `/usr/sbin/nologin` |
| Home | none (`/nonexistent`) |
| Groups | **`homelab-bot` only** — not `sudo`, not `docker`, not `adm` |
| Code | `/opt/homelab-telegram-bot/bot.py`, `root:root 0644` — the bot **cannot modify itself** |
| Token | `/etc/homelab-telegram-bot/token`, `root:root 0600` — the bot **cannot read it** |
| Unit exposure | `systemd-analyze security` → **1.3 OK** |

Proved by attempting each access, not by reading directives:

```text
ok  homelab-bot cannot read the admin home directory
ok  homelab-bot cannot read the Claude OAuth credential
ok  homelab-bot cannot read the Codex OAuth credential
ok  homelab-bot cannot read the Docker socket
ok  homelab-bot cannot read the bot token file
ok  homelab-bot cannot modify its own code
```

**The temptation in Phase 08 will be to give it "just a bit" of access** — the
docker group to restart a container, a sudo rule to read a log. ADR-011 exists to
make that explicit rather than ambient. If Phase 08 needs escalation, it designs
it as an executor with an auditable boundary; it does not widen this account.
`install-telegram-bot.sh` re-checks group membership on **every** run and refuses
to proceed if something has added `homelab-bot` to `sudo`, `docker` or `adm`.

### 2. The exposure model, and the one change that would break it

**Long polling. Outbound HTTPS only. No listening socket.**

```text
ok  6 listening sockets, matching the pre-Phase-07 baseline -- the bot added none
```

This is what makes a network service acceptable on a node with **no firewall**,
where `:22` is the only port reachable off-box.

> **Moving to webhooks would change the exposure model completely and requires
> its own ADR.** A webhook needs a publicly reachable inbound HTTPS endpoint,
> which this node does not have and should not casually acquire. It is not a
> configuration detail.

### 3. It is deterministic and calls no AI — and Phase 06's question is still open

The bot invokes neither Claude Code nor Codex. It shells out to nothing at all;
every figure comes from `/proc`, `/etc/hostname` or `statvfs()`.

Phase 06 left a question this phase did not touch and Phase 08 owns:

> Whether personal, subscription-backed CLIs are technically supported and
> appropriate for **unattended executor use**. ADR-008 authorises
> subscription-backed *interactive* access. It does not authorise unattended use,
> credential export, API keys, or paid overage.

Both AI credentials belong to `aleix`, and `homelab-bot` provably cannot read
either. **Do not resolve this by copying an OAuth file to a service account
because it works interactively.** That is a cross-phase architectural decision
and needs an ADR.

### 4. No escalation design was built — deliberately

The brief scoped this phase read-only, and no executor or escalation mechanism
was written, sketched or stubbed. Phase 08 starts from a blank page here on
purpose: designing privilege escalation inside a phase whose roadmap entry says
"keep it unprivileged" would have worked against the brief.

What Phase 08 inherits is the **shape of the boundary**, not a proposal: one
choke point before dispatch, an account that holds nothing, and a service that
cannot execute a program.

### 5. Where the token lives, and how to handle a leak

`/etc/homelab-telegram-bot/token`, `root:root 0600`, supplied to the process by
systemd `LoadCredential=` on a tmpfs. **The value is not in the repository, not
in this handover, and not in any agent transcript.**

`bot.py` carries a `redact()` helper because the token is part of every API URL
and `urllib` puts URLs into exception messages — without it, one connection error
would write a permanent bearer credential into the journal. Verified:

```text
ok  token does not appear in the unit's journal
```

**If it ever leaks: revoke with BotFather first.** Cleaning up wherever it
appeared is the second action. A bot token is a bearer credential — whoever holds
it is the bot, from anywhere, with no second factor.

### 6. The reboot test result — Phase 08 will add units to this same boot

```text
18:50:53  boot
18:51:00  unit started — 7s after boot, unattended
18:51:00  WARNING: Telegram unreachable: Temporary failure in name resolution
18:51:56  Telegram reachable again
```

Zero restarts. Three journal lines. Boot: **24.4s**.

The unit uses `After=network.target`, **not** `network-online.target`, and the
above is why that is safe: the bot retries with bounded backoff and recovered
unaided. **Any unit Phase 08 adds should either handle unavailability the same
way, or state explicitly why it must block boot** — on a console-less node, a
service that hangs the boot ordering is a lockout risk.

Note the flip side of bounded logging: an outage logs **once** and then goes
quiet until recovery. **"No recent log lines" does not mean "healthy".**

### 7. Open risks carried forward

Unchanged unless noted.

| Risk | Owner |
|---|---|
| **The node still has no backup of any kind** | Phase 13 — and now there is state worth losing |
| Single SSH key, no backup, no console | Phase 13 |
| No firewall; `:22` open on the LAN | Phase 13 |
| No encryption at rest (ADR-015) | Phase 13 — **Phase 10 must revisit ADR-015 first** |
| Node key expiry disabled (ADR-019) | Phase 13 |
| `aleix` in the `docker` group — root-equivalent, no password | ADR-022; revisit with rootless |
| Volume group has no free extents | Not owned by any phase |
| IPv4/IPv6 `FORWARD` policy asymmetry | Phase 13 must not assume symmetry |
| Wi-Fi is a single point of failure for **both** routes; `eno1` unused | Not owned by any phase |
| **New:** the allowlist is per-deployment state on the node, in no backup | Phase 13 |
| **New:** Telegram is a third party; all messages transit and are stored there | Phases 08 and 10 |

## Validation performed

All eighteen checks from the brief's §8.

| Check | Result |
|---|---|
| Service account: no shell, no home, no privileged group | ✅ uid 999, `nologin`, groups `homelab-bot` only |
| **Isolation, by attempted access** | ✅ six probes, all refused |
| `systemd-analyze verify` before enabling | ✅ clean for this unit |
| `systemd-analyze security` | ✅ **1.3 OK** |
| Hardening read from the **running** service | ✅ nine directives confirmed |
| Commands answer correctly | ✅ `/status` returns host, uptime, load, memory, disk |
| **Non-allowlisted user refused** | ✅ logged and refused; no host data returned |
| **`ss -tln` matches baseline** | ✅ 6 sockets, unchanged |
| Outbound-only | ✅ 1 outbound connection, 0 listeners |
| Token file `0600 root:root`, unreadable by the service | ✅ |
| **Token absent from the journal** | ✅ searched with the real value, on the node |
| Token absent from the repository and history | ✅ `scan-history.sh` exit 0 |
| **Telegram unreachable handled gracefully** | ✅ observed for real at boot; recovered unaided in 56s |
| `systemctl restart` recovers | ✅ |
| **Reboot test** | ✅ started 7s after boot, 0 restarts |
| **Both routes after reboot** | ✅ `homelab` and `homelab-lan`, fresh connections |
| Host health, checked last | ✅ `running`, 0 failed units |
| `id aleix` unchanged | ✅ |

## Problems / failures / lessons

Five, in [`docs/build-log/2026-09-09-phase-07-telegram-bot.md`](../build-log/2026-09-09-phase-07-telegram-bot.md).
The three that generalise beyond this phase:

1. **I hardened a system-info reporter so it could not read system info.**
   `ProcSubset=pid` hides `/proc/uptime`, `/proc/loadavg` and `/proc/meminfo` —
   the only three files the bot reads. Copied from a checklist without checking
   it against what the program does. **Hardening that breaks the function it
   protects is not hardening.**

2. **One unguarded exception became a restart loop** on a console-less node. A
   user-facing command must never be able to kill the service. `StartLimitBurst`
   contained it, by luck of having been written for another reason.

3. **The verifier reported a confident `FAIL` about a file it lacked permission
   to see.** Fifth instance of this family here, after `sshd -T`, `who`, and two
   Phase 04 scanner bugs — written after the rule had been documented four times.
   **Intention has now failed four times; the defence has to be structural.**

Also: the disk figure was double the truth and entirely plausible, because
`used = total - available` counts root-reserved blocks as used.
**Wrong-but-plausible is the dangerous failure, not crashed.**

## Deviations from phase brief

1. **No `venv` and no third-party dependency.** §6.1 left this open with a
   stdlib presumption; the presumption held. Zero third-party code.
2. **`ProcSubset=pid` was specified in §7.3's directive list and removed.** It
   broke the bot. Recorded rather than quietly dropped.
3. **Telegram-unavailability handling was tested by accident, not design.** The
   reboot produced a real DNS-not-ready window, which is better evidence than a
   simulated outage would have been.

## Open issues / technical debt

- **The allowlist is deployment state on the node**, captured by no backup.
- **Bounded logging hides repeated failures.** Quiet ≠ healthy.
- **Polling costs one request every ~50 seconds, forever.** Negligible, but it is
  a permanent outbound connection from this node to a third party.
- **No metrics or alerting.** If the bot dies at 3am, nothing tells you.

## ADRs

| ADR | Status | Note |
|---|---|---|
| **ADR-023 — Telegram bot service design** | **Accepted** | Long polling over webhooks; native systemd over container; dedicated unprivileged account; `LoadCredential` over environment; allowlist as primary access control; read-only with escalation deferred |
| ADR-009 / ADR-011 | Implemented | ADR-011's first real application |
| ADR-020 / ADR-021 / ADR-022 | Referenced | Boot-class classification; token as disclosure risk; docker group kept away |

## Tested versions

| Component | Version |
|---|---|
| Python | 3.14.4 (stdlib only — no third-party packages) |
| systemd | 259 |
| Ubuntu / kernel | 26.04.1 LTS / 7.0.0-31-generic |

Nothing version-critical. `ProcSubset=` requires systemd ≥ 247 to reproduce the
failure in §1 of the build log.

## Costs

**0 DKK**, recorded as an explicit zero. Telegram bots are free; no new hardware,
subscription or paid service. Running total unchanged at **899 DKK (~121 EUR)**
plus the existing AI subscriptions recorded in Phase 06.

## Recommended roadmap changes

Actioned directly, since ADR-017 leaves no recipient:

1. **Phase 07 marked complete** in `ROADMAP.md`, with the read-only scope and
   deferred escalation stated inline so Phase 08 cannot assume otherwise.
2. **Phase 08 must decide the unattended-AI question** inherited from Phase 06
   (§3), and must not resolve it by copying a personal OAuth credential.
3. **Phase 13 inherits two new items**: the allowlist as unbacked-up state, and
   the absence of any alerting on this service.

No phase renumbering required.

## Definition of Done

- [x] Functional objective works — all twelve in §4 of the brief
- [x] Configuration/setup is reproducible — account, unit, bot and config all
      deployed from committed files via `scp` with SHA256 verified both sides
- [x] Validation/tests have passed — all eighteen checks, with captured output
- [x] Important security implications were considered — isolation proved by
      attempted access; token containment verified against the journal
- [x] Relevant repository files are committed
- [x] Human-facing guide is updated — `guide/07-telegram/README.md`
- [x] Project/internal documentation is updated
- [x] ADRs created or updated — ADR-023 accepted
- [x] Actual costs recorded — explicit 0 DKK
- [x] Problems, failed approaches and lessons recorded — five, four of them mine,
      including the fifth instance of a failure family this repository documents
- [x] Tested versions recorded
- [x] No unexplained critical AI-generated component remains — `bot.py` is
      commented for a reader who must be able to modify it safely
- [x] `main` represents a known-working state — after `--no-ff` merge
- [x] System reports no failed units and no degraded state — checked **last**,
      after the reboot
- [x] Structured handover written, stating what Phase 08 inherits
