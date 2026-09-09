# Phase 05 Brief — Docker & Docker Compose

- **Date:** 2026-09-09
- **Phase:** 05 — Docker & Docker Compose
- **Author:** the Phase 05 context
- **Status:** Accepted, self-ratified under ADR-017
- **Previous handover:** [`04-git-github-handover.md`](04-git-github-handover.md)

## 0. Governance note

Under ADR-017 there is no Project Planning context to ratify this brief. It is written and committed
**before implementation begins**. Fourth consecutive phase to do so.

### Three scope decisions taken with the owner before writing

Asked and answered on 2026-09-09:

1. **Rootful Docker, with every container running as a non-root user.** Not rootless. The standard
   path, which every later phase and every upstream document assumes. The consequence is accepted
   knowingly and must be recorded rather than glossed: **membership of the `docker` group is
   equivalent to root** (§9.3).
2. **Docker's official apt repository** — `docker-ce` plus the Compose v2 plugin. Not Ubuntu's
   `docker.io`. Follows the ADR-014 precedent already set for Tailscale: third-party repository,
   pinned with `signed-by`, verified before installing.
3. **Learning only — nothing persistent is left running.** Throwaway containers, one image built
   from a Dockerfile, one Compose stack brought up and torn down. No monitoring UI, no log viewer,
   no service the roadmap has not asked for. This mirrors Phase 02's sandbox discipline and honours
   `AGENTS.md`: infrastructure gets added when a phase has a concrete need, not because it is common.

## 1. Purpose

**This is the first phase where ADR-020 genuinely bites, and that is the most important sentence in
this brief.**

Phases 01 and 03 did their dangerous work with a monitor an arm's length away. Phase 02 deliberately
avoided every lockout-class change. Phase 04 ran entirely on the MacBook and never touched the node.
Docker is different:

- It **creates network interfaces** (`docker0`, and a veth pair per container).
- It **rewrites packet-filtering rules**, inserting its own chains and setting the `FORWARD` policy
  to `DROP`.
- It **enables IP forwarding** (`net.ipv4.ip_forward=1`).

By the standard's own definition that is **lockout-class: it touches the network**. And on this
machine the network is not one path but the only path — `eno1` is still `DOWN` with no carrier, so
`ssh homelab` (Tailscale) and `ssh homelab-lan` (LAN) are independent above the link layer and
identical below it. **Losing the network does not lose one route. It loses both, simultaneously, on
a machine with no console.**

Beyond surviving the install, the phase exists to:

- teach containers well enough that Phases 06–10 can be built on them rather than around them;
- establish **conventions before there are services to retrofit** — in particular how ports are
  published, which is a security decision most projects discover the hard way (§9.2);
- give the owner the operational commands for a technology whose failure mode is a silently full
  disk on a volume group that **cannot be grown** (§9.4).

## 2. Starting state

Verified from live output on 2026-09-09 at phase start, over `ssh homelab`.

### The node

| Fact | Value |
|---|---|
| OS / kernel | Ubuntu 26.04.1 LTS (`resolute`), `7.0.0-31-generic` |
| Health | `systemctl is-system-running` → `running`; **0** failed units |
| Root filesystem | 232 G total, **7.8 G used (4 %)**, 214 G available; inodes 1 % |
| Memory | 7.1 Gi total, 1.3 Gi used, 5.9 Gi available |
| Swap | 4.0 Gi, **0 B used** |
| `vm.swappiness` | **60** — inherited from Phase 01, which named Phase 05 as the trigger to revisit |
| **cgroup** | **v2 (`cgroup2fs`)** — unified hierarchy, which is what modern Docker expects |
| `iptables` | v1.8.11, **`nf_tables` backend** — not legacy |
| `nftables` | v1.1.6 |
| **Docker** | **Not installed.** No `docker`, no `containerd`, no related packages |
| apt sources | `ubuntu.sources`, `tailscale.list` — one third-party repository so far |

### Network — the thing this phase puts at risk

