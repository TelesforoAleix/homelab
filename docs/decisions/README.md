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
