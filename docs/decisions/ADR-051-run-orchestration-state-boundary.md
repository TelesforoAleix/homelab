# ADR-051: Run orchestration-state boundary — split lifecycle control and protected content

- **Status:** Accepted
- **Date:** 2026-09-17
- **Supersedes:** none
- **Superseded by:** none

## Context

ADR-050 makes a Run the durable, generic Home Lab lifecycle unit, but intentionally defers its
storage, account and locked-volume placement. The reference node has an unencrypted root filesystem
that remains available after unattended boot, and an encrypted `/srv/homelab` volume that is manually
unlocked after boot. The encrypted volume holds canonical project and knowledge content; root hosts
operational services and their limited state.

The delivered Phase 23.0 harness is a useful boundary fact, not an implementation of durable Runs:
it has a root-resident, content-free audit record and remains available while the volume is locked.
It does not establish where future Run state belongs. Conversely, the contemporaneous placement table
in ADR-037 described the harness as volume-side. Its enduring decision is the encrypted-content and
degraded-until-unlocked boundary; it is not a claim that later delivered content-free harness
operational state is unavailable on root.

The decision required before Phase 23.1 Part A is therefore an information-placement and recovery
boundary. It must make durable lifecycle recovery possible without moving canonical project, Brain,
or client content onto unencrypted root or giving root-resident machinery a way to unlock the volume.

## Decision

### 1. One Home Lab-owned lifecycle; split information placement

Home Lab adopts a split-state boundary with **one authoritative Run lifecycle**. The harness/
orchestrator owns the authoritative Run orchestration record. The split concerns where information
is held, not who owns lifecycle state; it does not create separate root-side and volume-side Run
authorities.

The harness/orchestrator may remain modules in the existing harness boundary. A distinct
orchestration-state service or process is not required unless a later credential, privilege,
filesystem/resource view, trust, lifetime, placement, or availability/failure boundary justifies
one.

### 2. Root-resident, content-minimized Run control record

A content-minimized Run control record remains available while `/srv/homelab` is locked. Its
purpose is durable identity and lifecycle continuity across restart/reboot, correlation, and safe
operational visibility that work is waiting, blocked, interrupted, cancelled, failed, completed,
partially completed, or superseded.

The control record may contain, conceptually:

- opaque Run and step identifiers;
- lifecycle and step statuses, timestamps and correlation identifiers;
- non-sensitive waiting or dependency reason codes;
- stable references to protected or domain-owned information needed after unlock; and
- minimal non-secret identity or authorization references needed for later revalidation.

This is not a state schema. A reference is not an authority grant, and root-resident control state
must not become a substitute source of client identity, delegated authority, project scope, or
approval. Content-minimized control state also requires content-minimized references: a locator,
path or label that unnecessarily embeds project names, user content, sensitive objective text or
other protected domain information remains protected where practical, with the root record using a
more opaque reference.

### 3. Protected and domain-owned information remains protected or referenced

The architecture defaults richer or sensitive Run-associated information away from unencrypted root.
This includes raw objective or user text; project or Brain content; sensitive plan or Definition of
Done text; complete context, prompts or conversations; artifact bodies; concern or evidence content;
rich project/resource-scope information; rich authorization evidence; and executor-session internals.

Such information remains in its canonical client/domain/service store or protected storage and may
be referenced by the Run. Run durability does not require copying it merely to make the lifecycle
durable. A protected/domain-side record does not independently decide lifecycle state.

Run persistence must never contain or acquire provider credentials, bearer tokens or other secrets,
volume-unlock material, or authority-granting secrets. The root-resident lifecycle machinery gains
no ability to unlock `/srv/homelab`.

### 4. Immutable objectives and unavailable references

ADR-050's immutable objective survives either as directly stored information where its placement is
permitted or through a stable, trustworthy reference to protected canonical information. This ADR
does not require raw objective text on root.

If a required reference, artifact, resource or protected information is unavailable, the Run records
that limitation. It must not claim successful, reproducible continuation or completion on the basis
of missing information. If referenced objective content has materially changed unexpectedly or
cannot be verified as the accepted objective, the runtime must not silently treat the current
referenced content as the original objective. It preserves that uncertainty and remains waiting,
revalidates, replans only within the accepted objective where possible, partially completes, fails
or escalates as appropriate; a materially changed desired objective creates a new Run under ADR-050.

### 5. Locked-volume and resume behavior

While `/srv/homelab` is locked, root-resident Run control state remains recoverable. Affected Runs
may be identified and reported operationally as waiting or blocked, with non-sensitive lifecycle and
correlation visibility. Full project or objective inspection before unlock is not required.

The orchestrator does not unlock the volume. It neither fabricates protected content nor copies it
onto root to continue work, and volume-dependent work does not execute while the volume is locked.

Unlock or dependent-service recovery is a resume opportunity, not automatic permission to continue.
Before affected work proceeds, the runtime revalidates as applicable:

- referenced-resource availability;
- client and authority provenance;
- revocation state;
- project/resource scope and applicable policy;
- required context or evidence; and
- service availability.

If revalidation fails or required information remains unavailable, the Run stays waiting, becomes
partial or failed, or escalates under later lifecycle policy. Nothing here selects detailed retry,
idempotency, or automatic-continuation rules.

### 6. Minimum recovery guarantees

The architecture requires the following minimum behavior:

