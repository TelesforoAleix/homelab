# 2026-09-09 — Phase 08: the escalation boundary

The phase where ADR-011 stopped being a principle. Four problems, three of them
mine, and one of them nearly restarted an access-critical service on a node with
no console.

## Outcome

A registry-based router, six executors at three capability levels, and a
privileged action that works without the service account gaining anything at all:

```console
$ id homelab-bot
uid=999(homelab-bot) gid=982(homelab-bot) groups=982(homelab-bot)   # unchanged
$ sudo grep -rl homelab-bot /etc/sudoers /etc/sudoers.d/ | wc -l
0
```

Exposure level still **1.3 OK**. Listeners still **6**.

## Problem 1 — the brief's mechanism could not work, and testing found it

The brief specified a sudoers rule:

```text
homelab-bot ALL=(root) NOPASSWD: /usr/bin/systemctl restart chrony.service
```

Before writing it, the unit's hardening was checked against it:

```console
$ setpriv --no-new-privs sudo -n true
sudo: The "no new privileges" flag is set, which prevents sudo from running as root.
```

`NoNewPrivileges=yes` and `sudo` are mutually exclusive. `sudo` is setuid; the
flag exists precisely to forbid that.

**Using sudo would have meant removing the hardening in order to add an
escalation** — weakening the process in order to grant it privilege. Backwards,
and it would have cost one of the strongest properties Phase 07 established.

**This is the second consecutive phase where a brief specified a mechanism the
runtime forbids**, after `ProcSubset=pid` in Phase 07. Both were found by running
something rather than reading something. The pattern is now clear enough to name:

> A brief is written against documentation. Documentation describes what a
> mechanism does, not what *this* machine will permit it to do. The gap between
> those is where both phases lost time — and both times the check that closed it
> took under a minute.

**The fix was better than the plan.** polkit needs no setuid: `systemctl` asks
PID 1 over D-Bus and polkit decides inside PID 1, so `NoNewPrivileges` stays on.
And a malformed polkit rule **denies**, whereas a malformed sudoers file breaks
`sudo` entirely on a node whose admin has no console. The deviation *reduced* the
phase's lockout risk.

## Problem 2 — a test that prompted the admin instead of testing the account

The escalation installer proved the grant did not extend, by attempting three
forbidden units as `homelab-bot`. It printed:

```text
--- proving it does NOT extend (as homelab-bot) ---
==== AUTHENTICATING FOR org.freedesktop.systemd1.manage-units ====
Authentication is required to restart 'ssh.service'.
Authenticating as: Aleix Moreno Telesforo (aleix)
Password:   ok   homelab-bot cannot restart ssh.service
==== AUTHENTICATING FOR org.freedesktop.systemd1.manage-units ====
Authentication is required to restart 'tailscaled.service'.
Password:
```

Two things wrong, and the second is worse than the first.

**1. It asked a human to authorise restarting `tailscaled`.** That is one of two
access routes into a machine with no console. `systemctl` had a controlling TTY,
so it registered a polkit *interactive agent*, and polkit escalated the question
to the admin — who is authorised. Typing the password would have restarted it.

**2. The `ok` line was a pass for the wrong reason.** `ssh.service` was not
restarted, but not because `homelab-bot` lacked authority — because nobody
answered a prompt. The test asserted only "the command failed", and a command can
fail for reasons that have nothing to do with authorisation. It was measuring the
operator's restraint, not the account's permissions.

**Fix, in two parts:**

```bash
# 1. No agent, so polkit answers on its own.
systemctl --no-ask-password restart "$forbidden"

# 2. Assert on the REASON, not merely on failure.
if printf '%s' "$OUT" | grep -qiE 'access denied|not authorized|interactive authentication'; then
  ok "$SVC_USER is DENIED $forbidden (polkit refused, no agent involved)"
else
  die "failed, but not because it was denied. Refusing to claim this as proof."
fi
```

Re-run, and the boundary is now actually demonstrated:

```text
ok  homelab-bot is DENIED ssh.service (polkit refused, no agent involved)
ok  homelab-bot is DENIED tailscaled.service (polkit refused, no agent involved)
ok  homelab-bot is DENIED systemd-networkd.service (polkit refused, no agent involved)
```

**Sixth instance in this project of a check producing a confident result it had
not established**, after `sshd -T`, `who`, two Phase 04 scanner bugs and the
Phase 07 verifier. **The first that could have caused harm rather than
confusion.** The others reported a wrong answer; this one asked a human to
perform the dangerous action for it.

Verified afterwards that nothing was damaged: `ssh` and `tailscaled` were both
still at their boot timestamps, both routes up, zero failed units.

## Problem 3 — polkit does not log what I said it logs

The rule's comment claimed "polkit logs every authorisation decision". Measured:

| Outcome | polkit journal |
|---|---|
| Denial | `FAILED to authenticate to gain authorization for action org.freedesktop.systemd1.manage-units ... (owned by unix-user:homelab-bot)` |
| **Grant** | **nothing. zero lines.** |

A `polkit.log()` call was added to cover the gap and produced no output either —
polkitd filters it at the default log level, and enabling polkit debugging
globally to record one rule is not a trade worth making.

