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

- [`ADR-027-agent-contract.md`](ADR-027-agent-contract.md) — the agent contract: system agents
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
