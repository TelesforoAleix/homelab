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
