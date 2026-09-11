# Phase 23 Brief — Homelab AI Foundation

- **Phase:** 23 — Homelab AI Foundation
- **Written:** 2026-09-11
- **Status:** Brief, committed before implementation per ADR-017
- **Implements:** ADR-034 §5, §11, §13; ADR-033 §5; ADR-035 §4 (the backend half)
- **Inherits from:** [Phase 20.0 handover](20.0-minimal-factory-workbench-handover.md)

> ## ⚠️ Superseded in part, 2026-09-11 — do not implement from §0 as written
>
> This brief was committed before **ADR-037 – ADR-044** were accepted, and its framing is now wrong in
> two places:
>
> - **§0.1's two gates are resolved.** ADR-037 puts knowledge and project content in an encrypted
>   volume on the server; ADR-038 places every component there and binds the harness to loopback;
>   ADR-039 replaces ADR-025 §8's enumeration with a policy classified by whose data it is.
> - **§0.2's checkpoint decision is already taken.** *Where the harness runs* is answered: on the
>   server. The three options it tables are no longer open.
>
> **§0.3 (no paid call before the spend governor) and §0.4 (this phase changes ADR-025 §10) still
> stand**, as do §4's objectives, §8's validation and §16's handover requirements.
>
> The brief is also **too large** — it spans five architecture layers plus the governor, and the
> roadmap reshape is expected to split it. It is preserved as written rather than edited, per
> ADR-017; a fresh brief is owed before implementation.

## 0. Governance note

### 0.1 Two accepted gates stand between this phase and its own core capability

**Read this before planning anything.** The harness's central job is **context assembly** — deciding
what a model should see. Two accepted ADRs constrain that, and they are *different* constraints that
are easy to conflate:

| Gate | Says | Consequence here |
|---|---|---|
| **ADR-032 §2** | The node must not hold any project repository, product source, or `ops/` record, in any form including a derived index or embedding | A harness running **on the node** has nothing to assemble context *from* |
| **ADR-025 §8** | Only the question and the five `/status` figures may leave the machine. *"Widening this requires its own ADR"* | Assembled context **leaving** is exactly that widening |

ADR-033 §6 already named the second one: *"A gateway carrying assembled context is a substantial
widening, and §8 requires its own ADR for that. **It is the immediate next decision.**"*

Neither gate blocks this phase. Both shape where it can run and what it may send, and **guessing
either would be applying a cross-phase change silently**, which ADR-017 forbids.

### 0.2 The first decision, taken at a checkpoint before implementation

Phase 20.0 resolved its §6.1 at a checkpoint before any code was written, and that worked — it
surfaced a parser problem that would otherwise have been designed around. **Do the same here.**

The question: **where does the harness run, and what may leave the machine?**

| Option | Consequence |
|---|---|
| **On the MacBook**, like Workbench | The content is already there, so ADR-032 is not engaged. The node stays a service host. Splits homelab across two machines |
| **On the node**, public content only | Keeps homelab on its own hardware; cannot touch any project or knowledge content until encryption is revisited (Phase 13/14, owner-gated) |
| **On the node**, after encryption | Clean, and it waits on the only track that requires the owner at a keyboard |

This is a recommendation to be *made and justified in the phase*, not assumed here. It probably
produces two ADRs: one for placement, one for the ADR-025 §8 egress widening.

### 0.3 No paid call before the spend governor

**ADR-033 §5 is a precondition, not an improvement.** It does not exist. Until it does, this phase
makes no metered call — and since the phase's whole point is model access, the governor is
plausibly its *first* deliverable rather than a late one.

### 0.4 This phase changes a security lock

**ADR-034 §13 takes effect here and nowhere earlier.** ADR-025 §10's *"the model's output is never an
instruction"* — proved in Phase 09 by making a model emit `/restart ssh.service` to no effect —
becomes *checked by the runtime* rather than *inert by architecture*. That is the single largest
security change on this roadmap. Until this phase ships it, §10 stands as written and the Phase 09
canary check applies.

## 1. Purpose

> **Homelab is an AI execution harness.** It performs the context selection, task decomposition,
> retrieval decisions, per-call model selection and controlled execution that a tool such as Codex or
> Claude Code normally performs *internally*.

That sentence, from the Phase 19 design review, is the measure of what belongs here. When Claude Code
decides which files to read, whether to search the repository for a sub-question, how to break a
request into steps, and which model serves each one — those decisions are homelab's.

This phase builds the parts of that which have no other home.

## 2. Starting state

