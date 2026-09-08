# ADR-013: Keep main as a known-working state

- **Status:** Accepted
- **Date:** 2026-09-08

## Context

The repository is both a portfolio artifact and operational source of truth. Unfinished experiments should not make the primary branch unreliable.

## Decision

Keep `main` in a known-working state and use feature/experiment branches for unfinished work.

## Alternatives considered

Commit all experimentation directly to main; create a complex GitFlow model immediately.

## Consequences

Branching remains simple while preserving a reliable default branch.