| Interface | State |
|---|---|
| `lo` | UP |
| **`eno1`** | **DOWN, `NO-CARRIER`** — present, cabled to nothing, still unused |
| **`wlp1s0`** | **UP** — the only physical link, and therefore a single point of failure for *both* access routes |
| `tailscale0` | UP |

Listening sockets, which must be **identical** at phase close except for anything Docker
deliberately adds:

```text
0.0.0.0:22        and  [::]:22        sshd
127.0.0.54:53     and  127.0.0.53:53  systemd-resolved (loopback only)
127.0.0.1:44207                       loopback only
100.71.62.71:36121                    tailscaled, on the tailnet address
[fd7a:115c:a1e0::…]:57273             tailscaled, IPv6 tailnet address
```

**`:22` is the only port reachable off-box.** That fact is the baseline this phase must not
accidentally change.

### Address-space check

Docker's defaults must not collide with anything already in use. By inspection:

| Network | Range | Collision with Docker defaults? |
|---|---|---|
| LAN | `192.168.1.0/24` | No |
| Tailnet | `100.64.0.0/10` | No |
| Docker `docker0` default | `172.17.0.0/16` | — |
| Docker default address pools | `172.16.0.0/12` … | — |

No overlap is expected. **This must still be confirmed from live output after install**, not assumed
from this table — a subnet collision would be a network-layer fault on the only path in.

## 3. Learning objectives

By the end the owner should be able to explain, without an agent present:

1. **What a container actually is** — a normal Linux process, isolated by namespaces and limited by
   cgroups. Not a small virtual machine. There is no guest kernel; `ps` on the host can see it.
2. **Image vs container vs volume** — an image is a read-only stack of layers, a container is a
   writable layer plus a process, a volume is storage that deliberately outlives both.
3. **Why layers matter for the Dockerfile you write** — each instruction is a cached layer, ordering
   determines what gets rebuilt, and a secret in an early layer stays in the image even if a later
   layer deletes it. *(That is the `.gitignore` lesson from Phase 04 in a different costume, and the
   guide should say so explicitly.)*
4. **What `-p` actually does**, and why `-p 8080:80` is a different security decision from
   `-p 127.0.0.1:8080:80` (§9.2).
5. **Why the `docker` group is equivalent to root**, and why that is acceptable here but must never
   be handed to a service account.
6. **Compose as a declarative file**, and why the project prefers it to long `docker run` lines that
   live only in shell history.
7. **Where the disk goes** — images, containers, volumes, build cache — and how to find and reclaim
   it before a volume group that cannot be grown fills up.
8. **How to read a container's logs and exit status** when it will not start, which is the container
   equivalent of Phase 02's `systemctl status` / `journalctl` work.

## 4. Functional objectives

1. **The ADR-020 procedure is executed and evidenced** — not merely referenced. Before/after network
   and firewall state captured, two sessions held, both routes proved from the MacBook by a third
   new connection afterwards.
2. Docker Engine and the Compose v2 plugin installed from Docker's official repository, with the
   repository verified (`signed-by`, correct `Origin`, correct suite) before installation.
3. `docker run hello-world` succeeds, and a container is proved to be an ordinary host process.
4. **A non-root container is demonstrated** — `USER` in a Dockerfile, and `id` inside the container
   showing a non-zero UID.
5. One image built from a written Dockerfile, kept in the repository.
6. One Compose stack brought up, inspected, and torn down.
7. **Port-publishing convention established and proved**: a container published to `127.0.0.1` is
   *not* reachable from the LAN, demonstrated by testing from the MacBook.
8. `/etc/docker/daemon.json` configures **log rotation**, because the default `json-file` driver
   grows without limit on a volume group that cannot be extended (§9.4).
9. `vm.swappiness` reduced from 60 and made persistent, closing the item Phase 01 raised.
10. Disk accounting understood: `docker system df` before and after, and a reclaim demonstrated.
11. **The node ends the phase with `:22` still the only port reachable off-box**, proved by `ss` and
    from the MacBook.
