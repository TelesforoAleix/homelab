# Securing a node on a network you do not control

*Written 2026-09-10, out of phase, because a premise the whole project rested on turned out to be
wrong.*

## 1. What we were trying to achieve

Answer one question before publishing this repository publicly: **does publishing it create a
security problem for the node?**

The answer turned out to be no — and finding that out uncovered a much bigger problem that had
nothing to do with publishing.

## 2. The premise that was wrong

Every security decision in this project up to Phase 09 was reasoned on an unstated assumption: *this
is a home LAN*. A handful of devices, all the owner's, behind a router the owner administers.

That is what made three deferrals reasonable:

| Deferred | Reasoning at the time |
|---|---|
| No firewall until Phase 13 | Only trusted devices can reach the node |
| No encryption at rest (ADR-015) | The node holds nothing sensitive, and physical access means someone is already in the house |
| SSH on the LAN as a fallback path | A safety net if Tailscale fails |

**None of it was true.** The Wi-Fi is shared across 40–50 rooms. The subnet is a flat
`192.168.0.0/21` — 2046 usable addresses. The router is not the owner's, cannot be configured by
them, and its management interface answers from the public internet.

The reference build's own documentation said "the server is behind the router's NAT and exposes only
SSH on the LAN" — which is *literally* true and completely misleading, because "the LAN" was doing
an enormous amount of unexamined work in that sentence.

**The lesson worth taking:** a security control is only as good as the premise it was chosen under,
and premises decay silently. Nothing broke. Nothing alerted. The documentation stayed accurate word
by word while becoming wrong as a whole.

## 3. What the reader needs to understand

### A port being "open" tells you less than you think

`ss -tln` said `0.0.0.0:22` from the first day. That means *sshd accepts connections on every
interface*. Whether that matters depends entirely on who is on those interfaces — and that is not a
fact `ss` can tell you.

### Public-key-only authentication is exposure control, not access control

SSH here refuses passwords entirely (ADR-018). An attacker on the shared network cannot brute-force
their way in. But they can reach the service, fingerprint its version, and be waiting the day a
vulnerability in it is published. **Reachable and unexploitable today is not the same as safe.**

### "Is a port forwarded to me?" is answerable, and the answer is a host key

Connecting to your own public address from *inside* your own network proves nothing: many routers
answer such connections themselves, and the packets never leave the building. We saw ports 22, 80
and 443 apparently open and it meant nothing.

What settles it is identity. SSH servers present a **host key**, unique to the machine:

```text
node    192.168.1.57   SSH-2.0-OpenSSH_10.2p1 Ubuntu    RSA 3072 / ECDSA / ED25519
public  <our address>  SSH-2.0-OpenSSH_7.0              single RSA 2048, different fingerprint
```

Different software, different version, different key. Whatever answers on the public address is
**not this machine** — it is the router's own management service. No forwarding exists.

### A shared Wi-Fi passphrase provides no confidentiality between residents

With WPA2-PSK, anyone who knows the passphrase can decrypt another station's traffic given a
captured handshake. SSH, HTTPS and Tailscale are unaffected — they encrypt end to end, above the
link. But the correct mental model for the link itself is **open Wi-Fi**.

## 4. Realistic alternatives

| Option | Verdict |
|---|---|
| Fix the router | **Impossible.** Not ours to administer |
| Move to Ethernet | Same building network. Solves nothing |
| Bind sshd to `tailscale0` only | Works, but editing sshd config is the classic lockout, and Tailscale must be up before sshd |
| **Firewall: deny inbound, allow the tailnet** | **Chosen.** One config, reversible, independent of sshd, and it covers every future service rather than just SSH |
| `fail2ban` | **Rejected.** It watches for repeated failed passwords against a server that accepts none. It would add a service and protect nothing |

## 5. What the reference build chose

```text
default deny incoming
default allow outgoing
allow in on tailscale0                   <- the access path
allow in on wlp1s0 proto udp port 41641  <- Tailscale direct connections
```

That last rule matters: without it, Tailscale still works but falls back to relaying through a DERP
server. Slower, and dependent on someone else's infrastructure for something that was working
peer-to-peer.

## 6. How it is applied — the self-revert

A firewall change applied over the connection it might break is the classic way to lose a remote
machine. `scripts/server/apply-firewall.sh` therefore **arms an automatic revert before it applies
anything**:

```text
1. refuse outright if tailscale0 is missing, or Tailscale is down,
   or this session arrived over the LAN
2. arm: ufw disables itself in 10 minutes
3. apply the rules
4. operator proves access in a NEW session
5. only then cancel the timer
```

Do nothing and the node repairs itself. The failure mode is a ten-minute wait, not a lost machine.

## 7. How we verify it worked

**This is the part most people get wrong, and this project got wrong three times in one afternoon.**

Three tests, and all three are necessary:

```text
ssh homelab                      -> works        POSITIVE: the access path survives
ssh -o ConnectTimeout=5 homelab-lan -> times out  THE TEST: the LAN path is closed
ping 192.168.1.57                -> 2/2 received  NEGATIVE: the host is UP, the port is FILTERED
```

Without the third, "timed out" is indistinguishable from a crashed host, a dropped Wi-Fi link, or a
typo in the address. **Host alive plus port unreachable is the firewall doing its job and nothing
else.**

`ss -tln` still reports `0.0.0.0:22` afterwards, and that is correct. sshd still *binds* every
interface; ufw drops the packets before they arrive. The binding did not change — the reachability
did. Reading the listener list would have told you nothing.

## 8. What can go wrong

- **Docker publishes ports around the firewall.** Docker's DNAT runs before `INPUT`, so `-p 8080:80`
  is reachable regardless of `ufw` (ADR-022). On this network that publishes to 2046 hosts. Bind
  containers to `127.0.0.1` or the tailnet, always.
- **`sudo` strips the environment.** The first version of the script read `$SSH_CLIENT` to check
  where the session came from. Under `sudo`, that variable does not exist, and with `set -u` the
  script aborted. It failed *safely* — before arming, before applying — but it was a check that
  could not run. It now reads the value from its parent process's environment instead.
- **`/proc/PID/stat` field 4 is not reliably the parent PID.** The second field is the process name
  in parentheses; a name containing a space shifts everything after it. Use `/proc/PID/status`.

## 9. What the reference build actually encountered

The router's own management interface **is** reachable from the public internet, on an end-of-life
business gateway answering SSH with OpenSSH 7.0 (released 2015). The owner cannot patch it, cannot
configure it, and cannot get it fixed.

That is not a problem this project can solve. What it can do — and now has — is ensure the node
trusts that network for nothing at all.

**The honest summary:** Tailscale was the right decision from Phase 03, and it was not finishing the
job. A secure tunnel is not much use with an open door beside it.
