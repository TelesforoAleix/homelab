# Architectural Decision Records

ADRs capture durable project decisions and their reasoning.

## Status values

- Proposed
- Accepted
- Superseded
- Rejected

## Rule

Do not rewrite an accepted ADR to erase project history. If the architecture changes, create a new ADR and mark the previous one as superseded.

Use [`../templates/adr-template.md`](../templates/adr-template.md) for new records.

## Recent records

- [`ADR-022-docker-runtime-conventions.md`](ADR-022-docker-runtime-conventions.md) — Docker runtime
  and container conventions: rootful daemon, non-root containers, Docker's official apt repository,
  explicit-interface port publishing, Docker group root-equivalence, and log rotation.

- [`ADR-023-telegram-bot-service.md`](ADR-023-telegram-bot-service.md) — the Telegram bot as a
  native systemd service: long polling so there is no listening socket, an allowlist checked before
  dispatch, `LoadCredential` rather than an environment variable for the token, and a dedicated
  account in no privileged group.

- [`ADR-024-router-executors.md`](ADR-024-router-executors.md) — router/executor architecture and
  the escalation boundary: executors register in a registry, the authorisation check lives in one
  function, and the single privileged action is granted by polkit scoped to one user, one unit and
  one verb — chosen over `sudo`, which `NoNewPrivileges=yes` refuses outright.

- [`ADR-025-subscription-backed-model-access.md`](ADR-025-subscription-backed-model-access.md) —
  subscription-backed model access: the call happens in a helper service that already holds the
  credential rather than the bot ever gaining one, access control lives in the socket unit, the
  model gets no tools, the cheapest model is the default, two providers with independent limits and
  automatic fallback, caps enforced before the call, only the question and `/status` leave the
  machine, and **owner-initiated only** — the constraint that stands in for the unresolved
  licensing question.

- [`ADR-026-multi-provider-model-access.md`](ADR-026-multi-provider-model-access.md) —
  multi-provider model access and routing: metered providers become the target substrate with the
  vendor deliberately unnamed, models become configuration rather than code, every provider entry
  carries an `unattended` eligibility field the router enforces structurally, callers declare a need
  rather than a model, and subscription providers may serve unattended calls **as an owner-accepted
  risk** — recorded as a disagreement, with the mechanism keeping it reversible one provider at a
  time. Supersedes ADR-025 §9; discharges ADR-008's "later experiments".

- [`ADR-027-agent-contract.md`](ADR-027-agent-contract.md) — **Superseded in full by ADR-034**
  (2026-09-11); kept as history. The agent contract: system agents
  (homelab) are distinguished from work agents (Factory) by whether they survive The Factory being
  swapped out; an agent declares context, skills, tools, model policy and unattended eligibility but
  **never names a model**; Factory declares and homelab enforces, because enforcement belongs where
  it is enforced; declared tools are intersected with caller authorisation so an agent is never a
  privilege escalation path; an unknown tool name is a load failure rather than a warning.

- [`ADR-028-project-contract.md`](ADR-028-project-contract.md) — the project contract: The Factory
  is stateless method and the project carries all state; every Factory-managed project holds its own
  coordination layer in its own repository; project-local `agents/` **references** Factory rather
  than copying it, because a copy forks silently while a reference breaks loudly; a project may
  narrow an agent but never widen it; each project records the Factory version it ran under.
  Answers the question left open in the Factory workspace `FIRST-USE.md`.

- [`ADR-029-repository-topology.md`](ADR-029-repository-topology.md) — repository topology and the
  method/output boundary: four repositories, with `homelab` and `factory` public and `brain` and
  the product repository private; **method is public, output is private**, tested by asking whether a file would be
  useful to someone with none of the owner's knowledge or history; public repositories ship
  synthetic examples, never samples of real notes; the boundary is enforced by a check validated
  against planted content rather than by care.

- [`ADR-030-workspace-layers-and-project-ops.md`](ADR-030-workspace-layers-and-project-ops.md) — the
  four-layer workspace and where project ops records live: infrastructure, execution, projects and
  knowledge, with `projects/` a plain directory holding one private repository per project; **every
  project carries its own `ops/`** beside the product rather than inside it, which closes the
  question ADR-029 §6 left open by making the Factory's self-hosting records just another project's
  ops; the knowledge base holds knowledge and its own operating layer, nothing else; where a file
  existed in both the knowledge base and Factory the public copy wins, and deletion is gated on a
  counterpart existing rather than on content equality, because anonymisation guarantees the
  contents differ; and links in records are left broken with a translation table rather than
  rewritten, applying `PROJECT.md` §11 to link maintenance.

