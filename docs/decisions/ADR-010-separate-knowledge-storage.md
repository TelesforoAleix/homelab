# ADR-010: Separate knowledge storage from agent intelligence

- **Status:** Accepted
- **Date:** 2026-09-08

## Context

The project will later explore RAG, hybrid search, graph approaches, and memory systems. Coupling files directly to one agent would make replacement harder.

## Decision

Keep source files/storage independent. Index/retrieve through a knowledge layer that agents can query.

## Alternatives considered

Let each agent own its own copy/store of user files.

## Consequences

Knowledge infrastructure can evolve independently from model/agent implementations.
