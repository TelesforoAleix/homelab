# Phase 09 — Model executor (subscription-backed)

**Date:** 2026-09-09
**Branch:** `feature/09-model-executor`
**Outcome:** Complete. `/ask` answers from Telegram, via either subscription, with
the bot still unable to read either credential.

## What was built

| Thing | Where |
|---|---|
| `homelab-model-helper` — runs as `aleix`, socket-activated, one process per connection | `services/model-helper/` |
| Provider abstraction + Claude and Codex implementations | `services/model-helper/providers.py` |
| Per-hour / per-day caps, `flock`-protected file state | `services/model-helper/limits.py` |
| Socket unit carrying the access control | `config/systemd/homelab-model-helper.socket` |
| The bot's side — the only new code running as `homelab-bot` | `services/telegram-bot/model_client.py` |
| `/ask`, replacing the unconnected `/model` (kept as an alias) | `services/telegram-bot/executors.py` |
| Guarded installer that proves the boundary both ways | `scripts/server/install-model-helper.sh` |

## Measurements

Taken from live output, not inferred.

| Fact | Value |
|---|---|
| TCP listeners before / after | **6 / 6** — a UNIX socket adds none |
| `id homelab-bot` before / after | `uid=999 gid=982 groups=982` — identical |
| Socket | `aleix:homelab-bot:660` |
| `systemd-analyze security` (bot) | **1.3 OK**, unchanged |
| Claude | `haiku`, ~2–3s to a reply or a refusal |
| Codex | `gpt-5.6-luna`, ~12–15s to an answer |
| Caps in production config | 6/hour, 30/day, per provider |

## Problems

### 1. The cheapest Codex model could not be guessed, and one candidate was a trap

`codex exec --help` lists no models. The binary's embedded catalogue contains
`gpt-5.4-mini`, which looks exactly like the answer and is **rejected**:

```text
The 'gpt-5.4-mini' model is not supported when using Codex with a ChatGPT account.
```

The catalogue is the *CLI's* model list, not the *subscription's* entitlement.
The real answer came from the migration notes inside the same binary:
`gpt-5.6-luna` is recorded as the replacement for GPT-5.4 Mini, and it works.

**Lesson:** a capability listed by a tool is not a capability granted to the
account using it.

### 2. Two Codex flags that would have failed on first deploy

Found by running the real command rather than the one in my head:

```text
Not inside a trusted directory and --skip-git-repo-check was not specified.
Reading additional input from stdin...
```

`codex exec` refuses to run outside a trusted git directory, and it reads stdin
and **appends it to the prompt** — so a service with an open stdin hangs. Both
are now in the argv and in `stdin=DEVNULL`, with the observed text quoted beside
them so nobody removes them as noise.

### 3. I reported a finding I had measured wrong

I said `codex exec` "exited 0 on a hard API error" and flagged it as important.
It does not. I had written:

```bash
codex exec ... 2>&1 | tail -15; echo "EXIT=$?"
```

`$?` there is `tail`'s status, not Codex's. Re-measured without the pipeline:
`CODEX_EXIT=1`.

**This is the same family as Phase 08's `setpriv` error — the eighth instance —
and it is the family's purest form yet:** the rule "any command whose output you
will act on is a check" was written into `scripts/README.md` in Phase 08, and I
broke it in the shell one-liner rather than in committed code, which is exactly
where Phase 08 said the failure would move next. The prediction was right and it
did not help.

The retraction was made in the same breath as the claim, which is the only part
that went well.

### 4. `--tools ""` was validated with a positive control, and the first control was worthless

The security property the whole phase rests on is that the model cannot read the
host. First test: ask it to read `/etc/hostname` with `--tools ""`. It replied
with the *directory name*, `askprobe`, not the real hostname `homelab` — no tool
had run.

Then the control, without the flag — and it was **inconclusive**: default
permission mode refused because the file was *outside the working directory*, not
because the tool was absent. A pass for the wrong reason, which is precisely
what Phase 08's escalation test did.

The discriminating test was a canary inside the working directory:

```text
default tools : CANARY-7f3a-INSIDE-CWD
--tools ""    : "canary.txt does not exist ... the directory is empty"
```

Same file, same directory. **Lesson repeated:** the first control you think of
often varies two things at once.

A second finding fell out of it. The restricted model did not refuse — it
**confabulated**, twice, confidently. And in the first probe it emitted a
`function_calls` block as plain text. Anything that parsed model output looking
for tool calls would have found one.

### 5. The first real `/ask` misclassified an entirely normal condition

Reply from Telegram:

```text
Could not ask a model: the provider failed in a way this helper does not recognise
```

Cause: the exhaustion pattern was built from Codex's **observed** wording plus
**guesses** at Claude's. Claude actually says:

```text
You've hit your session limit · resets 11pm (UTC)
```

