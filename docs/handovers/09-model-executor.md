# Phase 09 Brief — Model Executor

- **Date:** 2026-09-09
- **Phase:** 09 — Model Executor (subscription-backed)
- **Author:** the Phase 09 context
- **Status:** Accepted, self-ratified under ADR-017
- **Previous handover:** [`08-router-executors-handover.md`](08-router-executors-handover.md)

## 0. Governance note

Under ADR-017 there is no Project Planning context to ratify this brief. It is written and committed
**before implementation begins**. Eighth consecutive phase to do so.

### 0.1 Roadmap amendment, recorded rather than made quietly

**Phase 09 was "Voice". It is now "Model Executor". Voice becomes Phase 17.**

The owner's reasoning, and it is better than the roadmap's original ordering: **voice on top of six
deterministic commands is a slower way to type `/status`.** Speech-to-text only becomes worth having
once there is something worth *saying* — which means a model executor first. Voice then arrives into
an interface that can actually answer.

Phase 09's slot was always "make the interface genuinely useful". Voice was one way to do that; this
is the better first way. `ROADMAP.md` is amended, and the change is stated here rather than edited in
silently (`PROJECT.md` §11).

The agreed running order from here: **09 Model Executor → foundations (backup + the ADR-015
encryption decision) → 17 Voice → 10 Knowledge → 11 Frameworks → 12 Automation.** Numbers stay
stable; order is flexible, exactly as when Phase 03 ran before Phase 02.

### 0.2 Four scope decisions taken with the owner before writing

1. **Subscription-backed, cheapest model.** Not a paid API key. Haiku by default, and the model is a
   configuration value rather than a constant.
2. **Both providers wired now** — Claude *and* Codex. The owner overruled a recommendation to ship
   one, and was right: see §1.2.
3. **Q&A with host status as context.** `/ask` sends the question plus the deterministic `/status`
   output. Not plain Q&A, and **not** the ability to read logs or files on request.
4. **Rate limits per hour and per day.**

## 1. Purpose

Phase 08 built the router and left one executor deliberately inert. This phase connects it, and in
doing so answers a question three phases have deferred.

The owner's stated goal is concrete: **a bot worth reaching for from a phone.** Six deterministic
commands are a status page. `/ask` makes it something you consult.

### 1.1 This phase is not lockout-class, and that is worth saying explicitly

Nothing here touches network, remote access, authentication, boot, or the admin account. ADR-020's
procedure does not apply.

**It carries a different risk class instead, and the standards do not cover it:** this is the first
phase in which **data leaves the machine on a routine basis, to a third party, as a side effect of
normal use.** Phase 07 established that Telegram sees every message. This adds a second recipient —
Anthropic or OpenAI — receiving the host's own metrics on every `/ask`.

That is not a lockout risk. It is a disclosure risk, and it needs its own reasoning (§9), not a
borrowed checklist.

### 1.2 Why wiring both providers is a resilience decision, not a demonstration

Measured at phase start, 2026-09-09 20:28 UTC:

```console
$ claude -p --model haiku "Reply with exactly: OK"
OK

$ codex exec --sandbox read-only "Reply with exactly: OK"
ERROR: You've hit your usage limit ... try again at 8:55 PM.
```

**One provider was already exhausted before the phase began.** Phase 06 hit the same wall on Claude
and had to wait until 18:00 UTC.

Two subscriptions have **independent limits**. Wiring both is therefore not about proving ADR-007's
abstraction is real — although it does that — it is about the bot still working when one allowance is
spent. The recommendation to ship a single provider would have produced something that fails for
hours at a time.

It also means the exhausted-provider path can be tested against a genuinely exhausted provider today,
rather than simulated.

### 1.3 The constraint that makes subscription use defensible

ADR-008 authorises subscription-backed **interactive** access. It is silent on unattended use, and
whether automating a personal subscription behind a service is within either provider's terms is
**not something this project has established.** That remains an unknown and is not resolved by this
phase.

What *is* decided is a constraint that keeps this close to interactive use, and it is binding:

> **Every model call is traceable to a message the owner just sent.** No scheduled calls, no
> autonomous loops, no retries the owner did not ask for, no background summarisation, no
> pre-warming. If nobody typed, nothing is called.

Phase 12 (Automation) will want to break this. It must not do so silently — it needs a new ADR.

## 2. Starting state

Verified from live output on 2026-09-09 at phase start.

### The bot

| Fact | Value |
|---|---|
| Unit | `homelab-telegram-bot.service` — active, enabled, **0 restarts** |
| Account | `homelab-bot` uid 999, groups `homelab-bot` only, **0 sudoers entries** |
| Exposure | `systemd-analyze security` → **1.3 OK** |
| Listeners | **6** — no listening socket of its own |
| Executors | 6 registered: `/status`, `/disk`, `/uptime` (READ), `/restart` (PRIVILEGED), `/model` (UNAVAILABLE), `/help` |
| Escalation | polkit, one user / one unit / one verb; second allowlist inside the bot |
| Forks | Yes, since Phase 08 — `/restart` execs `systemctl` |
| `AF_UNIX` | Permitted since Phase 08 |

