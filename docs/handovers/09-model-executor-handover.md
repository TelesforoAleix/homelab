# Phase 09 Handover — Model Executor (subscription-backed)

- **From:** Phase 09 context
- **To:** the **foundations** phase — backup, plus the ADR-015 encryption decision
- **Date:** 2026-09-09
- **Outcome:** **Complete.** `/ask <question>` answers from Telegram, via either subscription, with
  `homelab-bot` still unable to read either credential.

## 1. Is the licensing question any closer to resolved?

**No.** Nothing found in this phase resolves it, and it cannot be resolved by reading a CLI's
`--help`.

Phase 07 registered `/model` and refused to connect it for exactly this reason. Phase 09 connected
it under **a constraint instead of an answer**:

> **Every model call is owner-initiated** — traceable to a message the owner has just sent. No
> scheduled calls, no background calls, no autonomous calls.

The reasoning is that this keeps the usage pattern the same *shape* as a human using their own
subscription interactively, which is what ADR-008 authorises. That is a defensible position. It is
not a resolution, and it is written down as such in ADR-025 §9.

**What this means for whoever automates anything:**

> **Phase 12 must not make unattended model calls without a new ADR that addresses licensing
> directly.** The constraint is load-bearing. A scheduled `/ask` would break it silently, because
> nothing in the code enforces "a human asked for this" — the enforcement is that the only caller is
> the Telegram message loop.

If a later phase wants unattended calls, the honest options are: establish the terms position, move
to a metered API key (which ADR-008 currently forbids), or run a local model (Phase 16).

## 2. The exact credential boundary, and how the call is made

**Read this before touching anything model-related.** Two phases were spent establishing this
property and it would take one careless commit to undo.

```text
Telegram ──▶ homelab-bot ──socket──▶ homelab-model-helper ──▶ Claude / Codex
             uid 999                 runs as aleix
             no credential           already holds both credentials
             ProtectHome=yes
```

| Fact | Value |
|---|---|
| Socket | `/run/homelab-model-helper.sock`, `aleix:homelab-bot`, mode `0660` |
| Who decides access | **systemd, in the `.socket` unit**, before the helper process exists |
| Helper lifetime | `Accept=yes` — one process per connection. Nothing holds a token between requests |
| Bot's groups | `homelab-bot` only. `id homelab-bot` **byte-identical** to Phase 07 and 08 |
| Bot's sudoers entries | zero |
| Bot's access to `/home/aleix` | none — `ProtectHome=yes` |

**The bot was never added to a group. The socket was given the group the bot already had.** Same
effect on who can connect; completely different effect on what the bot *is*. Keep that direction.

**Forbidden, and recorded as forbidden so it is not rediscovered as a good idea:**

- copying either credential file to `homelab-bot`;
- adding `homelab-bot` to a group that can read them;
- giving the bot an escalation that runs a program taking arbitrary text. Phase 08's grant is one
  user / one unit / one verb *because* that is reviewable. "Run `claude` as `aleix`" is not.

**The interface is not a shell.** Two operations, `ping` and `ask`. The caller cannot name a
provider, a model, a binary, a file or a path — all of those come from a root-owned config file.
There is no field on the wire in which to name a program.

**Verify it, do not trust this document:**

```text
sudo bash /tmp/homelab-phase09/install-model-helper.sh verify
```

It attempts each forbidden access rather than reading directives, and reports `UNKNOWN` rather than
inventing a verdict.

## 3. What data leaves the machine — for the encryption and backup decisions

**On every `/ask`:** the owner's question, plus the literal output of `/status` — hostname, uptime,
load, memory, disk. Five figures the owner can already see on their phone.

**Nothing else.** No logs, no journal, no file contents, no configuration, no unit files, no
allowlists. The exact prompt is printable verbatim and was inspected as part of validation.

**This is a boundary, not a scope limit.** Journal lines are written by other software, some of it
reachable from the network. Sending them to a model would mean an unbounded amount of host data
leaving the machine, **chosen by whatever could write a log line rather than by the owner** — prompt
injection. Five numeric fields cannot carry an instruction. **Widening the context requires its own
ADR.**

**What the foundations phase should take from this:**

1. **There is now a routine outbound flow of host state to third parties.** It is small and bounded,
   but it is no longer true that node data stays on the node.
2. **Nothing of the conversation is stored.** `/ask` is stateless by decision — no history, no
   transcripts. Codex runs with `--ephemeral` so it writes no session files either. So there is
   **no new data at rest to back up or encrypt** from this feature, which was one reason for the
   choice on a node with neither.
3. **The journal now records model usage** — requesting user, provider, model, outcome, duration,
   and the provider's failure output. **Not the question text.** If journal retention or export is
   ever configured, that is the file that describes the owner's usage pattern.
4. **Two OAuth credentials remain the highest-value secrets on an unencrypted disk**, and Phase 09
   added a service that reads them on demand. This is unchanged in kind from Phase 06 and worse in
   degree, and it is an argument for the ADR-015 decision rather than against this design.

## 4. The rate-limit design, and that the allowance is shared

| Property | Value |
|---|---|
| Caps | 6/hour, 30/day, **per provider** |
| Where enforced | in the helper — it is what spends the allowance |
| When | **before** the call. A refused request costs nothing |
| State | `/var/lib/homelab-model-helper/calls.json`, `flock`-protected, owner `aleix` mode `0700` |
| Config | `/etc/homelab-model-helper/config.json`, root-owned |