- [`ADR-031-layer-boundaries-and-standalone-repositories.md`](ADR-031-layer-boundaries-and-standalone-repositories.md)
  — layer boundaries, per-artifact privacy and standalone public repositories: **Factory declares,
  homelab enforces, projects accumulate, brain supplies**, generalising ADR-027 §3 from tools to the
  whole system; a tool is what the runtime can refuse and a skill is what can only be followed;
  **privacy is per-artifact, not per-repository**, which supersedes the visibility tables in ADR-029
  §1 and ADR-030 §1 while leaving ADR-029 §2 intact; each public layer must be independently
  adoptable, which none currently is; the private `brain` is eventually renamed `aleix-brain` and
  becomes an archive while its ~32 method files are extracted into a **new public `brain`**,
  accepting that content written there afterwards has no version history; Factory is rewritten in a
  dedicated phase and cannot start until homelab publishes its tool vocabulary. Records that
  ADR-029's own revisit trigger fired.

  **Amended 2026-09-10**, the same day and before merge, with four further decisions recorded in
  place rather than in a successor: the brain rename and extraction is **deferred as a whole
  operation** and coupled to the new ingestion pipeline and RAG system, leaving the existing private
  `brain` as it is under its current name (§6); the four restored knowledge-base skill files are
  **superseded legacy, not method**, and stay private (§6.1); **agent manifests are JSON**, since
  ADR-027 §2 decided five fields and not a serialisation (§11); and **one plan and one progress
  record, both in homelab** — replacing §9's "each repository's own build plan stays in that
  repository" and superseding Factory's `roadmap.md` and its Locked Decisions, while §4's standalone
  adoptability is preserved because what a public repository ships is the method and the contracts,
  never the owner's roadmap (§4, §9).
- **[ADR-032](ADR-032-encryption-at-rest-reaffirmed-with-a-content-gate.md) — Encryption at rest,
  reaffirmed with a content gate** (2026-09-11, Phase 18). The revisit ADR-015 required. The node
  **stays unencrypted**, and its previously implicit "no sensitive data at rest" premise becomes an
  **explicit gate**: no knowledge base, no project content, no private repository until this is
  revisited. Measured rather than assumed: the console exists after all, so passphrase-at-boot is
  viable; the TPM is 2.0 and enrolment works, but only against the **SHA-1** bank, because
  allocating SHA-256 needs platform authority that firmware deliberately discards before boot; and
  the volume group has zero free extents, so a separate encrypted volume has nowhere to live.
  Reaffirming is a decision; silence would not have been.
- **[ADR-033](ADR-033-vercel-ai-gateway-as-the-metered-provider.md) — Vercel AI Gateway as the
  metered provider** (2026-09-11). Settles the vendor ADR-026 deliberately left unnamed. Its **spend
  governor is a precondition for any paid call**.

- **[ADR-034](ADR-034-agent-contract-capabilities-and-authority.md) — The agent contract: portable
  capabilities, backend tools, and independent authority** (2026-09-11). **Supersedes ADR-027 in
  full**, after the Phase 19 design review rejected its premise before any implementation began.
  **Factory agents declare portable capabilities; execution backends provide concrete tools** —
  homelab is one advanced backend, not a prerequisite, which is what ADR-031 §4's standalone
  requirement demands. A manifest's `capabilities` and `tools` are separate fields, and
  `model_policy` is **removed**: an agent's *role* is its declaration of need, so **ADR-026 §4
  survives intact** — removing the field changes the form §4 itself delegates, not the principle.
  Incompatibility fails **before activation**, naming every missing requirement, rather than being
  discovered at dispatch. One scalar capability level becomes independent **effect / minimum
  approval / availability / target scope** properties. **ADR-027's human ceiling is reversed** for
  service specialists, which may hold narrow independent authority and run unattended — safe only
  because delegation **does not transfer access** and the *receiving* agent validates every
  agent-to-agent request: *"a teammate asked" is never sufficient authorisation.* Identity is
  attached by the runtime and never claimed by the model. **Changes ADR-025 §10** — a model's tool
  request becomes an untrusted request checked by the runtime rather than something architecturally
  inert — but only when tool-using agents are implemented. Records the reversal honestly: the review
  first recommended homelab own the portable names, and the owner overruled it.