### The providers

| Fact | Value |
|---|---|
| Claude Code | `2.1.236`, native Linux, `claude.ai` / firstParty / **pro** |
| **Haiku available** | ✅ `--model haiku` and `--model claude-haiku-4-5-20251001` both returned `OK` |
| Model aliases offered | `fable`, `opus`, `sonnet` in `--help`; **`haiku` works but is undocumented there** |
| Codex CLI | `0.153.4`, `Logged in using ChatGPT`, non-interactive via `codex exec` |
| **Codex status** | ❌ **usage limit reached at phase start**, resets ~20:55 UTC |
| Credential files | `/home/aleix/.claude/.credentials.json`, `/home/aleix/.codex/auth.json`, both `0600 aleix:aleix` |

### The problem that dominates the design

**Both CLIs are owned by `aleix`. The bot runs as `homelab-bot`, which provably cannot read either
credential file.** That was verified in Phase 07 and must remain true:

```text
ok  homelab-bot cannot read the Claude OAuth credential
ok  homelab-bot cannot read the Codex OAuth credential
```

So the bot **cannot simply run `claude -p`** — it has no credential and no home directory. How the
call is made without breaking that boundary is the central design question of this phase (§7.1), and
the obvious answers are all wrong (§6.1).

## 3. Learning objectives

1. **Why a service cannot borrow a human's credential**, and what the alternatives cost.
2. **What a provider abstraction is for** — ADR-007 in code, with two real implementations that fail
   differently.
3. **That a rate limit is a resource you share with yourself.** The bot spends the same allowance the
   owner needs for work.
4. **What leaves the machine on every call**, exactly, and why "just send the logs too" is a much
   bigger decision than it looks.
5. **Prompt injection as a category** — why sending five numeric fields is safe and sending journal
   output would not be.
6. **Graceful degradation** — an exhausted provider is a normal operating state, not an error.

## 4. Functional objectives

1. **A provider abstraction** with two working implementations, Claude and Codex, selectable and
   swappable by configuration.
2. **`/ask <question>`** returns a model answer, with `/status` output supplied as context.
3. **The cheapest model is the default** — Haiku for Claude; the cheapest available for Codex.
4. **Per-hour and per-day call caps**, enforced before the call, with a clear message when spent.
5. **Automatic fallback**: if the preferred provider is exhausted, the other is tried. If both are
   spent, the bot says so plainly and names when to retry.
6. **Every call is owner-initiated** and logged with the requesting user, the provider, the model,
   and the outcome.
7. **`homelab-bot` still cannot read either credential file** — unchanged from Phase 07.
8. **No new listening socket**; `ss -tln` byte-identical.
9. **The `/model` executor is replaced** by the working one, and `/help` reflects it.
10. **The exhausted-provider path is tested against a genuinely exhausted provider**, not a mock.
11. `id homelab-bot` byte-identical to phase start.
12. Costs recorded as an explicit zero **in money**, with the allowance cost stated separately.

## 5. Decisions already fixed

| Source | Constraint |
|---|---|
| **ADR-007** | Model access behind replaceable executors. Two providers is this ADR being paid off. |
| **ADR-008** | Subscription-backed access. **No API keys, no paid overage, no credential export.** |
| **ADR-011** | The service stays unprivileged. It must not gain access to `aleix`'s credentials. |
| **ADR-023** | Long polling, no listening socket, allowlist before dispatch, `LoadCredential` for secrets. |
| **ADR-024** | Executors register in the router; the authorisation check stays in one function. |
| **Phase 08 handover** | Adding an executor should not require touching `dispatch()`. |
| Owner's decision | Cheapest model; both providers; host status as context; hourly and daily caps. |
| **This brief §1.3** | Owner-initiated only. No scheduled or autonomous calls. |

## 6. Decisions still open

1. **How the call is made without giving the bot a credential.** The central question. Candidates:
   - a **privileged helper** invoked like `/restart` is, running as `aleix` under a scoped polkit or
     systemd mechanism;
   - a **separate small service** running as `aleix` that the bot talks to over a local socket;
   - `systemd-run --uid=aleix` with a scoped grant.

   **Presumption: the second.** It keeps the credential inside a process the owner already trusts,
   gives a clean place for the rate limiting, and does not require the bot to execute anything as
   another user. **Rejected outright: copying either credential file to `homelab-bot`, or adding
   `homelab-bot` to a group that can read them.**
2. **Where the rate-limit state lives** — the bot, the helper, or a shared file. Presumption: the
   helper, because that is what actually spends the allowance.
