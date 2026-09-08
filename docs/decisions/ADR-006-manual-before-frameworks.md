# ADR-006: Build explicit router/executor layers before adopting an agent framework

- **Status:** Accepted
- **Date:** 2026-09-08

## Context

The project's primary objective is learning how AI systems are assembled. Starting with a large agent framework would hide useful architecture.

## Decision

Build a simple interface -> router -> executor -> tool/model flow manually before comparing agent frameworks.

## Alternatives considered

Start directly with a multi-agent/agent framework; build one monolithic bot.

## Consequences

Early implementations may be less feature-rich but will make later framework comparisons meaningful.
