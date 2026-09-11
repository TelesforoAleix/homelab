# Phase 19 design review outcome — handover to the orchestrating chat

- **Written:** 2026-09-11
- **For:** the orchestrating chat that reconciles the roadmap, ADRs, and phase briefs
- **Outcome:** the Phase 19 brief was successfully challenged; **do not implement it**
- **Implementation performed:** none
- **Governance status:** this document records the owner's decisions from the review. Cross-phase
  decisions below still need a successor ADR before they become accepted architecture (ADR-017).

## Read this first

The current Phase 19 brief is no longer a sound implementation plan. Its premise was that Factory
agents would name Homelab tools directly, so Homelab had to publish a tool vocabulary before Factory
could be rewritten. The owner rejected that coupling during review.

The replacement direction is:

> **Factory agents declare portable capabilities. Execution backends provide concrete tools.**

Factory must work on its own through Factory Workbench and a configured execution adapter. Homelab is
one advanced backend, not a prerequisite for Factory. Homelab owns its concrete tools and approved
capability-to-tool mappings. Other backends may satisfy the same Factory capability through Codex,
Claude Code, an API integration, MCP, or their own implementation.

The current Telegram executors were built to learn and prove routing and authorisation. The owner
clarified that they were mainly tests; they are not a production tool vocabulary to be published by
inertia. No Homelab tool name has yet earned a stable public contract.

Therefore:

1. **Do not implement** `docs/handovers/19-tool-vocabulary.md`.
2. Do not publish its proposed five-name vocabulary.
3. Remove Phase 20's hard dependency on Phase 19.
4. Build a minimal Factory Workbench first.
5. Build the Homelab AI foundation and discover tool needs through real workflows.
6. Return to Phase 19 only when concrete Homelab tools are needed.
7. Preserve the original brief and review documents as history; mark them superseded rather than
   rewriting them to appear correct in hindsight.

## What the review originally challenged

The initial review rejected approval of the Phase 19 brief for eight main reasons. These findings
matter because several were resolved by changing the architecture rather than by repairing the
brief locally.

### 1. “Tool” had two incompatible meanings

The brief treated a tool both as an authorisation label attached to a Telegram executor and as a
callable cross-repository API. It supplied no invocation, input, output, failure, or binding contract.
The live `Router.dispatch(user_id, text)` accepts Telegram command text, not an agent tool request.

**Review outcome:** separate portable capabilities from concrete tools. A capability states the
outcome an agent needs; a backend tool is an executable implementation.

### 2. Two proposed tools could not run on the reference node

`read_repo` and `post_review` presume private project content and `ops/` records on the node, while
ADR-032 currently forbids those objects there. More importantly, the owner clarified that none of
the five proposed names came from a real Homelab agent workflow.

**Review outcome:** Factory may define portable repository and review capabilities. Homelab does not
publish concrete counterparts until it implements them for a real need.

### 3. `READ` / `PRIVILEGED` was too coarse

The current router has one privileged-user bit, not a caller-authorised set of tools. Adding an
unrelated write operation at `PRIVILEGED` would accidentally give it to everyone authorised to
restart `chrony` once the tool was mapped to that level.

**Review outcome:** future tool contracts use independent effect, approval, availability, and target
scope properties. They do not force every mutation into the same host-privilege class.

### 4. The human-caller-only agent model was wrong for specialists

ADR-027 says an agent cannot hold authority its initiating human lacks. The owner wants unattended
specialists with their own narrow authority. A Brain specialist may search Brain on behalf of a
project agent without transferring Brain access to that agent.

**Review outcome:** distinguish user-delegated agents from service specialists. Delegation is
explicit, bounded, independently authorised, and audited.

### 5. Manifest loading was premature and under-specified

The brief proposed a production loader when no production manifest source, discovery process,
schema lifecycle, or agent invocation path existed. It also contradicted itself over whether one bad
manifest rejects one agent or stops the service.

**Review outcome:** the portable manifest belongs with the Factory Workbench design. Homelab later
validates concrete tool requirements when acting as the selected backend.

### 6. `ask_model` was not an agent tool

The brief promoted the Telegram `/ask` feature into a stable agent tool. The owner instead decided
that model invocation and selection are Homelab execution infrastructure. Agents do not request a
specific model or declare `model_policy`.

