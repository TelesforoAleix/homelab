# ADR-050: The core Home Lab execution contract — durable Runs, capabilities and client boundaries

- **Status:** Accepted
- **Date:** 2026-09-16
- **Supersedes:** The specific clauses of ADR-034, ADR-035, ADR-044,
  ADR-033 and ADR-039 accounted for below. No ADR is superseded in full.
- **Superseded by:** none

This accepted architectural contract is not a claim about deployed behavior. It establishes the
target contract; it does not migrate an interface, enable tool dispatch or declare any phase
complete. ADR-045's phase ownership and sequencing are not changed here.

## Context

Home Lab's target architecture describes a general AI execution system with Factory as one client.
Its agent contract, however, grew out of integrating Factory: ADR-034 makes system agents Home Lab
primitives, uses agent role as the declaration of model need, assigns portable capabilities to
Factory, and frames runtime identity and authority through projects, assignments and work items.
ADR-044 adds the stronger client-to-service exposure boundary but inherits that vocabulary.

The delivered interfaces reflect those decisions. Phase 15.0 uses `role` as a model-route lookup
key. Phase 23.0 requires that field and maps Factory's roster name to it. The endpoint returns a
result and records a content-free audit line; the client stores the result. Request identifiers,
Factory run records and persistent spend ledgers exist, but they do not define a generic durable
Home Lab work lifecycle. These are documented facts from the phase handovers, not defects erased
by adopting a new design.

The reconciliation must preserve the security and portability those decisions bought while making
Home Lab's execution contract meaningful without Factory. It must also distinguish proposing work
from coordinating it, and coordinating execution from owning a client's workflow. This ADR records
that boundary once rather than changing the same assumption independently in several phases.

## Decision

### 1. Home Lab is agent-agnostic

The core runtime does not require persistent agents or personas. Factory and other clients may
define agents, personas, roles, teams, workflows and domain-specific actors, supplied as context
where relevant. Such descriptions are not runtime authority.

Home Lab operates on these generic primitives:

| Primitive | Meaning in this contract |
|---|---|
| Request | A client's proposed outcome with supplied facts/references, constraints, preferences and inputs |
| Run | The durable orchestration record and lifecycle for an accepted request |
| Objective | The outcome the Run is accepted to pursue |
| Plan / step | Proposed work and its dependencies, constraints and completion/verification expectations |
| Capability | An implementation-independent runtime ability or outcome needed by planned work |
| Service | A stable, addressable provider of runtime capabilities that enforces its own hard boundaries |
| Tool / executor | A concrete operation or execution implementation behind a service |
| Context / provenance | Selected information and the record of its source, time and revision where applicable |
| Result / artifact | An execution outcome or produced material, which may be held by reference |
| Signal / concern | A structured observation, blocker or issue for the orchestrator to evaluate; never a grant or instruction |

Interpretation, planning, context assembly, routing and orchestration are runtime responsibilities
or modules, not inherently system agents. Claude Code, Codex and other coding harnesses are
executor implementations when used for work, not canonical Home Lab agents. This classification
does not grant them tools, credentials or filesystem access.

Logical responsibility separation alone does not justify a separate process/deployment boundary.
Such a boundary is justified when something must be held or enforced independently: credentials,
privilege, filesystem/resource view, trust level, state with a different lifetime, machine
placement, or an availability/failure boundary. Planner, orchestrator, interpreter and context
assembler may remain harness modules where no such boundary exists. No deployment or communication
mechanism is prescribed here.

**Boundary test: if Factory disappeared, every core Home Lab primitive would still make sense.**

### 2. A canonical request establishes an immutable objective

Client adapters normalize their ingress shapes into the canonical request described above. Identity
is attached or attested through the trusted ingress path, not accepted from a persona description
or a model's claim. The authentication/attestation mechanism is not selected here.

Every accepted new work request creates a Run, including simple work. Information supplied
specifically in response to a Run waiting for required input resumes that existing Run; a message
or request envelope is not necessarily a new work request.

