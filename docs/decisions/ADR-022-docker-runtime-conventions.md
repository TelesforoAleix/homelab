# ADR-022: Docker runtime and container conventions

- **Status:** Accepted
- **Date:** 2026-09-09
- **Supersedes:** none
- **Superseded by:** none

## Context

Phase 05 installs the first container runtime on the reference node. Every phase
from 06 onward is expected to build on it, so the conventions set here are
cheaper to get right now than to retrofit across a dozen services later.

Three facts about this machine shape the decisions:

1. **There is no console.** Docker creates network interfaces, rewrites
   packet-filtering rules and enables IP forwarding — lockout-class by the
   definition in ADR-020 — and `eno1` is down with no carrier, so both access
   routes share one Wi-Fi adapter. Losing the network loses both at once.
2. **The volume group has no free extents.** Images, containers, volumes and
   build cache all land on the root logical volume, and `lvextend` is not
   available. The remedy for a full disk here is reclaiming, never growing.
3. **There is no firewall yet.** Phase 13 owns that. Which makes now the right
   moment to set a port convention, before there are services to retrofit and
   before a firewall creates a false sense of safety.

## Decision

### 1. Rootful Docker, with containers running as non-root

The daemon runs as root. Every container specifies a non-root user.

Rootless was considered seriously and rejected for this build (see
Alternatives). The security gap it would have closed is instead addressed
per-container: a non-root `USER`, `cap_drop: ALL`, `no-new-privileges`, and a
read-only root filesystem where the workload allows.

**This matters more than it sounds**, and the reasoning is recorded because it
is easy to assume otherwise. Measured on the reference node:

```text
host  user ns: user:[4026531837]
container    : user:[4026531837]     <-- the SAME namespace
host  pid ns:  pid:[4026531836]
container    : pid:[4026532342]      <-- a different namespace
```

The PID namespace isolates. **The user namespace does not.** With no
user-namespace remapping, a container running as root is running as *the host's*
root, uid 0 to uid 0. What stands in between is capabilities and seccomp
(`CapEff: a80425fb` rather than a full `1ffffffffff`), not identity.

`USER` in a Dockerfile is also a **default, not a guarantee** — `--user 0:0`
overrides it. It is a good default, not a control.

### 2. Docker's official apt repository, not Ubuntu's `docker.io`

Added the way Tailscale's was (ADR-014): explicitly, pinned with `signed-by`,
and verified before use — never a script piped into a root shell.
`install-docker.sh` derives the codename from `/etc/os-release` and refuses to
continue unless the repository declares `Origin: Docker`, the running
architecture, and a `stable` component.

Confirmed on 2026-09-09: Docker publishes for `resolute`, so no fallback
decision was required.

### 3. Every published port names an interface — this is the important one

```bash
-p 127.0.0.1:8080:80      # loopback only
-p 100.71.62.71:8080:80   # tailnet only
-p 8080:80                # FORBIDDEN -- this is 0.0.0.0, every interface
```

**Why a convention and not a firewall rule.** Docker publishes ports with a DNAT
rule in `nat/PREROUTING`, which is evaluated *before* the `filter/INPUT` chain
that `ufw` and friends manage. A published port is therefore reachable **even
when the host firewall is configured to deny it**.

Verified on the reference node rather than taken from documentation. Docker adds
**nothing at all** to `INPUT`:

```text
-A INPUT -j ts-input          <-- the only INPUT rule, and it is Tailscale's
-A PREROUTING -m addrtype --dst-type LOCAL -j DOCKER
```

And the binding behaviour, measured with two containers running at once:

| Bound to | From the tailnet | From the LAN |
|---|---|---|
| `127.0.0.1:8080` | no answer | no answer |
| `100.71.62.71:8081` | **HTTP 200** | no answer |

Binding to the tailnet address is the useful middle ground for this project: a
service reachable from the owner's devices over an authenticated network, and
invisible to everything else on the LAN.

### 4. `aleix` is in the `docker` group, and that is root-equivalence

Recorded plainly rather than glossed: the `docker` group can start a container
that mounts the host filesystem, so it is equivalent to root — and unlike
`sudo`, it has **no password prompt**.

It grants `aleix` no capability they lacked; it removes the gate in front of it.
Accepted because `aleix` is the sole administrator and already has `sudo`, and
because the alternative made a learning phase impractical.

**It must never be granted to a service account** (ADR-011). Any later phase
running containers on a user's behalf must treat socket access as root access.

### 5. Log rotation is a disk-exhaustion control

`/etc/docker/daemon.json` sets `json-file` with `max-size: 10m`, `max-file: 3`,
written **before** the daemon first starts. The default driver has no size
limit; on a volume group that cannot be extended, that is the realistic way this
node fills up. Nothing else is configured — the rest would be speculative.

## Alternatives considered

**Rootless Docker.** Genuinely stronger: a container breakout lands in an
unprivileged user rather than root, which directly addresses the shared user
namespace described above. Rejected for this build because every later phase and
essentially all upstream documentation assumes rootful; because it cannot bind
ports below 1024 without extra setup; and because the friction would land in
Phases 07–10, which have enough novelty of their own. **This is the decision most
worth revisiting** — Phase 13 should reconsider it on its merits rather than
inherit it.

**Ubuntu's `docker.io`.** Simpler supply chain, one fewer third-party
repository. Rejected: older, and it packages Compose differently from every
tutorial the owner will read, which is a real cost in a learning project.

**`sudo` for every Docker command.** The stricter posture, keeping a password in
front of root-equivalent access. Rejected as impractical for a phase with dozens
of exercises, and because it would not have changed what `aleix` *can* do.

**Publishing to `0.0.0.0` and relying on a future firewall.** Rejected on the
evidence above: the firewall would not have helped, because published ports never
reach `INPUT`.

**Configuring `default-address-pools` and other daemon settings.** Rejected as
speculative. `172.17.0.0/16` was checked against the LAN (`192.168.0.0/21`) and
the tailnet (`100.64.0.0/10`) and does not collide.

## Consequences

**Positive.**

- Containers are non-root by default with capabilities dropped, verified on
  running containers rather than trusted from files.
- The port convention is set before any service exists to retrofit, and Phase 13
  inherits the reason rather than rediscovering it.
- Log growth is bounded on a filesystem that cannot be grown.
- `vm.swappiness` reduced from 60 to 10, closing a Phase 01 item.

**Negative, and accepted.**

- **`docker` group membership is root without a password.** Recorded, scoped to
  the sole administrator, and never to be extended to a service.
- **Rootful means container root is host root.** Mitigated per-container, not
  eliminated. Revisit in Phase 13.
- **`FORWARD` policy is asymmetric between address families** — `DROP` on IPv4,
  `ACCEPT` on IPv6. Not currently reachable (`net.ipv6.conf.all.forwarding = 0`,
  Docker's bridge has IPv6 disabled), but it is a trap for anyone who later
  enables IPv6 forwarding or Tailscale subnet routing and assumes symmetry.
- **Docker's rules are now interleaved with Tailscale's** in the same tables.
  Phase 13 adds a third writer to that arrangement.

## Related

- **ADR-011** — privilege separation; this is its container form.
- **ADR-014** — third-party repository verification; the pattern reused here.
- **ADR-020** — change safety on a console-less node; the phase this was written for.
- **ADR-015** — no encryption at rest; container volumes inherit it.