**Review outcome:** exclude `ask_model` from the tool vocabulary. Model routing consumes the agent
role and bounded task information.

### 7. Availability was treated as stable vocabulary data

`Capability.UNAVAILABLE` mixed privilege with implementation status, while the proposed replacement
would manually duplicate whether a binding exists.

**Review outcome:** a backend advertises its actual capabilities and concrete tools. Workbench checks
compatibility before activating an agent. Unsupported work never starts and then fails late.

### 8. Several proposed tests could not prove their claims

Examples included dispatching an unwired name through a command-only router, detecting unbound tools
while deliberately permitting two of them, proving model-output isolation by counting textual call
sites, and demanding byte-identical live output from dynamic status and model commands.

**Review outcome:** the eventual implementation needs repeatable standard-library tests plus planted
refusal controls. Live checks remain for real service boundaries, not pure manifest logic.

## The owner's intended system, consolidated

### 1. The four layers remain useful, but the execution boundary changes

The owner's mental model is:

- **Factory** provides the generative operating model: agents, roles, skills, workflows, work items,
  project-management contracts, communication rules, and portable capability requirements.
- **Homelab** provides the owner's advanced AI operating environment: model access, routing, context
  assembly, task decomposition, concrete tools, enforcement, budgets, auditing, and system controls.
- **Projects** contain their products and canonical `ops/` records, including their team, tasks,
  inbox, reviews, approvals, and provenance.
- **Brain** supplies knowledge. Whether Brain eventually runs its own retrieval agent or is queried
  by a Homelab-hosted specialist remains deliberately undecided.

**The defining sentence for Homelab's scope**, stated by the owner during this review and recorded
here because the bullet above under-describes it:

> **Homelab is an AI execution harness.** It performs the context selection, task decomposition,
> retrieval decisions, per-call model selection and controlled execution that a tool such as Codex or
> Claude Code normally performs *internally*.

That is the measure of what belongs in Homelab. When Claude Code decides which files to read, whether
to search the repository for a sub-question, how to break a request into steps, and which model
serves each one — those decisions are Homelab's. It is not a gateway with a router in front of it; it
occupies the position the coding-agent harness occupies today.

Two consequences follow, and both are easy to lose:

- From Workbench's side, "run this through Homelab" and "run this through Claude Code" are **the same
  shape of adapter**. That is why the adapter abstraction is load-bearing rather than tidy.
- The cache economics observed in the owner's measured week are a property of *those harnesses'*
  stable-prefix discipline, not of the models they call. A Homelab harness earns them only by
  engineering for them deliberately.

Factory must be independently useful. An adopter can use Factory through Codex, Claude Code, an IDE,
direct APIs, MCP, another backend, or manual operation without installing Homelab.

### 2. Factory is fork-and-customise software

Factory is distributed publicly as a starting operating system for projects. Each adopter edits and
configures their own installation. They do not receive upstream changes automatically. If they later
update, they deliberately merge upstream changes and resolve any collisions themselves.

Do not introduce a central live registry, global namespace machinery, or an automatic override layer
for all adopters. Simple exact names are sufficient until real collisions justify more.

### 3. Factory Workbench is the main Factory interface

The owner expects users to interact with Factory primarily through **Factory Workbench**.

Workbench lives in the Factory repository and:

- opens an existing project by being pointed at its project root or `ops/`;
- creates a new project and its minimum valid `ops/` structure;
- manages tasks, inbox messages, team assignments, reviews, workflow state, and approvals;
- validates and directly writes the project's Factory records;
- invokes AI work through a configured execution adapter;
- contains no Homelab credentials, model registry, or Homelab tool implementations.

Factory Workbench is executable software. This supersedes ADR-031's statement that Factory is fully
operational only as a specification and “never executes.” The narrower replacement boundary is:

> Factory Workbench executes Factory project operations; the configured backend executes AI and
> concrete tools.

### 4. Workbench execution backends

Workbench should eventually support:

- **Homelab** as the owner's advanced backend;
- a user's **direct API key**;
- locally authenticated **Claude and/or Codex subscription CLIs**, if official support and
  implementation complexity make them practical;
- **MCP** and other service integrations;
- **manual mode** with no AI execution;
- a **deterministic fake adapter** for repeatable tests.