The Run's core objective becomes immutable at acceptance. Clarification, evidence and refinement
may change the plan or Definition of Done, but every refinement must remain consistent with the
accepted objective, binding client requirements and applicable constraints. A Definition of Done
change may never redefine the requested outcome, silently or explicitly. A planner may not remove
a required acceptance condition merely because it becomes difficult. Material ambiguity that
cannot be resolved within the accepted objective requires clarification, replanning, partial
completion, failure or escalation as appropriate; it cannot be converted into successful completion.
A materially different objective creates a new Run, which may supersede the previous one. The
relationship is recorded; the old objective and history remain intact.

This defines the conceptual contract, not a new wire schema. The delivered version-1 endpoint is
covered by the compatibility section below.

### 3. A Run is the durable lifecycle unit

The Run exists independently of the submitting transport connection. Home Lab owns its
orchestration record, including as needed:

- client and immutable objective;
- resource/project scope and constraints;
- current plan, step states and dependencies/waiting conditions;
- concerns/signals and executor-session references;
- results/artifact references, lifecycle status and telemetry references.

Runs may wait and resume, depend on other Runs, be cancelled, fail, complete partially or fully,
or be superseded. Partial completion must remain distinguishable from full completion; waiting
and interruption must not be reported as success. Durable records preserve what happened rather
than requiring a transport connection or an executor session to remain alive. This does not
promise recovery of every executor's internal session or safe automatic repetition of every action.

Durability does not transfer canonical domain records to Home Lab. Factory project state remains
Factory/project state; Brain knowledge remains owned by its knowledge domain. Produced artifacts
may remain in domain or service storage and be referenced by the Run. Home Lab records the generic
execution relationship and outcome, not a replacement ticket system or knowledge store.

Home Lab owns the durable orchestration record, not exhaustive payload storage. Durability does
not inherently require every raw prompt, complete client conversation history, copies of project
files or Brain documents, full executor session state, or every artifact body. References to
canonical/domain-owned resources are valid where appropriate. If a referenced external resource
or artifact becomes unavailable, the Run must reflect that limitation rather than imply guaranteed
reproducibility or continuation. This does not choose a retention policy.

No persistence technology, detailed state schema, storage placement or new backup mechanism is
chosen here. Existing content-storage, account and locked-volume boundaries remain binding.

### 4. Planning and orchestration are distinct logical responsibilities

The **planner** determines what work should happen and may propose or revise an outcome-oriented
plan. It may use AI. Its output is a proposal subject to validation.

The **orchestrator** is the deterministic Run-state coordinator. It determines which steps are
ready or waiting, applies scope and policy checks, performs capability/service dispatch, records
outcomes, and invokes the planner when replanning is required. AI may inform a proposal; it does
not decide whether the proposal is authorized or directly commit a Run-state transition.

These may initially be modules in the same harness process. Separate services or processes are
not required.

Services and executors do not rewrite the Run objective or global plan, or independently expand
Home Lab's work graph. They return structured results, blockers, concerns or additional capability
needs to the orchestrator. An executor's internal work remains bounded by its dispatched scope; internal
activity cannot create new Home Lab authority or independently commission additional Runs.

### 5. Plans describe outcomes; resolution chooses implementations

A plan step describes required work/outcomes, dependencies, constraints and completion/verification
expectations. The accepted plan does not authoritatively bind execution to a concrete service,
tool, model or provider. A planner may include non-binding implementation observations or
preferences, but these cannot bypass downstream resolution or policy. Capability, service and
model resolution occur downstream of planning:

```text
plan step → required Home Lab capability → eligible service → tool/provider/executor
```

One-step plans are normal. The contract does not require a model call to produce a simple plan.
Capability resolution and service routing apply deterministic policy to select eligible
implementations. An unavailable or unauthorized requirement produces an explicit blocker or
refusal; it is not silently dropped or substituted with broader authority. Alternative work may be
proposed to the orchestrator and validated within the same objective and constraints.

### 6. Home Lab owns runtime capabilities; client catalogues remain independent

Home Lab owns the canonical runtime capability vocabulary/registry connecting planned work to
eligible services. Services implement and advertise those capabilities. Tools are finer-grained
concrete operations behind services; an executor may implement the bounded work a service accepts.

Examples of the intended granularity are `language.reason`, `knowledge.retrieve`,
`external.research`, `project.inspect`, `project.modify`, `tests.execute`, and future modality
capabilities. These examples do not advertise implemented services or publish concrete tool
contracts. Actual support must be stated honestly; dynamic discovery is not decided here.

