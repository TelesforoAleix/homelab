# Target Architecture — Home Lab execution and orchestration

- **Written:** 2026-09-11; reconciled with ADR-050 and ADR-051: 2026-09-17
- **Status:** Frozen version-one design at project closure (2026-09-18). It describes intended
  architecture that was not fully implemented, not deployed behavior or a commitment for version
  two. See ADR-052 and the closure handover.
- **Standing:** Accepted ADRs govern this document. ADR-050 and ADR-051 govern their scoped successor decisions; ADR-045 remains authoritative for phase allocation.

## Purpose and boundary

Home Lab is a generic, agent-agnostic AI work-execution and orchestration platform. It accepts work from clients, coordinates its lifecycle, assembles context, selects eligible execution paths, and returns structured outcomes under policy and service-enforced boundaries.

Factory is a client/domain system, not part of the Home Lab core. It may own software-development roles, agents, teams, tickets, project workflows, Definition of Done, project graphs, and promotion/integration decisions. Other clients may use chats, scheduled triggers, command-line requests, automation, or no human interaction at all. If Factory disappeared, every core Home Lab primitive below would still make sense.

Home Lab does not require persistent system agents or personas. Client actors, personas, roles and workflows may be supplied as client context where useful, but are neither Home Lab runtime primitives nor authority.

## Core concepts

| Concept | Target meaning |
|---|---|
| **Client** | A domain system, interface, or automated source that submits work through a client-specific ingress path |
| **Request** | A proposed outcome with supplied facts/references, constraints, preferences and inputs |
| **Run** | The durable Home Lab orchestration record and lifecycle for accepted work |
| **Objective** | The immutable outcome a Run was accepted to pursue |
| **Plan / step** | Outcome-oriented proposed work, dependencies, constraints and completion/verification expectations |
| **Planner** | The logical responsibility that proposes what should happen |
| **Orchestrator** | The deterministic logical responsibility that coordinates Run state and permitted dispatch |
| **Capability** | An implementation-independent Home Lab runtime ability or outcome required by work |
| **Service** | A stable, addressable provider of runtime capabilities with its own enforceable boundary |
| **Tool / executor** | A concrete operation or execution implementation behind a service |
| **Context / provenance** | Selected information and its source, time and revision where applicable |
| **Result / artifact** | A structured outcome or produced material, often held by reference |
| **Signal / concern** | Structured evidence, blocker or additional need for the orchestrator to evaluate; never authority |

Interpretation, planning, context assembly, routing and orchestration are runtime responsibilities. They may be modules in the harness rather than agents or separately deployed services.

## Canonical work flow

~~~text
client
  -> client ingress / normalization
  -> canonical request
  -> semantic interpretation / WorkIntent
  -> planner
  -> outcome-oriented plan
  -> orchestrator
  -> capability resolution
  -> policy, scope and service routing
  -> service
  -> tool / provider / executor
  -> structured result / artifact references
~~~

A Run spans this flow. It is created when a new work request is accepted and is updated as work is interpreted, planned, dispatched, waits, resumes, produces evidence, or ends. The flow describes logical responsibilities, not a mandatory process topology. A simple request normally has a one-step plan and need not make a model call merely to create that plan.

Client ingress normalizes client-specific shapes and attaches or attests identity through a trusted path. A persona description, model claim, or request body does not establish runtime identity. The mechanism for ingress attestation and the future wire contract are intentionally deferred.

### Interpretation, planning and orchestration

Semantic interpretation identifies the proposed objective, relevant entities/resources, supplied facts and provenance, constraints, preferences, assumptions, information needs, verification needs and ambiguity. Structured client facts pass deterministically; AI may assist with unstructured language, but its output is proposal/evidence rather than authority.

The **planner** determines what work should happen and may propose or revise an outcome-oriented plan based on evidence. It may be AI-assisted. The accepted plan never authoritatively binds a step to a concrete service, tool, model or provider. Non-binding implementation observations or preferences cannot bypass later resolution or policy.

The **orchestrator** is the deterministic Run-state coordinator. It evaluates readiness, dependencies and waiting conditions; applies policy and scope checks; resolves eligible capabilities/services; records outcomes; and invokes planning or replanning when required. A planner does not directly commit a Run transition or dispatch an action.

Services and executors return structured results, blockers, concerns, or additional capability needs. They do not rewrite the Run objective or global plan, expand Home Lab's work graph, or create additional Runs independently. Their internal activity remains within dispatched scope.