12. Everything created for learning is removed; `docker system df` shows the reclaimed state.

## 5. Decisions already fixed

| Source | Constraint |
|---|---|
| **ADR-020** | Binding, and this is the phase it was written for. Applies in full. |
| **ADR-011** | Privilege separation. Containers run as non-root. Nothing user-facing is root by default. |
| **ADR-014 precedent** | A third-party apt repository is pinned with `signed-by` and verified before use, exactly as Tailscale was. |
| **ADR-013 / ADR-017 / ADR-021** | Known-working `main`; brief before implementation; the repository is public, so a secret committed now is a disclosure (§9.6). |
| **`AGENTS.md`** | No infrastructure added because it is common. This is why objective 3 is learning-only. |
| Owner's standing rule | **Never commit MAC addresses.** The node has two, both visible in `ip link` output. Any captured network output committed to this repository must have them stripped. |
| Phase 04 handover | The volume group has no free extents; `eno1` unused; the node still has no backup. |

## 6. Decisions still open

To be resolved inside the phase and recorded:

1. **Whether `aleix` joins the `docker` group**, or whether every Docker command uses `sudo`. Group
   membership is more convenient and is root-equivalent; `sudo` is more honest about what is
   happening and keeps a password prompt in the loop. Decide explicitly and record the reasoning.
2. **The exact `vm.swappiness` value.** 10 is the usual recommendation for a server with adequate
   RAM. Decide from the machine's actual memory behaviour, not from folklore.
3. **Whether `daemon.json` sets anything beyond log rotation** — for example explicit
   `default-address-pools`. Presumption: **no**. Log rotation has a concrete justification; the rest
   is speculative configuration.
4. **Whether Docker's own `containerd` or the distribution's is used.** The official packages bring
   `containerd.io`; confirm nothing conflicts.
5. **Whether the phase adds a `scripts/server/` helper** for pre-change network capture, or whether
   the commands live only in the guide. Presumption: a script, because this capture will be needed
   again by Phase 13, which is worse.

## 7. Implementation scope

### 7.1 The ADR-020 procedure — this comes first and is not optional

Docker's installation is **lockout-class**. The standard is applied in full, and its evidence is
committed.

**Before touching anything:**

1. Run `scripts/macos/preflight.sh` **from the MacBook**, proving both routes arrive from outside.
2. Open **two** SSH sessions; leave the second idle and untouched. Count sessions with `w`, never
   `who` — `/run/utmp` does not exist on systemd 259 and `who` reports zero while exiting 0.
3. **Do the installation inside `tmux`.** Both access routes share one Wi-Fi adapter; a dropped link
   mid-`apt` can leave `dpkg` half-configured, and that is a far worse state than a failed install.
4. **Capture the complete "before" state** and keep it off the node as well as on it:
   - `ip -br addr`, `ip -br link`, `ip route`
   - `sudo iptables-save`, `sudo nft list ruleset`
   - `ss -tlnp`
   - `sysctl net.ipv4.ip_forward`
5. **Type the rollback before the change**, so it exists when it is needed rather than being composed
   under stress: how to stop and disable `docker.service` and `docker.socket`, and how to restore the
   captured ruleset.

**After installing, before declaring anything works:**

6. Verify from a **third, freshly opened** connection — an established session proves nothing about
   whether new connections still arrive. Prove **both** routes.
7. Diff the before/after network and firewall state and **explain every difference**. Docker will
   legitimately add `docker0`, its own chains, and set `FORWARD` to `DROP`. Anything else is a
   finding.
8. Confirm no new listening socket is reachable off-box.

**Only then** does the learning work begin.

### 7.2 Installation

- Add Docker's repository with `signed-by`, deriving the codename from `/etc/os-release` rather than
  hardcoding it, and **refuse to continue if the repository does not declare the expected `Origin`
  and architecture** — the same guard `install-tailscale.sh` already implements (ADR-014).
