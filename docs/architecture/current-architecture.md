# Current Architecture

- **State:** Delivered system through Phase 23.0 and Phase 15.1. This document records deployed behavior; accepted ADR-050 describes a later target contract and is not presented here as implemented.
- **Evidence:** Completed Phase 15.0, 15.1, 20.0 and 23.0 handovers, plus ADR-047 through ADR-049 and the established storage, placement and credential decisions.

## Current topology

The reference node runs all deployed Home Lab and Factory components. The MacBook is an administration/client machine; it is not a host for the running system. The encrypted data volume at /srv/homelab contains the repository clones, Factory and project content. It is locked at boot and unlocked manually over SSH. Components that need that content wait for the volume; the harness remains available because its small operational state is on root.

~~~text
Factory Workbench
  -> loopback HTTP, 127.0.0.1:8766
  -> homelab-harness endpoint
  -> UNIX socket, homelab-model group
  -> homelab-model-helper
  -> configured provider/model choice
  -> Claude CLI | Codex CLI | Vercel AI Gateway

Telegram bot
  -> UNIX socket, homelab-model group
  -> homelab-model-helper
  -> configured provider/model choice
~~~

The Telegram path still bypasses the harness. It uses the delivered /ask model-helper operation directly; it is not yet a generic client of the endpoint. The current split is deliberate: the harness has no delivered capability that requires the bot to use it, and both paths share helper-level controls.

The two loopback listeners are:

- Factory Workbench on 127.0.0.1:8765, reached remotely only through an SSH local forward.
- The harness endpoint on 127.0.0.1:8766.

The Telegram bot long-polls and has no listening socket. Every listener is accounted for and bound to its stated interface under ADR-038.

## Delivered request paths

### Factory Workbench through the harness

The Factory Workbench runs as homelab-workbench.service and invokes its configured homelab adapter for the Workbench run action. The adapter’s contract was proved in Phase 23.0 against the fake adapter: project records differ only in the expected adapter/result fields. Factory continues to own ticket/workflow records and writes them into project ops state; the harness does not own or update Factory workflow state.

The delivered harness is a synchronous HTTP endpoint. It validates a version-1 closed request schema, deterministically classifies it, optionally forwards a supported question to the helper, returns a response, and writes a content-free audit line. It does not retain the request as generic Home Lab work for later lifecycle processing.

The current v1 request is a compatibility contract. A served question requires its question content and a role routing key. The body is a closed schema: identity-shaped fields, including client, origin, user, peer, request_id and timestamps, are refused by name. The endpoint accepts X-Homelab-Client as a declared client label and records it as client_declared. This is **not authenticated or attested client identity**.

Classification is deterministic and deliberately narrow:

| Class | Current endpoint behavior |
|---|---|
| question | Forward to the model-helper and synchronously return the result |
| task | Refuse as needs_decomposition |
| command | Refuse as not_a_request |
| unclassifiable | Refuse with its classification reason |

Structural work signals override a client-declared kind. This is a narrow compatibility classifier, not semantic WorkIntent interpretation or a planner.

For a question, the harness forwards the role, bounded question, supplied context string and non-selecting hints to the model-helper. It returns the helper’s result and a request identifier to the adapter. The Workbench records that identifier through its delivered side channel because Result has no generic correlation field. The endpoint’s own audit record contains identifiers, labels, enums and lengths, not request text or copied context. This is synchronous return-and-forget behavior: the client records its own result/workflow state, while the harness records an audit event.

The harness currently owns schema validation, declared-origin labelling, deterministic classification, question forwarding, helper health probing and content-free audit. It does not own durable Runs, semantic WorkIntent, a planner, a Run orchestrator, capability resolution, generic service routing, context assembly, waiting/resume, replanning, structured signals/concerns or a generic artifact lifecycle.

### Telegram through the model-helper

The Telegram bot remains the earlier Interface -> Router -> Executor path. Its router is a command router, not the generic harness request endpoint. It has two allowlists and a fixed registry of executors. The bot is not simply “read-only”: its ordinary status/model behavior is unprivileged, but a narrowly scoped restart action exists. It is constrained by the bot authorization path and a polkit grant for one user, one unit and one verb; the bot receives no sudoers entry or general host authority.

The bot’s /ask operation reaches the model-helper directly over the UNIX socket. Model output is returned as text and is not dispatched. The Phase 09 canary property still applies: model-shaped commands remain inert because no checked tool-dispatch path is implemented.

## Current model routing and invocation

The model-helper is the current provider boundary. It owns provider adapters, model registry/configuration, route selection, subscription count limits, gateway access and spend enforcement. The caller supplies a role/route key; the registry resolves it to an ordered set of eligible provider/model choices. Existing role routing is delivered compatibility. Inference-purpose/task-profile routing from ADR-050 is not implemented.

Delivered provider mechanisms are:

| Provider mechanism | Current role |
|---|---|
| Claude CLI | Subscription-backed provider adapter |
| Codex CLI | Subscription-backed provider adapter |
| Vercel AI Gateway | Metered provider adapter behind the same provider abstraction |

Provider/model configuration is in the model-helper’s controlled configuration. Callers above the helper cannot name an arbitrary provider/model or program. The gateway path uses a credential supplied through LoadCredential; the subscription CLIs run where their existing owner credentials are accessible. This preserves the credential boundary: bot, harness and operator account do not receive provider credentials.