## Run lifecycle and ownership

Every accepted **new work request** creates a Run, including simple one-step work. Information supplied specifically in response to a Run waiting for required input resumes that Run; a message or request envelope is not automatically unrelated new work.

The Run objective is immutable on acceptance. Evidence and clarification may refine the plan or Definition of Done only when consistent with the accepted objective, binding client requirements and applicable constraints. A Definition of Done change cannot redefine the requested outcome or remove a required acceptance condition because it became difficult. Material ambiguity requires clarification, replanning, partial completion, failure, or escalation rather than successful completion by reinterpretation. Materially different work creates a new Run, which may supersede the earlier Run while preserving its history.

A Run may wait and resume, depend on other Runs, be cancelled, fail, complete partially or fully, or be superseded. Waiting and interruption are not success; partial outcome remains distinct from full completion. Run relationships use structured signals, results and artifact references, not unbounded inherited histories or direct mutation of another Run's state.

Runs are independent of the submitting transport connection, client conversation, and executor session. A Run may use several executor sessions and remains meaningful if one disappears. Client interaction continuity remains client-owned: Factory may be ticket/workflow-centric, Telegram may later have chats/threads/sessions, and automation may have none.

Home Lab owns the durable orchestration record: client and immutable objective; scope and constraints; current plan, steps, dependencies and waits; signals/concerns; executor-session references; results/artifact references; lifecycle state; and telemetry references as needed. It does not thereby own canonical client/domain state. Factory project state remains Factory/project state; Brain knowledge remains in its knowledge domain; artifacts may remain in domain or service storage and be referenced by the Run.

ADR-051 establishes one harness/orchestrator-owned Run lifecycle with split information placement. A content-minimized root-resident control record remains available while `/srv/homelab` is locked for Run/step identity, lifecycle state, restart/reboot recovery, correlation, opaque waiting/blocking visibility and protected references needed for later revalidation. It is not a second lifecycle authority or a general root content store.

Richer or sensitive Run-linked material remains protected or domain-owned by reference: raw objectives/user content, project or Brain material, sensitive plans/Definition of Done, context/prompts, artifact bodies, concern/evidence bodies, rich scope/authorization information and executor-session internals. Root references themselves remain content-minimized where practical. The root lifecycle boundary gains no volume-unlock capability, provider credentials, bearer tokens, secrets or authority-granting material. If a protected reference is unavailable, materially changed or unverifiable as the accepted objective, the Run records the uncertainty rather than silently redefining the objective or claiming continuation/completion.

Unlock or dependent-service recovery is a revalidation opportunity, not automatic permission to resume. The orchestrator revalidates applicable references/resources, identity/authority provenance, revocation, scope, policy, context/evidence and service availability before continuing. Active/waiting control state is durable operational state; completed lifecycle history is durable audit/provenance state. Persistence technology, exact path, schema, serialization, retention duration, detailed backup mechanism, retry/idempotency and process topology remain deferred.

## Capabilities, services, tools and executors

~~~text
plan step -> required Home Lab runtime capability -> eligible service -> tool / provider / executor
~~~

Home Lab owns the canonical runtime capability vocabulary. Capabilities describe stable, implementation-independent abilities or outcomes, such as language.reason, knowledge.retrieve, external.research, project.inspect, project.modify, tests.execute, and future modality abilities. Names advertise neither deployment nor authority. Dynamic service discovery is not decided here.

A capability is not a permission, service or tool. A service implements/advertises capabilities; a tool is a more concrete operation behind a service; an executor is an implementation that performs bounded work accepted by a service. Capability-to-service/tool mappings are security decisions: new or changed mappings require the existing human approval path, while normal deterministic use of an already-approved mapping does not need fresh mapping approval on every dispatch. Applicable tool/action approvals still apply.

Factory may independently own portable or domain-specific requirements/capabilities. When Factory uses the Home Lab adapter/runtime, its execution requirements translate to Home Lab runtime capabilities without forcing Factory's internal vocabulary to match Home Lab's. Validated Factory or project restrictions must survive translation as narrowing Run constraints. Factory's existing pre-activation compatibility contract remains its own: it must refuse activation before work begins when requirements cannot be met and report every missing requirement. Other clients need not adopt Factory's activation model.