Credentials use the operating system's credential store when available. Environment variables or a
protected user-local secret file outside every repository are fallbacks. Credentials never enter
project `ops/`, committed Factory configuration, logs, or browser storage.

Local Workbench binds to `127.0.0.1` and needs no separate application login; the OS user boundary is
sufficient. The first real Workbench runs on the MacBook. A later Homelab-hosted deployment is
Tailscale-only initially and adds application authentication and secure sessions. Public exposure is
not part of the initial design.

### 5. There are two dashboards, not one moved dashboard

The review separated two products that ROADMAP Phase 22 currently conflates:

| Factory Workbench | Homelab administration dashboard |
|---|---|
| One project view at a time | Whole AI system |
| Project `ops/` and project inbox | Homelab-wide approval inbox |
| Tasks, team, reviews, workflow | Models, providers, costs, tools, runtime health |
| Portable execution adapters | Authoritative Homelab execution/configuration |
| Lives in Factory | Lives in Homelab |

One Workbench installation opens multiple projects; dashboard code is not copied into every project.
Each project's private content and inbox remain in that project's `ops/`.

## Portable capabilities and concrete tools

### 1. The hybrid manifest model

Reusable Factory agents declare portable requirements. User-created agents may additionally name
exact local tools when portability is intentionally unnecessary. Keep the two concepts in separate
fields:

```json
{
  "capabilities": ["repository_read", "review_append"],
  "tools": ["optional_local_specialized_tool"]
}
```

- **Factory owns portable capability definitions.**
- **Each backend owns its concrete tools.**
- **Each backend owns its approved capability-to-tool mappings.**
- Factory requests; the backend decides whether and how it can fulfil the request.

This supersedes ADR-027's rule that Factory manifests directly compose Homelab's tool vocabulary.

### 2. Compatibility is checked before activation

The selected backend advertises what it actually supports. Workbench may load a valid agent
definition even when the current backend lacks a required capability, but it must refuse to activate
that agent before work begins and name every missing requirement.

Do not use the current Phase 19 design's “load now, discover refusal at dispatch” behaviour.

If Homelab lacks a needed mapping or tool, the project orchestrator automatically creates a private
capability-gap proposal. Human approval in the Homelab inbox is required before a sanitised proposal
enters Homelab's public backlog. Acceptance into the backlog does not create or grant a tool.

### 3. Mapping is a security decision

A portable requirement such as `repository_read` can be implemented safely or mapped carelessly to
a broad shell. New or changed capability-to-tool mappings therefore require human approval.

If a capability requires technical enforcement, a human cannot override an incompatible backend and
pretend prompt-only compliance is enforcement. The user must choose another adapter or define an
honestly weaker capability.

### 4. Tool contracts evolve compatibly

Tool improvements should reach every agent using the tool without changing its name. The public
compatibility promise is:

- faster, safer, more accurate, or backward-compatible changes keep the name;
- every known internal consumer is tested before merge;
- existing inputs, outputs, and minimum safety guarantees remain compatible;
- a truly incompatible public change requires a new version because unknown external adopters
  cannot be repaired automatically.

### 5. Future Homelab tool properties

The owner accepted replacing one scalar `READ` / `PRIVILEGED` level with independent properties:

- **effect:** `read`, `append`, `modify`, or `control`;
- **minimum approval:** `automatic`, `approve_when_granted`, or `approve_each_action`;
- **runtime availability:** supported or unsupported;
- **target scope:** the projects, records, services, or other objects the implementation may touch.

Homelab defines the minimum approval policy. Factory may make an agent or workflow stricter but can
never weaken Homelab's minimum.

Concrete examples discussed, not yet Homelab tools:

- `repository_read` should read explicitly named files and return revision/source provenance;
- `repository_search` should be separate and permit bounded discovery within project scope;
- `review_append` may automatically add an append-only, agent-authored review tied to the task;
- accepting a review or advancing release state is a separate action;
- destructive host control requires approval for each action.

## Agents, projects, and authority

### 1. Catalogue agents and project teams

- Factory holds a reusable catalogue of agent definitions.
- A project's canonical roster lives in that project's private `ops/`.
- Humans add agents to a project; the orchestrator may recommend an addition through the inbox but
  cannot approve it or edit the roster itself.
