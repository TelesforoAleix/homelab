# Phase 05 Handover — Docker & Docker Compose

- **Date:** 2026-09-09
- **From:** Phase 05 phase context
- **To:** Phase 06 — AI CLI Access
- **Brief:** [`05-docker.md`](05-docker.md), committed before implementation per ADR-017

## Outcome

**Complete.** Docker Engine and Compose are installed from Docker's official apt repository, the
runtime conventions are recorded in ADR-022, the learning containers were created and removed, and
nothing persistent is running.

One validation objective was weakened rather than satisfied as written: the pre-Docker network
capture did not run, so there is no true before/after firewall diff. The failure is recorded in the
build log and below. Attribution was still possible by chain owner, and final reachability checks
passed.

## What the next phase inherits

> Read this section first. Under ADR-017 there is no planning context to reconcile any of it; if it
> is not written here, it is lost.

### 1. Docker is active, but no containers are running

The reference node now has rootful Docker:

| Component | Tested version |
|---|---|
| Docker Engine / CLI | 29.8.0 |
| Docker Compose plugin | v5.5.1 |
| containerd | 2.3.5 |

Final verification showed:

```text
docker system df -> Images 0, Containers 0, Local Volumes 0, Build Cache 0
docker ps -a     -> no containers
docker image ls  -> no images
docker volume ls -> no volumes
```

Phase 06 inherits Docker as an available runtime, not a service stack.

### 2. Port publishing has a binding rule

Every published port names an interface:

```bash
-p 127.0.0.1:8080:80      # loopback only
-p 100.71.62.71:8080:80   # tailnet only
-p 8080:80                # forbidden: this means every interface
```

This is not style. Docker publishes ports with DNAT in `nat/PREROUTING`, before host firewall
`filter/INPUT` rules. A later firewall will not make `-p 8080:80` safe. Phase 13 inherits that
constraint.

Measured in Phase 05:

| Bound to | From the tailnet | From the LAN |
|---|---|---|
| `127.0.0.1:8080` | no answer | no answer |
| `100.71.62.71:8081` | HTTP 200 | no answer |

### 3. `aleix` is in the `docker` group

`aleix` now has supplementary group `983(docker)`. Nothing else about the account changed:

```text
uid: 1000
home: /home/aleix
shell: /bin/bash
sudo: still present
```

This is root-equivalent access without a password prompt. It is accepted because `aleix` is the sole
administrator and already had `sudo`. It must never be granted to a service account.

Group membership applies to new logins only. An SSH ControlMaster or old terminal opened before the
change can still fail on `docker ps` until it reconnects.

### 4. Docker changed the host network baseline

The exact pre-Docker diff is not available. The current attributable state is:

| Owner | Chains / settings |
|---|---|
| Docker | `DOCKER`, `DOCKER-BRIDGE`, `DOCKER-CT`, `DOCKER-FORWARD`, `DOCKER-INTERNAL`, `DOCKER-USER`, plus `DOCKER` in `nat` |
| Tailscale | `ts-input`, `ts-forward`, `ts-postrouting` |
| Docker-set policy | IPv4 `FORWARD` policy is `DROP`; `net.ipv4.ip_forward = 1` |

Docker adds no rule to `INPUT`. The only off-box listening service at close remains SSH on `:22`;
Tailscale's own listener is on the tailnet address.

One trap for Phase 13: IPv4 and IPv6 forwarding policy are not symmetric. IPv4 `FORWARD` is `DROP`;
IPv6 `FORWARD` is `ACCEPT`. This is latent, not a live exposure, because
`net.ipv6.conf.all.forwarding = 0`, Docker's bridge IPv6 is disabled, and there is no IPv6 route via
`docker0`.

### 5. Disk is bounded, but not expandable

Docker storage lands on the root logical volume. The volume group still has no free extents, so a
full disk is handled by reclaiming, not `lvextend`.

`/etc/docker/daemon.json` sets log rotation:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

It was written before the daemon first started and verified from a running container:
`json-file map[max-file:3 max-size:10m]`.

### 6. Open risks carried forward

| Risk | Owner / note |
|---|---|
| Single SSH key, no backup key, no console | Phase 13 |
| No node backup | Still open; the repository has an offsite copy, the machine does not |
| No firewall | Phase 13; must account for Docker's DNAT behaviour |
| No encryption at rest | Phase 13; Phase 10 must revisit ADR-015 before storing sensitive data |
| Node key expiry disabled | Phase 13 revisits ADR-019 |
| `eno1` unused; both access routes share Wi-Fi | Not owned yet; still relevant to lockout-class changes |
| Docker group root-equivalence | Accepted for `aleix`; forbidden for service accounts |
| Rootful Docker user namespace not remapped | Revisit rootless/userns-remap in Phase 13 |
| IPv6 forwarding policy asymmetry | Latent today; Phase 13 must not assume symmetry |