3. **The cheapest Codex model**, once the limit resets and it can be queried.
4. **Whether `/ask` keeps conversation context.** Presumption: **no.** Each question stands alone.
   Stateless is cheaper, simpler, and avoids storing conversation data on a node with no backup and
   no encryption.
5. **What `/status` context looks like in the prompt** — the same five fields the command returns,
   verbatim, so what is sent is exactly what the owner can already see.

## 7. Implementation scope

### 7.1 The credential boundary is the design

`homelab-bot` cannot read the credentials and must not gain the ability. So the model call happens in
a process that already has them, and the bot asks it.

Whatever mechanism is chosen must satisfy all of:

- the bot gains **no group, no sudoers entry, no read access** to `/home/aleix`;
- the helper accepts **only** a question and returns **only** an answer — it is not a shell;
- the helper enforces the rate limits, because it is what spends the allowance;
- the interface is small enough to review in one sitting;
- failure is closed and legible.

### 7.2 The provider abstraction

```python
class Provider(Protocol):
    name: str
    def ask(self, question: str, context: str) -> Answer: ...
    # Answer carries: text | exhausted(retry_at) | error(reason)
```

Two implementations. **They fail differently and that is the point** — Claude reports a reset time in
one format, Codex in another, and the abstraction exists to make "exhausted" a single concept.

Selection order is configuration. Fallback is automatic and logged.

### 7.3 Rate limiting

Per-hour and per-day caps, checked **before** the call, counted per provider. When both are spent the
reply names the earliest retry time rather than failing obscurely.

This protects the owner from themselves: Phase 06 lost an evening to an exhausted Claude window, and
Codex was already exhausted when this brief was written.

### 7.4 What is sent, exactly

The question, plus the literal output of `/status` — hostname, uptime, load, memory, disk. Five
figures the owner can already read on their phone.

**Nothing else.** No logs, no file contents, no journal, no configuration, no allowlists, no unit
files. Extending this is a separate decision with a separate risk assessment (§9.3).

### 7.5 Not in scope

No conversation memory. No scheduled calls. No tool use by the model. No ability for the model to run
commands or trigger executors — **`/ask` cannot reach `/restart`**, and the router's capability check
is what guarantees it.

## 8. Validation / tests

1. `/ask` returns a real answer via Claude/Haiku, logged with provider and model.
2. **`homelab-bot` still cannot read either credential file** — tested by attempting it.
3. `id homelab-bot` byte-identical; no new group, no sudoers entry.
4. **`ss -tln` byte-identical** to phase start.
5. The exact prompt content is inspectable and contains **only** question + `/status` output.
6. Hourly cap enforced: the (n+1)th call in an hour is refused with a clear message.
7. Daily cap enforced likewise.
8. **Exhausted provider handled** — tested against genuinely exhausted Codex.
9. **Fallback works**: with the preferred provider exhausted, the other answers.
10. Both spent → a legible message naming the earliest retry time.
11. `/ask` **cannot** invoke a privileged executor; the model's output is never dispatched.
12. Every call appears in the journal with user, provider, model and outcome; **no credential or
    token appears**.
13. `/help` shows `/ask` and no longer shows an unavailable `/model`.
14. `systemd-analyze security` ≤ 1.3, or any change explained.
15. A failing provider does not kill the service.
16. Reboot test: the service and the helper both return; `/ask` works afterwards.
17. `systemctl is-system-running` → `running`, 0 failed units — checked **last**.

## 9. Security considerations

### 9.1 The credential boundary must survive this phase

The single most important property carried from Phase 07. `homelab-bot` cannot read
`/home/aleix/.claude/.credentials.json` or `/home/aleix/.codex/auth.json`, and this phase must not
change that. **Copying a credential to a service account because it works interactively is
explicitly forbidden** by the Phase 08 handover and by ADR-008.

### 9.2 Data now leaves the machine routinely

Every `/ask` sends the host's metrics to a third-party model provider, in addition to Telegram
already seeing the message. That is two external recipients for one question.

Bounded and predictable — always the same five figures — but it is a genuine change in posture and
the guide must state it plainly rather than burying it.

### 9.3 Why not logs, and why "just add files" is a different decision

Sending journal output would mean **an unbounded amount of host data leaving the machine, selected by
a model rather than by the owner.** It also opens **prompt injection**: journal lines contain text
written by other software, and anything that can write a log line could then write instructions into
the model's context.

Five numeric fields cannot carry an injection. Log output can. That is the whole reason for the
boundary, and any later phase widening it needs an ADR.

### 9.4 The allowance is a shared resource

The bot spends the same subscription the owner needs for work. Phase 06 lost an evening to it;
Codex was exhausted before this brief was finished. Rate limits are not politeness — they stop a
chatty phone session leaving the owner unable to work.