- When approving an agent, the human chooses **task-scoped** or persistent **team-scoped** membership.
- Task-scoped membership ends automatically with the task.
- Shared specialists are enabled explicitly per project rather than globally.

### 2. Agent definitions are live, tasks are pinned

An agent comes with a pre-approved set of tools and skills. Adding a tool or skill to the catalogue
agent makes it available in every project where that agent works, like a person being upskilled.

Controls accepted by the owner:

- global catalogue changes require human approval;
- approved additions take effect for the agent's **next task**, not during an active task;
- security revocations and emergency suspensions take effect immediately;
- every work item records the exact agent-definition version or content digest it used.

### 3. Logical identities, not OS accounts

Agents initially have logical identities carried by the trusted runtime. They do not receive an OS
account or credential merely because they exist.

The runtime, not model output, attaches immutable execution context:

- agent identity and version;
- project;
- work item;
- active assignment;
- authorisation and budget state.

The model supplies a proposed operation and arguments. It cannot claim another identity, switch
projects, or manufacture a grant.

### 4. Routine orchestration is autonomous inside approved bounds

The orchestrator is the human's principal project contact and communicates through the project's
inbox. Within the approved project, roster, workflow, and budget it may autonomously:

- decompose work;
- create routine tasks;
- assign them to approved team members;
- request bounded specialist help;
- run the accepted implementation/review loop.

It may recommend, but not autonomously perform:

- adding an agent;
- expanding project scope;
- expanding an agent's approved definition;
- exceeding a task budget;
- creating an external repository;
- merging or publishing;
- invoking an action whose minimum policy requires human approval.

### 5. Service specialists deliberately supersede ADR-027's human ceiling

The owner explicitly rejected the rule that every agent must be limited to what the initiating human
could do directly. A Brain specialist may have its own narrow service authority and operate without a
human in the loop.

This does **not** transfer the specialist's access to the requester. A coding agent can ask the Brain
specialist a bounded question, but cannot search Brain itself.

Agent-to-agent requests are explicit delegation. The receiving agent independently validates the
request against:

- its own role;
- the active project and workflow;
- permitted delegation relationships;
- scope and data-sharing policy;
- tool approval policy;
- remaining budget.

“A teammate asked” is never sufficient authorisation. Otherwise an agent without merge authority
could bypass its boundary by asking a release agent to merge.

## Context, prompts, routing, and knowledge

### 1. Context selection is a separate job

The agent that selects context is not necessarily the agent that writes code. The task author or
context-selection role identifies what the implementer should receive. If the implementer needs more,
it asks the orchestrator/context role; it does not silently gain repository search access.

The effective execution boundary is conceptually:

```text
approved agent definition
∩ active project/task assignment
∩ work-item context scope
∩ approved capability-to-tool mapping
∩ backend tool and target policy
∩ applicable moment-of-action approval
```

### 2. Fixed instruction hierarchy

The owner accepted this order:

```text
Homelab security and tool policy
→ approved Factory agent and skill definition
→ project policy
→ approved work-item instructions
→ retrieved context as untrusted data
```

Repository files, Brain results, API output, and messages from other agents are untrusted data by
default. Text does not become an instruction merely because it uses imperative language.

Another agent's response, including the Brain specialist's, is advisory. It cannot grant tools,
change project scope, weaken approval, or redefine the receiving role. Workbench or Homelab validates
every proposed state transition.

### 3. Model selection belongs to Homelab

Agents do **not** declare `model_policy` and never name a provider or model. The Homelab router receives:

- the agent role;
- a bounded task summary rather than the full private task;
- non-authoritative metadata such as priority, severity, and complexity (see below);
- required capabilities and context characteristics;
- model availability, eligibility, capacity, cost, and latency.

The target is an AI-assisted Homelab routing agent. Start deterministically because that is simpler
to validate, and retain deterministic routing as the fallback. The AI router itself sees only the
bounded routing summary unless a future decision explicitly widens that boundary.

**Priority, severity and complexity are hints, never selectors.** The router weighs them alongside
everything else; they cannot choose a model, cannot reach a model tier on their own, and cannot
bypass the pre-call budget check. This follows directly from the instruction hierarchy in §2 above:
an agent's own statement about its work is **data**, not an instruction. Without this, an agent could
route itself to an expensive model by asserting that its task is hard, and the spend governor would
only notice after the cost was already committed.

