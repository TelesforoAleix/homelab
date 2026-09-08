# ADR-009: Use Telegram as the first remote interface

- **Status:** Accepted
- **Date:** 2026-09-08

## Context

The project needs an accessible remote interface that can later support text commands and voice notes.

## Decision

Build a Telegram Bot as the first external interface, beginning with simple deterministic commands.

## Alternatives considered

Start with a custom web app, Discord, Slack, or a full chat UI.

## Consequences

The first interface remains simple. More interfaces can be added later without changing the router/executor concept.