A service is a stable, addressable provider of capabilities, but logical responsibility separation alone does not justify a process or deployment boundary. A separate boundary is justified when it must independently hold or enforce credentials, privilege, filesystem/resource view, trust level, state with a different lifetime, machine placement, or an availability/failure boundary. Planner, interpreter, orchestrator and context assembly may remain modules in one harness when no such boundary exists. This preserves credential isolation without prescribing systemd, containers, RPC, sockets, or another mechanism.

## Context and knowledge

Home Lab owns final context selection and assembly for the relevant step, not all source knowledge. Inputs may include client-supplied facts/references, scoped project/domain data, Brain/personal knowledge, external retrieved information, and derived/model-produced information. Planning may use the minimal relevant context needed before a full step context exists.

Project truth remains in the project/domain, and Brain remains its knowledge domain. Retrieved web, repository, API, log, and model-produced material is information with provenance, not authority. Step-specific context is assembled deliberately rather than dumping an entire project or Run history into each inference call. Provenance records source, time and revision where applicable; it supports classification, audit and later explanation while prompts carry only what is needed.

Egress remains governed by ADR-039. An authorized Run/context-assembly path may select content only within authenticated client exposure, Run/project/resource scope, applicable privacy/egress policy and service-enforced boundaries. Secrets never leave; third-party/personal data requires the existing new-decision gate; providers must be approved. Logs, journals, unit files, configuration and allowlists are not automatically included merely because they can be read. AI can propose relevant context but cannot authorize egress or broaden scope.

Caching is an optimization, not memory. Where provider prompt caching is used, stable instructions/context should precede volatile request/step data when practical. Detailed cache and compaction mechanisms remain deferred.

## Model routing and provider access

Three distinct concepts must not be collapsed:

| Concept | Meaning |
|---|---|
| **Client actor/persona** | Client/workflow context; not a runtime identity claim or universal model selector |
| **Inference purpose/task requirements** | What an individual inference call needs |
| **Provider/model route** | The eligible route selected by Home Lab policy |

Role is not the future universal Home Lab routing abstraction. Inference requirements and AI-generated complexity assessments are advisory inputs. Deterministic policy selects an eligible provider/model using applicable quality, context-size, availability, privacy, cost/safety and latency constraints. A client, planner or model cannot select a route by naming a provider/model or asserting that work is difficult.

Provider abstraction, configured model registry, provider eligibility, credential isolation, fallback controls, and fail-closed spend controls remain binding under ADR-025, ADR-026 and ADR-033. The Vercel AI Gateway is the accepted metered-provider implementation behind that abstraction; callers above it do not name providers. Existing role-based routes are delivered compatibility behavior until a later versioned contract replaces them, not the target abstraction.

## Authority, policy and service enforcement

> **AI proposes. Policy decides. Services enforce.**

~~~text
authenticated/attested client + valid delegated/request authority + request constraints
  -> Run
  -> planner proposes
  -> orchestrator validates
  -> capability / scope / policy resolution
  -> service
  -> tool / executor
~~~

A Run cannot exercise more authority than the initiating client/human validly delegated for that request. Authentication and client exposure alone are not authority. Effective Run authority is bounded by the intersection of authenticated/attested client authority, explicit delegated/request authority, validated client/domain restrictions, Run/project/resource scope, Home Lab policy and service-enforced boundaries.

Constraints only narrow downstream. No model, retrieved or supplied content, persona, other Run, planner output or executor can broaden authority, project/resource scope or policy. Required approval is a separate trusted decision; a plan, completion criterion, artifact, or dependency cannot manufacture it. Supplied content cannot rewrite runtime identity or authorization provenance, and logical Runs/personas/executors do not acquire OS accounts or credentials merely by existing.

Client exposure is the first authorization boundary: a client reaches only explicitly exposed services, default exposure is none, and system-control services remain unreachable from Factory and other project-work clients under ADR-044. Exposure refusal remains distinct from a subordinate capability/scope/policy refusal.

Services enforce their own hard credential, privilege, filesystem, resource and trust boundaries. A narrowly privileged service may have an independently granted, bounded mandate, but invocation does not transfer that authority to a caller, planner, Run, model or another service. Its requests and returned information remain bounded by permitted operation and data-sharing scope.

Only structured proposed operations enter checked dispatch. Identity, scope, approved mappings, tool/target policy, budgets and required approvals are checked before action. Replanning or resuming cannot reuse approval for a materially different action. Applicable policy revisions are recorded; ordinary additions do not widen in-flight work, while security revocation and emergency suspension apply immediately, including before resumption. Provider processes retain no ambient host tools, and untrusted content remains untrusted through every boundary.