- **[ADR-035](ADR-035-factory-workbench-and-execution-adapters.md) — Factory Workbench: Factory
  executes project operations, backends execute AI** (2026-09-11). **Refines ADR-031 rather than
  replacing it** — nine of its eleven sections are untouched. ADR-031 §1's *"fully operational as a
  specification and never executes"* over-claimed: it forbade all execution in order to forbid
  *enforcement*, and writing a ticket into a project's `ops/` enforces nothing. The narrower
  boundary: **Factory Workbench executes Factory project operations; the configured backend executes
  AI and concrete tools.** Workbench holds **no homelab credential, no model registry and no tool
  implementation**, which is where §1's real property lives. AI reaches it through one of several
  adapters — homelab, a direct API key, subscription CLIs, MCP, manual mode, and a **deterministic
  fake** for repeatable tests — of which only the fake is fixed. **Two dashboards, not one that
  moved**: Workbench stays in Factory and owns project views; Phase 22 becomes the homelab
  administration dashboard. **ADR-031 §7's prerequisite on homelab's tool vocabulary is void**, so
  the Factory rewrite is unblocked and the dependency inverts — concrete tools should follow observed
  capability gaps rather than precede them, which is exactly what Phase 19 demonstrated. Local
  Workbench binds `127.0.0.1` with no application login; a hosted one is Tailscale-only and public
  exposure is out of scope. The plan stays in homelab (§9) even though the code lives in Factory.

- **[ADR-036](ADR-036-workbench-write-path-and-runtime.md) — Factory Workbench's write path: a local
  server over a CLI engine** (2026-09-11, Phase 20.0). Resolves the Phase 20.0 brief's §6.1, which
  turned out to be a question **Factory had already framed** — V1.5's exit criterion named "the
  CLI/server/webview bridge decision" and `open-questions.md` asks whether the first bridge should be
  CLI-first. **The CLI is the write engine; a `127.0.0.1` server is a surface in front of it**, so
  adding or removing a surface changes no write semantics. The owner chose click-to-act over the
  smaller CLI-only phase, **overruling the assistant's recommendation**, and the rejected options are
  recorded because the engine boundary keeps them available as a fallback. **The server parses and
  serves JSON so the browser stops parsing records**, which answers the finding that
  `dashboard.js:223` is a hand-rolled YAML subset parser that silently drops nested structure —
  harmless in a viewer, a correctness bug in a writable system. **Python**, on the stdlib where
  possible, with a YAML library as the one accepted dependency; "one language everywhere" would have
  favoured Node but stops being load-bearing once the browser no longer parses. ADR-035 §2's
  boundary is untouched: no homelab credential, no model registry, no tool implementation, loopback
  only, no public exposure.

### Proposed 2026-09-11 — the constraint review's outcome

Eight decisions taken together after [`constraint-review.md`](../reference/constraint-review.md)
tested every accepted constraint against the
[target architecture](../architecture/target-architecture.md). They are listed as one group because they
were decided as one, and several only make sense together.

- **[ADR-037](ADR-037-encryption-at-rest-executed.md) — Encryption at rest, executed.** Discharges
  ADR-032's content gate, which contradicted the architecture: the system is meant to be always
  running and to hold the knowledge, and the gate kept the knowledge off the machine that is always
  running. **Shrink the root LV, put a LUKS volume in the freed extents, leave root unencrypted, and
  unlock over SSH via Tailscale** — which removes the TPM, and with it the SHA-1 binding weakness,
  rather than answering it. **Degraded-until-unlocked is a normal state**: the node returns, the bot
  returns, the AI system waits. Gated on `findmnt -no FSTYPE /`: **if it returns `xfs` this ADR is
  void**, because XFS cannot be shrunk. States honestly that the security value is modest and the
  governance value is the point.

- **[ADR-038](ADR-038-component-placement.md) — Everything runs on the server.** Supersedes ADR-035
  §7's "first real Workbench runs on the MacBook". Harness, Workbench, Factory, projects and `brain`
  all on the node; the MacBook is a client and a terminal. **The harness binds loopback only**, since
  every client is a local process — stronger than a tailnet endpoint. Workbench binds loopback too and
  is reached by SSH tunnel, keeping the OS user boundary as the boundary. ADR-023's property survives
  for the bot, and the measurable rule becomes *every listening socket is accounted for and bound to a
  stated interface*.

