# 05 — Docker & Docker Compose

## Goal

Understand what a container actually is, run one safely on a machine you cannot
walk up to, and know why the way you publish a port is a security decision
rather than a formatting choice.

By the end you should be able to look at any `docker run` line and say what it
exposes, what privileges it holds, and where its disk usage will land.

## Why this matters

Every phase from here on is expected to run things in containers. But the reason
this phase is written the way it is has less to do with containers than with the
machine:

**This is the first change in the project that could have locked you out.**

Docker creates network interfaces, rewrites packet-filtering rules, and enables
IP forwarding. `docs/standards/safe-changes-headless.md` calls that
lockout-class, because it touches the network. And on this node the network is
not one path but the only path — `eno1` is down with no carrier, so
`ssh homelab` (Tailscale) and `ssh homelab-lan` (LAN) are independent above the
link layer and **identical below it**. Losing the network does not cost you one
route. It costs both, at once, on a machine with no monitor.

Phases 01 and 03 did their dangerous work with a screen an arm's length away.
Phase 02 avoided lockout-class changes entirely. Phase 04 never touched the node.
This is the one the standard was written for.

### What we are not doing

Not a container textbook. A concept earns a place only if it explains something
this project has done or will do by Phase 07. So there is a lot about
namespaces, port publishing and disk, and nothing about Kubernetes, swarm mode,
or multi-stage build tricks.

**Nothing is left running.** No monitoring UI, no log viewer, no service the
roadmap has not asked for. This is a learning phase, and `AGENTS.md` says
infrastructure gets added when a phase has a concrete need.

---

## 1. Before you type anything: the procedure

This is not preamble. It is the part that could have cost something.

```bash
# On the MacBook
bash scripts/macos/preflight.sh
```

It proves both routes arrive **from outside**, which a script on the server
cannot do — it would be inside the thing it is testing.

Then, on the server:

```bash
tmux new -A -s docker          # -A: attach if it exists, create if not
sudo bash /tmp/capture-network-state.sh before
```

**Check the file exists. Do not trust your memory of running the command.**

```bash
ls -l /tmp/netstate-before.txt
```

In the reference build this step silently did not run, and the pre-Docker
firewall rules are gone permanently. See "What actually went wrong" below.

Two more things before the install:

- **Two sessions**, one idle, as the way back. Count them with `w`, never
  `who` — `/run/utmp` does not exist on systemd 259, so `who` reports zero
  sessions while exiting 0.
- **Type the rollback before the change**, so it exists when you need it rather
  than being composed under stress:

```bash
sudo systemctl stop docker.socket docker.service
sudo systemctl disable docker.socket docker.service
```

### Afterwards — and this is the part people skip

```bash
# From the MacBook, a THIRD, freshly opened connection
ssh homelab true && ssh homelab-lan true
```

An **established** session proves nothing about whether **new** connections can
arrive. If you are using SSH connection multiplexing, force a real one:

```bash
ssh -o ControlPath=none homelab true
```

That distinction caught nothing this time. It is the entire point of the check.

---

## 2. What a container actually is

Not a small virtual machine. There is no guest kernel. A container is **an
ordinary process on the host**, isolated by namespaces and limited by cgroups.

Prove it rather than believing it:

```console
$ docker run -d --name proof alpine:3.22 sleep 300
$ docker inspect -f '{{.State.Pid}}' proof
9760

$ ps -o pid,ppid,user,args -p 9760
    PID    PPID USER     COMMAND
   9760    9736 root     sleep 300

$ ps -o pid,ppid,args -p 9736
    PID    PPID COMMAND
   9736       1 /usr/bin/containerd-shim-runc-v2 -namespace moby -id 57ed0d…
```

The host can see the process. Its parent is a containerd shim, whose parent is
PID 1. No hypervisor anywhere.

Inside, the same process believes it is PID 1:

```console
$ docker exec proof ps -o pid,args
  PID   COMMAND
    1   sleep 300
```

