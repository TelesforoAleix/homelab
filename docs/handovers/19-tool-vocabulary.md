# Phase 19 Brief — Tool Vocabulary & Capability Levels

- **Phase:** 19 — Tool Vocabulary & Capability Levels
- **Written:** 2026-09-10
- **Status:** Brief, committed before implementation per ADR-017
- **Implements:** ADR-027 §3, §4, §5; ADR-031 §2, §7
- **Predecessors read:** `08-router-executors-handover.md`, `09-model-executor-handover.md`
- **Prerequisite for:** Phase 20 (Factory rewrite), and through it Phase 22

## 0. Governance note

### 0.1 Why this phase exists at all, stated plainly

Factory ships **zero agent manifests**. It cannot write the `tools` line of one, because the thing
that line names does not exist. ADR-027 §3 puts the vocabulary in homelab — *"because homelab is what
enforces them"* — and ADR-031 §7 makes publishing it the stated prerequisite of the Factory rewrite.

So this phase is on the critical path for the whole method layer, and it is small. Those two facts
together are the risk: a small phase on a critical path attracts scope.

### 0.2 The standing rule this phase is most likely to break

This project's recorded failure mode is **specifying behaviour that does not execute**. Factory
currently holds 10,022 lines of markdown across 75 files and zero loadable manifests; ADR-031 §7
discards that format for exactly that reason.

A tool vocabulary is the ideal shape for repeating the mistake. A catalogue of forty plausible tool
names would look like progress, would cost nothing to write, and would be inert.

> **The rule for this phase: a name earns its place only if the runtime can refuse it today, or if
> ADR-027's own example manifest already requires it.** Nothing else goes in.

That is why §4 below proposes **five** names and not fifty, and why §7.1 lists what was deliberately
left out with reasons.

### 0.3 What "publishing an interface" commits this project to

ADR-027 Consequences: *"homelab must maintain a named tool vocabulary as a stable public interface.
Renaming a tool becomes a breaking change for every manifest that names it — which is the correct
cost, but it is a cost."*

This is the first artifact in the project with that property. `Capability` and `Executor` are
internal; a tool name will be written into files in another repository that homelab does not control.
Getting a name wrong is cheap this week and expensive in Phase 22.

### 0.4 Sequencing

Not lockout-class under ADR-020: no network, boot, authentication or disk configuration is touched.
It is a user-space service change, revertible from git.

It should follow Phase 18, because Phase 18 is the phase that gives the node a backup and this phase
changes the one service that holds a live credential path. It has no dependency on Phase 18's outcome
and does not need to wait on the ADR-015 decision.

**It has a soft dependency on Phase 15.0** — see §6.5. `ask_model` cannot carry ADR-027 §2's
`model_policy` until the helper's wire protocol has a task class. That is a reason to sequence 15.0
first, not a reason to build it here.

## 1. Purpose

Publish homelab's named tool vocabulary and its capability levels as a stable public interface, and
build the enforcement that makes it a contract rather than a list:

1. an unknown tool name **fails to load** (ADR-027 §5);
2. `effective tools = agent.tools ∩ what this caller is authorised for`, evaluated in
   `Router.dispatch()` and nowhere else (ADR-027 §4);
3. both proved against a **planted positive control**, because an authorisation check that has only
   ever permitted is unvalidated.

The phase delivers a vocabulary that no manifest yet consumes. That is not the same as inert prose:
**the refusal path executes on every load and every dispatch, with zero manifests present**, and it
is what the phase is validated on.

## 2. Starting state

Verified by reading the installed source on 2026-09-10, not copied from documentation. File and line
references are to `services/telegram-bot/` at commit `8f9c258`.

### 2.1 The capability levels that actually exist

`router.py:39-51`:

| Value | Documented meaning | Members today |
|---|---|---|
| `READ` | *"answers from the host's own state; changes nothing"* | `/status`, `/disk`, `/uptime`, `/ask`, `/help` |
| `PRIVILEGED` | *"changes something. Requires the privileged allowlist"* | `/restart` |
| `UNAVAILABLE` | *"registered so it appears in /help and in the architecture, but deliberately not wired"* | **none** |

**`Capability.UNAVAILABLE` currently has zero members.** Phase 09 connected the last one. `/help`'s
legend is derived from the registry (`executors.py:302-313`) precisely *because* it went on explaining
a `-` marker that no longer appeared against anything. The level survives with no user, and §6.2
treats that as a finding rather than a curiosity.

### 2.2 Every executor currently registered

Registration is `executors.py:329-356`.

