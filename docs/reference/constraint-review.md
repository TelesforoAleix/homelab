# Architectural Constraint Review

- **Originally written:** 2026-09-11
- **Reconciled:** 2026-09-17
- **Purpose:** The forward-planning constraint set for roadmap reconciliation. It distinguishes
  delivered facts, binding decisions, ADR-050/ADR-051 target requirements and deliberately deferred work.
- **Authority:** Accepted ADRs govern. In their scoped successor areas, accepted
  [ADR-050](../decisions/ADR-050-core-execution-contract.md) and
  [ADR-051](../decisions/ADR-051-run-orchestration-state-boundary.md) take precedence over the historical
  analysis below. [ADR-045](../decisions/ADR-045-roadmap-reshape.md) remains authoritative for phase
  allocation until a later decision changes it.

## How to use this review

This is not a roadmap or implementation plan. A future roadmap/brief must respect every **still
binding** and **binding but reinterpreted** constraint below. **Satisfied/delivered** entries are
evidence and compatibility constraints, not missing work. **Historical** and **superseded** entries
are retained to explain decisions but must not be used as present blockers. **Deferred/open** entries
need an owning design/planning decision before implementation depends on them.

The detailed deployed-state source is [current architecture](../architecture/current-architecture.md).
The accepted destination is [target architecture](../architecture/target-architecture.md), governed
by ADR-050 and ADR-051. [Project state](project-state.md) provides the concise delivery/planning summary.

## Forward-planning constraints

### Delivered system and compatibility

| Status | Constraint future work must respect |
|---|---|
| **Still binding** | Provider credentials remain in the model-helper. The harness, bot and operator account do not acquire them; socket-group and account boundaries remain enforcement boundaries (ADR-025, ADR-048, ADR-049). |
| **Still binding** | The model registry/provider abstraction, configured eligibility, subscription caps, metered Vercel AI Gateway and persistent fail-closed spend governor are delivered controls. Callers do not select arbitrary providers or programs (ADR-026, ADR-033). |
| **Still binding** | Listening sockets are accounted for and bound to their approved interface. Workbench and harness are loopback-only; Telegram remains outbound long-polling (ADR-038). |
| **Still binding** | The Workbench runs as `aleix`; its systemd sandbox—not a dedicated account—is its accepted trust boundary. Its `ProtectHome`, strict root protection, restricted writable volume and no-`AF_UNIX` properties remain load-bearing (ADR-047). |
| **Still binding** | Canonical project/knowledge content is on the encrypted `/srv/homelab` volume. Degraded-until-unlocked is normal. The root-resident harness audit and helper ledgers do not make root a canonical content store (ADR-037, ADR-046). |
| **Satisfied/delivered compatibility** | Phase 23.0 provides a version-1, synchronous harness endpoint: closed-schema validation, declared client label, deterministic classification, required role key for served questions, forwarding, content-free audit and return-and-forget behavior. Telegram still calls the helper directly. These are current compatibility mechanisms, not the target contract. |
| **Satisfied/delivered compatibility** | Factory Workbench owns project/workflow records and uses the delivered `homelab` adapter. The adapter proof remains valid. Factory’s existing pre-activation compatibility checks, including reporting missing requirements, remain its domain contract. |

### Accepted target requirements not yet implemented

