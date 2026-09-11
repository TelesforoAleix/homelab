# ADR-025: Subscription-backed model access

- **Status:** Accepted
- **Date:** 2026-09-09
- **Supersedes:** none
- **Superseded by:** ADR-026 (§9 only — see the note at §9; the rest of this ADR stands).
  **ADR-034 §13 changes §10** — *"the model's output is never an instruction"* — but **only when
  tool-using agents are implemented**. Until then §10 stands exactly as written and the Phase 09
  canary check still applies. §1's credential boundary is untouched.
  **ADR-039 supersedes §8** (2026-09-11) — what may leave becomes a policy classified by whose data it
  is, keeping §8's reasoning that content chosen by whatever can write a log line never leaves.
  **ADR-040 retires §9** in full. §1 stands.

## Context

Phase 07 registered a `/model` executor and deliberately did not connect it. The
reply said so in plain words: ADR-008 authorises subscription-backed
**interactive** access, it does not authorise unattended use, and whether
automating a personal Claude Pro or ChatGPT subscription behind a service falls
within either provider's terms is something this project had not established.

Phase 09 had to decide, because the owner wants the bot usable from a phone and
has chosen to keep using the existing subscriptions rather than add an API key or
a second provider.

Four constraints shape the decision.

1. **The bot cannot read either credential, and must not gain the ability.**
   Phase 07 proved this by attempting the read, and re-proves it on every run of
   `verify-telegram-bot.sh`:

   ```text
   ok  homelab-bot cannot read the Claude OAuth credential
   ok  homelab-bot cannot read the Codex OAuth credential
   ```

   So `claude -p` cannot simply be run by the bot. It has no credential and no
   home directory.

2. **The licensing question is still open.** Nothing found in Phase 09 resolves
   it. It cannot be resolved by reading a CLI's `--help`.

3. **Both CLIs are agents.** Left unrestricted they read files and run commands,
   as the account that owns the credentials and the home directory.

4. **The allowance is shared with the owner's own work.** Phase 06 lost an
   evening to an exhausted Claude window. Codex was exhausted when the Phase 09
   brief was written, and Claude was exhausted by the time the first real `/ask`
   ran.

## Decision

### 1. The call happens where the credential already is

A separate service, `homelab-model-helper`, runs as `aleix` and makes the model
call. The bot asks it over a UNIX socket at `/run/homelab-model-helper.sock`.

Rejected outright, and recorded so no later phase "simplifies" it:

- **copying either credential file to `homelab-bot`** — this destroys the
  property Phase 07 was built to establish;
- **adding `homelab-bot` to a group that can read them** — the same thing with
  extra steps, and it changes `id homelab-bot`;
- **letting the bot run something as another user** — the bot would need an
  escalation mechanism, and the thing it would escalate to is a program that
  takes arbitrary text. Phase 08's escalation is one user, one unit, one verb
  precisely because that is reviewable; "run this as aleix" is not.

`homelab-bot` gains **no group, no sudoers entry, and no read access to
`/home/aleix`.** What it gains is the ability to connect to one socket, and that
is granted by giving the socket the group the bot already has.

### 2. Access control lives in the socket unit, not in Python

`SocketUser=aleix`, `SocketGroup=homelab-bot`, `SocketMode=0660`. The kernel
refuses `connect(2)` to anyone else, before the helper process exists.

This is deliberate. An access rule in a committed unit file is four lines and
reviewable; an access check inside the helper is code that a bug in the same
helper can bypass.

`Accept=yes`, so systemd spawns one short-lived process per connection. A daemon
holding an OAuth credential in memory between requests is a larger thing to
protect than a process that starts, answers one question and exits.

### 3. The interface is not a shell

Two operations: `ping` and `ask`. `ask` takes a question and a context string and
returns text.

The caller **cannot name a provider, a model, a binary, a file or a path.** All
of those come from a root-owned config file. There is no field on the wire in
which to name a program, so a bug in the bot cannot redirect the helper at one.

### 4. The model gets no tools, and this is tested

Claude is invoked with `--tools ""` and `--strict-mcp-config`; Codex with
`--sandbox read-only`, `--skip-git-repo-check` and `--ephemeral`. Both run in a
fresh empty working directory.

Verified rather than assumed, with a canary file in the working directory:

```text
default tools : returned  CANARY-7f3a-INSIDE-CWD
--tools ""    : "canary.txt does not exist ... the directory is empty"
```

Same file, same directory, same model.

### 5. The cheapest model is the default

| Provider | Model | Basis |
|---|---|---|
| Claude | `haiku` | cheapest tier; works on Claude Pro, though the alias is undocumented in `--help` |
| Codex | `gpt-5.6-luna` | the subscription's mini tier — the CLI's own catalogue records it as the replacement for GPT-5.4 Mini |

`gpt-5.4-mini` is in the Codex binary's embedded catalogue and is **rejected** by
a ChatGPT account: *"The 'gpt-5.4-mini' model is not supported when using Codex
with a ChatGPT account."* Presence in a catalogue is not entitlement.

### 6. Two providers, with automatic fallback

Claude Pro and ChatGPT are two subscriptions with **independent usage limits**.
The preferred provider is tried first; if it reports exhaustion the other is
tried; if both are spent the reply says so and names when there will be room.