**These are not billing controls.** There is no marginal charge — both subscriptions are flat. They
protect **capacity**, and what they protect it from is the owner.

Every `/ask` spends allowance from the same bucket the owner needs for their own work. This is not
hypothetical: Codex was exhausted when this brief was written, and **Claude Pro hit its session
limit during implementation**, partly consumed by this phase's own verification.

Two design details worth preserving:

- **A failed attempt still counts.** Claude exhausted + Codex answering spends one call from each,
  because two calls were made.
- **State is a locked file, not memory,** because `Accept=yes` means no process outlives a request.
  Proved with ten concurrent processes racing for one slot: exactly one winner.

## 5. What the next phase inherits

**Working, and verified by live output:**

| Thing | State |
|---|---|
| `/ask <question>` | Answers from Telegram; `/model` kept as an alias |
| Providers | Claude (`haiku`) and Codex (`gpt-5.6-luna`), independent limits, automatic fallback |
| Fallback | **Proved against a genuinely exhausted Claude**, not a mock |
| Caps | Hourly, daily, both-spent message naming time to room |
| `/help` | Generated from the registry, legend included |
| Model tools | **Disabled**, verified with a canary file against a positive control |
| Model output | Never dispatched — proved by making the model emit `/restart ssh.service` |
| Listeners | `ss -tln` → **6**, byte-identical |
| Bot exposure | `systemd-analyze security` → **1.3 OK** |

**Deliberately absent:**

- conversation memory (stateless by decision);
- scheduled or background calls (§1);
- tool use by the model, and any route from `/ask` to a privileged executor;
- context beyond `/status` (§3);
- a narrower `ReadWritePaths` for the helper — `/home/aleix` is broader than it should eventually
  be, and was **not** guessed at. Phase 07 set `ProcSubset=pid`, broke every `/status`, and
  established that hardening which breaks the function it protects is not hardening. Narrowing it
  is a fine task for a later phase, done by measuring what the CLIs touch.

**Three hardening directives are absent from the helper unit with reasons recorded in it:**
`MemoryDenyWriteExecute` (both CLIs ship a JIT, which needs writable-then-executable pages),
`RestrictNamespaces` (Codex's read-only sandbox is built from namespaces — forbidding them would
disable the thing keeping the model's shell tool off the filesystem), and `SystemCallFilter`
(unmeasured surface; a guessed filter produces intermittent failures that look like model outages).

## 6. Open risks carried forward, plus what this phase added

Carried forward unchanged: no backup of the node; root filesystem unencrypted; no firewall; single
Wi-Fi adapter shared by both access routes; single SSH key; `aleix` in the `docker` group
(root-equivalent); no alerting — **nothing reports the bot dying**; Telegram is a third party.

**Added by Phase 09:**

1. **A service runs as the human's account.** The only one. `aleix` can `sudo` and is in `docker`,
   so this process is a more valuable target than the bot. `NoNewPrivileges=yes` retained.
2. **The licensing question is now load-bearing** rather than deferred (§1).
3. **Routine outbound flow of host state** to two third parties (§3).
4. **The bot can now consume a resource the owner needs.** Capped, but shared (§4).
5. **A model's output is displayed to the owner as text.** It is never executed, but it can be
   confidently wrong — during testing a tool-less model invented a hostname and declared a
   non-empty directory empty. `/ask` is not a source of truth about this machine; `/status` is.

**Fixed by Phase 09, in Phase 07's code:** `StartLimitIntervalSec` was in `[Service]`, where systemd
ignores it. The effective window was 10s against a `RestartSec=10` policy, so five starts could
never land inside it and the restart limit was **unreachable for two phases** — the tight restart
loop it was written to stop could have run indefinitely on a console-less node. Found by
`systemd-analyze verify`, which `install-telegram-bot.sh` now runs on every install and prints.

## 7. Recorded deviations from the brief

Per ADR-017, deviations are recorded rather than quietly applied.

| Brief | What happened | Why |
|---|---|---|
| §10 placed `providers.py` under `services/telegram-bot/` | It lives in `services/model-helper/` | It follows from resolving §6.1 as the brief presumed. The providers run in the helper, as `aleix`; putting them in the bot's directory would suggest the bot runs them. Same code, honest location |
| Phase 08 handover: "adding an executor should not require touching `dispatch()`" | `dispatch()` changed | `/ask` is the first executor that needs the caller's identity (the audit record of who spent the allowance must be written by the process that spent it) and the first whose argument is the owner's prose rather than a service name. Two additive `Executor` fields, `wants_user` and `log_args`, both defaulted so no existing executor changed. The alternative was a module-level "current user" variable, which is how this gets smuggled in |
| §8.8 "tested against a genuinely exhausted provider" | Satisfied — but by **Claude**, not Codex | Codex's limit reset before implementation began; Claude's ran out during it. The requirement was a real exhausted provider, and that is what was tested |

## 8. Suggested next phase

The owner's agreed order after Phase 09:

1. **Foundations** — backup, plus the ADR-015 encryption decision. **This handover is addressed to
   it.** The node has now accumulated enough that is expensive to rebuild — two OAuth credentials, a
   bot token, a polkit grant, three service accounts and a working service stack — and still has no
   backup at all.
2. **Phase 17 — Voice** (moved out of Phase 09 at the owner's request)
3. **Phase 10 — Knowledge**
4. **Phase 11 — Frameworks**
5. **Phase 12 — Automation** — see §1. It **must not** make unattended model calls without a new ADR.
