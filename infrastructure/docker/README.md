# Container definitions

## `example/`

The Phase 05 teaching image. Deliberately small and deliberately boring: its
job is to demonstrate three things, not to be useful.

| File | Shows |
|---|---|
| `Dockerfile` | A non-root `USER`, and why instruction order decides what rebuilds |
| `app.sh` | Reports its own uid, so "non-root" is observable rather than claimed |
| `compose.yaml` | The port-publishing convention, and per-service hardening |

Build and run:

```bash
docker build -t homelab-example:1 .
docker run --rm homelab-example:1
docker compose up -d && docker compose logs && docker compose down
```

### Why `USER` is not sufficient on its own

`USER app:app` in the Dockerfile is a **default, not a guarantee**. It is
overridden by `--user`:

```console
$ docker run --rm homelab-example:1
uid=10001 gid=10001 user=app

$ docker run --rm --user 0:0 homelab-example:1
uid=0 gid=0 user=root
```

That matters more than it looks, because on a rootful daemon with no
user-namespace remapping, the container's root **is** the host's root.
Measured on the reference node:

```console
host  user ns: user:[4026531837]
container    : user:[4026531837]     <-- same namespace
host  pid ns:  pid:[4026531836]
container    : pid:[4026532342]      <-- different namespace
```

The PID namespace isolates. The user namespace does not. What stands between a
root container and the host is capabilities and seccomp, nothing more — which
is why `compose.yaml` drops all capabilities and sets `no-new-privileges`.

### The port-publishing convention (ADR-022)

Every published port names an interface. `"8080:80"` means `0.0.0.0` — every
interface, including the LAN.

```yaml
ports:
  - "127.0.0.1:8080:80"     # loopback only
  - "100.71.62.71:8080:80"  # tailnet only
```

Measured on the reference node, with two containers running simultaneously:

| Bound to | From the tailnet | From the LAN |
|---|---|---|
| `127.0.0.1:8080` | no answer | no answer |
| `100.71.62.71:8081` | **HTTP 200** | no answer |

See `guide/05-docker/README.md` for why a host firewall would not have saved
you from the `0.0.0.0` form.