The helper retains subscription count caps and provider eligibility controls. For the metered gateway, the Phase 15.1 spend governor is active: it persists its ledger, applies hour/day/week/month windows separately for attended and unattended work, reserves before egress, settles usage afterward, and fails closed when its state cannot be read or validated. Metered-provider configuration and the governor are delivered, not future gaps. Detailed current routes/models remain configuration, not an architecture contract.

Current complexity, priority, severity and summary fields are logged/advisory hints; they do not select a model or bypass a cap/governor check. Existing route selection is still keyed by role rather than the target inference-purpose vocabulary.

Claude Code and Codex are currently provider/CLI mechanisms behind the model-helper. They are not an implemented generic execution service or Home Lab executor abstraction. The delivered helper invokes models with the existing no-tools/canary protections; it does not provide a generic coding-agent loop.

## Current context and result handling

Current context handling is deliberately limited. The endpoint accepts client-supplied context items and renders them for the helper; it adds no retrieved project, Brain, web, log, journal, configuration or allowlist content. It carries supplied source information when present. Factory’s delivered adapter sends no selected ticket context, so actual Factory endpoint requests currently have empty context.

There is no delivered generic context-selection or provenance-assembly system. No complete project, conversation history or Run history is assembled into calls. ADR-039 still governs any content that may leave the node; the current endpoint does not turn client-supplied context into authorization.

The endpoint returns a synchronous model result. Factory decides whether and how to record it in its own project workflow. Telegram returns text to the chat. There is no current generic result/artifact store or artifact lifecycle.

## Deployed processes and boundaries

| Component | Current boundary and responsibility |
|---|---|
| **Factory Workbench** | Runs as aleix, not a dedicated Workbench account. ADR-047 deliberately retained this account/sandbox design; its sandbox, loopback binding and volume dependency are the boundary. It writes Factory/project records and cannot directly reach the helper socket because it lacks AF_UNIX access. |
| **Harness endpoint** | Runs as homelab-harness with no shell, home, sudo, Docker membership or provider credential. It binds loopback and has AF_UNIX only to reach the helper. Its root StateDirectory holds the content-free audit file and permits it to remain available while the encrypted volume is locked. |
| **Model-helper** | Runs as aleix because it is the credential holder. Its UNIX socket is aleix:homelab-model:0660; access is kernel-enforced by the dedicated homelab-model group, not a Python caller check. |
| **Telegram bot** | Runs as homelab-bot, long-polls outbound, has no provider credential and no general privileged account. It is a member of homelab-model solely to connect to the helper socket. |
| **Watchdog/notifier** | Uses the bot’s outbound notification capability for boot and failure reporting; it has no model path. |
| **Operator account** | homelab-agent is an operator account for an executor agent on the MacBook, not a Home Lab runtime agent or service account. It has its own key and a bounded NOPASSWD command list, but no provider credential, Docker, aleix or homelab-model membership. |

ADR-048 fixes the socket consumers as exactly homelab-bot and homelab-harness. A third account outside that group is refused at the socket. ADR-049’s separate operator account does not change the helper or harness authority model.

The encrypted data volume holds canonical repositories, project records and Brain content. The Workbench is volume-dependent and is skipped while locked. The harness audit file and model-helper operational ledgers are persistent node state, but do not make root a store for canonical project/knowledge content.

## Current persistence and lifecycle

Persistent records currently include:

- Factory project/ops records, including Factory’s own run/workflow records;
- the harness content-free audit JSONL on root;
- model-helper count and spend ledgers, including the fail-closed gateway governor state;
- configuration, unit, account/group and backup/recovery records for the operational services;
- encrypted-volume repository/project/Brain data and their backup state.

These records do not constitute a first-class durable Home Lab Run. The current endpoint does not keep a global objective, mutable plan, step states, dependencies, waiting conditions, executor-session references, concerns/signals or generic results/artifact references. It cannot resume waiting work because no such lifecycle exists. A Factory run record or endpoint request_id is not an ADR-050 Run.

## Current gaps relative to the accepted target

The accepted target is not yet delivered in these areas:

- canonical authenticated/attested client identity and delegated Run authority;
- durable Home Lab Runs with immutable objectives, waiting/resume, dependencies and supersession;
- semantic WorkIntent interpretation, general planner and deterministic Run orchestrator;
- implementation-neutral plans, Home Lab runtime capability resolution and generic service routing;
- step-specific context assembly and provenance management;
- generic execution-service/executor integration, structured concerns/signals and artifact lifecycle;
- target inference-purpose routing that replaces role keys;
- checked model-operation dispatch under the ADR-034 §13 transition.

These are target gaps, not instructions to replan or implement them here. Their migration, storage, wire-contract and phase-allocation decisions remain separate work.

## Current security and compatibility invariants

- Client origin at the v1 endpoint is declared metadata, not identity; loopback/local-process trust is the current boundary.
- Existing role routing, closed schema behavior, task/command refusal, synchronous return-and-forget behavior and the Factory adapter remain delivered compatibility mechanisms until a later contract replaces them.
- Credential isolation, socket-group access, loopback placement, encrypted-volume separation, provider registry/governor controls, egress policy and structural refusals remain active constraints.
- Model, retrieved and client-supplied content does not currently gain authority or tool dispatch. The accepted target’s fuller authority/Run contract is not implemented merely by accepting ADR-050.

