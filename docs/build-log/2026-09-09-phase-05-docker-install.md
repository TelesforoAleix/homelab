# 2026-09-09 — Phase 05: installing Docker on a console-less node

The first lockout-class change this project has made. It did not lock anyone
out. Several things still went wrong, and one of them cost evidence that cannot
be recovered.

## Outcome first

Docker Engine 29.8.0, Compose v5.5.1, containerd 2.3.5. Both access routes
proved from genuinely new connections afterwards. Listening sockets identical to
phase start. No failed units.

## Problem 1 — the "before" capture never ran, and the diff is gone forever

`capture-network-state.sh` exists for one reason: Docker rewrites packet-filter
rules, and "what exactly did this change?" can only be answered by diffing
against a baseline. The script was written, transferred, checksummed — and then
the `before` run did not happen.

**Cause: how the step was handed over.** The instruction given was

```bash
! ssh -t homelab 'sudo bash /tmp/capture-network-state.sh before'
```

That form cannot reliably present a `sudo` password prompt in the harness, so it
failed before writing anything. The owner reasonably believed it had run. The
absence was only discovered afterwards, by checking for the file:

```console
$ ls /tmp/netstate-*.txt
NO netstate files exist
```

**The cost is real and unrecoverable.** The pre-Docker `iptables` and `nft`
rulesets no longer exist anywhere. A reboot does not restore them, because
Docker re-adds its chains at boot. For the single change where the diff was the
whole point, there is no diff.

**What was salvaged.** Attribution by chain name, which is weaker and is labelled
as such rather than dressed up as equivalent:

| Owner | Chains |
|---|---|
| Docker | `DOCKER`, `DOCKER-BRIDGE`, `DOCKER-CT`, `DOCKER-FORWARD`, `DOCKER-INTERNAL`, `DOCKER-USER`, `DOCKER` (nat) |
| Tailscale | `ts-input`, `ts-forward`, `ts-postrouting` |

Every non-stock chain is attributable to one of the two. Nothing is unexplained.
Combined with the listening-socket comparison — which *was* possible, because the
brief recorded the baseline — the security question is answered. The forensic
question is not.

**Lesson.** A capture step is worthless unless its output is confirmed to exist.
The script self-checks its redaction but never checked that anyone ran it, and
the procedure had no "verify the baseline exists before proceeding" gate. It has
one now, in the guide: *check the file, not your memory of running the command.*

**Second lesson, about handovers.** Privileged steps must be handed over in a
form that can actually prompt for a password: log in first, then run the bare
command. Wrapping `sudo` inside a non-interactive `ssh` invocation looks
convenient and fails silently.

## Problem 2 — the install ran outside tmux, after being warned

```text
duplicate session: docker
  --   not running inside tmux -- a dropped link mid-apt can leave dpkg
  --   half-configured. Strongly consider: tmux new -s docker
```

A tmux session named `docker` already existed, so `tmux new -s docker` failed;
the shell moved straight on to the install, the script's own warning fired, and
it proceeded anyway.

It downloaded 99.8 MB over the only Wi-Fi adapter, outside a session that would
have survived a dropped link. It worked. It was still a near-miss on the exact
failure the warning describes, and half-configured `dpkg` on a console-less node
is worse than a failed install.

**Lesson.** The warning was correctly worded and correctly placed and changed
nothing, because it was advisory in a script that then continued. A guard that
does not stop is a comment. Whether this should become a hard refusal is
recorded as an open question for Phase 13 rather than changed retroactively —
`tmux new -A -s docker` (attach-or-create) would also have avoided it entirely,
and is the better instruction.

## Problem 3 — `preflight.sh` cannot see a ControlMaster connection

The automated way to hold "a second session you can still use" is an SSH
`ControlMaster`: later commands multiplex over an existing TCP connection instead
of opening a new one, which is exactly the property ADR-020 wants.

`preflight.sh` reported **FAIL: only 1 interactive session** with two masters
running. It is not wrong — it counts pty sessions via `w`, and a `-N` master
allocates no pty, so it is genuinely invisible.

