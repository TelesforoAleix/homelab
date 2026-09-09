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
