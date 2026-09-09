# Docker Reference

Operational counterpart to [`guide/05-docker/README.md`](../../guide/05-docker/README.md).
The guide explains *why*; this is what you reach for mid-task.

Grouped by the question being asked, like
[`linux-command-reference.md`](linux-command-reference.md) and
[`git-workflow.md`](git-workflow.md).

- **Engine:** Docker 29.8.0, Compose v5.5.1, containerd 2.3.5 (rootful, ADR-022)
- **`aleix` is in the `docker` group** — which is root-equivalent, with no password prompt
- **Log rotation:** `json-file`, 3 × 10 MB per container, set in `/etc/docker/daemon.json`

---

## The rule that matters most

**Every published port names an interface.**

```bash
-p 127.0.0.1:8080:80      # loopback only
-p 100.71.62.71:8080:80   # tailnet only
-p 8080:80                # FORBIDDEN -- means 0.0.0.0, every interface
```

Docker publishes with a DNAT rule in `nat/PREROUTING`, evaluated **before**
`filter/INPUT`. A published port is reachable even when a host firewall denies
it. There is no firewall on this node yet; when Phase 13 adds one, this stays
true.

---

## "What is running, and what is it doing?"

| Question | Command |
|---|---|
| What is running? | `docker ps` |
| **What exists at all, including crashed?** | `docker ps -a` |
| What is it exposing? | `docker port <name>` |
| What is the host listening on? | `ss -tln` |
| What user is it running as? | `docker exec <name> id` |
| Its PID on the host | `docker inspect -f '{{.State.Pid}}' <name>` |
| Everything about it | `docker inspect <name>` |
| Live resource use | `docker stats --no-stream` |

`docker ps` hides exited containers. If something "did not start" and the list is
empty, you are looking at the wrong list.

---

## "Why won't it start?"

```bash
docker ps -a                                              # is it even there?
docker logs <name>                                        # what did it say?
docker inspect <name> --format '{{.State.ExitCode}}'      # how did it die?
docker inspect <name> --format '{{.State.Error}}'
```

| Exit code | Means |
|---|---|
| `0` | ran and finished successfully |
| `1`–`125` | **the program ran and failed** — its own exit status |
| `126` | found but not executable |
| `127` | **command not found — it never ran** |
| `137` | killed (SIGKILL) — often the OOM killer |
| `143` | terminated (SIGTERM) — a normal `docker stop` |

`127` vs a small number is the same distinction as systemd's `203/EXEC` vs `1`,
and it sends you to entirely different places (Phase 02).

---

## "Where has the disk gone?"

The volume group has **no free extents**. The root LV cannot be grown by
`lvextend`. Reclaiming is the only remedy.

```bash
docker system df                  # images / containers / volumes / build cache
docker system df -v               # per-item detail
docker system prune -a            # everything unused EXCEPT volumes
docker system prune -a --volumes  # includes volumes -- deletes data
docker builder prune              # build cache only
```

`prune` without `--volumes` leaves volumes alone, which is usually what you want:
volumes hold the data you meant to keep.

Logs are the other way it fills up. The default driver is unbounded; this host
caps it at 3 × 10 MB per container. Verify from the running container:

```bash
docker inspect <name> --format '{{.HostConfig.LogConfig}}'
```

---

## "Is this container actually contained?"

```bash
docker inspect <name> --format '{{.Config.User}}'                 # non-root?
docker inspect <name> --format '{{.HostConfig.CapDrop}}'
docker inspect <name> --format '{{.HostConfig.ReadonlyRootfs}}'
docker inspect <name> --format '{{.HostConfig.SecurityOpt}}'
docker inspect <name> --format '{{.HostConfig.Privileged}}'       # must be false
docker exec <name> grep CapEff /proc/1/status
```

Remember what rootful means: the container's user namespace is **the host's**
(measured: both `user:[4026531837]`). A container running as root is running as
the host's root; capabilities are what stand in between, not identity.

`USER` in a Dockerfile is a default, not a guarantee — `--user 0:0` overrides it.

---

## "What did Docker do to the network?"

```bash
ip -br link | grep -E 'docker|br-'
ip route | grep docker
sudo iptables-save | grep -E '^(-A|:)(DOCKER|FORWARD|INPUT|PREROUTING)'
docker network ls
docker network inspect bridge
```

On this host, after installation:

| Fact | Value |
|---|---|
| Bridge | `docker0`, `172.17.0.0/16` — no collision with the LAN (`192.168.0.0/21`) or tailnet (`100.64.0.0/10`) |
| Docker's chains | `DOCKER`, `DOCKER-BRIDGE`, `DOCKER-CT`, `DOCKER-FORWARD`, `DOCKER-INTERNAL`, `DOCKER-USER` |
| Tailscale's chains | `ts-input`, `ts-forward`, `ts-postrouting` |
| Rules added to `INPUT` | **none** |
| `FORWARD` policy | `DROP` on IPv4, **`ACCEPT` on IPv6** — see below |
| `net.ipv4.ip_forward` | `1` (Docker set it) |

**The IPv6 asymmetry is latent, not live.** `net.ipv6.conf.all.forwarding = 0`,
Docker's bridge has IPv6 disabled, and there is no IPv6 route via `docker0` — so
nothing is forwarded. It becomes real if anyone enables IPv6 forwarding, Docker
IPv6, or Tailscale subnet routing. Phase 13 must not assume the two families
match.

---

## Compose

```bash
docker compose up -d
docker compose ps -a
docker compose logs -f
docker compose config          # render the file as Compose actually reads it
docker compose down            # add -v to remove named volumes
```

`docker compose config` is the underrated one: it resolves variables and defaults
so you see what will actually run rather than what you think you wrote.

Compose is preferred to long `docker run` lines because a `run` line with eight
flags lives only in shell history, and shell history is not documentation.

---

## Before a lockout-class change

Docker is installed, but any later change to its networking is still
lockout-class (ADR-020).

```bash
# On the Mac
bash scripts/macos/preflight.sh

# On the server, in tmux
tmux new -A -s work
sudo bash /tmp/capture-network-state.sh before
ls -l /tmp/netstate-before.txt        # CONFIRM IT EXISTS

# afterwards, from the Mac, a genuinely NEW connection
ssh -o ControlPath=none homelab true
```

Two things learned the hard way in Phase 05:

- **Confirm the capture file exists.** The reference build's `before` capture
  silently never ran, and the pre-Docker ruleset is gone permanently.
- **A ControlMaster connection cannot verify a route** — it rides an existing
  TCP connection. Use `-o ControlPath=none`. It also does not show up in `w`, so
  `preflight.sh` will not count it as a session.

---

## Conventions in force (ADR-022)

- Rootful daemon; **every container runs as a non-root user**.
- `cap_drop: [ALL]`, `no-new-privileges`, `read_only` where the workload allows.
- **Every published port names an interface.** Never `-p 8080:80`.
- `--privileged` and `--network host` are not used. If a phase needs either, it
  needs an ADR.
- Images come from official sources. "It's in a container" is isolation, not
  trust — every `docker pull` runs someone else's code.
- The `docker` group is **never** granted to a service account (ADR-011).
