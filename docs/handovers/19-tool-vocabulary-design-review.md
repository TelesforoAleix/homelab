# Phase 19 — design review before implementation

- **Written:** 2026-09-11
- **For:** a new chat picking up Phase 19
- **Status:** working document, not a phase artifact. Spent once the review concludes.

## What you are being asked to do — and not do

**Do not implement Phase 19 yet.**

The brief at [`19-tool-vocabulary.md`](19-tool-vocabulary.md) is committed and was written to ADR-017's
rule that a brief precedes implementation. It has not been challenged by anyone other than its
author. The owner wants it challenged first.

Your job is to **read the design, understand why it is shaped the way it is, and then argue with
it.** Raise questions and concerns. Say what you think is wrong, what is under-specified, and what
is being decided too early or too late. Only once the owner has responded to those is the design
considered settled and implementation begins.

A review that returns "this looks good" without having tried to break it is worth nothing here. This
project has recorded thirteen separate occasions where a check reported a result it could not
support; the standing rule is that **a detector which has only ever reported "clean" is
unvalidated**, and that applies to design reviews too.

## Read these, in this order

1. `AGENTS.md`, `PROJECT.md` — the operating rules. §12's Definition of Done is applied literally.
2. `docs/handovers/19-tool-vocabulary.md` — **the design under review.**
3. `docs/decisions/ADR-027-agent-contract.md` — **the whole thing.** It is the specification Phase 19
   serves, and most of the design follows from it.
4. `docs/decisions/ADR-031-layer-boundaries-and-standalone-repositories.md` §1, §2, §11 — the layer
   seam, written *after* ADR-027 and reframing it.
5. `docs/decisions/ADR-025-subscription-backed-model-access.md` §1, §8, §10 — two locks this phase
   must not open.
6. `docs/decisions/ADR-026-multi-provider-model-access.md` and `docs/handovers/15.0-model-registry.md`
   — the soft dependency.
7. The live runtime: `services/telegram-bot/router.py`, `executors.py`, `bot.py`, and the three
   `*-allowlist.example` files. **Read the code, not just the docs about the code.**
8. `ROADMAP.md` Phases 19–22 and the Sequencing note at the end.

## Where this sits, in one paragraph

The system has four layers. **Homelab** (this repo, public) is the AI OS: routing, execution,
interfaces, the node. **Factory** (public) is the operating model: agents, roles, skills, workflows.
**Projects** (private, one repo each) hold products and their `ops/` records. **Brain** (private)
holds knowledge. The rule that binds them, from ADR-031 §1: **Factory declares, homelab enforces,
projects accumulate, brain supplies.** Factory is fully operational *as a specification* and never
executes anything.

Phase 19 publishes homelab's **named tool vocabulary and its capability levels**, so a Factory agent
manifest has something real to compose against. ADR-027 §5 makes an unknown tool name a *hard load
failure*, so a manifest written before the vocabulary exists either names tools that cannot load or
invents a vocabulary in the wrong repository. **Phase 20 (the Factory rewrite) and, through it, Phase
22 (the dashboard) both wait on this.** It is the only item on the architecture critical path.

## What the brief proposes

A five-name vocabulary. Three are wired today; two are published **unwired but loadable, and refused
at dispatch with a reason** — a refusal the runtime performs rather than a promise in a document.

| Tool | Level | Wired |
|---|---|---|
| `read_host_status` | READ | yes |
| `ask_model` | READ | yes, granted to nobody |
| `restart_service` | PRIVILEGED | yes |
| `read_repo` | READ | **no** |
| `post_review` | PRIVILEGED | **no** |

It explicitly declines to invent `search_knowledge`, `create_ticket`, `write_file`, `run_command`,
`git_commit`, or a `WRITE` level for nobody. Manifests are JSON, not the YAML ADR-027 §2
illustrates, because the bot has a zero-third-party-dependency constraint and the stdlib ships
`json` and no YAML parser (ADR-031 §11).

## Seeds for the review — find your own too

These are known soft spots, offered so you do not spend the review rediscovering them. **They are a
floor, not a ceiling.**

1. **Is "published but unwired" a good idea, or a confusing third state?** `read_repo` and
   `post_review` would load successfully and then be refused at dispatch. That is defensible — the
   refusal is real and observable. It also means "the manifest loaded" stops implying "the agent can
   work". Is there a better shape?

2. **The `Capability` enum conflates two different things.** It mixes *privilege required* with
   *wiring state* — `UNAVAILABLE` currently has zero members. If `read_repo` ships as `UNAVAILABLE`
   and later becomes `READ`, every manifest that reasoned about its level sees a silent semantic
   change. **A tool's level must not change because it got implemented.** The brief flags this.
   Does fixing it belong in Phase 19, or does it need its own ADR first?