**A capability request or possession is not authority.** Approved capability-to-service/tool
mappings remain security decisions. New or changed mappings require human approval under
ADR-034 §10. Normal deterministic use of an already-approved mapping does not require approval
on every dispatch merely for using that mapping; applicable tool/action approval requirements
still apply. Neither registration nor a planner's reference grants access. Technical enforcement
cannot be replaced with prompt-only compliance. Unknown tools fail clearly and unsupported
requirements are named before affected work begins.

Factory may retain its own portable/domain-specific requirements or capability catalogue. Those
concepts can map to Home Lab runtime capabilities at the adapter/request boundary. Factory's
internal model must not depend on Home Lab's vocabulary, and Factory remains usable through other
backends or manual operation. This replaces only Factory's ownership of the **generic Home Lab
runtime capability contract**, not its ownership of Factory requirements.

Factory's existing compatibility/activation obligations under ADR-034 §6 remain mandatory and
Factory-owned: Workbench may load a valid definition with unsupported requirements, but must
refuse activation before work begins and name **every** missing requirement. Home Lab's generic
runtime checks do not replace or weaken that obligation, and other clients need not adopt
Factory's activation model. Translation through the Home Lab adapter must preserve validated
client/domain restrictions as narrowing constraints on the resulting Run.

### 7. Actor context, inference need and model route are separate

| Concept | Responsibility |
|---|---|
| Client actor/persona | Client/workflow context; not an identity claim or model selector |
| Inference purpose/task requirements | What an individual inference call needs |
| Provider/model route | Selected by Home Lab under deterministic routing policy |

`role` ceases to be the universal Home Lab routing abstraction in the target contract. Model/task
requirements and AI-generated complexity assessments are advisory inputs, never authority.
Deterministic policy selects an eligible provider/model using applicable constraints such as
quality requirement, context size, availability, privacy, cost/safety and latency. A description
of difficult work cannot select a tier or bypass a budget check. AI-assisted routing suggestions
may be considered, but policy retains the selection decision.

Provider abstraction, configured model registries, provider eligibility, credential isolation,
fallback controls, call limits and the fail-closed spend governor survive. Clients and planners
do not select a concrete provider/model by embedding its name in their request. Existing
role-based routes remain delivered compatibility behavior until a later contract/version replaces
them; acceptance of this ADR alone changes no route.

### 8. Authority invariant: AI proposes. Policy decides. Services enforce.

```text
authenticated/attested client + valid delegated/request authority + request constraints
    → Run
    → planner proposes
    → orchestrator validates
    → capability/scope/policy resolution
    → service
    → tool/executor
```

A Run cannot exercise more authority than the initiating client/human has validly delegated for
that request. Authentication and client service exposure alone are not sufficient authority.
Effective Run authority is bounded by the intersection of authenticated/attested client authority,
explicit delegated/request authority, validated client/domain restrictions, Run/project/resource
scope, Home Lab policy and service-enforced boundaries. Requested authority is not a grant merely
because it appears in a request.

No model, supplied or retrieved content, client persona, other Run, planner output or executor may
broaden authority, project/resource scope or policy. Constraints may only narrow downstream. A new
Run or a dependency on another Run does not manufacture a grant. Required approval remains a separate
trusted decision under existing policy, not something a plan or completion criterion can supply.

Client exposure remains the first and stronger authorization boundary. A client reaches only
explicitly exposed services; default exposure is none, and system-control services remain
unreachable from Factory and other project-work clients under ADR-044 §3. Discovering a candidate
mapping is not permission to invoke it. Exposure refusal precedes evaluating subordinate
capability entitlement or executing any action; the refusal reasons remain distinguishable.

Services enforce their own hard trust, credential, filesystem and resource boundaries in addition
to orchestrator checks. A narrowly privileged specialist service may possess and exercise its own
independently granted, bounded and audited mandate. Invoking it transfers none of that authority
to the caller, planner, Run, model or another service. Its invocation and returned information must
remain within the Run's permitted operation and data-sharing scope. Another service or Run's
response is advisory and cannot weaken the receiver's policy.

The security properties of ADR-034 survive without a mandatory agent primitive:

