# ADR-002: Use the M700 as an orchestration node, not a local-LLM workstation

- **Status:** Accepted
- **Date:** 2026-09-08

## Context

The M700 has an efficient older CPU and limited expansion suitable for infrastructure services but not modern CUDA-centric local AI experimentation.

## Decision

Use the M700 for orchestration, agents, services, storage/indexing, and remote tooling. Add a separate NVIDIA/CUDA-capable machine later if local AI becomes justified.

## Alternatives considered

Attempt to maximize the M700 for local CPU inference; replace it immediately with a GPU workstation.

## Consequences

The initial build remains cheap and power-efficient. Local-model learning becomes a later multi-node expansion rather than an early blocker.