3. **There are three allowlists, not the two ADR-027 §4 assumes.** `restart-allowlist` scopes the
   **target** — `load_restart_units()` returns unit names, not caller ids. So ADR-027 §4's
   `effective tools = agent.tools ∩ caller authorisation` has no term for it: a tool name is a verb
   whose permitted object set lives in a file the vocabulary cannot see. Is `restart_service` the
   right granularity at all, or should a tool be a verb+object pair? What happens when `post_review`
   needs to be scoped to one project?

4. **`ask_model` may not belong in the vocabulary at all.** ADR-025 §10 says model output is never
   dispatched. An agent that calls `ask_model` and then chooses its next tool based on the answer is
   not literally dispatching model output — but it is adjacent, and naming the tool makes that path
   thinkable. Is granting it to nobody sufficient, or is naming it premature?

5. **"Caller" is not defined for an agent.** Both allowlists are files of numeric Telegram ids.
   ADR-027 §4 presupposes an on-behalf-of relation that has no representation today, and the journal
   line `user {id}: {executor.name} {args}` has no agent field. Is Phase 19 where that gets defined,
   or does it need an ADR of its own?

6. **The subset rule is a startup guarantee, not a runtime invariant.** `bot.py:315` computes
   `stray = privileged - allowlist` and exits if non-empty. `Router.__init__` receives
   `privileged_users` already validated and never re-checks — line 153 only tests membership. The
   property holds *because there is exactly one construction path today*. An agent loader would be a
   second one. The brief proposes moving the invariant into `Router`. Is that the right fix, or does
   it deserve more?

7. **Scope.** Phase 19 is "publish the vocabulary". Is writing the *manifest loader* also Phase 19's
   job, or is that the consumer side and therefore Phase 20's? Where does the boundary fall, and
   does ADR-027's validation list force the answer?

8. **The premise itself.** ADR-027 was written on 2026-09-10, before ADR-031 reframed the seam as
   *declare/enforce* across the whole system rather than just tools. Does anything in ADR-027 §2–§5
   read differently now? If so, say so — ADR-031 amended itself in place before merge, and there is
   no rule against a further ADR.

## Constraints that are NOT open for review

Challenge the design freely; these are accepted decisions and changing one means proposing a new ADR
that supersedes it, not quietly working around it.

| Constraint | Source |
|---|---|
| `homelab-bot` must never read either AI credential | ADR-025 §1 |
| The model gets **no tools**; its output is **never dispatched** | ADR-025 §10, ADR-027 §6 |
| An unknown tool name is a **hard load failure**, never a warning | ADR-027 §5 |
| Tools open **one agent at a time**, advisory-first, each with a recorded reason | ADR-027 §6 |
| The prose role spec stays the human source of truth; a manifest sits *alongside* | ADR-027 §7 |
| Agent manifests are **JSON** | ADR-031 §11 |
| Nothing private is cloned onto the node — no knowledge base, no project, no private repo | **ADR-032 §2** |
| Brief committed before implementation; deviations recorded, never silently applied | ADR-017 |
| Do not rewrite history to look linear. Records stay as written | `PROJECT.md` §11 |

## Working agreements

- Feature branch, merge `--no-ff`. `main` is branch-protected (force-push and deletion blocked).
- **The owner dictates via speech-to-text.** Filter transcription noise; ask only when ambiguity
  changes the action.
- Learning-first: explain decisions, do not just execute them.
- **Never mark anything installed, tested or verified without real output.** Assertion is not
  evidence — Phase 18 disproved three confidently-stated mechanisms by testing them, and each first
  test was itself invalid.
- Record problems and reversals. Do not tidy them away.
- Privileged node steps are handed to the owner as bare commands; the assistant has no sudo password.

## State you are inheriting

```
homelab       main @ af51673, clean, pushed. Phase 18 complete, DoD satisfied in full
node          running, 0 failed units, 6 listeners, 0 repositories (ADR-032 gate holds)
backup        verified 2026-09-11: 182 entries, restore proved, planted control fires
Phase 19      brief committed at docs/handovers/19-tool-vocabulary.md. NOT started
Phase 15.0    brief committed. Soft dependency — see seed 4 and the brief's §6.3
```

Phase 18 is genuinely finished; you are not inheriting loose ends from it beyond one recorded and
accepted gap: **no bare-metal restore has been performed**, so the backup is *verified*, not
*proven*. That does not constrain Phase 19.

## What "done" looks like for this review

A written response to the owner containing:

1. **Your questions and concerns**, ranked by how much they would change the design.
2. **What you think is wrong or under-specified**, with file and line references where the code
   contradicts the design or the ADRs.
3. **What you would change**, and what you would leave alone and why.
4. Anything in the seeds above you think is a **non-issue**, and the reasoning — disagreeing with
   this document is in scope.

Then **stop and wait.** The owner responds, the design settles, and only then does implementation
begin. If the review changes the design, the brief is amended and **the amendment is recorded** —
ADR-017 forbids deviations being quietly applied.
