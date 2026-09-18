# Home Lab version one — Closure handover

- **Date:** 2026-09-18
- **Outcome:** Closed by owner decision; not every roadmap phase was completed
- **Decision:** [ADR-052](../decisions/ADR-052-close-version-one-and-preserve-the-repository.md)
- **Last pre-closure public state:** `main` at `26ce1c0`

## What a future reader should know first

Home Lab version one is closed. This repository remains public because its guides, implementation,
decisions and failure records are useful, but it is no longer an active roadmap. Version two is
being developed separately; this repository does not yet name its permanent public location.

The correct boundary is:

- **Delivered v1 behavior:** the completed phase handovers and
  [`current-architecture.md`](../architecture/current-architecture.md).
- **Unfinished v1 intent:** future phases in `ROADMAP.md`, the accepted target architecture and
  open debts in historical handovers.
- **Not part of v1:** Phase 23.1. Its unpublished local work was discarded before node deployment,
  handover, PR or merge.

No v1 decision automatically governs version two. It may reuse any useful material, but its scope,
architecture and operational contract must be chosen in its own repository.

## What version one achieved

The project produced a working, inexpensive, remotely administered AI systems lab and documented
how it was built:

- Ubuntu Server on a used Lenovo M700 Tiny, upgraded to 32 GB RAM.
- Key-only SSH over Tailscale, a tested console recovery path and safe-change procedures for a
  headless node.
- Docker installation and conventions, while avoiding unnecessary persistent infrastructure.
- A Telegram interface with centralized authorization, bounded status commands and one narrowly
  privileged service restart.
- Subscription-backed Claude and Codex access through a credential-isolating helper socket.
- Configured model/provider routes, unattended eligibility controls, count caps and a fail-closed
  metered-provider spend governor.
- Backup and restore evidence, a separate LUKS2 encrypted data volume, monitoring, notifications,
  firewalling and service-hardening work.
- Factory Workbench on loopback plus the Phase 23.0 synchronous harness endpoint and adapter proof.
- A public learning guide, operational references, ADR history, build logs and explicit records of
  failed checks, reversals and lessons.

## What the final architecture review concluded

The last read-only architecture and overengineering review was performed on 2026-09-17 against
public `main` and the then-in-flight Phase 23.1 Part A work. It matters to the interpretation of this
closure because it did **not** conclude that the working v1 system was an unnecessary reinvention.

It classified these areas as justified custom platform work:

- the credential-isolating model helper and provider adapters;
- the registry, unattended-eligibility controls, count caps and fail-closed spend governor;
- egress policy, content-free audit and runtime-owned identity boundaries;
- systemd sandboxing, loopback placement, encrypted storage, locked-boot behavior and monitoring;
- Factory's revision-bound approvals and refusal tests;
- the proposed Part A split between content-minimized lifecycle state and protected content.

The risk was primarily in what had **not** been delivered. A literal implementation of later
planning, replanning, capability, tool and retrieval phases could have become a bespoke graph
runtime, tool protocol and RAG stack. The review's proposed boundary was that Home Lab own Runs,
policy, routing, provenance and checked dispatch, while mature libraries or framework adapters own
in-step workflows and retrieval machinery; it identified MCP as a candidate service/tool boundary.
Those recommendations are useful input to version two, but this repository never accepted or
implemented them.

The review also made the repository's principal cost explicit: documentation and governance effort
had become large relative to the production implementation. It recommended completing Part A and
then narrowing the future architecture. The owner subsequently chose to stop sooner. The local
branch was discarded not because its design had been disproved, but because finishing it no longer
served the decision to close v1 and redesign the successor independently.

## Final delivered architecture

The final v1 topology has two principal request paths:

```text
Factory Workbench -> loopback harness endpoint -> model-helper -> configured provider
Telegram bot ----------------------------------> model-helper -> configured provider
```

The harness is the delivered Phase 23.0 compatibility endpoint. It validates and classifies a
closed v1 request, forwards supported questions and records a content-free audit event. It does not
implement durable Runs, general decomposition, planning, context assembly, capability resolution,
generic service routing or checked tool dispatch. Those concepts appear in the target architecture
because they were designed, not because they were built.

For the detailed boundary and security invariants, read
[`current-architecture.md`](../architecture/current-architecture.md).

## Final operational observation

Read-only checks on 2026-09-18 observed:

- `systemctl is-system-running` -> `running`;
- no failed units were reported;
- the harness, model-helper socket, Telegram bot, Factory Workbench and watchdog timer were active;
- `/srv/homelab` was mounted from `/dev/mapper/homelab-data`;
- the node's `homelab` clone was clean on `main` at `8897a91` (the Phase 23.0 merge).

The node clone is older than public `main`; later phases commonly deployed staged files and updated
the repository record separately, so its checkout is not a complete deployment-version marker.
This close-out deliberately made no node change and did not pull, restart or reinstall anything.

## Open operational responsibility

Repository closure is not system decommissioning. Until version two assumes the node or v1 is
explicitly retired, the owner still needs to maintain:

- service and host security;
- provider, GitHub and Telegram credentials;
- model count limits and metered spend controls;
- encrypted-volume unlock and backup/restore procedures;
- any personal or project data held on the node;
- deliberate shutdown and credential revocation if the services are retired.

Historical handovers contain unresolved debts. They are not a new v1 backlog, but they remain useful
warnings if the corresponding v1 component continues operating or is reused.

## Repository disposition

- `main` remains the authoritative v1 history.
- The unfinished local-only `feature/23.1a-run-foundation` branch was deleted by owner decision.
- Existing public historical branches and tags are retained.
- No code, service configuration or live-system state changed during closure.
- The repository remains public. A final tag/release and GitHub's Archive setting may be applied
  after the version-two location and operational handover are settled.

## Validation performed for closure

- Confirmed the working tree was clean before leaving the unfinished branch.
- Confirmed local `main` matched `origin/main` at `26ce1c0` before close-out edits.
- Confirmed the unfinished Phase 23.1 branch had no remote counterpart.
- Confirmed the public repository had no open issues or pull requests and was not archived.
- Performed the read-only node checks recorded above.
- Reviewed the project contract, roadmap, current and target architecture, current state, relevant
  handovers and ADRs before writing this closure.

## Costs

No new paid dependency and no usage-based model call. Closure changed documentation only.

## Final lesson

The repository achieved its purpose before it achieved its entire roadmap. Treating that as a
successful closure is more accurate than either deleting the history or claiming unfinished target
architecture was delivered.
