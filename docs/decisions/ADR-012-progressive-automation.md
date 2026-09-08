# ADR-012: Use progressive automation

- **Status:** Accepted
- **Date:** 2026-09-08

## Context

The learning objective conflicts with automating every setup step before the mechanism is understood, while long-term reproducibility conflicts with leaving everything manual.

## Decision

Perform processes manually when that materially improves understanding, then automate repeatable configuration once the mechanism is understood.

## Alternatives considered

Automate everything immediately; keep all setup manual permanently.

## Consequences

The repository may contain both explanatory manual steps and later scripts/configuration. Documentation should clarify which is canonical for reproduction.