One process, two truths, because of one namespace.

### The namespace that is *not* isolated

This is the most important thing in this section.

```console
$ readlink /proc/self/ns/pid            # host
pid:[4026531836]
$ docker exec proof readlink /proc/1/ns/pid
pid:[4026532342]                        # different -- isolated

$ readlink /proc/self/ns/user           # host
user:[4026531837]
$ docker exec proof readlink /proc/1/ns/user
user:[4026531837]                       # THE SAME
```

The PID namespace isolates. **The user namespace does not.** With a rootful
daemon and no user-namespace remapping, a container running as root is running
as *the host's* root — uid 0 is uid 0.

What stands between it and your machine is capabilities, not identity:

```console
$ docker exec proof grep CapEff /proc/1/status
CapEff:  00000000a80425fb          # a subset

# a fully privileged process would show 000001ffffffffff
```

That is the whole argument for the next section.

---

## 3. Run containers as non-root

```dockerfile
RUN addgroup -g 10001 -S app \
 && adduser  -u 10001 -S app -G app
USER app:app
```

```console
$ docker run --rm homelab-example:1
uid=10001 gid=10001 user=app
STATUS: running as a non-root user, which is what we want
```

**But `USER` is a default, not a guarantee:**

```console
$ docker run --rm --user 0:0 homelab-example:1
uid=0 gid=0 user=root
```

Anyone who can run `docker` can override it. That is fine — it is a good default
and a bad control. The actual controls are in Compose:

```yaml
cap_drop: [ALL]
security_opt: ["no-new-privileges:true"]
read_only: true
```

Verified on the running container, not read back from the file:

```console
$ docker inspect $CID --format '{{.HostConfig.ReadonlyRootfs}} {{.HostConfig.CapDrop}}'
true [ALL]

$ docker run --rm --read-only homelab-example:1 sh -c 'touch /nope'
touch: /nope: Read-only file system
```

---

## 4. `-p` is a security decision

**The most valuable thing in this phase.**

Docker publishes a port by inserting a **DNAT rule in `nat/PREROUTING`**. That
chain is evaluated *before* `filter/INPUT` — the chain `ufw` and every similar
tool manages.

The consequence surprises almost everyone:

> A container published with `-p 8080:80` is reachable from the LAN **even if
> your host firewall is configured to deny it.**

This is not folklore. On the reference node, Docker adds **nothing at all** to
`INPUT`:

```text
-A INPUT -j ts-input        <-- the only INPUT rule, and it belongs to Tailscale

-A PREROUTING -m addrtype --dst-type LOCAL -j DOCKER
```

Everything Docker does happens in `nat` and `FORWARD`. Your firewall's `INPUT`
rules never see the packet.

### The convention

**Every published port names an interface.**

```bash
-p 127.0.0.1:8080:80      # loopback only  -- nothing off-box
-p 100.71.62.71:8080:80   # tailnet only   -- your devices, over an authenticated network
-p 8080:80                # FORBIDDEN      -- this means 0.0.0.0, every interface
```

Measured with two containers running simultaneously:

| Bound to | From the tailnet | From the LAN |
|---|---|---|
| `127.0.0.1:8080` | no answer | no answer |
| `100.71.62.71:8081` | **HTTP 200** | no answer |

The tailnet form is the useful middle ground for this project: reachable from
your own devices, invisible to everything else on the network — and it does not
depend on a firewall existing, which is convenient, because one does not.

---

## 5. Layers, and the secret that will not go away

Each Dockerfile instruction is a cached layer. A layer rebuilds only if it, or
something before it, changed. So: **least-likely-to-change first.**

```dockerfile
RUN apk add --no-cache tini        # rarely changes -> near the top
COPY app.sh /app/app.sh            # changes constantly -> near the bottom
```

Change only `app.sh` and rebuild:

```console
#6 [2/5] RUN apk add --no-cache tini
#6 CACHED
#7 [3/5] RUN addgroup -g 10001 -S app  && adduser -u 10001 -S app -G app
#7 CACHED
#8 [4/5] COPY --chown=app:app app.sh /app/app.sh
#9 [5/5] RUN chmod 0555 /app/app.sh
```

The `apk` layer stayed cached. Put `COPY` first and every one-character edit
re-runs the package manager.

### The security consequence

A layer is immutable. If you `COPY` a secret in one instruction and `rm` it in
the next, **the secret is still in the earlier layer** and travels with the
image to anyone who pulls it.

If that feels familiar, it should: it is the Phase 04 `.gitignore` lesson in
different clothing. Removing something at the tip does not remove it from the
history. Same shape, different technology, same fix — never put it there, and if
you did, rotate the credential first.

---

## 6. Diagnosing a container that will not run

The container equivalent of Phase 02's `systemctl status` work.

```console
$ docker run --name broken1 homelab-example:1 /nonexistent
[FATAL tini (7)] exec /nonexistent failed: No such file or directory
$ docker inspect broken1 --format '{{.State.ExitCode}}'
127

$ docker run --name broken2 homelab-example:1 sh -c 'echo "doing work"; exit 42'
doing work
$ docker inspect broken2 --format '{{.State.ExitCode}}'
42
```

**127 = the command was never found. 42 = it ran and failed.** Exactly the
distinction Phase 02 drew between systemd's `203/EXEC` and `1`, and it directs
your attention to completely different places.

### The trap

```console
$ docker ps
CONTAINER ID   IMAGE   ...        # empty!

$ docker ps -a
broken2  Exited (42)
broken1  Exited (127)
```

`docker ps` shows only **running** containers. A container that crashed on
startup is invisible without `-a`. If something "did not start" and you see
nothing, you are looking at the wrong list.

---

## 7. Where the disk goes

This node's volume group has **no free extents**. The root LV cannot be grown by
`lvextend`. The remedy for a full disk here is reclaiming, never growing — so
learn the accounting early.

```console
$ docker system df
TYPE            TOTAL     ACTIVE    SIZE      RECLAIMABLE
Images          4         1         116MB     103.1MB (88%)
Containers      2         0         8.192kB   8.192kB (100%)
Build Cache     10        0         4.053MB   53.96kB

$ docker system prune -af --volumes
Total reclaimed space: 107.2MB
```

Four things consume space independently: **images**, **containers**, **volumes**,
**build cache**. `prune` without `--volumes` leaves volumes alone — which is
usually what you want, since volumes hold the data you meant to keep.

### Logs are the other way it fills up

The default `json-file` driver has **no size limit**. One chatty container can
fill the filesystem. `/etc/docker/daemon.json` bounds it:

```json
{ "log-driver": "json-file", "log-opts": { "max-size": "10m", "max-file": "3" } }
```

Written *before* the daemon first started, so it applied to the first container
rather than a later one. Verify from the running container, not the file:

```console
$ docker inspect $CID --format '{{.HostConfig.LogConfig}}'
{json-file map[max-file:3 max-size:10m]}
```

---

## 8. The `docker` group is root

Said plainly, because it is easy to gloss:

**Anyone in the `docker` group can start a container that mounts the host
filesystem and read or write anything on it.** There is no meaningful privilege
boundary between `docker` group membership and root — and unlike `sudo`, there
is no password prompt.

`aleix` is in it, deliberately, because `aleix` already has `sudo` and the
alternative made this phase impractical. It grants no new capability; it removes
the gate in front of one.

**Never grant it to a service account.**

### Group membership applies to new logins only

Same machine, same user, same moment — two connections:

```console
$ ssh homelab 'docker ps'        # session opened BEFORE the change
permission denied

$ ssh homelab 'docker ps'        # a NEW connection
CONTAINER ID   IMAGE   ...
```

A session keeps the groups it was given at login. This is why the advice is
always "log out and back in", and why you should not conclude the change failed
until you have.

