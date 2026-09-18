# ADR-052: Close Home Lab version one and preserve the repository

- **Status:** Accepted
- **Date:** 2026-09-18
- **Supersedes:** the active-development and next-phase assumptions in `PROJECT.md`, `ROADMAP.md`
  and the living target-architecture documents

## Context

Home Lab began as a learning-first project. It succeeded at that purpose: the reference node was
built, secured, backed up and made remotely operable; progressively more capable interfaces, model
access, routing, monitoring and orchestration components were implemented; and the repository
recorded the decisions, failures and corrections that made those results understandable.

The project also accumulated a large governance and documentation surface. Continuing to evolve
the same repository would make version two inherit that structure before version two has decided
which parts still serve it. The owner has therefore chosen to end development here and design the
successor separately.

At closure, public `main` at `26ce1c0` is the last known-working repository state before the
documentation-only close-out. Phase 23.1 was not delivered. Work toward it existed only on an
unpublished local branch, had not completed its node proof or handover, and was deliberately
discarded rather than merged or described as partial delivery.

## Decision

1. This repository is **Home Lab version one**. Active development ended on 2026-09-18.
2. The repository remains public as a historical, educational and reproducible reference until the
   owner decides otherwise. Existing guides, code, decisions, build logs and failures are retained.
3. No further roadmap phase is implied. Future-looking roadmap and target-architecture material is
   preserved as unfinished design history, not as a commitment and not as deployed behavior.
4. The final delivered implementation is the state documented by
   `docs/architecture/current-architecture.md`, completed handovers and the closure handover. Phase
   23.1 and later target-runtime work are not part of version one.
5. Version two is a separate project and repository. Nothing is automatically inherited merely
   because version one accepted an ADR or planned a phase. Selection and migration are separate
   work, and a link will be added when the successor has a stable public location.
6. Closing this repository does not decommission the reference node. Its running services,
   credentials, data, backups and security obligations remain operational concerns until version
   two assumes them or they are explicitly retired.
7. Routine feature and documentation development stops after this close-out. A critical security
   or factual correction requires an explicit decision to reopen the repository or must be handled
   by its successor.
8. GitHub's platform-level Archive setting is optional and may be applied after the successor link
   and operational ownership are settled. The documented project closure does not depend on that
   setting.

## Alternatives considered

### Complete Phase 23.1 before closing

Rejected. Completion would require deployment, disruptive recovery proofs, documentation and a
handover for functionality the owner no longer intends to develop in this repository. Calling the
existing branch complete would violate the Definition of Done.

### Merge the unfinished Phase 23.1 work for preservation

Rejected. `main` is the known-working public record. Merging unproved code would blur the boundary
between delivered v1 and abandoned exploration. The branch was local-only and the owner chose to
discard it.

### Delete or heavily reduce the documentation

Rejected. The guides, operational records, ADRs and failure history are the principal reusable
output of the learning project. Historical complexity is acceptable when the entry points explain
what is delivered and what remained aspirational.

### Continue maintaining this repository alongside version two

Rejected. Two active authorities for the same Home Lab would create drift and make operational
ownership unclear.

## Consequences

- Readers get a stable v1 reference with an explicit boundary between delivered behavior and
  unfinished intent.
- Historical documents retain dated statements such as "next phase"; closure notices explain that
  those statements no longer govern.
- Version two can reuse ideas without silently inheriting v1 governance, architecture or technical
  debt.
- The running node still needs an owner. Public archival is not service shutdown, credential
  revocation, backup transfer or security maintenance.
- If the owner later removes the public repository, an independently verified repository backup
  should exist first.

## Validation / revisit trigger

Revisit only if this repository is intentionally reopened, the reference node is decommissioned,
or a stable public version-two URL becomes available and should replace the placeholder notice.