`session limit` matched none of the guesses, and the reset time has no "at" for
the retry pattern to anchor on. So exhaustion was classified as a hard error —
and since a hard error deliberately does *not* spend the other subscription, no
fallback was attempted.

The guessed half was wrong; the observed half was right. **A branch exercised
only against invented input is untested**, which is the Phase 04 scanner lesson
arriving in new clothing.

Both patterns are now built from text seen from both providers, with the negative
cases tested too — a real error must not be read as exhaustion either.

### 6. I suppressed the evidence I needed, and called it a security decision

Problem 5 took longer than it should have, because when it happened **there was
nothing in the journal to say what the provider had said.**

Keeping raw CLI output out of the Telegram reply was right: it carries absolute
paths and the reply leaves the machine. Concluding it should therefore go
*nowhere* was wrong.

**Lesson:** "do not show this to the user" and "do not record this" are two
different decisions. I made the first and silently got the second. Provider
failures are now logged to the journal, truncated, with the exit code.

### 7. Phase 07's restart limit had never been capable of firing

`systemd-analyze verify`, run by the new installer, said:

```text
homelab-telegram-bot.service:59: Unknown key 'StartLimitIntervalSec' in section [Service], ignoring.
```

The running unit confirmed it — `StartLimitIntervalUSec=10s`, not the 300s the
file asks for. The directive belongs in `[Unit]`; in `[Service]` systemd ignores
it and carries on with its default.

The consequence is worse than a wrong number. With `RestartSec=10`, restarts land
~10s apart, so five starts could never fall inside a 10s window. **The limit was
unreachable, and the restart loop it was written to prevent — on a console-less
node, filling a journal on a volume group with no free extents — could have run
indefinitely.**

What kept it alive for two phases: `StartLimitBurst=5` **is** accepted in
`[Service]`, so half the setting worked and `systemctl show` reported a plausible
pair of values. Fixed, and `install-telegram-bot.sh` now runs
`systemd-analyze verify` on every install and prints what it says.

**Lesson:** systemd does not fail on a misplaced directive, it ignores it and
starts anyway. This is Phase 03's "configuration versus the running daemon" with
a new mechanism — and the fix is to ask the tool, every time, rather than to read
more carefully.

### 8. Three bugs in my own installer, found by reading it before shipping it

- the group check compared `"$(echo "$groups")"` against `"homelab-bot "` —
  command substitution strips the trailing space, so it could **never** have
  passed;
- the code-writability check looped over `find` output and would have reported
  `ok` having examined **zero files** if the directory did not exist. That is the
  Phase 04 scanner bug — a verdict on an empty corpus — reproduced from memory in
  a new script. It now counts and reports `UNKNOWN`;
- `setpriv ... test -w` invokes a shell builtin that `setpriv` cannot exec;
  `/usr/bin/test` was needed.

### 9. Session-count check refused the install three times, correctly

The bot installer requires two interactive sessions. It refused twice while only
one existed, then once more after a second terminal was opened — because the
**first** session had silently dropped after sitting idle for 1h03m, so the two
were never open simultaneously.

Not a bug. A demonstration of the risk the check exists for: both access routes
share the single Wi-Fi adapter, and a long-idle session on this node is not a
reliable way back in. The check also correctly ignores my own non-interactive
`ssh` connections, which have no pty and exit immediately — counting those as "a
way back in" would defeat the purpose.

## What was proved, and how

| Claim | Method |
|---|---|
| The bot can reach the socket **from inside its own sandbox** | probe run under `systemd-run` with the bot's filesystem directives, reporting errno rather than a verdict |
| `connect(2)` works on a read-only mount under `ProtectSystem=strict` | measured by the above, not reasoned about. It succeeds |
| `homelab-bot` still cannot read either credential | attempted the read as that user, both files |
| `id homelab-bot` unchanged | compared before and after |
| No new TCP listener | `ss -tln`, 6 both times |
| Caps enforced before the call | seeded counter, `outcome=capped` with no provider line — **zero allowance spent proving it** |
| Fallback works | Claude genuinely exhausted, Codex answered |
| Both spent → legible message | seeded both counters, message names time to room |
| `/ask` cannot reach `/restart` | the model was **asked to emit** `/restart ssh.service`; it complied; chrony's `ActiveEnterTimestamp` was unchanged either side |
| Only question + `/status` is sent | the exact prompt printed verbatim |
| The lock actually serialises | 10 concurrent processes, one slot, exactly one winner |

## Costs

**0 DKK incremental.** Both subscriptions already exist (Phase 06 ledger,
€45.50/month ≈ 339 DKK/month). No API key, no overage, no new service.

**The capacity cost is real and was paid during this phase.** Claude Pro hit its
session limit partway through, and a meaningful share of that was my own
verification: the canary test, its inconclusive first control, the model-name
probes and the repeated `Reply with exactly: OK` calls. That was the right trade
— the alternative was assuming the tool restriction worked — but it was the
owner's allowance that paid for it, and the ledger should say so.
