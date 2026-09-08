# ADR-005: Prefer Tailscale for remote network access

- **Status:** Accepted
- **Date:** 2026-09-08

## Context

The server should be reachable away from home without directly exposing SSH to the public internet.

## Decision

Use Tailscale as the preferred remote connectivity layer, alongside SSH key authentication.

## Alternatives considered

Port-forward SSH directly; operate only on the local LAN; deploy a self-managed VPN first.

## Consequences

Remote access is simpler and avoids making public SSH exposure a prerequisite. Exact service capabilities/pricing must be verified when implemented.