| Status | Constraint future work must respect |
|---|---|
| **Binding but reinterpreted by ADR-050** | Home Lab core is agent-agnostic. Persistent agents, personas, teams, roles and workflows belong to clients/domains such as Factory; they may be context, never automatic runtime identity or authority. |
| **Binding but reinterpreted by ADR-050** | Existing role-key routing remains compatibility. The future model-routing vocabulary separates client actor/persona, inference purpose/task requirements and provider/model route. Model or AI-derived complexity assessments are advisory only. |
| **Binding but reinterpreted by ADR-050** | Home Lab owns the generic runtime capability vocabulary between planned work and eligible services. Capabilities describe implementation-independent abilities, are not permissions, and are distinct from tools and services. Factory may retain an independent portable/domain requirement vocabulary; its adapter maps it only when executing through Home Lab. |
| **Binding but reinterpreted by ADR-050** | Factory restrictions validated at its adapter boundary continue to narrow the resulting Run. Factory workflow semantics, tickets, roles and Definition of Done do not become Home Lab primitives. |
| **Binding, not yet delivered** | Every accepted new work request creates a durable Home Lab Run with an immutable objective. A waiting Run resumes on its required input; materially different work creates a new Run. Plan and Definition of Done may refine only within the accepted objective and binding requirements. |
| **Binding, not yet delivered** | ADR-051 fixes the Run persistence/trust/availability boundary: the harness/orchestrator owns one generic Run lifecycle; content-minimized control state remains root-resident and available while `/srv/homelab` is locked; richer/sensitive content remains protected or domain-owned by reference. Root gains no volume-unlock capability, provider credential, bearer token, secret or authority-granting material. Unlock or dependency recovery requires revalidation, not automatic resume. Active/waiting control state is durable operational state; completed lifecycle history is durable audit/provenance state distinct from telemetry. |
| **Binding, not yet delivered** | Planner and orchestrator are distinct logical responsibilities. The planner proposes outcome-oriented work; the orchestrator deterministically manages Run state, readiness, policy/scope checks, capability/service dispatch and replanning. They need not be separate processes. |
| **Binding, not yet delivered** | An accepted plan does not authoritatively bind a concrete service, tool, model or provider. Resolution is `plan step -> runtime capability -> eligible service -> tool/provider/executor`. A service/process boundary needs an independent credential, privilege, resource/filesystem view, trust, state-lifetime, placement or availability/failure reason—not merely separation of code responsibilities. |
| **Binding, not yet delivered** | The authority invariant is **AI proposes. Policy decides. Services enforce.** Initiating/delegated authority is a ceiling; validated client/domain restrictions and all downstream constraints only narrow it. Supplied/retrieved/model content, personas, planners, executors and other Runs cannot grant authority or rewrite provenance. Independently privileged services do not transfer their authority to callers. |
| **Binding, not yet delivered** | Context selection remains within client exposure, Run/resource scope, egress/privacy policy and service boundaries. Retrieved/model-produced content remains untrusted. The current endpoint's client-supplied context pass-through is not the target context/provenance system. |
| **Binding, not yet delivered** | Model-proposed operations remain inert until the separately implemented ADR-034 §13 checked-dispatch transition validates identity, scope, mappings, policy, target, budget and approvals. Immediate revocation and existing egress/provider controls survive. |

### Phase and governance constraints

| Status | Constraint future planning must respect |
|---|---|
| **Still binding** | ADR-043 preserves accepted-ADR precedence and permits living architecture specifications without treating them as a separate implementation phase. Completed handovers remain historical evidence. |
| **Still binding** | ADR-045 retains phase numbers and assigns Phase 15 to routing, 15.0 to registry, 15.1 to gateway/governor, and Phase 23.0–23.3 to the former endpoint/understanding-result, decomposition-service-routing, context, and governance scopes respectively. No phase may silently claim another phase's scope. |
| **Still binding** | ADR-050 and ADR-051 do not reallocate phases. The reconciled roadmap retains ADR-045's 23.1/23.2/23.3 ownership: 23.1 implements the minimal Run/orchestrator, planning and capability-routing seams; 23.2 owns context/provenance; 23.3 owns trusted authority and checked dispatch. Any changed allocation still requires an explicit successor decision, not a brief-level rewrite. |
| **Satisfied/delivered** | The earlier collision over model routing, registry and gateway/governor was resolved by ADR-045 and delivered through Phases 15.0 and 15.1. It is not a roadmap blocker. |

## Persistence mechanics and ingress decisions intentionally open

The following are architectural seams, not permission to improvise an implementation:

