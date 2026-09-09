# Telegram status bot

Phase 07. A deterministic, read-only Telegram bot that reports this machine's
own state and can change nothing. See
[`guide/07-telegram/README.md`](../../guide/07-telegram/README.md) and
[ADR-023](../../docs/decisions/ADR-023-telegram-bot-service.md).

| File | Purpose |
|---|---|
| `bot.py` | The bot. Standard library only — no third-party dependencies |
| `allowlist.example` | Template for `/etc/homelab-telegram-bot/allowlist` |
| `token.example` | Placeholder only. **The real token never enters this repository** |

Deployed by [`scripts/server/install-telegram-bot.sh`](../../scripts/server/install-telegram-bot.sh),
verified by [`scripts/server/verify-telegram-bot.sh`](../../scripts/server/verify-telegram-bot.sh),
and run under [`config/systemd/homelab-telegram-bot.service`](../../config/systemd/homelab-telegram-bot.service).

## Four design constraints, and why

**No inbound port.** Telegram offers webhooks (Telegram connects to you) or long
polling (you connect to Telegram). This uses long polling, so the bot opens only
outbound HTTPS and listens on nothing. That is not a preference: this node has no
firewall and `:22` is the only port reachable off-box. Moving to webhooks would
require a publicly reachable inbound HTTPS endpoint and changes the exposure
model completely — it would need its own ADR.

**No third-party dependencies.** The Bot API is JSON over HTTPS; the standard
library does it. A dependency would buy about forty lines in exchange for a
supply-chain risk and an upgrade obligation.

**No subprocesses at all.** Every figure comes from `/proc`, `/etc/hostname` or
`os.statvfs()`. The bot never forks or executes anything, which is why the unit
can forbid so much. A process that cannot execute a program cannot be talked
into executing the wrong one.

**Read-only.** No command changes anything. A compromise leaks host metrics; it
cannot act. Escalation is Phase 08's, deliberately (ADR-011).

## The two things that fail closed

Both are deliberate, and both were tested:

```console
$ python3 bot.py
ERROR: CREDENTIALS_DIRECTORY is not set.
Refusing to look for the token anywhere else -- an environment variable or a
world-readable file would be a downgrade, not a fallback.

$ CREDENTIALS_DIRECTORY=... HOMELAB_BOT_ALLOWLIST=/tmp/empty python3 bot.py
ERROR: the allowlist at /tmp/empty is empty.
Refusing to start. An empty allowlist must never mean 'allow everyone'.
```

An empty allowlist meaning "allow everyone" is the classic version of this bug.
A status bot that answers strangers reports this machine's state to whoever
finds it, and Telegram bots are discoverable.

## Where the token lives

`/etc/homelab-telegram-bot/token`, mode `0600`, owned **`root:root`** — so the
service account **cannot read it**. systemd reads it as root at unit start and
hands the process a private copy via `LoadCredential=`, on a tmpfs unmounted
when the unit stops.

It is deliberately not an environment variable: anything able to read
`/proc/PID/environ` would see it, and environment variables leak into crash
dumps, `systemctl show` output and logs.

`redact()` in `bot.py` exists for one specific reason — the token is part of
every API URL, and urllib puts the URL into its exception messages. Without it,
a single connection error would write a permanent bearer credential into the
system journal.