- The trusted runtime attaches execution identity, scope, authorization and budget context;
  model output supplies only proposed operations and arguments. Supplied content, model output,
  retrieved content and personas cannot rewrite runtime identity or authorization provenance.
  Logical Runs, personas and executors do not acquire OS accounts or credentials merely by existing.
- Home Lab security/tool policy takes precedence over approved client/domain instructions,
  project/resource policy and accepted work instructions. Those instructions can narrow but not
  weaken governing policy. Retrieved material and other actors' output are untrusted data.
- Only structured proposed operations may enter checked dispatch. Identity, scope, approved
  mappings, tool/target policy, budgets and required approvals are checked before action.
- Approval binds to the exact action and material inputs/revision, expires, and is invalidated
  by material change. Replanning or resuming cannot reuse approval for a different action.
- Applicable execution definitions/policy revisions are recorded. Ordinary additions do not
  silently widen in-flight work; security revocations and emergency suspensions apply immediately,
  including before resumed work proceeds.
- No undeclared or ungranted tools become available by default. Destructive host control retains
  moment-of-action approval where the client may reach that service at all.
- Observable decisions, concise rationale, refusals, operations, evidence, usage and outcomes are
  auditable. Hidden chain-of-thought is not a durable record. Refusals require positive controls
  as well as denied attempts when the contract is implemented.

ADR-025's raw-provider isolation remains: a provider CLI receives no ambient host tools. The
ADR-034 §13 transition from inert output to checked action requests is **not activated by this
ADR alone**. It requires an implemented and validated enforcement path; until then the existing
canary property and inert-output behavior stand. Naming a coding harness
an executor does not authorize an unrestricted native tool loop.

### 9. Clients retain domain workflow and interaction continuity

Factory owns PM/engineer/reviewer/tester roles, epics/user stories/tickets, project workflow,
project-specific Definition of Done, documentation conventions, project dependency/graph semantics,
and the semantic decision that work is ready for promotion or integration. Home Lab supplies
generic execution/orchestration beneath those abstractions. Completion of a Run does not itself
approve a merge, advance a ticket or establish readiness for release.

Generic Run dependencies do not replace Factory's project graph. Project approval and system
action approval retain their separate scopes under ADR-043. Factory's canonical records remain
where ADR-028 and ADR-030 place them; Brain retains knowledge ownership.

A Run is not a universal conversation/session abstraction. Clients own interaction continuity:
Factory may be ticket/workflow-centric; Telegram may later define conversations, threads or
sessions; automated clients may have none. Executor-session references do not make those sessions
the Run's lifecycle. An answer to required input for an existing waiting Run resumes that Run,
subject to its constraints and current policy. A new work request creates a new Run
with explicit supplied context/references; continuity is not inferred from conversational history.

### 10. Authorized context selection preserves the egress boundary

ADR-039's owner selection remains valid. Its runtime selection subject is generalized from an
approved agent acting on a work item to an **authorized Home Lab Run/context-assembly path**.
Selection is permitted only within authenticated client exposure, Run/project/resource scope,
applicable egress/privacy policy and service-enforced boundaries.

AI may propose relevant context; it cannot authorize egress or broaden scope. Selection must be
deliberate and attributable to that authorized path. Content does not become eligible merely
because a log, fetched page, repository file, persona or other Run mentions it.

ADR-039's restrictions survive: only permitted data classes may leave; secrets never leave;
third-party/personal data requires the existing new-decision gate; providers must be approved;
provenance travels with assembled information. Automatic inclusion of logs, journals, unit files,
configuration or allowlists remains forbidden. Service access alone is not permission to send
what it can read to a model. Retrieved material remains untrusted, and any required downstream
action gate cannot be bypassed by forwarding it through another service or Run.

## Supersession and survival accounting

Original ADR bodies, alternatives and validation history remain intact. “Superseded” applies only
to the named portion, not the entire section. “Qualified/generalized” changes the universal runtime subject or scope while preserving the
client/domain rule. “Preserved/unchanged” records no semantic change. Unlisted decisions are not
implicitly repealed. Validation obligations in affected ADRs follow the preserved security
property under the new subjects, rather than being discarded because an agent field is no longer
mandatory.