| Command | Capability | What it actually does | Source |
|---|---|---|---|
| `/status` | READ | Reads `/etc/hostname`, `/proc/uptime`, `/proc/loadavg`, `/proc/meminfo`, `os.statvfs("/")`. Five figures. No subprocess | `executors.py:124-131` |
| `/disk` | READ | `os.statvfs("/")` only — a projection of one `/status` line | `executors.py:134-135` |
| `/uptime` | READ | `/proc/uptime` + `/proc/loadavg` — a projection of two `/status` lines | `executors.py:138-139` |
| `/restart` | PRIVILEGED | Execs `/usr/bin/systemctl --no-ask-password restart <unit>`, exact argv, no shell, 30 s timeout. Unit checked against a target allowlist first | `executors.py:146-209` |
| `/ask` (alias `/model`) | READ | Writes one JSON object to `/run/homelab-model-helper.sock`, reads one back. `wants_user=True`, `log_args=False` | `executors.py:216-273`, `model_client.py:112-116` |
| `/help` (alias `/start`) | READ | Generated from the registry, legend derived from what is present | `executors.py:280-326` |

**Six unique executors, two aliases.** `/ask` is READ and the comment at `executors.py:341-345`
explains why: it gains no privilege on this host; what it spends is a subscription allowance, and *"a
resource limit is not an authorisation question."*

### 2.3 The allowlists — there are three, not two

ADR-027 §4 and the router docstring both speak of two. The code has three, and the third is a
different kind of thing.

| File | Loader | Empty means | Question it answers |
|---|---|---|---|
| `allowlist` | `bot.py:130-164` | **fatal — refuses to start** | May this user talk to the bot? (authentication) |
| `privileged-allowlist` | `bot.py:167-180` → `router.py:170-194` | *"nobody may escalate"* — fine | May this user invoke a PRIVILEGED executor? (authorisation) |
| `restart-allowlist` | `bot.py:183-198` | the executor can do nothing | Which **units** may `/restart` name? (target scope) |

The asymmetry between the first two is deliberate and documented in both the loader and
`privileged-allowlist.example`: *"empty-means-nobody fails safe, empty-means-everybody does not."*

**The subset rule is enforced in `bot.py:315-322`, not in `Router`.** `Router.__init__` accepts
`privileged_users` already-validated and never re-checks it. Today there is exactly one construction
site. An agent loader is a second one — see §9.

