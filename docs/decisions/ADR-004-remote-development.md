# ADR-004: Use the MacBook as the primary development interface

- **Status:** Accepted
- **Date:** 2026-09-08

## Context

The M700 is intended to be an execution/server environment rather than a workstation.

## Decision

Develop and administer primarily from the MacBook using SSH, SSH keys, Tailscale, and VS Code Remote SSH.

## Alternatives considered

Attach permanent monitor/keyboard to the server; develop locally on the MacBook and copy builds manually.

## Consequences

The server remains headless while code can live and execute on the M700. Remote access becomes a core early phase.
