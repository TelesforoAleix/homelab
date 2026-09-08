# ADR-011: Do not run user-facing AI interfaces as root

- **Status:** Accepted
- **Date:** 2026-09-08

## Context

Telegram and future AI interfaces may eventually trigger system actions. Giving the interface process unrestricted privileges would create unnecessary risk.

## Decision

Run bot/router services unprivileged and introduce controlled executors/escalation for operations that genuinely require additional permissions.

## Alternatives considered

Run the bot as root for convenience; give broad passwordless sudo immediately.

## Consequences

Some operations will require additional design, but privileges remain explicit and auditable rather than ambient.
