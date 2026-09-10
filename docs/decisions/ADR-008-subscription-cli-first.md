# ADR-008: Use subscription-backed AI CLIs first where officially supported

- **Status:** Accepted
- **Date:** 2026-09-08

## Context

The owner already has access to Claude and ChatGPT subscriptions and wants to compare subscription-backed CLI workflows with APIs later.

## Decision

Start with Claude Code CLI and OpenAI Codex CLI using officially supported subscription authentication where available. Introduce direct API billing intentionally in later experiments.

## Alternatives considered

Start with direct APIs and API keys; start with only local models.

## Status note (2026-09-10)

This ADR's closing sentence — *"Introduce direct API billing intentionally in later experiments"* —
has been taken up by [ADR-026](ADR-026-multi-provider-model-access.md). ADR-026 **discharges** this
decision rather than superseding it: the sequencing was start-with-subscriptions, and that sequence
has now advanced. Subscription-backed CLIs remain in use.

Recorded because the Phase 09 handover compressed this ADR to "no API keys, no paid overage", which
is stricter than what it says, and that reading briefly became load-bearing.

## Consequences

Early experimentation avoids unnecessary API architecture/cost while preserving later API comparison as a learning phase. Supported authentication must be verified at implementation time.