| Existing clause | Disposition and exact scope | Surviving rule / replacement |
|---|---|---|
| **ADR-034 §2** | **Superseded:** Factory ownership of the generic Home Lab runtime capability vocabulary only | Factory retains its portable/domain requirements. Backend tools, approved mappings, honest support and standalone adoption survive; §6 here defines runtime ownership |
| **ADR-034 §3** | **Superseded:** system agents as required Home Lab primitives | System/work responsibility separation survives as runtime modules versus client/domain actors (§1) |
| **ADR-034 §4** | **Qualified/generalized:** agent declarations are not the required generic Home Lab request contract | Factory's manifest contract, capabilities/tools distinction and JSON serialization survive; Home Lab uses the generic request (§§1–2) |
| **ADR-034 §5** | **Superseded:** role as declaration of model need and an AI routing agent as the target decision-maker | Need-based backend selection, bounded input, advisory metadata, deterministic policy and budget checks survive (§7) |
| **ADR-034 §6** | **Qualified/generalized:** activation is not every client's runtime checkpoint | Factory must still validate compatibility before activation, refuse unsupported activation and name every missing requirement. Generic runtime checks do not replace this obligation (§6) |
| **ADR-034 §7** | **Preserved/unchanged** | Independent effect/approval/availability/target-scope properties, minimum policy, compatibility and public versioning rules all survive |
| **ADR-034 §8** | **Qualified/generalized:** agent-shaped authority terms become generic Run/service terms | The delegated-authority ceiling, validated domain restrictions, bounded independent specialist mandate and non-transfer of authority remain mandatory (§8) |
| **ADR-034 §9** | **Qualified/generalized:** agent-to-agent relationships are not required generic runtime subjects | Receiver-side validation of scope, permitted delegation, data sharing, tool policy and budget survives; another actor's request/response is never authority. Applicable Factory actor/workflow restrictions still narrow the Run |
| **ADR-034 §10** | **Qualified/generalized:** a project orchestrator is not the only source of capability-gap concerns | New/changed mappings still require human approval and technical enforcement. A Run may raise a private concern; human approval in the Home Lab inbox is still required before a sanitized proposal reaches the public backlog. Backlog acceptance grants nothing |
| **ADR-034 §11** | **Qualified/generalized:** mandatory agent/version/project/work-item identity shape and Factory hierarchy tier | Trusted runtime identity and authorization provenance, no automatic OS credentials/accounts, applicable scope, policy precedence and untrusted-data rules survive (§§2, 8, 10) |
| **ADR-034 §12**, generic lifecycle/storage reading | **Superseded:** agent task as generic lifecycle and Factory/`ops/`/Brain as exhaustive durable runtime destinations | Home Lab owns Run orchestration records (§3), not canonical domain records. Applicable definition revisions, durable observable evidence rather than hidden reasoning, and immediate security revocation survive |
| **ADR-034 §12**, Factory governance | **Preserved/unchanged** | Factory catalogue/roster ownership, human membership and global catalogue approval, task-scoped membership expiry, explicit per-project specialist enablement, next-task additions, exact definition pinning and incremental tool opening remain Factory/domain rules |
| **ADR-034 §13** | **Qualified/generalized:** agent-specific subjects of checked dispatch | All security checks, provider isolation and the implementation-dependent transition from ADR-025 §10 survive (§8); no dispatch is enabled here |
| **ADR-034 §14** | **Qualified/generalized:** agent-shaped refusal/default-tool subjects | Structural refusals, Factory's mandatory pre-activation check, no implicit tools, credential/secret exclusion and positive-control validation survive |
| **ADR-034 §15** | **Preserved/unchanged** | Prose and manifest remain complementary; disagreement is a reconciliation bug, not a precedence rule |
| **ADR-044 §§1–2** | **Qualified/generalized:** agent-specific subordinate authorization and refusal subjects | Client exposure remains first and stronger, but not sufficient; delegated authority and subordinate capability/scope/policy checks remain distinct (§8) |
| **ADR-044 §5** | **Superseded:** Factory ownership of the generic runtime capability contract only | Home Lab runtime vocabulary (§6); separate service/tool granularity and client-owned catalogues survive |
| **ADR-035 §3** | **Qualified/generalized:** Factory ownership applies to Factory capabilities, not all Home Lab runtime capabilities | Tool/skill distinction, capability as a request rather than authority, backend enforcement and Factory's independent vocabulary survive (§6) |
| **ADR-035 §8** | **Preserved/unchanged** | Factory has no prerequisite on Home Lab vocabulary; tools follow real needs. Runtime capabilities do not restore that prerequisite |
| **ADR-033 §6**, role-derived route-vocabulary resolution | **Superseded:** role as the declaration from which routing must derive | The gateway/provider decision is untouched; actor context, inference need and selected route separate under §7 |
| **ADR-039 §2**, approved-agent/work-item selection subject | **Qualified/generalized:** agent/work-item is not the required runtime selector | Owner selection and authorized Run/context selection (§10); deliberate selection and every egress restriction survive |