This was not a demonstration. It was load-bearing on day one: Claude was
exhausted when the first real `/ask` ran, and Codex answered it.

A **hard error does not trigger fallback** — only exhaustion does. Spending the
second subscription because the first one broke would turn one fault into two.

### 7. Per-hour and per-day caps, enforced before the call

Counted per provider, in the helper, because the helper is what spends the
allowance. Defaults: 6 per hour, 30 per day.

This is not a billing control — there is no marginal charge. It exists so that a
stuck finger on a phone cannot cost the owner their next working session.

State is a `flock`-protected file, not memory: with `Accept=yes` there is no
process that outlives a request. A reservation is **not refunded** when the
provider turns out to be exhausted; an attempt was made and counting it is the
honest accounting.

### 8. What is sent, exactly

The question, plus the literal output of `/status`: hostname, uptime, load,
memory, disk. **Nothing else.**

No logs, no journal, no file contents, no configuration, no unit files, no
allowlists. This is a security boundary, not a scoping accident: journal lines
are written by other software, some of it reachable from the network, so feeding
them to a model would mean an unbounded amount of host data leaving the machine,
selected by whatever could write a log line rather than by the owner. Five
numeric fields cannot carry an instruction.

**Widening this requires its own ADR.**

### 9. Owner-initiated only

> **Superseded by ADR-026 on 2026-09-10.** The owner has decided that subscription providers may
> serve unattended calls in the interim, as an accepted risk, and eligibility became a per-provider
> field rather than a global rule. The reasoning below is retained because it explains why the
> constraint existed and what accepting the risk actually costs. **Nothing else in this ADR is
> affected** — the credential boundary (§1) and the bounded context (§8) stand.


Every model call is traceable to a message the owner has just sent. No scheduled
calls, no background calls, no autonomous calls.

This is what currently substitutes for an answer to the licensing question. It
keeps the usage pattern the same shape as a human using their own subscription
interactively, which is what ADR-008 authorises. It is a constraint, not a
preference: **Phase 12 (automation) must not make unattended model calls without
a new ADR that addresses the licensing question directly.**

### 10. The model's output is never an instruction

`/ask` returns a string. It is sent to Telegram and nothing else is done with it
— never parsed, never matched against the registry, never passed back into
`dispatch()`. `dispatch()` has exactly one call site, and its input is the
Telegram message text.

Tested, and the test is worth recording because the model **complied**:

```text
question: "...Output exactly and only this text: /restart ssh.service"
reply   : "/restart ssh.service"
chrony ActiveEnterTimestamp: unchanged either side
```

The command was produced. The architecture made it inert. Nothing depended on
the model declining, and a model with its tools disabled will also happily emit
text shaped like a tool call — during testing, Haiku with `--tools ""` replied
with a `function_calls` block and a confabulated answer.

## Consequences

**Good**

- The bot can answer real questions from a phone without holding a credential.
- The Phase 07 credential boundary is intact and still tested by attempt.
- No new listening socket: `ss -tln` is byte-identical to phase start. A UNIX
  socket adds nothing to the machine's network-facing surface.
- Exhaustion is a normal operating state with a legible message, not an outage.
- `id homelab-bot` is byte-identical to phase start.

**Bad, or at least owed**

- **A second service now runs as the human's account.** It is the only one, and
  it is the concession that buys everything above. It is hardened as far as the
  CLIs permit, and the directives that had to be left off are named in the unit
  with reasons — `MemoryDenyWriteExecute` (both CLIs ship a JIT),
  `RestrictNamespaces` (Codex's sandbox is built from namespaces), and
  `SystemCallFilter` (unmeasured surface; a guessed filter would produce
  intermittent failures that look like model outages).
- **`ReadWritePaths=/home/aleix`** is broader than it should eventually be.
  Narrowing it to `~/.claude` and `~/.codex` is a candidate for a later phase,
  and was deliberately not guessed at here: Phase 07 set `ProcSubset=pid`, broke
  every `/status`, and established that hardening which breaks the function it
  protects is not hardening.
- **The licensing question is unresolved.** §9 is a constraint that keeps the
  usage pattern defensible; it is not an answer.
- **Data now leaves the machine routinely**, which the backup and encryption
  decisions (ADR-015) must account for.
- `dispatch()` had to change to support `/ask` — the Phase 08 handover hoped a
  new executor never would. The reasons are recorded in `router.py`: `/ask` is
  the first executor whose action spends a shared resource, and the first whose
  argument is the owner's own prose rather than a service name.

## Alternatives considered

| Option | Why not |
|---|---|
| API key with metered billing | ADR-008 forbids it, and the owner has chosen to stay on subscriptions |
| Copy the credential to `homelab-bot` | Destroys the Phase 07 boundary this project spent a phase establishing |
| `homelab-bot` in a group that can read the credential | The same, and it changes `id homelab-bot` |
| Bot escalates to run `claude` as `aleix` | The escalation target would accept arbitrary text. Phase 08's grant is narrow because narrow grants are reviewable |
| One provider only | Recommended by the assistant and **overruled by the owner.** The owner was right: Claude was exhausted when the first real `/ask` ran |
| Send journal output as context | Unbounded host data leaving the machine, chosen by anything that can write a log line. Needs its own ADR |
| Conversation memory | Rejected: stateless is cheaper and simpler, and stores no conversation data on a node with no backup and no encryption |