> **An audit trail that records refusals but not approvals is half an audit
> trail, and it is the wrong half.** For a privileged action, the successes are
> what you most need to be able to reconstruct.

The second independent record is therefore **systemd's**, not polkit's:

```text
Sep 09 19:53:09 homelab systemd[1]: Stopping chrony.service ...
Sep 09 19:53:09 homelab systemd[1]: Started chrony.service ...
```

PID 1, a different process from the bot with a different failure mode, recording
the action *happening* rather than an intention to perform it. Together with the
bot's own log — requesting user, executor, arguments, outcome — that is two
independent records. polkit contributes a third, for denials only.

The dead `polkit.log()` call was removed rather than left in place implying a
guarantee it never provided.

## Problem 4 — AF_UNIX had to be re-permitted

Phase 07's unit set `RestrictAddressFamilies=AF_INET AF_INET6`, on the stated
grounds that the bot talked to nothing locally. Phase 08 changed that:
`systemctl` reaches PID 1 over a UNIX socket, so without `AF_UNIX` the call fails
at the socket and never reaches polkit at all.

A real widening of Phase 07's posture, recorded rather than slipped in. What it
does **not** open, checked rather than assumed: the Docker socket is
`root:docker 0660` and `homelab-bot` is in no group but its own. `AF_UNIX` grants
the ability to *attempt* a local socket, not the right to use one.

Notably the exposure score did not move: **1.3 OK before and after.**

## Problem 5 — I made Problem 2's mistake again, four minutes after writing it up

The reboot test needed to prove the polkit grant survived. The command run was:

```console
$ setpriv --reuid=homelab-bot ... /usr/bin/systemctl --no-ask-password restart chrony.service
setpriv: setresuid failed: Operation not permitted
  GRANT BROKEN after reboot
```

**The grant was not broken.** `setpriv` cannot change uid without root, and the
command was run as `aleix`. The earlier passes had run inside
`sudo bash install-bot-escalation.sh`. The test never executed.

`Operation not permitted` is an **error**. It was read as a **negative result**,
and reported as a definite conclusion about a security property.

This is the seventh instance of that family in this project, after `sshd -T`,
`who`, two Phase 04 scanner bugs, the Phase 07 verifier and Problem 2 above. It
happened roughly four minutes after Problem 2's lesson — *"a test must assert on
the reason, not the outcome"* — was written into this file, in an ad-hoc command
that asserted on neither.

**What that says about the fix.** The structural defences added in Phases 04 and
07 worked: `scan-history.sh` checks its own privilege before reporting, and
`verify-telegram-bot.sh` reports `UNKNOWN` rather than `FAIL`. Neither has
regressed. But both are *committed scripts*, and this failure was in a one-off
verification command typed at a terminal — the place the discipline had never
been applied because it did not feel like "a check".

> The rule is not "write careful scripts". It is **"any command whose output you
> will act on is a check"**, including the throwaway one. Ad-hoc verification is
> where the belief actually forms, and it is the least reviewed code in the
> project.

**Resolved properly:** the grant was proved end-to-end from Telegram instead,
which needs no privilege from the verifier and exercises the real path. Two
independent records, correlating to the second:

```text
20:00:37  bot:        /restart chrony -> restart chrony.service: ok
20:00:37  systemd[1]: Stopping chrony.service ...
20:00:37  systemd[1]: Started chrony.service ...
20:00:48  bot:        REFUSED restart: ssh.service is not in the restart allowlist

chrony active since 20:00:37   (boot was 19:58:20 -- the grant survived)
ssh    active since 19:58:34   (boot time -- never restarted)
```

## What went right

The design was verified before it was granted anything. With the polkit rule not
yet installed, the local test suite showed both gates working independently:

```text
alice  /restart ssh          -> 'ssh.service' is not permitted.        # gate 2: the bot
alice  /restart chrony       -> failed: Access denied ... interactive
                                authentication has not been enabled     # gate 1: polkit
```

The in-process allowlist refused units polkit would also have refused, and polkit
refused the permitted unit because no rule existed. **Fail-closed on both sides,
proved before any privilege existed to test against.**

And the end state is the point of the whole phase:

- `id homelab-bot` byte-identical to phase start
- zero sudoers entries
- one service it can restart, three it provably cannot
- `NoNewPrivileges` still `yes`, exposure still 1.3, listeners still 6

## Lessons

1. **Check the mechanism against the runtime, not the documentation.** Second
   phase running. The check took under a minute both times.
2. **A test must assert on the reason, not on the outcome.** "The command failed"
   and "the account was denied" are different claims, and only one of them is
   evidence.
3. **Never let a test raise an interactive prompt.** It converts an automated
   check into a request for a human to do the dangerous thing, and it produces a
   pass for the wrong reason.
4. **Verify what your audit trail actually records.** Assuming a system logs
   something is how you discover, during an incident, that it does not.
5. **A deviation can reduce risk.** polkit was not the plan and was better than
   the plan, in the specific sense that its failure mode is denial rather than
   lockout.
6. **Any command whose output you will act on is a check** — including the
   one-off typed at a terminal. The structural defences added in Phases 04 and 07
   held, and the failure moved to the one place they had never been applied.