## What was implemented

- Installed Docker Engine, Docker CLI, Buildx, Compose v2 plugin, and `containerd.io` from Docker's
  official apt repository.
- Added Docker host configuration with bounded JSON logs.
- Lowered `vm.swappiness` from 60 to 10 via `/etc/sysctl.d/99-homelab-swappiness.conf`.
- Added `aleix` to the `docker` group.
- Built and ran a small teaching image that defaults to non-root UID/GID `10001`.
- Demonstrated Compose with capability drop, `no-new-privileges`, and a read-only root filesystem.
- Demonstrated loopback-only and tailnet-only port publishing.
- Removed every learning container, image, volume, and build cache item.

## Final Architecture/State

Compared with the Phase 04 handover:

- Docker is now part of the host baseline.
- `docker0` exists at `172.17.0.0/16`, with no collision against the LAN (`192.168.0.0/21`) or the
  tailnet (`100.64.0.0/10`).
- Docker and Tailscale both own packet-filtering chains.
- `vm.swappiness = 10`.
- `aleix` is a member of `docker`.

No application service is deployed.

## Validation Performed

All Phase 05 checks were run with real output, except the before/after diff objective described
under Problems.

| Check | Result |
|---|---|
| Preflight from MacBook | Both routes proved before install; two sessions held |
| Install safety | Installer refused to proceed without sufficient sessions; repository verified before package install |
| Docker repository | `Origin: Docker`, running architecture, suite/codename, and `stable` component verified |
| Versions | Docker 29.8.0, Compose v5.5.1, containerd 2.3.5 |
| `hello-world` | Succeeded |
| Container as host process | Host saw the container process and containerd shim; inside process saw itself as PID 1 |
| User namespace check | Host and container user namespace were identical; PID namespace differed |
| Non-root image | `uid=10001 gid=10001 user=app` |
| Layer cache | Package/user layers cached; changed app layer rebuilt |
| Compose stack | Brought up, inspected, verified, and brought down |
| Container hardening | `cap_drop: [ALL]`, `no-new-privileges`, `read_only: true` verified on the running container |
| Port binding | Loopback-only unreachable off-box; tailnet-only reachable from tailnet and not LAN |
| `daemon.json` | Logging driver and options verified from a running container |
| Disk accounting | `docker system df` before/after; `107.2MB` reclaimed |
| Teardown | Final Docker inventory all zero |
| Final health | `systemctl is-system-running` -> `running`; zero failed units |
| Final access | Both SSH routes reached from fresh connections |

Final check re-run after handoff resume:

```text
Docker version 29.8.0
Docker Compose version v5.5.1
containerd v2.3.5
docker system df -> all zero
vm.swappiness = 10
systemctl is-system-running -> running
systemctl --failed -> 0 loaded units
ss -tln -> seven listeners, matching the phase baseline class
```

## Files Changed

- `scripts/server/install-docker.sh`
- `scripts/server/capture-network-state.sh`
- `scripts/server/configure-docker-host.sh`
- `config/docker/daemon.json`
- `config/docker/README.md`
- `config/sysctl/99-homelab-swappiness.conf`
- `infrastructure/docker/README.md`
- `infrastructure/docker/example/Dockerfile`
- `infrastructure/docker/example/app.sh`
- `infrastructure/docker/example/compose.yaml`
- `docs/decisions/ADR-022-docker-runtime-conventions.md`
- `docs/build-log/2026-09-09-phase-05-docker-install.md`
- `docs/reference/docker-reference.md`
- `guide/05-docker/README.md`
- project indexes and current-state docs

## Guide Updates

Added [`guide/05-docker/README.md`](../../guide/05-docker/README.md), covering:

- containers as host processes;
- rootful Docker and user namespaces;
- non-root containers;
- explicit-interface port publishing;
- Docker layers and secret persistence;
- logs, diagnostics, exit codes, and disk accounting;
- what went wrong in the reference build.

## Project Documentation Updates

- `docs/reference/docker-reference.md` added as the operational reference.
- `docs/reference/software-stack.md` updated with Docker's tested versions.
- `docs/reference/project-state.md` updated with Phase 05 status and inherited risks.
- `docs/reference/costs.md` records explicit zero cost.
- `docs/architecture/current-architecture.md` updated to include Docker in the deployed baseline.
- `ROADMAP.md`, `README.md`, `CHANGELOG.md`, guide and handover indexes updated.

