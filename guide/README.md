# Home Lab Guide

This directory contains the human-facing, explanation-first guide to building and understanding Home Lab.

## Intended reader

Someone with a business and some technical background who is comfortable with computers and light programming, but who is not necessarily a Linux/system administration engineer.

## Writing standard

Each guide should answer, in roughly this order:

1. What are we trying to achieve?
2. Why does this component exist?
3. What does the reader need to understand to make the relevant decisions?
4. What are the realistic alternatives and trade-offs?
5. What does the reference build choose, and why?
6. What commands/configuration implement it?
7. How do we verify it worked?
8. What can go wrong?
9. What did the reference build actually encounter?

The guide should not become a general textbook. Explain only the theory needed to understand and safely reproduce the project.

## Pre-development guides

Multiple guides may use the `00-*` prefix because they are foundational rather than sequential implementation phases.

Current bootstrap topics:

- [`00-project-overview`](00-project-overview/README.md)
- [`00-hardware-selection`](00-hardware-selection/README.md)
- [`00-reference-build`](00-reference-build/README.md)
- [`00-budget-and-costs`](00-budget-and-costs/README.md)

## Implementation-phase guides

These mirror the numbered project roadmap.

- [`01-ubuntu-server`](01-ubuntu-server/README.md) — installing Ubuntu Server on the reference node
  and making it boot headless and unattended. *(Complete 2026-09-08, and corrected five times by
  being used.)*
- [`03-remote-access`](03-remote-access/README.md) — SSH keys, disabling password authentication,
  Tailscale, VS Code Remote SSH, and removing the monitor. *(Complete 2026-09-09. Run before Phase
  02 by the owner's sequencing decision, to close Phase 01's principal open risk early.)*
- `02-linux-fundamentals` — **next.** Deferred behind Phase 03; see `ROADMAP.md`.
