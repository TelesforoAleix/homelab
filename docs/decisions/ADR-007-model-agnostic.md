# ADR-007: Keep the system model-agnostic

- **Status:** Accepted
- **Date:** 2026-09-08

## Context

The project is intended to compare subscriptions, direct APIs, hosted providers, gateways, and local models over time.

## Decision

Define model/tool access behind replaceable executors and avoid hard-coding the entire platform around one provider.

## Alternatives considered

Build provider-specific architecture around the first model used.

## Consequences

Some abstraction is required, but it should remain minimal until multiple executors create a real need.
