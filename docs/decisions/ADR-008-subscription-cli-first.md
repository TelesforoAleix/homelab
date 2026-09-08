# ADR-008: Use subscription-backed AI CLIs first where officially supported

- **Status:** Accepted
- **Date:** 2026-09-08

## Context

The owner already has access to Claude and ChatGPT subscriptions and wants to compare subscription-backed CLI workflows with APIs later.

## Decision

Start with Claude Code CLI and OpenAI Codex CLI using officially supported subscription authentication where available. Introduce direct API billing intentionally in later experiments.

## Alternatives considered

Start with direct APIs and API keys; start with only local models.

## Consequences

Early experimentation avoids unnecessary API architecture/cost while preserving later API comparison as a learning phase. Supported authentication must be verified at implementation time.
