# ADR-047: The Workbench's trust boundary is its systemd sandbox, not a dedicated account

- **Status:** Accepted
- **Date:** 2026-09-12
- **Supersedes:** none. Answers the question Phase 18.2's handover left to Phase 13 by name (*To
  Phase 13*, item 3) and its brief §6.1 recommended. Sits beside ADR-022 (`aleix` in `docker`; never
  a service account) and ADR-038 (loopback; every socket accounted for).
- **Superseded by:** none

## Context

Phase 18.2 put the first web application on the node: `homelab-workbench.service`, Python's
`ThreadingHTTPServer` on `127.0.0.1:8765`, no application login, reached only through the
`homelab-workbench` SSH alias. It runs as **`aleix`** — the sudo-capable administrator, a member of
`docker` — because its writes into `/srv/homelab/projects/*/ops/` must be commit-able by the owner
from the same account without ownership repair. 18.2 accepted that "for now" and asked Phase 13 to
take the dedicated-account upgrade (`workbench` owning the projects, `aleix` a member) or decline it
with a reason, and to make that an ADR because Phase 23.0's endpoint design depends on it.

**What Phase 13's audit OBSERVED (2026-09-12):**

- `systemd-analyze security homelab-workbench.service` → **1.3 OK**.
- `ProtectHome=yes` — the process has **no view of `/home`**: not `~aleix/.ssh/id_ed25519_github`
  (the passphrase-less push key), not the two OAuth files.
- `ProtectSystem=strict` with `ReadWritePaths=/srv/homelab` — the whole OS read-only; the volume is
  the only writable path.
- `NoNewPrivileges=yes`, empty `CapabilityBoundingSet=` — `sudo` and every setuid path closed.
- `RestrictAddressFamilies=AF_INET AF_INET6` — **no `AF_UNIX`**: it cannot open the model helper's
  socket (`/run/homelab-model-helper.sock`), although the account it runs as is the socket's owner.
- `MemoryDenyWriteExecute=yes`, the bot's syscall allow-list, `UMask=0027`.
- It **never commits or pushes** (18.2 correction `8045856`: `gitops.py` is called only by the
  acceptance fixture), so it has no need of the key it cannot see anyway.

So the thing the account question was really asking — *can a compromised Workbench reach the
administrator's credentials or privileges?* — has an observed answer: no. What it **can** do is
what `ReadWritePaths=` says: read and write **anything under `/srv/homelab` as `aleix`** — all five
clones, including the public `homelab` clone's working tree.

## Decision

**The Workbench keeps running as `aleix`. Its trust boundary is the systemd sandbox, and that
sandbox is the contract — not the account.** The dedicated-account upgrade is declined, with the
reasoning below and the triggers that would reopen it.

### What the boundary is, precisely

A compromised Workbench process can:

- read and write every file under `/srv/homelab` (the five clones' working trees and `ops/` data),
  as `aleix`, with `umask 027`;
- speak TCP/IP outbound (no `IPAddressDeny`); it is reached only over loopback.

It cannot:

- read `/home/aleix` (the GitHub key, the OAuth files, shell configuration) — `ProtectHome=yes`;
- write anywhere on the root filesystem — `ProtectSystem=strict`;
- gain privileges, run `sudo`, or use `docker` — `NoNewPrivileges`, empty bounding set (the socket
  `/var/run/docker.sock` is also unreachable: no `AF_UNIX`);
- reach the model helper or any UNIX socket — no `AF_UNIX`;
- push to GitHub — no key, and no code path that would.

The **blast radius** is therefore the contents of the volume's working trees — recoverable from
the remotes for everything committed, and from the Phase 14 backup for `ops/` data once that
exists (18.2 handover, *To Phase 14*, item 1). Not the node, not the credentials, not the other
repositories' histories.

### Why not a dedicated account

A `workbench` account with `aleix` as a group member would narrow the writable set from
`/srv/homelab` to `projects/*/ops/`. The cost: group-writable directories *inside git working
trees the owner commits from*, which is the standing source of `fatal: detected dubious ownership`,
permission drift on every `git checkout`, and a `setgid`/`umask` discipline the owner would have to
keep by hand. Phase 18.2 §6.1 chose `aleix:aleix 0750` on the volume for exactly this reason. The
narrowing would protect the four clones the Workbench never touches from a process that today has
no route to the credentials that would make writing to them matter. Measured against the cost, and
against the observed sandbox, it is not worth taking now — and it is cheap to take later, because
nothing outside the unit file and `chown` depends on the account.

### What this means for Phase 23.0

The endpoint runs as **its own account** (the baseline's §3 rule) and reaches the Workbench **over
loopback, not the filesystem** — it needs no membership in `aleix`, no path into the volume, and
this ADR gives it nothing to inherit but a port. If the endpoint needs the volume for its own
state, that is trigger 3 below, not a reason to add its account to the `aleix` group.

## Revisit triggers — any one reopens this

1. **A second human** with an account on the node, or anyone but the owner reaching the Workbench.
2. **An automated client with write access** — anything that drives the Workbench's API without a
   person behind the keystroke (a Phase 23 agent, a timer, a webhook).
3. **The Workbench gains commit or push ability**, or any process on the volume side needs the
   GitHub key — the day `ProtectHome=yes` stops being the whole answer.
4. **The sandbox is weakened** for a feature: `AF_UNIX` added, `ProtectHome` relaxed,
   `ReadWritePaths` widened beyond the volume. A change to any of those directives cites this ADR
   and either keeps the boundary or supersedes this decision.
5. **A `systemd-analyze security` score above 2.0** for the unit at any phase close without a
   `# WHY` in the unit — the baseline standard's threshold.

## Consequences

**Accepted:** a compromised Workbench can alter working trees on the volume. The remotes are the
recovery for committed content; uncommitted `ops/` data is Phase 14's.

**Required:** the unit's `ProtectHome=yes`, `ProtectSystem=strict`, `ReadWritePaths=/srv/homelab`,
`NoNewPrivileges=yes` and `RestrictAddressFamilies=AF_INET AF_INET6` are load-bearing and named in
[`docs/standards/service-security-baseline.md`](../standards/service-security-baseline.md) §3 as
the compensation for `User=aleix`. The unit's `# WHY` for `User=aleix` points here.

**Easier:** Phase 23.0's account model is decided — own account, loopback, no group membership.

**Deferred:** the `workbench` account, until a trigger fires. When it does, the migration is
`useradd --system workbench`, `chown -R workbench:aleix projects/*/ops`, `chmod g+s`, `User=workbench`
in the unit, and a `# WHY` on the group write — an afternoon, not a phase.