The major surviving decisions are explicit:

- **ADR-025:** credential separation, restricted helper access and raw-provider isolation remain;
  §10 retains its conditional transition, with prior supersessions of §§8–9 undisturbed.
- **ADR-026:** callers declare needs and the backend selects; registry/configuration, provider
  eligibility and owner allowance protection remain. Changing declaration form does not restore
  caller-selected models.
- **ADR-033:** Vercel AI Gateway, provider abstraction, credential handling, governor precondition,
  persistent fail-closed controls and telemetry remain. Only §6's role-derived resolution changes.
- **ADR-038:** server placement, local harness clients, loopback binding and tunnel access remain.
  Run durability chooses neither a new host nor a storage location.
- **ADR-040:** autonomous calls remain normal, governed by budgets and provider eligibility.
- **ADR-043:** ADR precedence, normative contracts and separate implementations per scope remain.
- **ADR-047–049:** Workbench sandbox/account boundaries, the helper consumers group and the
  development operator's bounded access remain. A Run inherits none of the operator account's
  authority. Their revisit triggers still apply to any later change that engages them.
- **ADR-028/030/031/035:** canonical project records, Factory independence, project operations,
  separate dashboards and portable execution adapters remain, subject only to the listed clauses.
- **ADR-037/039/046 and service standards:** encrypted content storage, egress, credential rules
  and degraded-until-unlocked behavior remain constraints on subsequent design.
- **ADR-045 is not superseded.** Phase ownership/sequencing remains undecided for any new work
  that cannot fit its existing allocations; this ADR grants no phase a silent scope expansion.

## Compatibility and migration implications

Phase 23.0's required `role`, request taxonomy, request ID, declared client label, content-free
audit and return-and-forget behavior remain historical delivered compatibility. The new Run
contract does not retroactively turn those requests into durable Runs or authenticate their client
labels. Phase 15.0/15.1 routes and limits remain effective until explicitly migrated.

A later versioned contract must reconcile canonical requests, Run identity and adapter correlation.
The 23.0 handover's rule remains: an additive version-1 field must preserve absent-means-today;
a changed meaning requires version 2. This ADR does not specify that schema or edit Factory's
`Request`/`Result`. The existing `last_request_id` side-channel finding remains recorded, not
silently declared fixed.

Migration must preserve Factory's other adapters and re-prove compatibility with a second adapter.
Client-owned requirements may be translated at the boundary without importing Home Lab names into
Factory's internal model or discarding validated client/domain restrictions. ADR-035 §4's adapter
contract is unchanged; future correlation/versioning remains an unresolved compatibility issue.
Existing endpoint labels and role keys cannot be treated as attested authority simply because
they can be translated into the new vocabulary.

Run content cannot be added to the root-resident endpoint's state by implication. Its storage and
account design must satisfy the encrypted-volume and sandbox decisions. Durable Run state leaves
a storage/account/locked-volume placement question for subsequent design; this ADR grants no
volume access or exception to existing placement and security boundaries.

No roadmap, architecture map, completed brief/handover or service contract is rewritten by this
record. Later work must update living documents to distinguish accepted target from delivered state
and resolve any phase-allocation changes explicitly under ADR-017/043/045.

## Alternatives considered

**Keep agents and role as the universal contract.** Preserves the delivered shape, but requires
generic work to manufacture a persona and mixes client identity with per-call inference needs.
Retained only as delivered compatibility, not as the proposed target.