Resolved by *also* opening a real pty session rather than arguing with the
check. Recorded because the gap is real: an operator working through
ControlMaster connections will be told they have no way back while holding two.

**A related trap, worth more than the bug.** A ControlMaster is useless for
*verifying* a route, because it rides an already-established connection. Every
post-change check in this phase used `-o ControlPath=none` to force a genuinely
new TCP connection. An established session proves nothing about whether new ones
arrive — which is section 3 of the standard, and it applies to the tooling too.

## Problem 4 — the brief said `/24`; the LAN is a `/21`

The brief recorded the LAN as `192.168.1.0/24` and checked Docker's default
pools against it. The route table says otherwise:

```text
192.168.0.0/21 dev wlp1s0 proto kernel scope link src 192.168.1.57
```

The router hands out a `/21` (192.168.0.0–192.168.7.255). No collision with
Docker's `172.17.0.0/16` either way, so the conclusion held — but it held by
luck rather than by the check, since the check was performed against the wrong
network. Corrected in the brief and in `project-state.md`.

## Problem 5 — nearly reported a false finding, twice

**First**, every rule appeared duplicated:

```text
-A INPUT -j ts-input
-A INPUT -j ts-input
-A FORWARD -j DOCKER-USER
-A FORWARD -j DOCKER-USER
```

Not duplication. An `awk '/^\*filter/,/^COMMIT/'` range matched the `filter`
table **twice** — once in the `iptables-save` section and once in
`ip6tables-save`. IPv4 and IPv6, concatenated by a sloppy extraction. Caught by
separating the sections before reporting it.

**Second**, having separated them, a genuine asymmetry appeared — and the
temptation was to report it as an exposure:

```text
v4 filter:  :FORWARD DROP
v6 filter:  :FORWARD ACCEPT
```

Docker set the `FORWARD` policy to `DROP` for IPv4 and left IPv6 at `ACCEPT`.
Before writing that up, the reachability was checked:

```text
net.ipv6.conf.all.forwarding = 0
bridge EnableIPv6: false
ip -6 route | grep docker  ->  none
```

**Not reachable.** The kernel forwards no IPv6 at all, Docker's bridge has IPv6
disabled, and `docker0` has no IPv6 address. So it is a **latent asymmetry, not a
live exposure** — and it is recorded as that, because the difference matters.

It is still a trap for Phase 13, which will reason about a firewall on top of
these chains and would reasonably assume the two families match. They do not.

## Problem 6 — the server cannot SSH to itself, which is correct

```text
aleix@homelab: Permission denied (publickey).
```

Produced by running `ssh homelab` while already on the node. Harmless, and
actually the desired posture: there is **no private key on the server**, so the
node cannot authenticate anywhere, including to itself. Noted so it is not
mistaken for a fault later.

## What went right, and why

The lockout did not happen, and that was not luck:

- Both routes proved from the Mac before starting.
- Two sessions held throughout; the count taken with `w`, never `who`.
- The installer refused to run without a second session, and verified the
  repository's `Origin`, suite, architecture and `stable` component before
  writing anything to `/etc`.
- `daemon.json` written **before** first daemon start, so log rotation applied
  to the first container rather than a later one.
- The rollback was typed out, unexecuted, before the change.
- Both routes re-proved afterwards from **new** connections, not the existing
  ones.

The single most useful control was the cheapest: classifying the change as
lockout-class before typing it. Everything else followed from that.

## A demonstration worth keeping

Group membership applies to new logins only — shown here by two connections to
the same machine, as the same user, at the same moment:

```console
$ ssh -S <controlmaster> homelab 'docker ps'      # opened BEFORE the change
permission denied

$ ssh -o ControlPath=none homelab 'docker ps'     # opened AFTER
CONTAINER ID   IMAGE   COMMAND   ...
```

The usual advice is "log out and back in". This is why, and it is also why
`configure-docker-host.sh` prints the warning rather than assuming success.