- Install `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`,
  `docker-compose-plugin`.
- Record exact versions. Do not mark anything installed until real output exists.

> **Risk to anticipate:** Ubuntu 26.04 (`resolute`) is recent. If Docker does not publish packages
> for this codename, that is a **recorded problem with a decision attached**, not a silent fallback
> to an older suite or to `docker.io`. ADR-014 established that principle for Tailscale and it
> applies here.

### 7.3 Configuration

`/etc/docker/daemon.json`, with **log rotation only**:

```json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
```

Justification, because configuration without justification is how a project accumulates cargo: the
default `json-file` driver writes container logs with **no size limit**. A single chatty container
can fill the root filesystem, and this volume group **has no free extents**, so the usual remedy —
grow the volume — is unavailable. This is a concrete need, not a preference.

`vm.swappiness` is lowered and made persistent via `/etc/sysctl.d/`. Not lockout-class, but it is a
kernel tunable and gets recorded.

### 7.4 The learning work

Mapped onto Phase 02's tier model, which continues to apply:

| Tier | Meaning here | Examples |
|---|---|---|
| **1 — Free** | Read-only inspection | `docker ps`, `images`, `inspect`, `logs`, `system df`, `ps` on the host showing the container process |
| **2 — Sandboxed** | Disposable containers, images and Compose stacks — the direct analogue of Phase 02's `labuser` | `run --rm`, building a scratch image, `compose up`/`down`, deliberate breakage |
| **3 — Not this phase** | Anything that would change the host's network or expose a port off-box | `--network host`, `-p 0.0.0.0:…`, `--privileged`, changing Docker's iptables behaviour, subnet-routing or exit-node configuration |

Exercises expected to earn their place:

- Show a container process from the **host's** `ps`, proving it is not a virtual machine.
- `docker run --rm -it` something, and inspect its namespaces.
- Write a Dockerfile with a `USER` directive; prove `id` inside reports a non-zero UID.
- Rebuild after changing an early line vs a late line, and observe layer caching.
- Publish a port to `127.0.0.1` and **prove from the MacBook that it is not reachable**, then explain
  why `-p 8080:80` would have been.
- Break a container deliberately and diagnose it from `docker logs` and its exit code — the container
  counterpart of Phase 02's `status=203/EXEC` exercise.
- `docker system df`, then `docker system prune`, with before/after figures.

### 7.5 Teardown

Everything created is removed, and the removal is **proved**, as Phase 02 proved the sandbox was
gone. Images, containers, volumes and networks accounted for; `docker system df` showing the
reclaimed state; `ss -tln` identical to phase start.

## 8. Validation / tests

Every check produces real output. Nothing is marked passing without it.

1. `preflight.sh` run from the MacBook **before** the change; both routes proved.
2. Two sessions held during the change; session count verified with `w`, not `who`.
3. Before/after `ip`, `iptables-save`, `nft list ruleset`, `ss -tlnp` captured and **diffed**, with
   every difference explained.
4. **A third, freshly opened connection** succeeds on **both** routes after installation.
5. Docker repository verified — `signed-by`, `Origin`, suite, architecture — before install.
6. Versions recorded for engine, CLI, containerd, buildx, compose.
7. `docker run hello-world` succeeds.
8. A container process visible in the **host's** process table.
9. A container proved to run as a **non-root** UID.
10. An image built from a repository-committed Dockerfile.
11. A Compose stack up, inspected, and down.
12. **A published port on `127.0.0.1` proved unreachable from the MacBook**, and the reasoning
    recorded.
13. `daemon.json` in effect — confirmed from `docker info`, not from the file.
14. `vm.swappiness` changed, persistent across the setting being re-read.
15. `docker system df` before and after a prune.
16. **`ss -tln` at phase close is identical to phase start** — `:22` still the only port off-box.
17. Teardown proved: no leftover containers, images, volumes or networks beyond what was decided.
18. **`systemctl is-system-running` → `running`, 0 failed units** — checked **last**.
19. `id aleix` compared against phase start; any change is deliberate and recorded.

