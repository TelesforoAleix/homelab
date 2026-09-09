# 2026-09-09 — Phase 07: the first service this project wrote

Six phases of building a machine that did nothing for its owner. This is the one
that produced something used.

It also produced five failures, four of them mine, and one of those is the fifth
instance of a mistake this repository has been documenting since Phase 02.

## Outcome

A read-only Telegram status bot: standard library only, no subprocesses, no
listening socket, running as a dedicated unprivileged account under a systemd
unit scoring **1.3 OK** on `systemd-analyze security`. Verifier passes with
**0 failures, 0 warnings**. Reboot test passed.

## Problem 1 — I hardened a system-info reporter so it could not read system info

Every `/status` crashed:

```text
File "/opt/homelab-telegram-bot/bot.py", line 213, in host_uptime
  with open("/proc/uptime", "r", encoding="utf-8") as fh:
FileNotFoundError: [Errno 2] No such file or directory: '/proc/uptime'
```

`/proc/uptime` absolutely exists on this machine. It did not exist *for this
process*, because the unit set `ProcSubset=pid`, which restricts `/proc` to
process directories and hides `/proc/uptime`, `/proc/loadavg` and
`/proc/meminfo`.

Those are the only three files the bot reads.

**Cause.** `ProcSubset=pid` was copied from a hardening checklist without being
checked against what the program actually does. It is an excellent directive —
for a service that has no business reading system-wide state. This service's
entire purpose is reading system-wide state.

**Fix.** Removed, with the reasoning written into the unit so nobody re-adds it.
`ProtectProc=invisible` is kept: it hides *other processes*, which the bot
genuinely does not need, without touching the files it does.

> **Hardening that breaks the function it protects is not hardening.** A
> checklist tells you what is possible to restrict. It cannot tell you what this
> program needs, and applying it by reflex produces a service that is beautifully
> secured and does not work.

## Problem 2 — one unguarded exception turned a status bot into a restart loop

Problem 1 was much worse than it needed to be. `handle()` had no exception guard,
so the `FileNotFoundError` killed the process. systemd restarted it. The same
`/status` message was still queued at Telegram. It crashed again.

A restart loop driven by a single message, on a machine with no console.

`StartLimitBurst=5` in the unit is what stopped it becoming continuous — a rate
limit written for a different reason that happened to contain this.

**Fix.** Command dispatch is fault-isolated. A failing handler logs, replies
"That command failed", and the loop continues.

> A user-facing command must never be able to kill the service. The blast radius
> of a bug in one handler should be that one reply.

## Problem 3 — my verifier reported a confident FAIL about a file it could not see

```text
FAIL  /etc/homelab-telegram-bot/token does not exist
```

The token existed. The bot was authenticating with it at that moment.

`/etc/homelab-telegram-bot` is `0750 root:homelab-bot`, so `aleix` cannot
traverse it, and `[ -e "$path" ]` returned false. The script reported "it is not
there" when the truth was "I cannot see it". It made the same error about the
outbound socket count, reporting `0` where `ss` simply cannot attribute another
user's sockets without root.

**This is the fifth instance in this project of the same failure family:**

| Phase | Check | How it failed |
|---|---|---|
| 03 | `sshd -T` | Read the config file, not the running daemon |
| 02 | `who` | Zero sessions, exit 0, on a machine with six |
| 04 | binary detection | Skipped all 213 blobs, reported clean |
| 04 | private-key pattern | Could not run at all, reported clean |
| **07** | **verifier file checks** | **Reported "does not exist" for a file it lacked permission to see** |

`scripts/README.md` has carried the rule since Phase 02 — *a check that cannot
determine an answer must say **unknown**, never a plausible-looking zero* — and
this script was written after that rule had been documented four separate times,
twice by the same hand in the same repository.

**Knowing a failure mode does not confer immunity to it.** It appears to require
a structural defence rather than an intention: check your own privilege first,
and make "unknown" a first-class result the report can express.

**Fix.** The verifier now determines what it is allowed to see before it reports
anything, and prints `UNKNOWN` for everything it cannot establish. The listener
check was deliberately *kept* unprivileged, because `ss -tln` shows every socket
on the host regardless of owner — comparing the whole list against a known
baseline is conclusive without pid attribution. Knowing which checks survive
without privilege is part of the fix, not an afterthought.

## Problem 4 — the disk figure was double the truth, and looked plausible

Before deployment, the bot reported **19.3G used** where `df` reported **8.9G**.

The naive calculation is `used = total - available`. A filesystem reserves a
percentage of blocks for root (5% by default on ext4), and those blocks are
neither used nor available to anyone else — so they were being counted as used.

More than double, with no error anywhere, on the single number an operator is
most likely to act on.

**Fix.** `used` from `f_bfree`, `available` from `f_bavail`, percentage as
`used/(used+available)` — `df`'s own semantics. Now agrees to within rounding.

> A status bot that disagrees with `df` is worse than no status bot, because
> someone will believe it. Wrong-but-plausible is the dangerous failure, not
> crashed.

## Problem 5 — a dead terminal buffers everything you type at it

After `sudo reboot`, the connection died instantly. Lines typed afterwards sat in
the local shell's buffer and executed **on the MacBook** when a prompt returned:
`tmux` (not installed there) and a `sudo` line, which raised a bare `Password:`
prompt with no visible owner.

Nothing ran — the prompt timed out with `sudo: a password is required` — but the
right move was to refuse it, because the server **cannot** produce a password
prompt: since Phase 03 it accepts publickey only, verified by asking the running
daemon.

> A password prompt that should be impossible is a reason to stop, not to type
> faster. And the project's own rule about short, one-per-line commands exists
> partly for this: a dead terminal hands everything you typed to whatever comes
> back.

## What went right

The reboot test was supposed to answer one question and answered two.

```text
18:50:53  boot
18:51:00  unit started — 7s after boot, unattended
18:51:00  WARNING: Telegram unreachable: Temporary failure in name resolution
18:51:56  Telegram reachable again
```

Zero restarts. **Three journal lines total.**

The bot started before DNS was ready, logged the outage **once**, backed off, and
recovered unaided 56 seconds later. That validates three design decisions in one
event, none of which could have been tested deliberately without simulating an
outage:

- the bounded-backoff retry loop;
- **bounded logging** — an outage logs once rather than flooding a journal on a
  volume group with no free extents;
- `After=network.target` rather than `network-online.target`, argued on paper as
  "the bot handles unavailability, so it need not block boot", and now
  demonstrated rather than asserted.

Isolation was proved by attempting each access rather than reading directives:
`homelab-bot` cannot read `/home/aleix`, either AI OAuth credential, the Docker
socket, or its own token file, and cannot modify its own code.

And the listener baseline is unchanged: six sockets, exactly as before Phase 07.
The bot added none, because long polling opens only outbound connections.

## Lessons

1. **Hardening that breaks the function it protects is not hardening.** Check
   each directive against what the program does, not against a checklist.
2. **A user-facing command must never be able to kill the service.**
3. **Check your own privilege before reporting a result.** Fifth occurrence.
   Intention has now failed four times; the defence has to be structural.
4. **Wrong-but-plausible beats crashed, for danger.** The disk bug produced a
   confident, credible, doubled number.
5. **A prompt that should be impossible is a reason to stop.**
