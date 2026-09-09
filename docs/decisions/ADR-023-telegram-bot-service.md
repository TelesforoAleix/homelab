# ADR-023: Telegram bot service design

- **Status:** Accepted
- **Date:** 2026-09-09
- **Supersedes:** none
- **Superseded by:** none

## Context

Phase 07 builds the project's first user-facing service and its first long-running
process. ADR-009 chose Telegram as the first interface; ADR-011 requires that
bot/router services run unprivileged with escalation explicit rather than
ambient. Neither had a service to apply to until now.

Three facts about this machine shape the decisions:

1. **There is no firewall.** Phase 13 owns that. `:22` is the only port reachable
   off-box, and anything this phase exposes would be exposed to the LAN.
2. **There is no console** (ADR-020). A unit `WantedBy=multi-user.target` is
   boot-class by the standard's own definition, so this phase is lockout-class
   even though its realistic risk is low.
3. **`aleix` holds passworded `sudo` and root-equivalent Docker-group access**
   (ADR-022), plus two personal AI OAuth credentials (Phase 06). The Phase 06
   handover forbids this service inheriting any of it.

## Decision

### 1. Long polling, never webhooks

The bot opens **outbound HTTPS only** and listens on nothing.

This is the decision that makes running it acceptable here. A webhook requires a
publicly reachable inbound HTTPS endpoint; this node has no public address, no
firewall, and no reverse proxy. **Moving to webhooks would change the exposure
model completely and requires its own ADR** — it is not a configuration detail.

Verified: listening sockets are byte-identical to the pre-Phase-07 baseline.

### 2. A native systemd service, not a container

Docker is available (ADR-022) and deliberately unused. A small deterministic
poller does not need an image, and systemd's directives express ADR-011 more
directly than a container would — `ProtectHome=yes` *is* the enforcement of "no
access to `/home/aleix`", checkable on the running unit.

Measured result: `systemd-analyze security` → **1.3 OK**.

### 3. A dedicated unprivileged system account

`homelab-bot`, uid 999, `/usr/sbin/nologin`, no home directory, member of no
group but its own. Never `sudo`, never `docker`, never `adm` — the installer
re-checks this on every run, not only at creation, because Docker-group
membership is root-equivalent and would make every hardening directive
meaningless.

**Proved by attempting each access, not by reading directives.** The account
cannot read `/home/aleix`, either AI OAuth credential, the Docker socket, or the
token file, and cannot modify its own code.

### 4. `LoadCredential=`, not an environment variable

The token file is `root:root 0600`, so **the service account cannot read it at
all**. systemd reads it as root at unit start and hands the process a private
copy on a tmpfs, unmounted when the unit stops.

An environment variable would be visible to anything able to read
`/proc/PID/environ`, and environment variables leak into crash dumps,
`systemctl show` output and logs. A bot token is a bearer credential: whoever
holds it *is* the bot, from anywhere, with no second factor. It is closer to a
private key than to a password.

The bot also carries a `redact()` helper, for one specific reason: the token is
part of every API URL, and `urllib` puts URLs into its exception messages.
Without it, one connection error would write a permanent bearer credential into
the system journal.

### 5. An allowlist of numeric user IDs is the primary access control

Telegram bots are discoverable and there is no approval step. Without an
allowlist, a "harmless read-only status bot" reports this machine's disk usage,
uptime and memory to whoever finds it.

- Numeric **user IDs**, not usernames — a username can be changed by its owner.
- Checked **once, in the dispatch loop, before any handler runs**, so a command
  added later cannot accidentally be unprotected.
- **An empty allowlist is a hard error.** The bot refuses to start. The failure
  mode of a misconfigured allowlist must never be "answer everyone".

### 6. Read-only, with escalation deferred to Phase 08

No command changes anything. A compromise leaks host metrics; it cannot act.
ADR-011 wants escalation designed deliberately, and Phase 08 owns the executor
pattern. Widening this account is Phase 08's decision to make, not to inherit.

### 7. Standard library only, and no subprocesses

The Bot API is JSON over HTTPS; the standard library does it. A dependency would
buy about forty lines in exchange for a supply-chain risk and an upgrade
obligation (`AGENTS.md`).

Every figure comes from `/proc`, `/etc/hostname` or `os.statvfs()`. **The bot
never forks or executes anything**, which is why the unit can forbid so much. A
process that cannot execute a program cannot be talked into executing the wrong
one.

### 8. `After=network.target`, not `network-online.target`

The bot retries with bounded backoff, so it does not need to wait for
connectivity — and depending on `network-online.target` would tie a
non-essential service to a boot ordering barrier on a console-less node.

**Validated accidentally and better than by design.** On the reboot test the unit
started 7 seconds after boot, before DNS was ready, logged one
`Temporary failure in name resolution`, backed off, and recovered unaided 56
seconds later. Zero restarts, three journal lines total.

## Alternatives considered

**Webhooks.** Lower latency and no polling. Rejected: requires an inbound,
publicly reachable HTTPS endpoint on a node with no firewall and no public
address. Not a trade-off worth making for a status bot.

**A Docker container.** Would use the Phase 05 investment and give a reproducible
image. Rejected: an image build/rebuild lifecycle for ~380 lines of standard
library, running under a daemon that is itself root-equivalent, when systemd
already provides stronger and more directly verifiable isolation for this shape
of workload.

**`python-telegram-bot`.** The obvious library. Rejected in favour of ~40 lines
of `urllib`, per `AGENTS.md`'s preference for minimal comprehensible
implementations. Revisit if the bot ever needs inline keyboards, media, or
conversation state.

**`EnvironmentFile=` for the token.** Simpler and very common. Rejected on the
`/proc/PID/environ` exposure and the tendency of environment variables to reach
logs and crash dumps.

**Running as `aleix`.** Zero setup. Rejected outright: it would hand a
network-facing process passworded `sudo`, root-equivalent Docker access, and two
AI OAuth credentials. This is the case ADR-011 exists for.

**Allowing everyone, relying on the bot being read-only.** Rejected. "Read-only"
still publishes this machine's state to strangers, and it would make every future
command addition a security decision by default.

## Consequences

**Positive.**

- No new listening socket; the pre-Phase-07 baseline is unchanged.
- Isolation is proved by attempted access, not asserted from a unit file.
- The token cannot be read by the process's own account.
- Boot-time behaviour validated by an actual reboot, including a real
  network-unavailability recovery.

**Negative, and accepted.**

- **Telegram is a third party.** Every message and response transits and is
  stored on their infrastructure. Acceptable for uptime and disk figures; a
  reason not to extend this bot toward anything sensitive without revisiting.
  A note for Phases 08 and 10.
- **Polling costs a request every ~50 seconds**, forever. Negligible here.
- **The allowlist is per-deployment state on the node**, not in the repository,
  so it is not captured by any backup — and the node still has no backup.
- **Bounded logging hides repeated failures.** An outage logs once and then goes
  quiet until recovery. That is deliberate on a volume group with no free
  extents, but it means "no recent log lines" does not mean "healthy".

## Related

- **ADR-009** — Telegram as the first interface.
- **ADR-011** — privilege separation; this is its first real application.
- **ADR-020** — a unit `WantedBy=multi-user.target` is boot-class.
- **ADR-021** — the repository is public; a committed token would be a disclosure.
- **ADR-022** — the Docker group is root-equivalent, which is why this account is
  kept out of it.