The checked-dispatch transition described by ADR-034 §13 requires a separately implemented and validated enforcement path. Until then, the current inert-output/canary property stands. This target architecture does not authorize unrestricted tool loops.

## Execution architecture and modalities

~~~text
Home Lab Run / orchestrator
  -> execution service
  -> Claude Code | Codex | future NativeHomeLabExecutor
~~~

Mature coding harnesses may initially own bounded inner coding loops. Their sessions, micro-plans, compaction, local tool loops and prompt cache are executor implementation state, not canonical Home Lab Run state. Claude Code and Codex are executor implementations, not canonical Home Lab agents. A native executor can later use the same seam without changing the Run contract.

The architecture is modality-neutral. Text, code, structured data, images, audio and future modalities use the same request, Run, capability, service and result/artifact model rather than creating a separate orchestration architecture.

## Work plane, control plane and telemetry

| Plane | Responsibilities |
|---|---|
| **Work plane** | Requests, Runs, plans, context, capabilities, services and execution |
| **Control plane** | Provider/model and routing configuration, capability/service configuration, client exposure, node/resource availability, system health and safety configuration |

Ordinary work-plane Runs cannot modify control-plane state merely because a planner proposes it. Configuration is evaluated at dispatch time; later or resumed work uses applicable current policy without silently broadening authority. This document does not design a control-plane UI.

Telemetry is foundational to the work plane and later evaluation. Record, as applicable, Run/step correlation, capability/service, model/provider, latency, token and cache metrics, cost, retries/replans/waits, and final status. It may correlate with completed Run history, but is not the authoritative Run lifecycle record and need not share its retention or backup policy. Evaluation is a later use of this evidence; no evaluation framework is selected here.

## Current delivered baseline and compatibility

This document is not the detailed deployed-state record; current-architecture.md, project state and phase handovers remain the source for that. The short compatibility baseline is:

- The Phase 23.0 loopback harness endpoint and Factory adapter are delivered. Its required role, declared client label, content-free audit and return-and-forget behavior are historical delivered compatibility, not durable Run semantics or attested identity.
- The model registry/configuration, metered gateway integration and fail-closed spend governor were delivered in Phase 15.0/15.1. Their provider abstraction, registry and governor controls remain binding; current route details are not target vocabulary.
- Existing Telegram routing and subscription helper paths remain delivered compatibility. They are not the generic request/Run/orchestration contract.
- ADR-045 resolved the earlier roadmap ownership collisions: Phase 15 owns routing, 15.0 registry, 15.1 gateway/governor, and Phase 23 is split into 23.0–23.3. ADR-050 does not reallocate phases.

Future migration must preserve version compatibility explicitly. It must not retroactively label Phase 15, Phase 20.0, Phase 23.0, or accepted ADR history as if they had already implemented the new Run contract.

## Cross-cutting constraints that survive

- **ADR-025 / ADR-048:** credential access remains isolated at the helper/socket boundary; callers do not acquire provider credentials or the ability to name an arbitrary program.
- **ADR-033:** provider abstraction, gateway routing, model registry/configuration and fail-closed spend controls remain; no paid call proceeds when the governor is unavailable.
- **ADR-037 / ADR-046 / ADR-051:** canonical knowledge/project content stays on encrypted storage and degraded-until-unlocked is normal. The accepted Run boundary keeps content-minimized lifecycle control state root-resident without granting root volume-unlock capability; richer content remains protected or domain-owned by reference.
- **ADR-038 / ADR-047–049:** component placement, loopback exposure, separate accounts and bounded operator access remain. A logical Run inherits no OS-account authority.
- **ADR-039:** deliberate, attributable context selection and egress restrictions remain.
- **ADR-040 / ADR-043 / ADR-044:** autonomous work remains governed; ADR precedence and scope boundaries remain; client exposure precedes subordinate authorization.
- **ADR-045:** phase ownership and sequencing remain unchanged until a later decision says otherwise.

## Deliberate deferrals

This target establishes responsibility seams without choosing Run persistence technology, exact path, detailed Run schema/serialization, retention duration, detailed backup mechanism, ingress attestation mechanism, future request/wire version, retry/idempotency mechanism, dynamic service discovery, complex per-Run budgets, scheduler design, cache implementation, evaluation framework, physical process topology, or phase reallocation.

Those questions must be settled only when concrete evidence and an owning bounded task require them. Their deferral does not weaken current exposure, egress, approval, credential-isolation, provider-governor, or service-boundary controls.