| Condition | Required guarantee |
|---|---|
| Harness restart or server reboot | Accepted active or waiting Run control state is not silently forgotten. Interrupted work is never inferred to have completed merely because a process restarted. |
| Locked encrypted volume | An affected Run remains durably identifiable as waiting or blocked. |
| Model-helper or other service outage | Run state is preserved and the Run waits or fails safely; unavailable service work is not reported as complete. |
| Executor-session loss | An executor session is not Run state. Known references and outcome uncertainty are retained; the runtime does not promise session resurrection or blindly repeat potentially effectful work. |
| Restore from backup | Restored Run/history records do not automatically resume execution. Identity, authority, revocation, policy, scope, referenced resources and service availability require revalidation first. |

### 7. Backup and completed history

Active and waiting Run control state is durable operational state. Its silent loss is incompatible
with the Run contract and it must be included in the applicable backup/recovery guarantee.

Completed Runs retain a content-minimized durable history sufficient for audit/provenance and
correlation without requiring raw prompts or other content copies. This lifecycle history is the
durable orchestration/audit record. Telemetry may correlate to it, but is not the authoritative Run
lifecycle record and need not share its retention period or backup policy. Retention duration,
archival policy, telemetry retention and the exact backup/recovery mechanism remain deferred.

## Relationship to existing decisions

| Decision | Relationship |
|---|---|
| **ADR-037** | Preserved. Canonical project and knowledge content remain on encrypted storage; locked-volume degraded operation remains normal. This ADR adds no exception for rich Run content on root and does not rewrite ADR-037's historical harness-placement statement. |
| **ADR-046** | Preserved. Root-resident services receive no volume keyfile, TPM unlock path, cached passphrase or other ability to unlock the encrypted volume. |
| **ADR-047** | Preserved. Factory Workbench's `aleix` account/sandbox boundary remains Factory-specific and is not the generic Home Lab Run owner or store. |
| **ADR-048** | Preserved. This decision grants no additional model-helper socket consumer or credential access. |
| **ADR-050** | Refines its deferred Run storage/account/locked-volume placement question without changing Run ownership, immutable-objective, authority, canonical-domain-ownership, or executor-session rules. |

No accepted ADR is superseded. In particular, this decision does not change credential isolation,
volume unlock, Workbench sandboxing, client/domain ownership, or Phase 23 ownership under ADR-045.

## Alternatives considered

### All Run state available unencrypted on root

Rejected. Rich objectives, plans, context, project scope and evidence can be project or personal
content. Treating all of it as root operational state would weaken ADR-037's encrypted-content
boundary and expand the sensitive backup surface.

### All Run state volume-dependent

Rejected. Before unlock, the generic Home Lab lifecycle would disappear with the data volume. It
could not provide durable restart, interruption, waiting or correlation visibility precisely when
the node's root-resident recovery plane is available.

### Split state with independent lifecycle authorities

Rejected. Two stores independently deciding lifecycle state would create divergence, ambiguous
recovery and unclear authority. The Run has one Home Lab-owned lifecycle; protected/domain stores
hold content or references, not a competing lifecycle.

### A separate orchestration-state service now

Rejected. Logical separation alone is not a process boundary. The existing harness boundary already
provides the required generic ownership and locked-volume availability seam; a later independent
boundary must be justified by a concrete trust, credential, resource, lifetime, placement or
availability need.

## Consequences

Phase 23.1 Part A can exercise durable single-step Runs, restart survival and waiting/resume without
requiring the entire encrypted volume to be available or importing Factory workflow state into Home
Lab. It must treat content minimization and reference availability as correctness conditions, not
as optional privacy improvements.

The tradeoff is intentional: a locked-volume Run can be operationally visible without being fully
inspectable or executable. Recovery gains safe state visibility, but it does not promise transparent
continuation after loss of context, authority, external resources or executor state.

## Explicitly deferred

This ADR does not choose:

- SQLite, PostgreSQL, files, or any other persistence technology;
- an exact storage path, schema, serialization format or event model;
- queue technology, high availability, distributed persistence or multi-node failover;
- retention duration, archival policy, telemetry retention or an exact backup mechanism;
- detailed retry/idempotency behavior, executor checkpointing, or automatic-continuation policy;
- a physical process topology or a separate orchestration-state service; or
- a trusted-ingress mechanism, request/wire version, or detailed authority-proof format.

Those decisions belong to the bounded Phase 23.1 design/implementation work or later phases, while
preserving this boundary and ADR-050's authority invariants.

## Validation / revisit trigger

Acceptance review confirms that this ADR creates no root exception for protected content or volume
unlock and no Factory-owned lifecycle under ADR-037, ADR-046, ADR-047 or ADR-050.

Later implementation must demonstrate, at minimum:

1. an accepted Run remains identifiable after harness restart and server reboot;
2. a volume-dependent Run remains safely waiting/blocked while the encrypted volume is locked;
3. unavailable references, service loss and executor-session loss do not produce false completion or
   unreviewed repeated effectful work; and
4. backup restoration does not automatically resume work before required revalidation.

Revisit this decision if a required Run property cannot be represented without copying protected
content onto root, if a separate trust/availability boundary becomes concrete, or if recovery
evidence shows that the control/reference division causes unsafe lifecycle divergence. Any such
change requires an explicit architectural decision.