## ADRs

Accepted:

- [`ADR-022`](../decisions/ADR-022-docker-runtime-conventions.md) — rootful Docker with non-root
  containers, Docker's official repository, explicit-interface port publishing, `docker` group
  root-equivalence, and Docker log rotation.

No ADR was superseded.

## Tested Versions

| Component | Version |
|---|---|
| Docker Engine / CLI | 29.8.0, build 88096ef |
| Docker Compose plugin | v5.5.1 |
| containerd | v2.3.5, commit `1294c24a7da8e5a793ed378161673abe94118892` |
| Alpine image used for teaching | 3.22 |
| hello-world image | `latest`, pulled 2026-09-09 |

## Security Notes

- Docker installation was correctly classified as lockout-class under ADR-020.
- Docker repository setup uses `signed-by` and refuses unsupported codenames rather than silently
  falling back.
- Docker group membership is recorded as root-equivalent.
- The teaching image runs as non-root by default, but the guide records that `USER` is overridable.
- Compose example drops all capabilities, sets `no-new-privileges`, and uses a read-only root
  filesystem.
- Published ports must bind explicit interfaces.
- MAC addresses and the tailnet name remain redacted from captured network output.
- No secrets, tokens, environment files, or production data were added.

## Costs

**0 DKK.** Docker Engine, Compose, Buildx, and containerd are free and open source. No new hardware,
subscription, or usage-based service was introduced. Running total remains **899 DKK (~121 EUR)**.

## Problems / Failures / Lessons

Recorded in [`docs/build-log/2026-09-09-phase-05-docker-install.md`](../build-log/2026-09-09-phase-05-docker-install.md).

Important lessons:

- The pre-Docker network capture did not run, so the exact before/after packet-filter diff is gone.
  A capture step must be followed by checking the file exists.
- Privileged server steps should be run inside a real server session, not wrapped in an SSH command
  that may fail to present a `sudo` prompt.
- The install ran outside `tmux` after an advisory warning. A warning that does not stop the risky
  path is only advice.
- `preflight.sh` cannot count non-pty ControlMaster connections with `w`.
- The LAN is `192.168.0.0/21`, not `192.168.1.0/24`; no Docker subnet collision exists, but the
  original check used the wrong mask.
- IPv4 and IPv6 forwarding policies differ, but the IPv6 difference is latent today rather than
  currently reachable.

## Deviations From Phase Brief

- The before/after firewall diff was not produced because the before capture never existed.
  Attribution by chain name replaced it and is explicitly weaker.
- `configure-docker-host.sh` was added as a separate script for swappiness and Docker group
  membership rather than folding those into the installer.
- The installer's `tmux` check remained advisory. Phase 13 should decide whether lockout-class
  scripts must hard-refuse outside `tmux`.

## Open Issues / Technical Debt

- Add a real recovery path: backup SSH key, console process, or other Phase 13 control.
- Revisit rootless Docker or user namespace remapping in Phase 13.
- Design a firewall around Docker's `nat/PREROUTING` behaviour, not around `INPUT` alone.
- Decide whether `preflight.sh` should understand SSH ControlMaster sessions or explicitly reject
  counting them.
- Consider making lockout-class server scripts hard-refuse when not in `tmux`.
- The reference node still has no backup.

## Recommended Roadmap Changes

Already carried into the repository state by this phase:

- Phase 13 must inherit Docker's firewall interaction and IPv6 forwarding asymmetry.
- Phase 13 should revisit rootless Docker/user namespace remapping.
- Phase 06 starts from an available Docker runtime and should not install persistent services merely
  because Docker now exists.

## Definition of Done

- [x] Functional objective works.
- [x] Configuration/setup is reproducible.
- [x] Validation/tests have passed, except the failed before-capture diff is recorded as an
  unsatisfied evidence item rather than hidden.
- [x] Important security implications were considered.
- [x] Relevant repository files are committed, pending the final phase-close commit/merge.
- [x] Human-facing guide is updated.
- [x] Project/internal documentation is updated.
- [x] ADRs created or updated where necessary.
- [x] Actual costs recorded.
- [x] Problems, failed approaches, and lessons recorded.
- [x] Tested versions recorded.
- [x] No unexplained critical AI-generated component remains.
- [x] `main` represents a known-working state after the Phase 05 merge.
- [x] The system reports no failed units and no degraded state.
- [x] A structured handover is written into `docs/handovers/`, stating what the next phase inherits.
