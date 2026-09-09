# Docker host configuration

## `daemon.json`

Installed to `/etc/docker/daemon.json` by `scripts/server/install-docker.sh`,
**before** the package first starts the daemon, so log rotation applies from the
first container rather than from a later restart.

Log rotation is the only thing configured here, and it has a concrete
justification rather than being a preference.

The default `json-file` logging driver writes container logs with **no size
limit**. A single chatty container can fill the root filesystem. On this node
that is not merely inconvenient: the volume group has **no free extents**, so
the usual remedy — grow the logical volume — is unavailable. The only remedy is
reclaiming space, so the sensible thing is not to lose it in the first place.

`3 × 10m` per container is a deliberate ceiling, not a default someone copied.

Nothing else is set. `default-address-pools`, custom storage drivers and the
rest are speculative configuration until a phase has a concrete need for them
(`AGENTS.md`).

Verify it is actually in effect from the **running daemon**, not from the file:

```bash
docker info --format '{{.LoggingDriver}}'
docker inspect <container> --format '{{.HostConfig.LogConfig}}'
```
