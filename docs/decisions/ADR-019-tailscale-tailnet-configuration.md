# ADR-019: Tailscale tailnet configuration

- **Status:** Accepted
- **Date:** 2026-09-09
- **Phase:** 03 — Remote Access
- **Implements:** ADR-005 (Tailscale as the preferred remote connectivity layer)
- **Supersedes:** the DHCP-reservation control in ADR-016 (see below)
- **Superseded by:** none

## Context

ADR-005 chose Tailscale before any implementation existed, and said so: *"Exact service
capabilities/pricing must be verified when implemented."* This ADR records the operational decisions
that only arise once it is actually installed, and closes ADR-005's open verification.

ADR-014 carries a standing warning that applies here: **Tailscale's Ubuntu documentation must not be
cited for this release.** As of 2026-09-09 its Linux pages still reference Noble 24.04, and
`tailscale.com/kb/1187/install-ubuntu-2604` returns HTTP 200 while serving a generic docs index. The
package repository is the authoritative source, and was verified directly before installing:

```text
https://pkgs.tailscale.com/stable/ubuntu/dists/resolute/Release
Origin: Tailscale   Codename: resolute   Architectures: ... amd64 ...   Date: 2026-09-03
```

## Decision

### 1. Identity provider: Google

The tailnet is rooted in the owner's existing **Google** account. That identity is the root of trust
for every node now and later; changing it effectively means rebuilding the tailnet, so it was chosen
deliberately rather than by clicking the first button.

Reasoning: the account already exists and is already protected, adding no new credential to manage.
GitHub was the main alternative and would tie the tailnet to the same identity as the repository —
attractive, but it makes repository access and infrastructure access share a blast radius, which is
the opposite of what Phase 13 will want.

**The tailnet name and the account address are not recorded in this repository.** The repository is
intended to become public, the suffix is globally unique and tied to the account, and neither is
needed to understand any decision here. `scripts/server/verify-remote-access.sh` redacts both from
its output. Committed material says `<tailnet>` and `<account>`.

### 2. Tailscale SSH: declined

Tailscale can terminate SSH itself, authorising by tailnet identity and ACL rather than by key.
`tailscale up` was run **without** `--ssh`.

Declined because it would move SSH authentication into a third party's control plane, on top of an
already-working key setup (ADR-018). The current arrangement fails safe in a useful way: if Tailscale
is unavailable, SSH over the LAN still works and is still key-authenticated. With Tailscale SSH, a
control-plane problem is an access problem.

This is a defensible trade rather than an obvious one. Tailscale SSH genuinely centralises access
control, which matters more with several people or many nodes — neither of which is true here.
**Phase 13 should revisit it** with ACLs properly in scope.

### 3. Node key expiry: disabled for the server

Tailscale expires node keys by default; this node's key was set to expire **2027-03-08**, 180 days
out. It has been disabled in the admin console.

**This is a security control being switched off deliberately, and it should be read as such.** The
reasoning is availability: the node is headless and has no monitor attached as of Phase 03 Part F. A
lapsed key removes it from the tailnet silently, and recovery would mean physically reattaching a
display — for a scheduled event with no operational trigger and no warning.

The LAN fallback (`homelab-lan`) reduces the severity, but only while the operator is on the same
network, which is exactly the situation Tailscale exists to escape.

Compensating controls: `verify-remote-access.sh` **warns if an expiry is ever set again**, so this
cannot be quietly reverted; and access still requires the SSH key, so a compromised tailnet identity
alone does not yield a shell.

**Phase 13 must revisit this** rather than inherit it. Reasonable alternatives exist — a calendar
reminder and a manual re-auth, or an expiry long enough to be routine.

### 4. MagicDNS is the primary route; the LAN address is the documented fallback

`ssh homelab` resolves to the node's MagicDNS name over the tailnet. `ssh homelab-lan` reaches
`192.168.1.57` directly. Both are in `config/ssh/homelab.ssh-config.example`.

The fallback is kept **specifically because** the monitor has been removed. A single access path to
a machine with no console is one failure away from a physical visit.

### 5. Both machines join the tailnet

The MacBook joins as well as the server. A one-node mesh proves nothing, and the MacBook is the
development interface (ADR-004).

## This supersedes ADR-016's DHCP-reservation control

ADR-016 required a router-side DHCP reservation so the node's address would be stable. Phase 01
could not satisfy it — the owner has no router admin access — and recorded it as an unsatisfied
control, with static IP and mDNS considered and rejected with reasons.

**That control is now superseded rather than merely unmet.** The node has a stable identity that
does not depend on its LAN address at all: a MagicDNS name and a fixed `100.x` tailnet address that
follow it across networks. This is strictly better than a DHCP reservation, which would only have
been stable on one network.

ADR-016 is otherwise unaffected: Wi-Fi remains the reference link.

## Alternatives considered

- **Port-forward SSH from the router.** Rejected in ADR-005 and again here. It exposes port 22 to
  the internet, and Phase 01's handover forbids it outright.
- **Self-hosted WireGuard.** More to understand and more to maintain: key distribution, NAT
  traversal, and a public endpoint that must stay reachable. ADR-006 says build simple mechanisms
  manually first, but the thing being learned here is remote access, not VPN implementation. A
  candidate for a later experiment.
- **ZeroTier, Nebula, OpenVPN.** Comparable outcomes; no reason to depart from ADR-005.
- **LAN only.** Rejected — it defeats the point of a headless always-on node.

## Costs

**None.** Tailscale's Personal plan covers this tailnet at no cost, and both decisions taken here —
MagicDNS and disabling key expiry — are available on it. Recorded as an explicit zero in
`docs/reference/costs.md` so the decision is visible rather than merely absent.

Revisit if the tailnet ever exceeds the Personal plan's limits, or if a feature Home Lab depends on
moves behind a paid tier.

## Validation

Performed 2026-09-09:

| Check | Result |
|---|---|
| Repository publishes for `resolute` | `Origin: Tailscale`, `Codename: resolute`, `amd64`, dated 2026-09-03 |
| Installed version | `tailscale 1.102.3` on both machines |
| `tailscaled` | `active`, `enabled` |
| Mesh | Both nodes visible from both sides |
| Route in use | `ssh homelab` arrives from the MacBook's `100.x` tailnet address, not its LAN address |
| MagicDNS | `homelab.<tailnet>.ts.net` resolves to the node's tailnet address |
| Key expiry | `KeyExpiry: none` |
| Host identity | Host key on the MagicDNS name matches the fingerprint already trusted for `192.168.1.57` |
| Survives reboot | Rejoined the tailnet unattended after a cold boot with no console attached |

## Revisit trigger

- Phase 13, for **both** Tailscale SSH and the disabled key expiry.
- A second person or a third node joins, making ACLs and tags worth configuring.
- Any Home Lab dependency moves behind a paid Tailscale tier.
- Tailscale publishes actual 26.04 documentation, which would retire the ADR-014 warning.