This supersedes ADR-027's `model_policy` manifest field and Phase 15.0's task-class-to-model-policy
assumption.

**ADR-026 §4 is preserved, not superseded, and the successor ADR should say so explicitly.** §4
decides that *"an agent declares what it requires — 'cheap classification', 'fresh-context review' —
and the router selects"*, and adds that *"the declaration form is ADR-027's business"*. Removing
`model_policy` changes the **form**, which is precisely what §4 delegates, and not the principle:

> **The agent's role is its declaration of need.**

`review-qa` carries more routing signal than a hand-written tier does, and unlike a tier it cannot
drift out of sync with what the agent actually is. So ADR-026 §4 survives intact and only ADR-027's
manifest shape changes. An earlier draft of this handover did not mention ADR-026 at all, which would
have contradicted an accepted ADR silently — `AGENTS.md` forbids exactly that.

### 4. Model tool requests become untrusted requests, not direct power

The future system necessarily allows an agent model to propose tool use. The safe preservation of
ADR-025 is not “the model can never emit something that reaches a dispatcher”; it is:

- no raw provider CLI receives ambient filesystem, shell, credential, or OS tools;
- model output is untrusted;
- only a structured request enters the trusted runtime;
- runtime identity, assignment, scope, mappings, budget, and approval checks all run before action;
- the model cannot directly dispatch or grant itself anything.

This is a deliberate future change to ADR-025 §10's literal “model output is never dispatched” lock
and must be recorded in a successor ADR before tool-using agents are implemented.

### 5. Brain specialist contract

Projects explicitly enable access to a shared Brain specialist. A request contains only a bounded
question and deliberately selected project context, not repository access.

The response must distinguish evidence from interpretation and contain source provenance such as
document identifiers, revisions, and relevant excerpts. Project `ops/` stores the bounded answer and
citation identifiers. It does not copy whole Brain documents unless an explicit task needs an
attributed excerpt.

The project-facing knowledge contract remains stable whether the specialist later queries RAG
directly or asks a Brain-native agent. That internal execution location remains open until the Brain
and retrieval architecture are designed.

### 6. Durable state is explicit

Agents are stateless between tasks. An active task may have bounded temporary conversation context,
but anything needed later becomes an explicit record in Factory definitions, project `ops/`, or
Brain.

Task history stores observable decisions, concise rationale, messages, tool requests and results,
evidence, approvals, model usage, cost, and outputs. It does not store hidden chain-of-thought.

## Approvals, budgets, and workflow

### 1. Approval semantics

An approval is bound to one immutable proposed action, including its target and relevant revision.
Changing a branch, diff, repository, visibility, merge commit, or other material input invalidates the
approval. Approvals expire after a configurable period; the exact default was not decided.

### 2. Task completion versus publication

A task may close automatically when its declared acceptance checks pass and required reviews are
complete, unless the work item explicitly requires human acceptance. Technical completion does not
authorise publication, merge, or release.

### 3. Budgets

Every automated task has both:

- a monetary limit for metered providers; and
- a model-call limit, useful for subscriptions and unknown-cost providers.

The first limit reached stops execution and creates a project-inbox request. Tokens are recorded when
the provider reports them. Unknown cost stays `unknown`; it is not replaced with a confident estimate.

### 4. Review loop

The implementation agent and an independent review agent may run an automatic correction loop.

- The reviewer receives fresh context: ticket, acceptance criteria, diff, and test results, not the
  implementer's private reasoning.
- Default maximum: **two review-and-revision rounds**, configurable per project.
- Hitting the limit stops and escalates through the project inbox with findings, attempts, usage, and
  the proposed next action.

## The minimum Factory Workbench acceptance project

Factory should ship a **public, synthetic, resettable coding project**. It is simultaneously:

- the standalone quickstart;
- the end-to-end acceptance test;
- the development fixture;
- the learning example;
- the planted-control environment for refusals.

It must prove more than record management. The accepted scope includes:

