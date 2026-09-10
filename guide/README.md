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

## Out-of-phase guides

Work that did not belong to a numbered phase but changed the reference build.

- [`security-shared-network`](security-shared-network/README.md) — securing a node on a network you
  do not control. Why the "home LAN" premise every earlier security decision rested on was wrong,
  how to prove whether a port is forwarded to you (the answer is a host key), applying a firewall
  over the connection it might break, and why verifying it needs three tests rather than one.
  *(2026-09-10. Closes the "no firewall" risk carried since Phase 01; Phase 13 still owns the rest.)*

## Implementation-phase guides

These mirror the numbered project roadmap.

- [`01-ubuntu-server`](01-ubuntu-server/README.md) — installing Ubuntu Server on the reference node
  and making it boot headless and unattended. *(Complete 2026-09-08, and corrected five times by
  being used.)*
- [`03-remote-access`](03-remote-access/README.md) — SSH keys, disabling password authentication,
  Tailscale, VS Code Remote SSH, and removing the monitor. *(Complete 2026-09-09. Run before Phase
  02 by the owner's sequencing decision, to close Phase 01's principal open risk early.)*
- [`02-linux-fundamentals`](02-linux-fundamentals/README.md) — operating the node: permissions,
  services, logs, storage, packages, and the habit of recognising a change that could lock you out
  before typing it. *(Complete 2026-09-09. Run after Phase 03 by the owner's sequencing decision.)*
- [`04-git-github`](04-git-github/README.md) — git as this project actually uses it, taught from the
  repository's own history: what a commit really is, why the phase merges are `--no-ff`, conflicts,
  the `.gitignore` trap, recovery via the reflog, and auditing a history before publishing it.
  *(Complete 2026-09-09. The phase in which the repository was first pushed anywhere.)*
- [`05-docker`](05-docker/README.md) — Docker and Compose on a console-less node: containers as
  host processes, non-root containers, explicit-interface port publishing, layer caching, logs,
  diagnostics, disk accounting, and the Docker/firewall interaction Phase 13 inherits.
  *(Complete 2026-09-09. Leaves Docker installed and no containers running.)*
- [`09-model-executor`](09-model-executor/README.md) — asking a model a question without giving the
  bot a credential. Why the bot cannot just run `claude -p`, why the access rule belongs in the
  socket unit rather than in Python, what leaves the machine on every call and why logs do not,
  prompt injection explained concretely, and why the model's answer is text and nothing else.

- [`08-router-executors`](08-router-executors/README.md) — the structure behind the interface:
  authentication versus authorisation, a registry instead of a chain of ifs, and one privileged
  action performed by an account that gained nothing. Why polkit rather than sudo, and why a
  wildcard in an escalation grant is a full root grant in disguise. *(Complete 2026-09-09.)*
- [`07-telegram`](07-telegram/README.md) — the first thing the node does *for* you: a read-only
  Telegram status bot that needs no open port, runs as an account that can barely do anything, and
  fails closed on a misconfigured allowlist. *(Complete 2026-09-09.)*
- [`06-ai-cli-access`](06-ai-cli-access/README.md) — native Claude Code and Codex installation,
  subscription versus API billing, headless authentication, credential handling, constrained
  disposable-workspace exercises, sandbox prerequisites, and why operator CLIs are not service
  identities. *(Complete 2026-09-09. Leaves no AI process or service running.)*