**Move Factory's capability catalogue wholesale into Home Lab.** Rejected: it reverses the
standalone-adoption reason for ADR-034/035. Runtime capabilities and client/domain requirements
have distinct ownership, with translation at their boundary.

**Keep all execution state in clients.** Preserves the thin endpoint but leaves Home Lab unable to
own generic waiting, dependencies and recovery independently of a submitting connection. Clients
still own domain state; the Run owns the orchestration record.

**Let planners or executors directly dispatch and expand work.** Rejected: proposed work would become
authority, bypassing deterministic coordination and service policy.

**Require a workflow platform or separate planner/orchestrator services now.** Rejected: the logical
contract can begin with one-step work and ordinary modules. No new infrastructure is justified by
the vocabulary alone.

## Consequences and tradeoffs

The core can serve different clients without inventing agents or tickets for them. Immutable
objectives and durable Runs make continuation, partial outcomes and supersession explicit. Clear
planning and dispatch responsibilities preserve AI flexibility inside deterministic controls.

The cost is another explicit boundary: Factory requirements for execution through the Home Lab
adapter/runtime must map to Home Lab runtime capabilities, preserving validated narrowing
restrictions. Factory's internal vocabulary and other backends remain independent. Run orchestration
records must remain distinct from domain records. Durability introduces recovery, privacy,
retention and backup questions that the thin endpoint avoided. Existing adapters
need a deliberate version transition; accepting the target does not remove that work.

The design stays learning-first: simple requests have one-step plans, modules may share a process,
and contracts can be implemented and validated incrementally. No database, queue, framework or new
service is required merely to make these names real. Existing budget and authority controls remain
mandatory throughout migration.

## Intentionally deferred

This ADR does not decide persistence technology; a detailed Run database/state schema; dynamic
service discovery; complex per-Run budgeting; advanced autonomy limits; a native coding-agent/tool
loop; scheduler implementation; a full retry/idempotency framework; detailed caching; an evaluation
framework; or a physical process split for planner/orchestrator.

It also leaves the authentication/ingress attestation mechanism, wire/protocol version, process
topology, Run storage/account placement and retention, and any necessary phase reallocation to
subsequent design. None of those deferrals
permits weaker exposure, egress, approval or spend controls. A model-backed planner consumes the
existing governed allowance; decomposition does not create new budget authority.

## Validation / revisit trigger

These are acceptance obligations for later implementation, not claims of tests run for this ADR:

1. A non-Factory client completes one-step work without supplying an agent/persona; a Factory
   adapter preserves its own portable requirements, narrowing restrictions and project records.
   Factory refuses activation with every missing requirement reported, as ADR-034 §6 requires.
2. Accepted work remains identifiable after the submitting connection ends and after runtime
   restart; waiting input resumes the same Run, while a different objective creates a new one.
3. Replanning and Definition of Done refinement preserve the objective, binding client requirements
   and constraints; difficult acceptance conditions are not dropped. Partial completion, refusal,
   failure and unavailable referenced resources remain distinguishable in the durable record.
4. Planner output naming unauthorized work, a persona claiming privilege, another Run requesting
   broader access, and an executor proposing extra work cannot grant authority. Each refusal has
   a corresponding permitted positive control.
5. Service exposure refuses forbidden clients before subordinate entitlement or action; permitted
   clients still require valid delegated authority, validated domain restrictions, scope, mapping,
   tool policy, budget and approval checks. Service invocation never transfers independent authority.
6. An inference requirement or complexity claim cannot select a forbidden route or bypass the
   governor. Provider/credential isolation and the existing canary remain intact until checked
   dispatch is separately implemented and validated.
7. Authorized context selection carries provenance and enforces ADR-039's data/provider rules;
   untrusted content cannot authorize selection or egress. Revocation is enforced on resumed work.
8. Completing a Run does not mutate canonical client workflow state or promote/integrate work
   without the client's own validated operation and applicable approvals.

Revisit if runtime capabilities cannot map client needs without importing domain workflows; Run
records duplicate or diverge from canonical domain state; practical executors cannot remain inside
the assigned work boundary; or durable continuation requires weakening a preserved security rule.
Such evidence calls for an explicit decision, not a silent expansion of this contract.