- **[ADR-039](ADR-039-egress-policy.md) — What may leave the machine.** Supersedes ADR-025 §8, whose
  reasoning survives intact: content chosen by *whatever can write a log line* still never leaves.
  What changes is the form — an enumeration of two items becomes a policy classifying **by whose data
  it is**. The owner's own material may leave to approved providers; third-party or personal data may
  not without a new decision; secrets never. Tightens in one place on the day third-party data enters.

- **[ADR-040](ADR-040-autonomous-operation.md) — Autonomous operation is normal.** Retires ADR-025 §9
  fully rather than leaving it half-lifted. Scheduled, client-initiated and system-initiated calls are
  ordinary; **budget replaces attribution** as the control, because attribution never controlled spend.
  The licensing question is recorded as an **accepted judgement with reasoning**, not as resolved, so a
  later reader knows it was decided rather than missed. The rejected alternative — route autonomous
  work to metered inference — is kept as the reversal mechanism.

- **[ADR-041](ADR-041-change-safety-revised.md) — The node has a console on demand.** Supersedes
  ADR-020, whose title and premise say "console-less node" and whose premise **Phase 18 disproved**:
  `getty@tty1` active, login authenticated at `seat0/tty1`. Classification before change stays;
  **"lockout-class" is redefined from *unrecoverable* to *recovery requires physical access*** — a cost,
  not a catastrophe. Draws the distinction ADR-020 missed: between what needs a walk and what needs a
  backup. `AGENTS.md` asserted the false premise and is corrected.

- **[ADR-042](ADR-042-readable-not-packaged.md) — Public and readable, not packaged.** Narrows
  ADR-031 §4 for `homelab` only; Factory's standalone adoptability is unchanged and already proved.
  A personal AI operating system holding *your* knowledge and budgets is an installation, not a
  product, and requiring it to run standalone taxed every layer with abstraction for a user who does
  not exist. **Configuration is the seam**: examples published, values not. `homelab` holds the
  knowledge tools; **`brain` holds the knowledge**.

- **[ADR-043](ADR-043-cross-cutting-contracts.md) — Cross-cutting contracts and living specs.**
  Amends ADR-017 narrowly. Sequential self-contained phases stay. A concern applying at every layer is
  **specified once as a normative contract and implemented per scope** — applying ADR-031 §9, which was
  already the rule and was not being used. Two implementations of one contract is the design; the risk
  is drift, and both sides test against the contract. Living specs are legitimate artifacts that
  **decide nothing** — which is what keeps them from becoming the planning context ADR-017 abolished.

- **[ADR-044](ADR-044-client-service-exposure.md) — A declared capability is not a granted
  authorization.** Extends ADR-034 with the boundary it does not cover. **Factory declares what an
  agent is for; Home Lab decides what it will do.** Which services a *client* may reach is checked
  first and is the stronger boundary, and the two refusals must say different things. System-control
  services are unreachable from work clients whatever capability an agent declares — not a statement
  about trust in Factory, but that a client orchestrating autonomous agents is the wrong place to
  accept an instruction that can take the system offline. Fixes the service/capability/tool
  distinction before layer 4 is built.

- **[ADR-045](ADR-045-roadmap-reshape.md) — Reshaping the roadmap around the layer model**
  (2026-09-11). No phase is renumbered; insertions are sub-phases. **Phase 18.1 executes the
  encryption and comes first** — the only pending item needing the owner physically present — with
  **18.2** migrating everything onto the server behind it. **Phase 12 is repurposed, not absorbed**,
  correcting an earlier assessment: the scheduler is a client, but the watchdog and notifier had no
  other home, and they live on unencrypted root so they work before the volume is unlocked.
  **Layer 7 belongs to Phase 15** (15.0 registry, 15.1 gateway *and* governor together per ADR-033 §5,
  15 routing); Phase 23 consumes it. **Phase 23 splits into 23.0–23.3** by layer, because a phase
  spanning five layers cannot write one brief or hand over. Five gaps get homes, including
  **Phase 24 — Web Research**, which had no phase anywhere. **Phase 11 is superseded** — ADR-034 and
  Phase 20.0 answered its question by building the thing.