**The third allowlist has no term in ADR-027 §4's formula.** `effective tools = agent.tools ∩ caller
authorisation` has nowhere to express *"restart, but only `chrony.service`"*. A tool name is a verb;
its object set is decided in a file the vocabulary cannot see. §6.4 owns this.

### 2.4 Properties established at real cost that must survive

- `homelab-bot` cannot read either OAuth credential, and `id homelab-bot` is byte-identical to
  Phase 07 (Phase 08 and 09 handovers, both re-proved by attempt).
- The caller cannot name a provider, model, binary, file or path — *"there is no field on the wire in
  which to name a program"* (`model_client.py:12-19`).
- **The model gets no tools**, verified with a canary file against a positive control (ADR-025 §4).
- **Model output is never dispatched.** `dispatch()` has exactly one call site, `bot.py:294`, and its
  input is the Telegram message text (ADR-025 §10).
- The authorisation check happens **before** the handler runs, and its refusal is distinguishable
  from "unknown command" (`router.py:147-158`).
- `ss -tln` reports 6 listeners; `systemd-analyze security homelab-telegram-bot` reports 1.3 OK.

### 2.5 There is no test suite

`find` for any `test*` file across the repository returns nothing. Every validation this project has
performed is a shell script (`scripts/server/verify-*.sh`, `install-model-helper.sh verify`) or a
live check with captured output.

**This is load-bearing for §8.** The planted positive controls this phase requires have no harness to
live in, and inventing a framework is not in scope. §7.4 says where they go instead.

### 2.6 What Factory has

Read on 2026-09-10 at `/Users/home/Code/factory`.

| Thing | State |
|---|---|
| Agent manifests | **Zero.** No file declares ADR-027 §2's five fields |
| Role definitions | `agents/role-registry.md` — six core v0 roles, prose, with authority and boundary columns |
| Ops object templates | `templates/ops/*.yaml` — seven, including `review-record.yaml` |
| Format | Markdown and YAML, 75 files, 10,022 lines, **discarded by ADR-031 §7** |

`review-record.yaml` matters for §4: it is the concrete artifact `post_review` would write, and it
lands in a project's `ops/reviews/` per ADR-030 §2.

## 3. Learning objectives

By the end the owner should be able to explain:

1. **Why the vocabulary lives in the repository that enforces it**, and what specifically goes wrong
   if the catalogue owns its own permission names — ADR-027 §3 rejected that outright and this phase
   is where the reason becomes concrete rather than principled.
2. **Why an unknown tool name is a load failure and not a warning**, in the same terms as
   `load_ids(required=True)`: a dropped-tool warning is a message nobody reads at 3am; a load failure
   is a state that cannot be ignored.
3. **What the intersection in ADR-027 §4 actually protects against** — that an agent is not a
   privilege escalation path, and cannot do more than the human it acts for.
4. **Why a refusal path that has only ever permitted is unvalidated**, and what a *planted* positive
   control is that merely running the check is not.
5. **The difference between a tool and a skill**, by ADR-031 §2's one-sentence test — *if it can be
   refused it's homelab; if it can only be followed it's factory* — applied to a real pair.
6. **What it costs to publish a name.** Why renaming `read_repo` next year breaks every manifest that
   declares it, and why that cost is the point rather than a defect.

## 4. Functional objectives

### 4.1 The proposed vocabulary — five names

Each entry names a capability level, a status, and one line stating what it permits. Every one is
grounded in something that exists in the runtime today or in ADR-027 §2's own example manifest.
Nothing here is speculative.

| Tool | Level | Status | Permits | Grounded in |
|---|---|---|---|---|
| `read_host_status` | READ | wired | Read this host's hostname, uptime, load, memory and root-filesystem usage — the five `/status` figures, and nothing else | `executors.py:124-139` (`_status`, `_disk`, `_uptime`) |
| `ask_model` | READ | wired | Send one question plus the ADR-025 §8 bounded context to the model helper and receive text back | `executors.py:216-273`, `model_client.py` |
| `restart_service` | PRIVILEGED | wired | Request a restart of one systemd unit named in the node's restart allowlist | `executors.py:146-209` |
| `read_repo` | READ | **not wired** | Read files from a named project repository | ADR-027 §2 example manifest |
| `post_review` | PRIVILEGED | **not wired** | Write one review record into a project's `ops/reviews/` | ADR-027 §2 example manifest; ADR-030 §2; Factory `templates/ops/review-record.yaml` |

**Why each earned its place:**

- **`read_host_status`** — three executors, one tool. `/disk` and `/uptime` are projections of
  `/status` reading the same three sources; no caller has ever needed "may see disk but not memory",
  and a vocabulary entry per executor would be granularity invented for nobody. Splitting later is
  additive and cheap; merging later is a breaking rename. This also establishes the first structural
  point of the phase: **a tool is not an executor.** ADR-031 §2 already separates *"the tool
  vocabulary"* from *"the tool implementations"* as two rows of the same table.
- **`ask_model`** — the runtime can refuse it today, so by ADR-031 §2 it is a tool. It is also the
  entry that must be named carefully and granted to nobody: see §6.3.
- **`restart_service`** — the only PRIVILEGED verb that exists. Naming it is what makes the level
  real; it must appear in no manifest until ADR-027 §6's moment-of-action approval exists, which it
  does not (§5, §7.1).
- **`read_repo`** and **`post_review`** — ADR-027 §2's example manifest declares exactly these two,
  and Phase 20 cannot write a `review-qa` manifest without them. They are the only two entries not
  backed by running code, and §6.2 specifies the honest treatment: **named, loadable, and refused at
  dispatch on the reason** — a refusal the runtime actually performs, not a promise in a document.

### 4.2 The enforcement

1. **The vocabulary is the single source of truth for tool names**, and homelab is the only
   repository that may add to it.
2. **A manifest naming a tool not in the vocabulary fails to load**, on the reason, naming the
   offending token. The agent is absent from the registry afterwards — not present with the tool
   dropped.
3. **`Router.dispatch()` computes `agent.tools ∩ caller authorisation`** and remains the only place
   in the codebase permitted to decide entitlement.
4. **A tool named in the vocabulary but bound to no executor is refused at dispatch**, distinguishably
   from both "unknown command" and "not authorised".
5. **Behaviour from Telegram is byte-identical to today** when no agent is involved. This phase is
   not a user-facing change.
6. **The published reference is generated from the vocabulary**, never hand-maintained.

## 5. Decisions already fixed

Not reopened by this phase.

- **ADR-027 §3** — the vocabulary lives in homelab. Factory composes from it; a manifest is a request,
  never a grant. This phase implements it and does not relitigate it.
- **ADR-027 §5** — unknown tool name is a hard load failure.
- **ADR-027 §4** — the intersection, evaluated in `dispatch()`.
- **ADR-031 §2** — the tool/skill test. `skills:` stays a Factory field and homelab never validates it.
- **ADR-025 §4** — the model gets no tools. **Untouched.**
- **ADR-025 §8** — only the question and the five `/status` figures leave the machine. **Untouched.**
  Widening it needs its own ADR and this is not that phase.
- **ADR-025 §10** — model output is never dispatched. **Untouched.**
- **ADR-024** — the authorisation check stays in one function.
- **ADR-023** — no listening socket; long polling only.
- **ADR-006** — simplest thing that works. This phase must not acquire a framework, a schema
  validator, a plugin system or a dependency.
- **ADR-021** — the repository is public. The vocabulary is published the moment it is committed.
- **ADR-031 §11** — **agent manifests are JSON.** Settled on 2026-09-10, after this brief was first
  written; §6.5 below carries the reasoning and is no longer an open question.

### 5.1 What this phase explicitly does not open

Stated as its own list because ADR-027 §6 opens tools **one agent at a time**, and a phase that
publishes a vocabulary is the phase most likely to be misread as having opened it.

| Lock | Status after this phase |
|---|---|
| **The model gets no tools** (ADR-025 §4) | **Shut.** No tool name reaches any CLI invocation. `--tools ""`, `--strict-mcp-config`, `--sandbox read-only` unchanged. The vocabulary is homelab's list for *agents*, not a list handed to a *model* |
| **Model output is never dispatched** (ADR-025 §10) | **Shut.** `dispatch()` must still have exactly one call site at phase close — asserted, not assumed (§8 test 12) |
| **What leaves the machine** (ADR-025 §8) | **Unchanged.** No tool name, manifest, agent name or caller identity is added to the prompt |
| **Any agent actually holding a tool** (ADR-027 §6) | **Shut.** Zero manifests are granted anything in production. The vocabulary exists; nothing consumes it |
| **Destructive action without moment-of-action approval** (ADR-027 §6) | **Shut, and structurally.** That mechanism does not exist, so `restart_service` may appear in no manifest |
| **Unattended model calls** (ADR-026 §5) | **Unchanged.** The per-provider `unattended` field is Phase 15.0's; this phase neither sets nor reads it |
| **`/ask` context width** | **Unchanged.** Still the question plus five figures |
| Node privileges | **Unchanged.** No new account, group, sudoers entry, polkit rule, listener, or privileged-allowlist entry. `id homelab-bot` byte-identical |

**The first agents, when they arrive, are advisory** — they read and recommend; the human acts
(ADR-027 §6). That is Phase 20's business, not this one's.

## 6. Decisions still open

Resolvable locally unless marked. Cross-phase outcomes become ADRs and are carried forward (ADR-017).

**§6.5 is no longer one of them** — the manifest format was decided on 2026-09-10 in ADR-031 §11,
after this brief was committed. It is kept in place, marked decided, rather than deleted.

### 6.1 Where the vocabulary lives as an artifact

Three candidates:

| Option | For | Against |
|---|---|---|
| **A. A Python module** in `services/telegram-bot/` | One artifact, no parse step, no runtime failure mode, version-controlled with the code that enforces it | Not directly readable by Factory, which is a different repository |
| **B. A data file** on the node | Editable without a deploy | **Editable without a deploy.** A vocabulary the deployment can widen independently of the code enforcing it is the "catalogue grants itself privileges" shape ADR-027 §3 rejected, in miniature. Adds a parse failure mode for zero gain |
| **C. Module + a generated reference document** | Source of truth stays with the enforcer; the public interface is publishable and cannot drift | Needs a generator and a check that it was run |

**Recommendation: C**, and the reason is already in this codebase. `/help` is generated from the
registry, with the reason stated at `executors.py:280-286`: *"Hand-maintained help text is how an
undocumented command survives."* A hand-maintained vocabulary document is the same defect with a
larger blast radius, because the reader is in another repository.

So: **one Python module is the source of truth**, and `docs/reference/tool-vocabulary.md` is
**generated** from it, with a check that regenerating produces no diff.

Explicitly rejected: a package, an entry-point registry, or anything that lets a tool register itself.
Self-registration is how a vocabulary stops being a vocabulary.

### 6.2 The `UNAVAILABLE` conflation — and what to do about the two unwired tools

`Capability` today mixes two different facts: **what privilege a thing requires** (`READ`,
`PRIVILEGED`) and **whether it is wired** (`UNAVAILABLE`). That conflation was harmless while
`UNAVAILABLE` described one deliberately-inert executor. It is not harmless in a published interface:

> If `read_repo` is published at level `UNAVAILABLE` and later becomes `READ`, every manifest that
> reasoned about its level sees a silent semantic change. A tool's capability level must not change
> because it got implemented.

**Recommendation: split the two.** A vocabulary entry carries a **level** (`READ` or `PRIVILEGED` —
what it would require) *and* a **status** (wired / not wired — whether anything is bound). `read_repo`
is published as `READ`, not wired. `post_review` is published as `PRIVILEGED`, not wired. Wiring them
later changes the status and not the contract.

`Capability.UNAVAILABLE` then has no remaining use. Whether to remove it, keep it for executors, or
fold it into the new status is a local decision — but it must be *decided*, not left as a level with
zero members and now a second meaning nearby.

**This is the most likely ADR out of this phase** (§13).

### 6.3 Whether `ask_model` may ever be declared by a manifest

Naming it is right: `/ask` is refusable, so by ADR-031 §2 it is a tool, and leaving it unnamed makes
it undeclarable rather than unreachable.

**Granting it is a different question and this phase should not answer it.** An agent holding
`ask_model` receives model text and then decides what to do next. That is model output influencing an
agent's subsequent tool selection — not the same as ADR-025 §10's dispatch of model output, but
adjacent to it, and the adjacency deserves a decision rather than an assumption.

**Recommendation:** name it; grant it to nobody; record that the first manifest declaring it needs
this question answered first, in writing, before that manifest loads.

### 6.4 How a tool's target scope is expressed

`restart_service` names a verb. The unit it may name is decided by `restart-allowlist` (§2.3), which
the vocabulary cannot see and ADR-027 §4's formula has no term for.

Options: leave scope entirely outside the vocabulary (status quo — the tool name means "the verb",
the node decides the objects); or let a manifest declare a scoped form and intersect that too.

**Recommendation: leave it outside, and say so in the published reference**, because the current
arrangement fails closed — a manifest cannot widen a target set it cannot name. Revisit when a real
agent needs a narrower grant than the node's own allowlist gives.

### 6.5 Manifest format — **decided: JSON** (ADR-031 §11, 2026-09-10)

**This was the sharpest open question in the phase. It is no longer open.** It is kept here rather
than moved, so the reasoning stays next to the phase that consumes it; the decision itself is
recorded in **ADR-031 §11**.

**Agent manifests are JSON.** ADR-027 §2 illustrates a manifest in YAML, but it decided *five
fields*, not a serialisation — so this is a decision the ADR left to be made, not a contradiction of
it. ADR-027 itself is **not edited**: it is accepted and merged, and `docs/decisions/README.md`
forbids rewriting an accepted ADR.

The options as they were weighed:

| Option | Cost |
|---|---|
| **Manifests are JSON** — **chosen** | Contradicts the ADR's illustration but not its decision. Zero new dependency, and JSON is what the models handle natively — the owner's stated reason and the deciding one |
| Take a YAML dependency | Breaks a constraint held since Phase 07, for a format preference. A supply-chain risk and an upgrade obligation in the one service that talks to the internet |
| Write a bounded YAML subset parser | A hand-rolled parser for untrusted-ish input, in the process that enforces authorisation. Worse than either |

The bot's second design constraint (`bot.py:21-26`) is **no third-party dependencies**, and Python's
standard library ships `json` and no YAML parser — so JSON is also the only option that keeps the
constraint without hand-rolling a parser into the process that enforces authorisation.

If YAML is ever required for Factory-side ergonomics, the conversion belongs on the **Factory** side,
where the dependency is cheap and enforces nothing.

**Consequence for this phase:** §8.1's fixtures are JSON files, and §16 item 2 hands Phase 20 a
working JSON example and a failing one.

### 6.6 What a caller is, when the caller is not a Telegram user

Today `user_id` is a Telegram numeric id (`bot.py:271`, `router.py:132`), and both allowlists are
files of numeric ids. ADR-027 §4 requires an agent to be intersected with *"what this caller is
authorised for"* — which presupposes the agent acts **on behalf of** an identified human.

Open: how the on-behalf-of relationship is carried and logged. Note the journal line format today is
`user {id}: {executor.name} {args}` (`router.py:160-163`) and has no field for an agent.

**Recommendation:** keep the caller a Telegram id in this phase — every real caller still is one —
and make the agent an *additional* term rather than a replacement. Extend the journal line so an
agent-mediated invocation names the agent, the tool and the human. Do not invent a second identity
namespace; ADR-027's Consequences already foreclose "service agents with their own elevated identity".

### 6.7 Where the subset invariant is enforced

`bot.py:315-322` enforces "privileged ⊆ allowlisted" at startup, before `Router` is constructed. An
agent loader is a second construction path.

**Recommendation:** move or re-assert the invariant so it holds for every `Router`, not for the one
that `main()` happens to build. This is small and it is the kind of thing that is only small before
there are two callers.

## 7. Implementation scope

Expected shape, not exact commands.

1. **The vocabulary module** — the five entries of §4.1, each with name, level, status, and the
   one-line statement of what it permits. Frozen, no self-registration.
2. **Bind tools to executors.** `Executor` gains an optional tool field, **additive with a default**,
   so no existing executor changes — the Phase 09 precedent, recorded rather than smuggled in through
   module-level state (`router.py:64-68`; ADR-027 Consequences).
3. **Manifest loading**, with ADR-027 §5's refusal: unknown name → the agent does not load, on the
   reason. Exact-match, case-sensitive, no normalisation (§9).
4. **The intersection in `dispatch()`** — one place, alongside the existing `if`, not a second
   function that "helps" decide.
5. **The unwired refusal** — `read_repo` and `post_review` refused distinguishably at dispatch.
6. **The generator** for `docs/reference/tool-vocabulary.md`, plus a no-diff check.
7. **The fixtures and the positive controls** (§8), and the harness question resolved per §7.4.

### 7.1 Not in scope — and specifically, the names deliberately not invented

Refused because nothing can refuse them yet, or because the deciding phase has not run:

| Not named | Why not |
|---|---|
| `search_knowledge`, `retrieve_context` | Phase 10 has not run. The roadmap says specifying how an agent queries the knowledge base before retrieval exists **is guessing**, and reserves the Knowledge Contract ADR for that phase |
| `create_ticket`, `update_ticket`, `approve_release` | Factory's nouns, and ADR-031 §7 is discarding the format that defines them. Phase 20 decides what a ticket is |
| `write_file`, `run_command`, `git_commit`, `send_message` | No executor, no grant, no caller. Each is a large security decision wearing a small name |
| A `WRITE` level between READ and PRIVILEGED | A level invented for a hypothetical. See §9 for why two levels are sufficient *and* honest today |

Also out of scope: any manifest granted a tool in production; the moment-of-action approval mechanism
(ADR-027 §6 defers it, and it *"needs a real destructive action to design against"*); widening
ADR-025 §8; conversation memory; anything in Phase 15.0 or Phase 20.

### 7.2 The Factory side

**None of it.** Factory writes no manifest in this phase. ADR-031 §7 says nothing is to be written
into the current format, and the rewrite is Phase 20.

The only Factory-facing deliverable is the generated reference document, which is homelab's.

### 7.3 Node deployment

The bot is redeployed from committed files with SHA256 verified, as in Phase 08 and 09, and
`systemd-analyze verify` is run on every changed unit.

### 7.4 Where the tests live, given §2.5

There is no test harness and this phase must not invent one. Two acceptable homes, to be chosen in
phase:

- extend `scripts/server/verify-telegram-bot.sh`, which already attempts forbidden accesses rather
  than reading directives; or
- a `verify` subcommand on the install script, the shape `install-model-helper.sh verify` established
  and which the Phase 09 handover tells the reader to trust over the document.

Whichever is chosen must, per the project's standing rule, **report `UNKNOWN` rather than a
plausible-looking result** when it cannot determine an answer.

## 8. Validation / tests

> **An authorisation check that has only ever permitted is unvalidated** (ADR-027, ROADMAP §Phase 19).
> The project has recorded **nine** instances of checks reporting results they could not support
> (ADR-026), and a tenth in `18-foundations.md` §9.1. This phase's central control is a check that
> will permit every real call, so it is the exact shape that produces a tenth.

### 8.1 The planted positive control, specified

ADR-027 §5's refusal is the one that has never fired. It gets a **planted** fixture pair, not an
observation:

| | Fixture | Must show |
|---|---|---|
| **Negative** | A JSON manifest whose `tools` array is `["read_repo", "definitely_not_a_tool"]` | **Load fails**, on the reason, **naming the offending token**. The agent is **absent** from the registry afterwards |
| **Positive control** | The **byte-identical** manifest with only the unknown token removed | **Loads.** All five ADR-027 §2 fields present |

The two fixtures must differ in exactly one token. Without the positive control, a load failure caused
by a malformed fixture is indistinguishable from a load failure caused by the check working — which
is precisely the mistake made on 2026-09-10, where a test token with a 34-character segment instead of
35 produced *"a confident negative that looks exactly like a finding"*.

**Fixture discipline, mandatory:** assert the fixture's *shape* before asserting on the outcome —
that it parses, and that it yields the five declared fields. **A positive control validates the
detector; nothing validates the fixture but this.**

Three planted variants, each cheap and each closing a real hole:

| Variant | Must show |
|---|---|
| `"Read_Repo"` (case changed) | **Load fails.** Tool names are exact-match; `parse()` and `register()` lowercase *commands* (`router.py:99,129`) and tool names must not inherit that |
| `" read_repo "` (whitespace) | **Load fails.** No trimming. A normaliser is a second place that decides what a name means |
| `"tools": []` | **Loads, with no tools.** The default is "no tools", never "all tools" |

### 8.2 The full list

| # | Test | Must show |
|---|---|---|
| 1 | Unknown tool name in a manifest | **Load fails**, on the reason (§8.1 negative) |
| 2 | Same manifest, token removed | **Loads** — the positive control for 1 |
| 3 | Case and whitespace variants | **Load fails**, both |
| 4 | Agent declaring `[read_host_status]` invokes `restart_service` | **Refused**, on the reason: outside the declared set (ADR-027 validation 2) |
| 5 | Agent declaring `[restart_service]`, caller **not** in the privileged allowlist | **Refused**, and the refusal names *caller authorisation*, not the declaration (ADR-027 validation 3) |
| 6 | Same agent, same declaration, caller **in** the privileged allowlist | **Permitted** — the positive control for 5 |
| 7 | Agent with `"tools": []` | The Phase 09 canary check still passes; default remains "no tools" (ADR-027 validation 4) |
| 8 | Agent with `[read_host_status]` | Gets **exactly** that one, and not the other four |
| 9 | `read_repo` dispatched | **Refused as not wired**, distinguishably from "unknown command" and from "not authorised" |
| 10 | Vocabulary entry with no bound executor, and executor with no bound tool | Both detected at load, neither silently tolerated |
| 11 | `/status`, `/disk`, `/uptime`, `/ask`, `/restart`, `/help` from Telegram | **Byte-identical** to phase start, live output captured |
| 12 | `dispatch()` call sites | **Exactly one** (`bot.py:294`). ADR-025 §10 |
| 13 | Regenerate `docs/reference/tool-vocabulary.md` | **No diff** |
| 14 | `id homelab-bot` | **Byte-identical** |
| 15 | `ss -tln` | Still **6** |
| 16 | `systemd-analyze security homelab-telegram-bot` | Still **1.3 OK** |
| 17 | `systemctl is-system-running` | `running`, zero failed units — checked **last** |

Tests 4 and 5 are different refusals for different reasons and **must not collapse into one message**.
Phase 09 established that collapsing distinct failures costs an evening.

### 8.3 The check that this phase is honest

Test 12 and test 11 together are what prove ADR-025's two locks survived. They are not
box-ticking: this is the first phase that introduces the *concept* of an agent acting through
`dispatch()`, which is exactly where a second call site would appear.

## 9. Security considerations

- **`dispatch()` must remain the only place that decides entitlement.** The vocabulary supplies *data
  about* entitlement — a level and a status. It must not grow a `may_i(user, tool)` helper, because a
  helper is a second decision site regardless of where it is called from. The intersection is
  computed inline, next to the existing `if`.
- **Load-time refusal is not a dispatch decision.** Validating manifest names against the vocabulary
  at load time is the `load_ids(required=True)` pattern, not an authorisation check, and it does not
  move the boundary. Keeping that distinction clear in the code comments is part of the deliverable —
  ADR-027 §5 draws the parallel itself.
- **No name normalisation, anywhere.** Exact-match, case-sensitive. `register()` lowercases command
  keys and `parse()` lowercases the incoming command (`router.py:99,129`); tool names must not inherit
  that. Every normalisation is a second place where a name's meaning is decided, and this project has
  a rule about second places.
- **Two capability levels are sufficient and the coarseness is honest.** `post_review` is PRIVILEGED
  because it writes; that means only a caller already in the privileged allowlist can ever exercise
  it — the same caller who can already `/restart chrony`. That is coarse, and it **over**-restricts
  rather than under-restricts, so it fails closed. Recorded as an accepted coarseness with an explicit
  revisit trigger: *a caller who legitimately needs `post_review` but must not have `restart_service`*.
  Inventing a third level before that caller exists is inventing a level for nobody.
- **An agent is not a privilege escalation path.** The intersection is what enforces it, and test 5 is
  what proves it. Note the direction: ADR-027's Consequences forecloses *"service agents with their own
  elevated identity"* deliberately.
- **The vocabulary is published the moment it is committed** (ADR-021). A tool name is a statement
  about what this machine can be asked to do. Nothing in it may name a unit, a path, a credential, an
  account or a host detail.
- **The subset invariant must hold for every `Router`**, not just `main()`'s (§6.7). Adding a second
  construction path is precisely how a startup-time guarantee becomes a per-deployment accident.
- **Manifests are input.** Whatever format §6.5 settles on, a manifest is a file this process parses
  and acts on. It must not be able to crash the bot — `bot.py:293-298` guards a *failing handler*, not
  a failing load. A malformed manifest at startup should be a clean refusal to start, in the shape of
  `load_allowlist()`'s: a state someone notices.
- **No new listener, account, group, sudoers entry or polkit rule.** If any appears, something is
  wrong.

## 10. Repository changes expected

- `docs/handovers/19-tool-vocabulary.md` — this brief.
- `docs/handovers/19-tool-vocabulary-handover.md` — the handover.
- `services/telegram-bot/` — the vocabulary module; additive changes to `router.py` and
  `executors.py`; manifest loading.
- `docs/reference/tool-vocabulary.md` — **generated**, the published interface.
- Fixtures for §8.1, committed, including the deliberately-invalid one.
- `scripts/server/verify-telegram-bot.sh` or the install script's `verify` — extended per §7.4.
- `guide/19-tool-vocabulary/README.md`.
- `docs/architecture/current-architecture.md`, `docs/reference/project-state.md`, `ROADMAP.md`,
  `CHANGELOG.md`.

## 11. Guide documentation required

`guide/19-tool-vocabulary/README.md`, to the standard in `PROJECT.md` §7 — the alternatives and the
reasoning, not only what worked. It should cover: what a capability vocabulary is and why it lives
with the enforcer; why an unknown name is a load failure; what the intersection protects against;
how the refusal was proved with a planted control and why the positive control is the half that
makes it evidence; and what it costs to publish a name that another repository will write down.

## 12. Project documentation required

- `project-state.md` — the vocabulary, its five entries, and that the refusal path **exists and has
  been proved** rather than being a decision on paper.
- `current-architecture.md` — `Interface → Router → Executor` gains a tool term. The diagram should
  show that the vocabulary is read by `dispatch()` and by nothing else.
- The ADR-027 entry updated to record which of its four validation items are now satisfied, and
  which are not — items 2, 3 and 4 are reachable in this phase; item 1 is the one this phase exists
  for.

## 13. ADRs required / possible

- **Likely required:** the level/status split of §6.2. It changes the meaning of a published field
  and it supersedes part of ADR-024's capability model.
- **No longer needed:** the manifest serialisation of §6.5. Decided in **ADR-031 §11** on
  2026-09-10 — JSON — so this phase inherits it rather than producing it.
- **Possible:** the caller/agent identity relationship of §6.6, if it turns out to need more than an
  extra journal field.
- **Not expected:** anything reopening ADR-025 §4, §8 or §10. If this phase finds itself drafting one,
  it has left its scope.

## 14. Costs

**None, and explicitly zero.** No new service, no new dependency, no metered provider, no additional
model call — the vocabulary is enforced locally in a process that already runs. The validation runs
against fixtures, not against a provider, so it spends no subscription allowance.

If an implementation step wants to spend a model call to test `ask_model`, note that the allowance is
shared with the owner's own work (Phase 09 handover §4) and the existing `/ask` path already proves
that route.

## 15. Definition of Done

`PROJECT.md` §12 applied literally, item by item, plus:

- [ ] The vocabulary exists as one artifact, and the published reference is **generated** from it with
      a no-diff check.
- [ ] **An unknown tool name fails to load, proved against a planted positive control** (tests 1–3).
- [ ] A tool outside an agent's declared set is refused, on the reason (test 4).
- [ ] A non-privileged caller cannot reach a PRIVILEGED tool even when the agent declares it, proved
      against a positive control (tests 5–6).
- [ ] An agent with no declared tools still passes the Phase 09 canary check (test 7).
- [ ] A named-but-unwired tool is refused distinguishably (test 9).
- [ ] `dispatch()` has exactly one call site (test 12).
- [ ] Telegram behaviour byte-identical, with captured live output (test 11).
- [ ] `id homelab-bot` byte-identical; `ss -tln` still 6; bot still 1.3 OK.
- [ ] `systemd-analyze verify` clean on every changed unit.
- [ ] **Zero manifests hold a tool in production**, and the handover says so plainly.
- [ ] Every rejected tool name from §7.1 is recorded with its reason, so the next phase does not
      rediscover it as a good idea.

## 16. Return handover requirements

Addressed to **Phase 20 — Factory Rewrite**, which cannot start without this. It must state:

1. **The exact vocabulary**, name by name, with level, status and permitted action — in the form a
   manifest author copies. This is the deliverable Phase 20 consumes; if it is not written here it is
   lost (ADR-017).
2. **The exact manifest format — JSON** (ADR-031 §11), with a working example that loads and one that
   does not — because Phase 20's first act is writing a `tools` line.
3. **How the refusal was proved, including the fixtures**, so the next phase can extend rather than
   re-derive them.
4. **Which of ADR-027's four validation items are satisfied and which are not**, item by item. An
   unsatisfied item stated is a control; an unsatisfied item omitted is a claim.
5. **That `restart_service` and `ask_model` are named but grantable to nobody**, and precisely what
   must exist first — moment-of-action approval for the former (ADR-027 §6), and the §6.3 decision
   for the latter. This must not be silently inherited as "available".
6. **What `read_repo` and `post_review` do when dispatched today** — refuse, on the reason — so
   Phase 20 does not write a manifest expecting them to work.
7. **The target-scope gap** (§6.4): a tool name is a verb and its object set lives in a file the
   vocabulary cannot see.
8. **The Phase 15.0 dependency** (§0.4): `ask_model` cannot carry ADR-027 §2's `model_policy` until
   the helper's wire protocol has a task class.
9. **What renaming a tool now costs**, stated once and plainly, so the first rename is a decision
   rather than a refactor.