## 9. Security considerations

### 9.1 Docker rewrites packet filtering, and this machine has one network path

Covered in §7.1 as procedure. As a risk: Docker inserts `DOCKER`, `DOCKER-USER` and
`DOCKER-ISOLATION` chains, sets the `FORWARD` policy to `DROP`, and enables IP forwarding. On this
host `iptables` uses the **`nf_tables` backend**, and `tailscaled` maintains its own rules. The
interaction is the risk, and it is why the before/after ruleset diff is a validation item rather
than a nicety.

### 9.2 `-p 8080:80` bypasses host firewalls. This is the phase's most valuable convention.

Docker publishes ports by inserting **DNAT rules in the `nat` table**, which are evaluated *before*
the `filter` `INPUT` chain that `ufw` and similar tools manage. The practical consequence surprises
almost everyone:

> A container published with `-p 8080:80` is reachable from the LAN **even if the host firewall is
> configured to deny it.**

There is no firewall on this node yet — Phase 13 owns that — which makes now exactly the right time
to set the convention, before there are services to retrofit and before a firewall creates a false
sense of safety.

**Convention adopted by this phase:** every published port names an explicit interface.

```bash
-p 127.0.0.1:8080:80      # loopback only
-p 100.71.62.71:8080:80   # tailnet only
-p 8080:80                # NEVER -- this is 0.0.0.0
```

This must be proved, not asserted (validation 12), and carried into the Phase 13 brief, which will
otherwise install a firewall that does less than it appears to.

### 9.3 The `docker` group is equivalent to root

Anyone who can talk to the Docker socket can start a container that mounts the host filesystem and
read or write anything. There is no meaningful privilege boundary between `docker` group membership
and `root`.

Accepted here because `aleix` is the sole administrator and already has `sudo`. **It must never be
granted to a service account**, and any later phase that runs a container on a user's behalf needs to
treat socket access as root access. ADR-011 in container form.

### 9.4 Disk exhaustion is the realistic failure, and it cannot be fixed by growing the disk

Images, containers, volumes and build cache all land on the root logical volume. The volume group has
**no free extents**, so `lvextend` is not available. 214 G is free today and that is comfortable —
but the remedy when it is not comfortable is *reclaiming*, not *growing*. Hence log rotation in
`daemon.json` and `docker system df` as a taught command rather than a footnote.

### 9.5 Images are third-party code

Every `docker pull` executes someone else's software. This phase pulls only official images, and the
guide should say plainly that "it's in a container" is isolation, not trust. Deferring supply-chain
policy is reasonable; pretending the question does not exist is not.

### 9.6 The repository is public now

A `.env`, a compose file with a real credential, or a token baked into an image layer is a
**disclosure**, not an amendable mistake (ADR-021). Run `scan-history.sh` before pushing, as Phase 04
made routine, and remember an image layer keeps a secret even after a later layer deletes it.

## 10. Repository changes expected

| Path | Change |
|---|---|
| `docs/handovers/05-docker.md` | **This brief** — committed first |
| `scripts/server/install-docker.sh` | New — repository verification and installation, guarded like `install-tailscale.sh` |
| `scripts/server/capture-network-state.sh` | New (presumed, §6.5) — before/after capture for lockout-class changes. **Must strip MAC addresses** |
| `config/docker/daemon.json` | New — log rotation, with justification in a comment or adjacent README |
| `infrastructure/docker/` | New — the example Dockerfile and Compose file built during the phase |
| `guide/05-docker/README.md` | New — the phase guide |
| `guide/README.md` | Phase 05 entry |
| `docs/reference/docker-reference.md` | New — operational commands, grouped by question asked |
| `docs/decisions/ADR-022-…` | New — Docker runtime, port-publishing convention, `docker` group |
| `docs/build-log/2026-09-09-phase-05-*.md` | New — problems, failures, lessons |
| `docs/handovers/05-docker-handover.md` | New — addressed to Phase 06 |
| `docs/handovers/README.md` | Two new rows |
| `docs/reference/project-state.md` | Phase 05 status; swappiness closed; new risks |
| `docs/reference/software-stack.md` | Docker, Compose, containerd → Active with tested versions |
| `docs/reference/costs.md` | Phase 05 section — expected explicit zero |
| `scripts/README.md` | Rows for new scripts |
| `ROADMAP.md` / `CHANGELOG.md` | Phase 05 marked complete |