1. Create a project proposal.
2. Require human approval before creating its repository.
3. Initialise the repository and minimum `ops/` structure.
4. Create a feature branch or disposable worktree.
5. Create a task with metadata and acceptance criteria.
6. Assign work through an orchestrator to approved implementation and review agents.
7. Select and assemble bounded context.
8. Execute through one adapter.
9. Permit automatic edits, commits, tests, review, and revision on the feature branch.
10. Push the feature branch.
11. Refuse direct agent writes to `main`.
12. Create a pull request in GitHub mode.
13. Require a human approval bound to the exact reviewed revision before merge.
14. Merge and record provenance.

### Local and GitHub modes

- Default mode uses a disposable local bare Git remote: repeatable, credential-free, safe for tests.
- Optional GitHub mode uses the user's already authenticated `gh` CLI; Workbench does not store a
  GitHub token.
- GitHub repository creation requires human approval.
- Repository visibility defaults to **private**.
- Making it public requires a separate explicit approval.
- All GitHub changes use a pull request; agents never push directly to `main`.

The fixture must also plant and prove refusal cases, including:

- an unapproved agent addition;
- an unsupported backend capability;
- an approval-gated action waiting in the inbox;
- exhausted review rounds;
- exhausted call or monetary budget;
- an agent attempting to exceed project or context scope.

Use a deterministic fake AI adapter for repeatable automated tests and an optional real Codex,
Claude, or API adapter for the genuine end-to-end demonstration.

## Required governance changes

These are proposals this review requires. They have **not** been written or accepted yet.

### 1. Successor ADR for ADR-027

Write a new ADR replacing ADR-027 in full rather than layering exceptions across most of its sections.
It must restate retained controls and record the changed ones:

- Factory capabilities versus backend tools;
- the separate `capabilities` and `tools` manifest fields;
- removal of `model_policy`;
- project roster and task-scoped/team-scoped assignments;
- live agent definitions with task-pinned versions;
- human approval of roster and global catalogue changes;
- logical execution identities;
- service specialists with narrow independent authority;
- agent-to-agent delegation;
- compatibility checks before activation;
- model tool output as an untrusted request to the runtime;
- exact refusal and positive-control requirements.

The prose role specification remains valuable for humans. JSON remains the manifest serialisation
unless the successor ADR deliberately changes ADR-031 §11; this review did not reopen JSON.

### 2. Successor/refinement ADR for ADR-031

Record that Factory is no longer specification-only:

- Factory Workbench executes and validates Factory project operations;
- AI/tool execution goes through a backend adapter;
- Factory owns portable capabilities;
- Homelab owns its concrete tools, mappings, and refusals;
- there are two dashboards;
- the internal development plan may remain in Homelab even though Workbench code lives in Factory.

Do not silently edit the accepted ADR.

### 3. Mark the Phase 19 brief superseded before implementation

Preserve `docs/handovers/19-tool-vocabulary.md`. Add a dated amendment or status note stating:

- the design review rejected its premise;
- none of its five names is an accepted Homelab tool vocabulary;
- the Telegram executors remain experiments;
- Factory no longer depends on Homelab tool names;
- Phase 19 is deferred until concrete needs exist;
- implementation never began under the original brief.

When Phase 19 resumes, it needs a fresh brief committed before implementation. The eventual phase
should define concrete Homelab tools, mappings, effects, approval policies, target scope, capability
advertisement, compatibility checks, and planted refusal controls against real consumers.

### 4. Rewrite Phase 20's scope and dependency

Remove the hard Phase 19 dependency. Split the work conceptually:

- **first:** minimum Factory Workbench plus the synthetic end-to-end project;
- **later:** intensive Workbench development and full Factory catalogue/content migration after the
  Homelab AI foundation has been designed and built.

Use the roadmap's sub-phase rule or another explicit amendment; do not silently stretch one phase
across unrelated intervening work.

### 5. Amend Phase 15.0 and Phase 15

Retain provider configuration, eligibility, caps, fallback, and “callers never name a model.” Replace
the `model_policy` / task-class input with:

- agent role;
- bounded routing summary;
- validated task metadata;
- capability and context characteristics.

Start deterministically, retain deterministic fallback, and record the AI-assisted router as the
target rather than pretending Phase 15.0 completes it.

### 6. Rewrite Phase 22

Do not move the whole Factory dashboard into Homelab. Phase 22 should cover the Homelab administration
dashboard and, when prerequisites exist, the authenticated Tailscale integration/hosting boundary.
Factory Workbench remains in Factory and owns project views and project inboxes.