| Status | Open decision |
|---|---|
| **Deferred/open decision** | Persistence technology, exact path, detailed Run schema/serialization, retention duration and detailed backup mechanism. ADR-051 fixes the information-placement, ownership and locked-volume boundary without choosing these mechanics. |
| **Deferred/open decision** | Trusted ingress/client attestation and the next request/wire/correlation version. The delivered `X-Homelab-Client` label is not identity or delegated authority. |
| **Deferred/open decision** | Retry/idempotency, scheduler design, dynamic discovery, complex per-Run budgets, caching, evaluation, physical process topology and phase reallocation. These must preserve existing exposure, egress, approval and spend constraints. |

## Historical resolution register

The original 2026-09-11 review produced ADR-037–ADR-044. The table preserves each material
conclusion and its current classification so an old premise is not reused as a future blocker. The
accepted ADRs and completed handovers retain the contemporaneous detailed reasoning and evidence.

| Original topic | Current classification | Current interpretation |
|---|---|---|
| ADR-032 content gate | **Satisfied/delivered; still binding boundary** | ADR-037 delivered encrypted volume storage for canonical project/knowledge content. Do not treat the old absence of encrypted storage as a blocker; do keep encrypted-content and locked-volume constraints. |
| ADR-025 §8 egress enumeration | **Binding but reinterpreted** | ADR-039's egress restrictions survive. ADR-050 generalizes the selection subject from an approved agent to an authorized Run/context-assembly path; content never grants egress authority. |
| ADR-025 §9 owner-initiated calls | **Superseded** | ADR-026/ADR-040 replaced attribution with governed autonomous work. The delivered provider eligibility, caps and spend governor remain binding; complex per-Run allocation is deferred. |
| ADR-020 console-less premise | **Superseded; safety rule still binding** | ADR-041 records the console-on-demand reality and retains the headless safe-change classification rule. |
| ADR-023 no-listening-socket rule | **Satisfied/delivered and generalized** | ADR-038's bind/accounting policy governs listeners. The bot remains outbound-only; loopback Workbench and harness listeners are delivered. |
| ADR-031 standalone adoptability | **Superseded/narrowed** | ADR-042 makes `homelab` public and readable rather than packaged for standalone adoption; Factory's clean-clone/workflow boundary remains meaningful. |
| ADR-017 phase model | **Binding but reinterpreted** | ADR-043 retains sequential self-contained phases while recognizing cross-cutting contracts and living specifications. |
| ADR-033 §5 governor | **Satisfied/delivered; still binding** | The Phase 15.1 governor is active. The old absence of a gateway/governor is not a blocker; governor failure remains fail-closed. |
| ADR-034 agent/capability/service gap | **Binding but reinterpreted** | ADR-044 preserves exposure-before-subordinate-authorization. ADR-050 supersedes the generic agent/capability subject with agent-agnostic Runs, Home Lab runtime capabilities and meaningful service boundaries, while retaining Factory activation/compatibility obligations. |

## Concise checklist for roadmap replanning

Any new roadmap proposal must demonstrate that it:

1. preserves current credential, account, socket, egress, encrypted-content, provider and spend
   boundaries;
2. distinguishes delivered Phase 23.0 compatibility from ADR-050 target behavior;
3. implements no Home Lab system-agent, universal-role or Factory-owned-generic-capability premise;
4. preserves Factory's workflow independence and restriction-narrowing when it uses Home Lab;
5. treats durable Runs, trusted authority, implementation-neutral planning and capability-mediated
   service resolution as target requirements, not existing components;
6. allocates work consistently with ADR-045 or raises the required successor decision; and
7. leaves deferred persistence mechanics, attestation, protocol and process decisions open until an owning,
   evidence-based design task resolves them.

## Historical questions

The original review's seven owner questions were answered by ADR-037–ADR-044 and later delivery.
They are not open questions now. The remaining open decisions are those listed in the storage,
ingress and lifecycle section above.
