# Telegram bot profile and command menu

**Date:** 2026-09-09
**Branch:** `feature/telegram-bot-profile`
**Scope:** Small, outside Phase 09, which was already merged and tagged.
**Outcome:** Complete. Name, both descriptions and the command menu set and verified.

## Why

Phase 09 gave the bot `/ask`, but a Telegram client offers no autocomplete for commands the bot has
not registered, so every command had to be typed from memory on a phone. `setMyCommands` fixes that.

## What was found already there

`show` revealed a hand-set command list from BotFather that had drifted from the code:

```text
/help    "What you can do"
/status  "How is everything"
/model   "Chat with AI"
```

`/model` was advertised as "Chat with AI" while Phases 07 and 08 had it **registered and
deliberately unwired**, and `/ask` — the command that works — was not listed at all. The menu had
been describing a capability the bot did not have, for two phases.

That is the argument for the design choice: **the list is derived from `executors.register_all()`**,
the same single source of truth that generates `/help`. A menu that cannot be edited by hand cannot
drift by hand.

`/restart` is withheld from the default command scope and sent only to allowlisted chats. Not access
control — the allowlist already refuses non-owners — simply not advertising a privileged action.

## Problems

### 1. No timeout, so the first run hung until Ctrl-C

`show` printed `getMe:` and stopped. No `--max-time`, no `--connect-timeout`.

Diagnosis mattered here, because the obvious answer was wrong. `curl --config -` worked standalone
in 243ms. `getMyName` worked standalone. Two sequential calls worked. But in the loop it stalled —
and on the next run it stalled at a *different* call.

Then the actual measurement: five identical API calls from this node took **8914ms, 1397ms, 2484ms,
207ms, 3247ms.** The link is erratic by a factor of forty. Nothing was wrong with the script's
logic; it simply had no bound.

**Lesson:** every network call needs a timeout, including the one you are sure is fast. Deliberately
**no** `--retry` — a retry would hide exactly the variance that makes the timeout necessary.

Also `--ipv4`, chosen from a measurement rather than a preference: this host has **no working global
IPv6 route** (`curl -6` fails in 9ms; its only IPv6 address is Tailscale's) while
`api.telegram.org` publishes AAAA records.

### 2. The timeout number was a guess inside the measured spread

With `--connect-timeout 10`, the real `apply` failed:

```text
FAIL  description set
      curl: (28) Connection timed out after 10001 milliseconds
```

Ten seconds, on a link already measured at 8.9s. The decision to have a timeout was right; the
number was picked because it sounded generous. Now 20s connect, 60s total, and the reasoning is in
the script.

### 3. The verifier reported FAIL about three things it could not read — the ninth instance

```text
FAIL  name reads back as '<unreadable>', expected 'Home Lab'
FAIL  short description differs (got: <unreadable>)
FAIL  description differs
```

Two of those were false. The name and short description had been set correctly — the `ok` lines
above them were true.

The cause was in the check:

```bash
FIELD="$field" api "$method" | python3 -c '... os.environ["FIELD"] ...'
```

In a pipeline, `VAR=val cmd1 | cmd2` sets the variable for **`cmd1` only**. `python3` never received
`FIELD`, raised `KeyError`, and a bare `except Exception` converted that into the string
`"<unreadable>"`. The caller compared that string against the expected value and printed `FAIL`.

**A bug in the check was reported as a defect in the thing being checked.**

This is the **ninth** instance of this project's oldest failure family — after `sshd -T`, `who`, two
Phase 04 scanner bugs, the Phase 07 verifier, the Phase 08 escalation test, the Phase 08 `setpriv`
misread and the Phase 09 installer's group check. It was written in the same session in which two of
those were documented, hours apart.

**Reading the rule is demonstrably not sufficient.** What was changed is structural, not
intentional:

- a reader returns a value, **or returns nothing with a non-zero status** — never a sentinel string;
- the caller has **three** branches: matched, differs, could-not-check;
- `UNKNOWN` states in words that it is not a mismatch;
- all three outcomes were validated against crafted input — `ok:false`, non-JSON, empty, and a
  missing field — before any of them was trusted.

A fourth bug was caught *while* fixing this one, by reading rather than running:
`python3 - <<'HEREDOC' <<<"$data"` is two stdin redirections, the last of which wins, so python
would have tried to read its own program out of the JSON.

## Verified

After the fixes, a real `apply`:

```text
ok    name set
ok    short description set
ok    description set
ok    default-scope commands set (5)
ok    full command set applied to an allowlisted chat
ok    name matches
ok    short description matches
ok    description matches
ok    default-scope command list matches what was sent
ok    everything read back as sent
```

The command list is compared as a **set**, because Telegram is not obliged to preserve ordering and
a check that fails on ordering is a check that gets ignored.

## Costs

**0 DKK.** No model calls, no new service, no subscription. The Bot API is free.