### 7. Replace the current sequencing note

The agreed dependency shape is:

```text
successor architecture ADR(s)
    ↓
minimal Factory Workbench + public synthetic vertical slice
    ↓
Homelab AI foundation
  - provider/gateway integration
  - deterministic then AI-assisted routing
  - task decomposition
  - context assembly and caching
  - budgets, audit, approvals
  - Brain/RAG retrieval contract
    ↓
real capability gaps observed
    ↓
Phase 19 concrete Homelab tools and mappings
    ↓
intensive Factory Workbench/catalogue development
```

This is a dependency outline, not yet a final allocation of every item to Phase 10, 15, 15.0, 19,
20, or a new sub-phase. The orchestrating chat must reconcile it against the entire roadmap and use
stable phase numbers/sub-phases rather than renumbering existing history.

## Accepted decisions that remain intact

Unless a successor ADR explicitly restates and changes them:

- `homelab-bot` does not receive or read either AI credential.
- Raw Claude/Codex provider processes receive no ambient host tools.
- Model/provider/binary/path selection is never accepted directly from an agent.
- JSON remains the agent manifest serialisation.
- Unknown concrete tool names must fail clearly in the backend that is asked to execute them.
- Tool/capability incompatibility fails before agent activation.
- Human-facing prose remains the explanation of an agent role and its boundaries.
- No tool or mapping silently grants itself authority.
- Existing headless-node safe-change controls still apply.
- No secret enters Git, `ops/`, prompts, logs, or browser storage.

## Explicitly unresolved — do not invent answers

1. Whether the Brain specialist queries RAG itself or delegates to a Brain-native agent.
2. The exact Factory manifest schema after adding `capabilities` and removing `model_policy`.
3. The exact machine-readable backend capability-advertisement protocol.
4. The exact effect/approval/target-scope schema for future Homelab tools.
5. The first real Workbench AI adapter; only the deterministic fake adapter is fixed for tests.
6. The default approval expiry period.
7. The exact implementation and provider used by the future AI-assisted router.
8. The final sub-phase numbering and running order after the roadmap is reconciled.
9. Any change to ADR-032. The storage/classification discussion drifted outside this review; the
   owner explicitly stopped it. Leave ADR-032 governed in its own context rather than treating this
   chat as having superseded it.

## Important reversals and lessons

Record these rather than smoothing them away:

1. The initial review recommended that Homelab own portable tool names. The owner challenged this on
   Factory's standalone requirement, and the recommendation changed: Factory owns portable
   capabilities; backends own tools.
2. The initial review recommended a Homelab-hosted project dashboard. The owner explained that
   standalone Factory users need the same operating interface. The result is Factory Workbench plus
   a separate Homelab administration dashboard.
3. The review initially proposed omitting unwired `read_repo` and `post_review`; it later briefly
   accepted portable known-but-unsupported contracts. The final distinction makes both statements
   coherent: Factory may publish portable capabilities, but Homelab publishes no concrete tool until
   it implements one.
4. The current Phase 19 premise treated Telegram executors as emerging production tools. The owner
   clarified they were primarily tests. Implementation history does not define the future interface.
5. The discussion began to redesign ADR-032 through data classification. The owner identified that
   as scope drift. No storage-policy outcome from that branch should be inherited.

## What the orchestrating chat should do next

1. Read this document, the original review prompt, ADR-025 through ADR-032, both committed briefs,
   the full roadmap, and the live Factory repository.
2. Check the Factory repository's real current state; this review intentionally did not claim that
   the proposed Workbench structures already exist.
3. Draft the successor ADR(s) first and show the owner the actual supersession table.
4. Amend the roadmap and mark the original Phase 19 brief superseded, preserving history.
5. Write and commit the minimal Factory Workbench brief before implementation.
6. Do **not** implement Phase 19, publish its five names, modify the node, widen model context, or
   expose a dashboard as part of the reconciliation.

## Repository and validation state for this review

- Review began on `main`, clean and aligned with `origin/main`.
- The live Telegram router/executor code and the three allowlist examples were read.
- No node command, deployment, model call, provider call, privileged action, or live validation was
  performed.
- No tested-version, cost, service-health, listener-count, or system-state claim is made by this
  handover.
- The only material output is this design record and its handover index entry.