## 11. Guide documentation required

`guide/05-docker/README.md`, following Phases 01–04:

- Explains containers as **Linux processes**, using output from this machine.
- Leads with the ADR-020 procedure, because that is the part that could actually cost something.
- Names the two things most worth remembering: **`-p` bypasses your firewall**, and **a secret in an
  image layer survives its deletion** — the Phase 04 `.gitignore` lesson in new clothing.
- Includes a reference-build experience section recording what actually went wrong.

## 12. Project documentation required

As listed. Specifically: `software-stack.md` records exact tested versions; `project-state.md` closes
the `vm.swappiness` item and records Docker's effect on the network baseline; `costs.md` records an
explicit zero.

## 13. ADRs required / possible

| ADR | Status | Subject |
|---|---|---|
| **ADR-022 — Docker runtime and container conventions** | **Required** | Rootful with non-root containers; official repository over `docker.io`; **explicit-interface port publishing**; `docker` group as root-equivalence; log rotation as a disk-exhaustion control. Records the rejected alternatives, including rootless. |
| Firewall interaction | **Not this phase** | Phase 13 owns firewalling; this brief hands it §9.2 as an inherited constraint. |

## 14. Costs

**Expected: 0 DKK.** Docker Engine and Compose are free and open source. No new hardware, no
subscription. Running total expected to remain **899 DKK (~121 EUR)**.

## 15. Definition of Done

From `PROJECT.md` §12, applied **literally, item by item**:

- [ ] Functional objective works — all twelve in §4
- [ ] Configuration/setup is reproducible — installation is a committed, guarded script; `scp`'d, not pasted
- [ ] Validation/tests have passed — all nineteen checks in §8, with captured output
- [ ] Important security implications were considered — §9, and the ADR-020 procedure evidenced
- [ ] Relevant repository files are committed
- [ ] Human-facing guide is updated — `guide/05-docker/README.md`
- [ ] Project/internal documentation is updated
- [ ] ADRs created or updated — ADR-022
- [ ] Actual costs recorded — explicit zero
- [ ] Problems, failed approaches and lessons recorded, including my own errors
- [ ] Tested versions recorded — engine, CLI, containerd, buildx, compose
- [ ] No unexplained critical AI-generated component remains
- [ ] `main` represents a known-working state — after `--no-ff` merge of `feature/05-docker`
- [ ] System reports no failed units and no degraded state — checked **last**
- [ ] Structured handover written, stating what Phase 06 inherits

## 16. Return handover requirements

Addressed to **Phase 06 — AI CLI Access**, and must state:

1. **The exact network and firewall delta Docker introduced**, so Phase 13 can reason about a
   firewall on top of it rather than discovering the interaction under pressure.
2. **The port-publishing convention**, as a rule Phase 06 onward is expected to follow, with §9.2's
   reasoning attached — not just the rule.
3. **Whether `aleix` is in the `docker` group**, and the root-equivalence consequence.
4. **Disk headroom and how to reclaim it**, with the no-free-extents constraint restated. Phase 06
   installs AI CLIs; Phase 10 will store data.
5. **That nothing persistent is running**, with proof, so Phase 06 does not inherit a phantom service.
6. **Open risks carried forward** — the single SSH key, no firewall, no encryption at rest, `eno1`
   unused, no node backup — plus anything Docker added.
7. **Whether the ADR-020 procedure was sufficient**, and any step that turned out to be missing.
   Phase 13 is the worst lockout risk in the roadmap and inherits whatever this phase learns.