**To be re-verified at phase start**; this is what was true on 2026-09-11.

| What | State |
|---|---|
| `services/model-helper/` | 714 lines. A two-provider router with per-provider limits and fallback, proved against a genuinely exhausted provider |
| `services/telegram-bot/` | Router/executor, two allowlists, one privileged action |
| Spend governor | **Does not exist** (ADR-033 §5) |
| Model registry as configuration | **Does not exist** — Phase 15.0 is briefed, not built |
| Task decomposition, context assembly, runtime approvals | **Do not exist** |
| Factory Workbench | **Exists and runs** (Phase 20.0), and is the first real consumer |
| Real execution adapter | **None.** Only the deterministic fake |
| Agents that have executed anything | **Zero** |

## 3. Learning objectives

By the end the owner should be able to explain:

- why context assembly is a security decision and not only an engineering one;
- what the spend governor refuses, and how to prove it refuses rather than trusting it;
- why cache economics are engineered rather than inherited (§7.4);
- what changed about ADR-025 §10, precisely, and what did **not** change;
- how a model's proposed tool use reaches the runtime without the model being able to dispatch it.

## 4. Functional objectives

1. **Spend governor** — four windows (hour, day, week, month), separate attended and unattended
   budgets, checked **before** the call, persisted across restart, **failing closed**.