### 9.5 The model's output is never an instruction

`/ask` returns text to a human. It is never parsed, never dispatched, never used to select an
executor. The router's capability check means even a model that emitted `/restart ssh` could not
cause it — but the design must not rely on that as its only defence.

### 9.6 The repository is public

The helper, the abstraction and the prompt construction all become public. They are mechanism.
Credentials stay on the node; `scan-history.sh` runs before the push.

## 10. Repository changes expected

| Path | Change |
|---|---|
| `docs/handovers/09-model-executor.md` | **This brief** — committed first |
| `services/telegram-bot/providers.py` | New — the abstraction and both implementations |
| `services/telegram-bot/executors.py` | Modified — `/model` becomes `/ask` |
| `services/model-helper/` | New — the credential-holding helper (§6.1) |
| `config/systemd/` | New unit for the helper |
| `scripts/server/install-model-helper.sh` | New — guarded installation |
| `scripts/server/verify-telegram-bot.sh` | Extended — credential boundary and rate-limit checks |
| `guide/09-model-executor/README.md` | New |
| `docs/decisions/ADR-025-…` | New — subscription-backed model access, the owner-initiated constraint, the credential boundary |
| `docs/build-log/2026-09-09-phase-09-*.md` | New |
| `docs/handovers/09-model-executor-handover.md` | New — addressed to the foundations phase |
| `ROADMAP.md` | **Amended** — Phase 09 redefined, Voice → Phase 17 |
| `docs/reference/*`, `CHANGELOG.md`, `guide/README.md`, `scripts/README.md`, `docs/architecture/current-architecture.md` | Updated |

## 11. Guide documentation required

`guide/09-model-executor/README.md`:

- Leads with **why the bot cannot just run `claude -p`** — the credential boundary is the lesson.
- States plainly **what leaves the machine on every call**.
- Explains rate limits as a shared resource, with the real exhausted-Codex output.
- Explains prompt injection well enough that the reader understands why logs are excluded.

## 12. Project documentation required

As listed. `ROADMAP.md` carries the amendment and the reason. `costs.md` records **0 DKK** and states
the allowance cost separately, because it is real and is not money.

## 13. ADRs required / possible

| ADR | Status | Subject |
|---|---|---|
| **ADR-025 — subscription-backed model access** | **Required** | Cheapest model by default; two providers with independent limits and automatic fallback; the credential boundary and how the call is made without breaching it; **owner-initiated only**; host status as the only context, and why logs are excluded. Records that the licensing question remains open and what constraint substitutes for an answer. |
| Widening the context beyond `/status` | **Not this phase** | Needs its own ADR (§9.3). |
| Automation calling the model unattended | **Not this phase** | Phase 12 must not break §1.3 silently. |

## 14. Costs

**0 DKK incremental.** Both subscriptions already exist and are recorded in Phase 06's ledger
(€45.50/month, ~339 DKK/month). No API key, no overage, no new service.

**The non-money cost is real and must be recorded as such:** every `/ask` consumes the owner's own
subscription allowance. Codex was exhausted before this phase began. The ledger should say that the
marginal financial cost is zero and the marginal capacity cost is not.

## 15. Definition of Done

From `PROJECT.md` §12, applied **literally, item by item**:

- [ ] Functional objective works — all twelve in §4
- [ ] Configuration/setup is reproducible — helper, unit and config all from committed files
- [ ] Validation/tests have passed — all seventeen checks in §8, with captured output
- [ ] Important security implications were considered — §9; the credential boundary re-proved
- [ ] Relevant repository files are committed
- [ ] Human-facing guide is updated
- [ ] Project/internal documentation is updated, including `ROADMAP.md` and the architecture document
- [ ] ADRs created or updated — ADR-025
- [ ] Actual costs recorded — explicit zero in money, allowance cost stated
- [ ] Problems, failed approaches and lessons recorded, including my own errors
- [ ] Tested versions recorded — both CLIs and both models
- [ ] No unexplained critical AI-generated component remains
- [ ] `main` represents a known-working state — after `--no-ff` merge
- [ ] System reports no failed units and no degraded state — checked **last**
- [ ] Structured handover written, stating what the next phase inherits

## 16. Return handover requirements

Addressed to the **foundations phase** (backup + the ADR-015 encryption decision), and must state:

1. **Whether the licensing question is any closer to resolved**, and that the owner-initiated
   constraint is what currently substitutes for an answer.
2. **The exact credential boundary** and how the call is made without breaching it, so no later phase
   "simplifies" it by copying a credential.
3. **What data leaves the machine**, so the encryption and backup decisions account for it.
4. **The rate-limit design**, and that the allowance is shared with the owner's own work.
5. **That Phase 12 must not make unattended calls without a new ADR.**
6. **Open risks carried forward**, plus anything this phase adds.