---

## 9. How to verify it worked

```bash
docker run --rm hello-world
docker info --format '{{.LoggingDriver}}'
ss -tln                                   # should be unchanged except what you published
sysctl vm.swappiness
systemctl is-system-running
ssh -o ControlPath=none homelab true      # a genuinely new connection
```

---

## 10. What can go wrong

| Symptom | Cause | Fix |
|---|---|---|
| `permission denied` on the docker socket | group applies to new logins | reconnect |
| Container "did not start" but nothing is listed | `docker ps` hides exited ones | `docker ps -a` |
| Exit code 127 | command not found in the image | check the path, and that it exists in *that* image |
| Port unreachable from another machine | bound to `127.0.0.1` | intended — bind the tailnet address if it should be reachable |
| Port reachable that should not be | published as `8080:80` = `0.0.0.0` | name the interface |
| Firewall "not working" for a container | published ports bypass `INPUT` | it is not your firewall; it is the convention |
| Disk full | images, volumes and build cache | `docker system df`, then `prune` — you cannot grow this volume group |

---

## 11. What the reference build actually hit

Six problems, recorded in
[`docs/build-log/2026-09-09-phase-05-docker-install.md`](../../docs/build-log/2026-09-09-phase-05-docker-install.md).
The three that generalise:

**1. The "before" capture never ran, and the diff is gone permanently.** The
script was written, transferred and checksummed — then the step was handed over
in a form (`ssh -t homelab 'sudo …'` from the Mac) that cannot present a password
prompt, so it failed silently. Nobody noticed until afterwards. The pre-Docker
firewall rules do not exist anywhere now; a reboot does not restore them, because
Docker re-adds its chains at boot.

> **A capture step is worthless unless you confirm its output exists.** Check the
> file, not your memory of running the command. And hand privileged steps over in
> a form that can actually prompt: log in first, then run the bare command.

**2. The install ran outside tmux, after being warned.** `tmux new -s docker`
failed with `duplicate session`, the shell continued, and the script's own
warning fired and was proceeded past. 99.8 MB downloaded over the only Wi-Fi
adapter outside a session that would have survived a dropped link. It worked.
A guard that does not stop is a comment. Use `tmux new -A -s docker`.

**3. Nearly reported a false finding, twice.** First, every firewall rule
appeared duplicated — it was IPv4 and IPv6 concatenated by a careless `awk`
range. Then, having separated them, a real asymmetry appeared: `FORWARD` is
`DROP` on IPv4 and `ACCEPT` on IPv6. Before writing that up as an exposure, the
reachability was checked — `net.ipv6.conf.all.forwarding = 0`, Docker's bridge
has IPv6 disabled, no IPv6 route via `docker0`. **Latent asymmetry, not live
exposure**, and recorded as that. It is still a trap for Phase 13, which will
reasonably assume the two families match.

Also: the brief recorded the LAN as a `/24` when it is actually a `/21`, so the
subnet-collision check was run against the wrong network and happened to reach
the right answer. And `ssh homelab` run *on* the server returns
`Permission denied (publickey)` — which is correct, and the posture we want:
there is no private key on the node.

---

## Command summary

| Question | Command |
|---|---|
| Is this container actually a host process? | `docker inspect -f '{{.State.Pid}}' <name>`, then `ps -p <pid>` |
| What user is it running as? | `docker exec <name> id` |
| What is it exposing? | `docker port <name>` and `ss -tln` |
| Why won't it start? | `docker ps -a`, `docker logs <name>`, `docker inspect --format '{{.State.ExitCode}}'` |
| What is on the running container, really? | `docker inspect <name> --format '{{.HostConfig}}'` |
| Where has the disk gone? | `docker system df` |
| Reclaim it | `docker system prune -af` (add `--volumes` only if you mean it) |
| Is daemon.json in effect? | `docker info --format '{{.LoggingDriver}}'` |