2. **Model registry as configuration**, with `unattended` eligibility enforced structurally
   (Phase 15.0's scope; build it here if 15.0 has not run).
3. **Deterministic routing** from agent role + bounded task summary + validated metadata. The
   AI-assisted router is the *target*, not this phase's completion criterion, and deterministic
   routing remains the fallback.
4. **Task decomposition** — break a request into steps that can be individually executed and checked.
5. **Context assembly**, with a stable-prefix discipline (§7.4).
6. **Runtime approvals, budgets and audit** as machinery the harness enforces, not as records a
   surface happens to write.
7. **A real execution adapter**, implementing the interface Phase 20.0 defined — which is what
   finally proves or disproves it (§5.1).

## 5. Decisions already fixed

- **ADR-033 §5** — the spend governor's shape. Numeric ceilings are configuration and belong here.
- **ADR-034 §5** — agents never name a model. The router receives role, bounded summary, validated
  metadata. **Priority, severity and complexity are hints, never selectors**, and cannot reach a
  tier or bypass the pre-call budget check.
- **ADR-034 §11** — execution identity is attached by the runtime, never claimed by the model. The
  instruction hierarchy is fixed; retrieved context is **untrusted data**.
- **ADR-034 §13** — a model's tool request is a *structured request to the runtime*, checked before
  any action. No raw provider CLI gets ambient filesystem, shell, credential or OS tools.
- **ADR-026 §4** — the agent's role is its declaration of need.
- **ADR-032 §2** — the content gate. Not reopened here.
- **ADR-020** — the node has no console; classify every change touching network, boot, auth or the
  admin account before making it.

### 5.1 The inherited risk this phase resolves

Phase 20.0's handover §1 states plainly that **the adapter interface is unproved** — one
implementation, the deterministic fake. ADR-036's second-adapter check requires the same project to
run on a second adapter without its records changing.

**This phase builds that second adapter.** Running that check is therefore a first-class deliverable,
not a courtesy to the previous phase. If the interface leaks backend-specific concepts, this is when
it is discovered, and the correct response is to change the interface rather than to work around it.

## 6. Decisions still open

1. **§0.2 — where the harness runs and what may leave.** Decide first, at a checkpoint.
2. **Which real adapter first.** Deliberately open (ADR-035 §4).
3. **Whether the Brain specialist queries retrieval itself or delegates** — unresolved by the design
   review; do not invent an answer.
4. **The numeric spend ceilings.** Configuration, decided here.
5. **Whether decomposition is deterministic, model-assisted, or both.** The routing precedent —
   start deterministic, keep it as fallback — is a strong prior but not a decision.
6. **Approval expiry default.** Phase 20.0 used 7 days as a placeholder; it is still a placeholder.

## 7. Implementation scope

1. **Decide §0.2 and record it.** Everything downstream depends on it.
2. **The spend governor, first.** Nothing metered happens before it, so building it late means
   building everything else against a fake.
3. **Model registry and deterministic routing.**
4. **Context assembly**, with its egress boundary decided rather than assumed.
5. **Task decomposition.**
6. **Runtime approvals, budgets and audit.**
7. **The first real adapter**, plus ADR-036's second-adapter check against Workbench's fake.
8. **The ADR-034 §13 transition**, with the Phase 09 canary re-run to show what changed and what
   did not.

### 7.4 Cache economics are engineered, not inherited

The favourable cache numbers observed in the owner's measured week are a property of *those
harnesses'* stable-prefix discipline, not of the models they call. A homelab harness earns them only
by designing for them deliberately — a stable prefix, ordered so that the volatile part is last.

Recorded here because it is the assumption most likely to be made silently and found false late,
after the cost model has already been built on it.

**Out of scope:** concrete homelab tools and their mappings (Phase 19, which follows the capability
gaps this phase observes); Factory catalogue migration (Phase 20); the administration dashboard
(Phase 22); knowledge ingestion and retrieval (Phase 10, still behind ADR-032).

## 8. Validation / tests

Every refusal proved by attempt against a **planted positive control**.

1. **The governor refuses at each of the four windows**, separately — and the control passes at each.
2. **Attended and unattended budgets are independent**: exhausting unattended leaves attended
   working. Without this the split is decorative.
3. **The governor fails closed**: make the counter unreadable, and the call is **refused, not
   estimated**.
4. **The governor is checked before the call**, so a refusal costs nothing — provable from provider
   telemetry showing no request.
5. **Persistence across restart**: spend recorded, service restarted, ceiling still enforced.
6. **An agent asserting high complexity does not reach a more expensive model** (ADR-034 §5).
7. **Nothing outside the decided egress boundary leaves** — proved by inspecting what is actually
   sent, not by reading the code that assembles it.
8. **ADR-036's second-adapter check** (§5.1).
9. **The Phase 09 canary, re-run**, showing precisely what ADR-034 §13 changed and what it did not.
10. **A model emitting a tool-shaped string still cannot dispatch it** — the Phase 09 test, in the
    new architecture. The mechanism changes; the outcome must not.

## 9. Security considerations

**This is the most security-sensitive phase since Phase 09**, for three independent reasons: it opens
metered spending, it widens what leaves the machine, and it changes ADR-025 §10.

- The spend governor is the only thing between autonomous work and an unbounded bill. **Fail closed.**
- Context assembly decides what leaves. Retrieved content is **untrusted data**: text does not become
  an instruction because it uses imperative language.
- `homelab-bot` receives neither AI credential. Unchanged.
- No raw provider process gets ambient host tools. Unchanged.
- ADR-020 applies to anything touching network, boot, authentication or the admin account.
- No secret in git, `ops/`, prompts, logs or browser storage.

## 10. Repository changes expected

New service or services under `services/`, configuration under `config/`, tests, and — depending on
§0.2 — possibly a component that does not run on the node at all. Plus this repository's usual
documentation set.

## 11. Guide documentation required

`guide/23-homelab-ai-foundation/` — what a harness is and why homelab is one; how to read and change
the spend ceilings; what leaves the machine and how to check; and an honest account of the ADR-025
§10 change written so the owner can decide whether they still agree with it.

## 12. Project documentation required

`ROADMAP.md`, `docs/reference/project-state.md`, tested versions, and **costs** — this is the first
phase that can spend money, so `docs/reference/costs.md` becomes load-bearing rather than nominal.

## 13. ADRs required / possible

- **Required:** the ADR-025 §8 egress widening (ADR-033 §6 names it as the immediate next decision).
- **Likely:** harness placement, if §0.2 lands off the node.
- **Possible:** the adapter interface, if §5.1's check shows it leaks.
- **Possible:** decomposition strategy, if it turns out to be architectural rather than local.

## 14. Costs

**The first phase with a real cost.** ADR-033 settled the provider (Vercel AI Gateway). Ceilings are
set here. Record **actual** spend, not projected, and record tokens only when the provider reports
them — unknown stays unknown.

## 15. Definition of Done

`PROJECT.md` §12, applied literally, with particular attention to: *actual costs recorded* (now
non-zero), *problems and reversals recorded*, and *the system reports no failed units* — which for
this phase means checking the node rather than inferring it.

## 16. Return handover requirements

1. **Whether ADR-036's second-adapter check passed**, and what it revealed about the interface.
2. **The §0.2 decision and what it gave up.**
3. **Every governor refusal and its positive control**, item by item.
4. **What actually leaves the machine**, described concretely enough to audit.
5. **What ADR-034 §13 changed in practice**, and the re-run canary result.
6. **The capability gaps observed** — this is Phase 19's actual input and the reason its dependency
   was inverted.
7. **Actual spend**, with unknown-cost calls counted rather than estimated.
8. **What was left undone**, named rather than omitted.
