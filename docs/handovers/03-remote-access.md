# Phase 03 Brief — Remote Access

- **Status:** Accepted (self-ratified under ADR-017)
- **Drafted:** 2026-09-09 by the Phase 03 phase context
- **Phase:** 03 — Remote Access
- **Depends on:** Phase 01 — Ubuntu Server (complete, 2026-09-08)
- **Previous handover:** [`01-ubuntu-server-handover.md`](01-ubuntu-server-handover.md)

## 0. Governance note

Under **ADR-017** phases are self-contained and sequential. There is no Project Planning context to
ratify this brief; the phase context writes it, commits it **before implementation begins**, and is
then bound by it. A brief written afterwards is documentation, not governance.

ADR-017 makes three compensating controls mandatory, and this brief is the first of them. The other
two — a handover stating what the next phase inherits, and a literal item-by-item reading of the
Definition of Done — are discharged in §15 and §16.

### Sequencing decision

The roadmap numbers Linux Fundamentals as Phase 02 and Remote Access as Phase 03. **Phase 03 is
being run first**, by the owner's decision on 2026-09-09. Phase 02 is deferred, not skipped, and
keeps its number — `ROADMAP.md` phase numbers are stable by policy.

The reasoning, recorded so it is not re-argued later:

- Phase 01's handover names **SSH password authentication as the phase's principal open risk**.
  Running Phase 02 first leaves that risk open for the whole of a long documentation-heavy phase.
- Phase 03 is small and mechanical. Phase 02 is not.
- Phase 03 improves the environment Phase 02 is carried out in: key-based login, a stable
  `ssh homelab` alias, VS Code Remote SSH, and a server that no longer needs a monitor attached.

Phase 02 still inherits Phase 01's "ground already covered" table, which is preserved in that
handover and is not consumed by this phase.

## 1. Purpose

Make the reference node **safely and conveniently administrable from the MacBook without a console
attached**, and close the principal security risk Phase 01 knowingly left open.

Concretely: replace SSH password authentication with key authentication, give the node a stable
identity that does not depend on its LAN address, and prove the machine is genuinely headless by
removing the monitor and keyboard.

This phase is the point at which ADR-004 ("the MacBook is the development interface, the server is an
execution environment") stops being an intention and becomes true.

## 2. Starting state

Verified on **2026-09-09** from live output, not from the previous handover's text — per
`docs/standards/documentation.md`, recorded state must be derived from the machine.

### Server

| Fact | Value | How verified |
|---|---|---|
| Reachable | `192.168.1.57`, 0% packet loss | `ping -c 2 192.168.1.57` |
| SSH offered methods | `publickey,password` | `ssh -o BatchMode=yes aleix@192.168.1.57` → `Permission denied (publickey,password)` |
| Authorized keys installed | **None** — the `publickey` offer has nothing behind it | implied by the above; re-confirm on the server |
| OS | Ubuntu Server 26.04.1 LTS, kernel 7.0.0-31-generic | Phase 01 handover; re-verify in this phase |
| Admin user | `aleix`, sudo-capable, no direct root login | Phase 01 handover |
| Console | Monitor and keyboard still physically attached | owner |

### MacBook

| Fact | Value | How verified |
|---|---|---|
| SSH keys | **None.** `~/.ssh/` contains only `known_hosts` | `ls -la ~/.ssh/` |
| `~/.ssh/config` | **Does not exist** | `ls -la ~/.ssh/` |
| SSH client | OpenSSH_9.9p2, LibreSSL 3.3.6 | `ssh -V` |
| Tailscale | **Not installed** | `command -v tailscale` → not found |

This is a genuinely clean slate on both sides. Nothing in this phase has to work around a
half-configured predecessor, which is worth stating because it will not be true again.

### Repository

`main` is clean at `f1e1e49` and represents a known-working state (ADR-013). Work happens on
`feature/03-remote-access`.

## 3. Learning objectives

By the end of this phase the owner should be able to explain, without looking it up:

- **What public-key authentication actually is** — why the private key never leaves the MacBook,
  what `authorized_keys` on the server holds, and why this is stronger than any password.
- **Why a passphrase on the key is not redundant** with the key itself, and what the SSH agent and
  the macOS keychain do about having to type it.
- **Why Ed25519** rather than RSA or ECDSA, and what "key type" is choosing between.
- **How `~/.ssh/config` turns connection detail into a name**, and why `ssh homelab` is an
  operational improvement rather than only a convenience.
- **How `sshd` reads its configuration**, specifically: that drop-in files under
  `/etc/ssh/sshd_config.d/` are included in lexical order and that **the first occurrence of a
  keyword wins** — the opposite of what most people assume — and why Ubuntu's own
  `50-cloud-init.conf` makes this a practical trap rather than trivia.
- **What socket activation changes about restarting SSH**, following on from the `ssh.socket`
  lesson already recorded in Phase 01.
- **Why the safe order is: install key → prove key login works → only then disable passwords**, and
  what the fallback is at each step if it goes wrong.
- **What a WireGuard-based mesh VPN like Tailscale does** — how it differs from port-forwarding and
  from a traditional central VPN server, what a coordination server can and cannot see, and what
  trust is being placed in a third party.
- **What MagicDNS and node key expiry are**, and why key expiry is specifically dangerous for an
  unattended headless server.
- **Why none of this is a substitute for a firewall**, which remains Phase 13.

## 4. Functional objectives

1. An Ed25519 SSH key pair exists on the MacBook, passphrase-protected, with the private key never
   copied anywhere.
2. The public key is installed in `aleix`'s `authorized_keys` on the server, with correct ownership
   and permissions.
3. `ssh homelab` from the MacBook logs in using the key, with no password prompt, via a committed
   `~/.ssh/config` entry.
4. **Password authentication is disabled** on the server, along with keyboard-interactive
   authentication, and this is proven by a failed password attempt rather than assumed.
5. Tailscale is installed on the server from the `resolute` repository and on the MacBook, both
   joined to the owner's tailnet.
6. The server is reachable over its Tailscale address **and** its MagicDNS name.
7. The server's Tailscale node key is set not to expire, so an unattended machine cannot silently
   drop off the tailnet.
8. VS Code Remote SSH connects from the MacBook to the server and can open a remote folder.
9. **The monitor and keyboard are physically removed**, and the server is rebooted and proven
   reachable with no console attached and no physical interaction.
10. The verification script reports the new posture, and no failed units.

## 5. Decisions already fixed

Binding on this phase and not to be reopened inside it:

| Decision | Source | Effect here |
|---|---|---|
| MacBook is the development interface | ADR-004 | The whole point of the phase |
| Tailscale is the preferred remote connectivity layer | ADR-005 | Tailscale, not a self-hosted VPN, not port-forwarding |
| Privilege separation | ADR-011 | No new root-run anything; no direct root SSH login |
| Manual before automation | ADR-012 | Configure by hand once, commit the artifacts, script only what repeats |
| `main` stays known-working | ADR-013 | Merge only after validation passes |
| Ubuntu LTS required; 26.04.1 tested | ADR-014 | Third-party repos must publish for `resolute` |
| Wi-Fi is the reference link | ADR-016 | Network link is not changed by this phase |

### Inherited from the Phase 01 handover — must not be silently ignored

- **Do not cite Tailscale's Ubuntu documentation.** It still references Noble 24.04, has no 26.04
  page, and `tailscale.com/kb/1187/install-ubuntu-2604` returns HTTP 200 while serving a generic
  docs index. The **package repository** at `pkgs.tailscale.com/stable/ubuntu/dists/resolute/` is
  the authoritative source (ADR-014). Follow the generic Ubuntu install path with the `resolute`
  codename, and re-verify the repository is still publishing before relying on it.
- **Do not port-forward SSH** from the router. This holds during the phase and after it.
- **ADR-016's DHCP-reservation control was never satisfied** — the owner has no router admin access.
  Static IP and mDNS were considered and rejected with reasons. This phase is where that control is
  formally superseded rather than left dangling (§13).
- ISO checksum verification was never confirmed in Phase 01. Nothing in this phase depends on it;
  noted so it is not lost.

## 6. Decisions still open

Resolvable inside this phase. Items marked **ask the owner** materially affect scope or create a
lasting external dependency, and must not be decided unilaterally.

1. **Tailscale identity provider — ask the owner.** Joining a tailnet requires signing in with an
   existing identity (Google, Microsoft, GitHub, Apple, or email). That account becomes the root of
   trust for every future node; changing it later effectively means rebuilding the tailnet. It also
   determines what the tailnet is called.
2. **Tailscale SSH — ask the owner.** Tailscale can terminate SSH itself, authenticating by tailnet
   identity and ACL rather than by key. It is genuinely convenient and it centralises access control,
   but it moves SSH authentication into a third party's control plane and would partly duplicate the
   key work in objectives 1–4. Default position: **install it disabled**, keep OpenSSH with keys as
   the authentication mechanism, and record why.
3. **Whether the MacBook joins the tailnet in this phase**, or only the server. Default: yes — a
   mesh with one node proves nothing, and objective 6 cannot be validated otherwise.
4. **`PermitRootLogin`**: Phase 01 left it at `prohibit-password`. Tightening to `no` costs nothing
   here since no root key exists. Default: set `no` and record it.
5. **Whether `~/.ssh/config` lives in the repository as an example file** or only on the MacBook.
   Default: commit a sanitised example under `config/ssh/`, because the Phase 01 convention is that
   configuration belonging in the repository is copied from it, never pasted.
6. **How the LAN address is treated after Tailscale exists.** Default: keep it as the documented
   fallback path, and make the MagicDNS name the primary route.

Anything that turns out to be a cross-phase architectural change is recorded as an ADR and carried
into the next phase's brief (ADR-017), not applied silently.

## 7. Implementation scope

Expected work. Exact commands follow from discovery; this is the shape, not a script.

**Part A — SSH keys (MacBook side)**
Generate an Ed25519 key pair with a passphrase. Create `~/.ssh/config` with a `homelab` host entry
using `AddKeysToAgent` and `UseKeychain` so the passphrase is typed once per boot rather than once
per connection.

**Part B — Install the public key (server side)**
Copy the public key to the server and into `~/.ssh/authorized_keys`, with `700` on `~/.ssh` and
`600` on `authorized_keys`, owned by `aleix`. Prove key login works **while password login still
works**, so there is a way back in.

**Part C — Disable password authentication**
Ship a drop-in as a repository file — `config/ssh/10-homelab-hardening.conf` — scp'd into
`/etc/ssh/sshd_config.d/`, then `chown root:root` (the Phase 01 privilege-escalation lesson).
Numbered `10-` deliberately: sshd takes the **first** value it sees for a keyword, and Ubuntu's
`50-cloud-init.conf` sets `PasswordAuthentication yes`. Validate with `sshd -t`, apply, then verify
with `sudo sshd -T` and a deliberately failed password attempt from a second terminal.

**Keep an existing session open throughout Part C.** The attached console is the final fallback and
is the reason this part happens before Part F.

**Part D — Tailscale on the server**
Add the `resolute` repository and keyring per ADR-014, install, `tailscale up`, authenticate. Enable
MagicDNS. **Disable key expiry for this node.** Record the tailnet address and MagicDNS name — these
are private-space identifiers and safe to commit; nothing here exposes a credential.

**Part E — Tailscale on the MacBook and VS Code Remote SSH**
Install Tailscale on the MacBook, join the same tailnet, confirm the server answers on its MagicDNS
name, and point the `homelab` SSH config entry at it with the LAN address kept as a documented
fallback. Install the VS Code Remote SSH extension and open a remote folder.

**Part F — Go headless**
Power down, physically remove the monitor and keyboard and the DisplayPort→HDMI cable, power up, and
prove reachability with no physical interaction — the same standard Phase 01 applied to its
power-loss test.

**Part G — Capture state**
Extend `scripts/server/verify-install.sh` (or add a companion) to assert the new posture, and
regenerate the state report from live output.

### Explicitly out of scope

Named so the phase does not drift, per the ADR-017 risk of unreviewed scope creep:

- **UFW / firewall** — Phase 13.
- **`fail2ban`** — Phase 13, and largely moot once password authentication is off.
- **Tailscale ACLs, tags, subnet routing, exit nodes** — beyond a two-node tailnet, Phase 13 or later.
- **2FA / hardware keys for SSH** — Phase 13.
- **Changing the network link, or revisiting Wi-Fi vs Ethernet** — ADR-016 stands.
- **Encryption at rest** — ADR-015, revisit trigger is Phase 10.
- **Anything from Phase 02's syllabus** beyond what this phase genuinely needs.

## 8. Validation / tests

Each item must be proven by real output pasted into the guide or handover. Nothing is marked done
from expectation — the Phase 01 standard.

| # | Check | Passes when |
|---|---|---|
| 1 | `ssh homelab` from the MacBook | Logs in with no password prompt |
| 2 | `ssh -v` auth method | Shows publickey succeeded, not password |
| 3 | Password login refused | `ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no aleix@192.168.1.57` → `Permission denied` |
| 4 | Effective sshd config | `sudo sshd -T \| grep -E 'passwordauthentication\|kbdinteractive\|pubkeyauth\|permitrootlogin'` shows the intended values |
| 5 | Config validity | `sudo sshd -t` silent before any restart |
| 6 | `authorized_keys` permissions | `~/.ssh` `700`, `authorized_keys` `600`, both owned by `aleix` |
| 7 | Drop-in ownership | `/etc/ssh/sshd_config.d/10-homelab-hardening.conf` owned `root:root` |
| 8 | Tailscale up | `tailscale status` shows the node online on both machines |
| 9 | MagicDNS | `ssh homelab` resolving via the MagicDNS name succeeds |
| 10 | Key expiry disabled | Admin console / `tailscale status --json` shows no expiry for the node |
| 11 | VS Code Remote SSH | Remote folder opens; remote terminal runs `uname -a` |
| 12 | **Headless reboot** | After console removal: server boots, rejoins Wi-Fi, rejoins tailnet, accepts `ssh homelab`, all with zero physical interaction |
| 13 | System health | `systemctl is-system-running` → `running`; `systemctl --failed` empty |
| 14 | No new failed units | Specifically `tailscaled` active and enabled |

Check 12 is the phase's real proof and inherits Phase 01's rule: the test forbids interaction, not a
display. Here the display is gone entirely.

## 9. Security considerations

**This phase's purpose is a security improvement**, so the analysis is more than a formality.

- **Private key never leaves the MacBook.** Only the `.pub` file is transferred. Never commit either.
- **Passphrase-protect the key.** An unprotected private key is a plaintext credential in a
  filesystem that ADR-015 leaves unencrypted on one end and macOS FileVault-dependent on the other.
- **Lockout is the realistic failure mode**, not intrusion. Mitigations, in order: keep a live SSH
  session open while changing sshd config; `sshd -t` before applying; the attached console until
  Part F; Part F happens last, deliberately.
- **Drop-in ordering is a security control, not cosmetics.** A `99-` file would be silently
  overridden by `50-cloud-init.conf` and password authentication would remain on while the
  documentation claimed otherwise. Verify with `sshd -T`, which reports what sshd actually resolved.
- **`chown root:root` after `scp` + `sudo mv`.** Phase 01's recorded privilege-escalation lesson. A
  file that root parses, owned by a non-root user, is an escalation path.
- **Tailscale is new third-party trust.** Its coordination server brokers connections and holds
  public keys and node identity; traffic is end-to-end WireGuard. Worth stating plainly rather than
  adopting silently, since ADR-005 accepted it before implementation existed.
- **Node key expiry is a security control that becomes an availability risk** on an unattended
  server. Disabling it is a deliberate trade-off and must be recorded as such, not slipped in.
- **Still no firewall** (Phase 13). Tailscale reduces exposure; it does not replace UFW.
- **Do not port-forward SSH.** Unchanged, and now unnecessary.
- **Secrets discipline:** never commit private keys, the Wi-Fi passphrase, Tailscale auth keys, MAC
  addresses, or the tailnet's login identity. Tailscale `100.x.y.z` addresses and MagicDNS names are
  private-space identifiers and are safe to record.

## 10. Repository changes expected

| Path | Purpose |
|---|---|
| `config/ssh/10-homelab-hardening.conf` | sshd drop-in — the phase's central artifact |
| `config/ssh/homelab.ssh-config.example` | Sanitised `~/.ssh/config` entry |
| `config/ssh/README.md` | What these files are and how they are applied |
| `scripts/server/verify-remote-access.sh` | Asserts the new posture from live output |
| `scripts/server/verify-install.sh` | Updated where its Phase 01 assumptions no longer hold |
| `guide/03-remote-access/README.md` | Phase guide |
| `docs/handovers/03-remote-access.md` | This brief |
| `docs/handovers/03-remote-access-handover.md` | Handover |
| `docs/build-log/2026-09-09-phase-03-*.md` | What actually happened |
| `docs/decisions/ADR-018`, `ADR-019` | See §13 |
| `docs/reference/{project-state,software-stack,costs}.md` | Updated |
| `docs/architecture/current-architecture.md` | Access path changed |
| `ROADMAP.md`, `CHANGELOG.md`, `MANIFEST.md` | Status and inventory |

Config files are **scp'd from the repository, never pasted** — the Phase 01 convention, reinforced by
the owner's terminal splitting pasted lines at ~65 characters.

## 11. Guide documentation required

`guide/03-remote-access/README.md`, following `docs/templates/guide-template.md`, aimed at the
audience in `PROJECT.md` §2: comfortable with computers, not a sysadmin.

It must explain, not merely instruct: what public-key auth is and why it beats passwords; why the
key gets a passphrase anyway; why Ed25519; the sshd drop-in first-match-wins rule and the
`50-cloud-init.conf` trap; the safe ordering and the fallback at each step; what Tailscale is and
what trust it adds; why key expiry is disabled here. Alternatives get a fair hearing —
port-forwarding with keys, WireGuard by hand, ZeroTier, OpenVPN — with reasons, not dismissal.

The **Reference-build experience** section is written from what actually happened, including
failures, per `PROJECT.md` §11.

## 12. Project documentation required

- `docs/reference/project-state.md` — new access posture, risk register, next phase.
- `docs/reference/software-stack.md` — Tailscale Planned → Active with tested versions.
- `docs/reference/costs.md` — Tailscale plan and cost, even if zero. An explicit 0 is a record; an
  absence is an oversight.
- `docs/architecture/current-architecture.md` — the access path is materially different.
- `docs/build-log/` — at least one entry, including failures.
- `ROADMAP.md` — Phase 03 complete; note that Phase 02 was deferred and why.
- `CHANGELOG.md`, `MANIFEST.md`.

## 13. ADRs required / possible

| ADR | Subject | Why it is a decision, not a detail |
|---|---|---|
| **ADR-018** | SSH access policy — Ed25519 with passphrase, password and keyboard-interactive authentication disabled, `PermitRootLogin no`, drop-in ordering as a control | Binds every later phase and every future node; the drop-in ordering rationale must survive this context |
| **ADR-019** | Tailscale tailnet configuration — identity provider, MagicDNS, node key expiry disabled, Tailscale SSH accepted or declined | ADR-005 chose Tailscale before implementation; the operational decisions are new, and **key expiry disabled is a deliberate security/availability trade-off** |

**ADR-019 must explicitly supersede ADR-016's unsatisfied DHCP-reservation control**, stating that
tailnet identity replaces LAN address stability. `PROJECT.md` forbids silently contradicting an
accepted ADR; the roadmap already anticipates this supersession.

Possible but not assumed: an ADR if Tailscale SSH is adopted (§6.2), or if the `resolute` repository
turns out not to publish and a fallback is used — ADR-014 requires that be recorded as a problem
rather than quietly worked around.

## 14. Costs

**Expected: zero.** Tailscale's Personal plan covers a small personal tailnet at no cost, and
everything else in this phase is already-owned software.

To confirm at implementation time and record either way: the current Personal plan node/user limits,
and whether disabling key expiry or MagicDNS requires a paid plan. If a cost appears, it is recorded
in `docs/reference/costs.md` in DKK and EUR per `PROJECT.md` §10 and flagged to the owner before
being incurred.

The DisplayPort→HDMI cable bought in Phase 01 (199 DKK) becomes redundant at Part F. It is not a new
cost and is not re-recorded; worth a line in the guide, since a reader may not need it at all if they
install headless from the start.

## 15. Definition of Done

The project-wide checklist from `PROJECT.md` §12, applied **literally, item by item** — under
ADR-017 this is the only standing check on phase quality.

- [ ] Functional objective works — all ten in §4, each with real output.
- [ ] Configuration/setup is reproducible — config in the repository, applied from it.
- [ ] Validation/tests have passed — all fourteen checks in §8.
- [ ] Important security implications were considered — §9, plus the Tailscale trust decision and
      the key-expiry trade-off recorded in ADR-019.
- [ ] Relevant repository files are committed.
- [ ] Human-facing guide is updated — `guide/03-remote-access/README.md`, including reference-build
      experience.
- [ ] Project/internal documentation is updated — §12.
- [ ] ADRs are created or updated — ADR-018, ADR-019, and the ADR-016 supersession.
- [ ] Actual costs are recorded — including an explicit zero.
- [ ] Problems, failed approaches, and lessons are recorded — not tidied away (`PROJECT.md` §11).
- [ ] Tested versions are recorded — Tailscale on both machines, OpenSSH both ends, VS Code
      Remote SSH.
- [ ] No unexplained critical AI-generated component remains — the sshd drop-in and the verification
      script are line-by-line explainable.
- [ ] `main` represents a known-working state — merge only after §8 passes.
- [ ] The system reports no failed units and no degraded state — check 13, **after** the headless
      reboot, not before.
- [ ] A structured handover is written into `docs/handovers/03-remote-access-handover.md`, stating
      what the next phase inherits.

## 16. Return handover requirements

The handover is addressed to **Phase 02 — Linux Fundamentals**, which is the deferred next phase, and
must state at minimum:

1. **Verified starting state** — access paths (MagicDNS, tailnet address, LAN fallback), effective
   sshd configuration, key location and type, Tailscale versions, and the re-verification command.
2. **That the console is gone.** Phase 02 must know its recovery options changed: a mistake that
   breaks networking or sshd is no longer a walk to the monitor. This is the most important single
   sentence in the handover.
3. **Open risks and who closes them** — carrying forward no firewall, no encryption at rest, 2016
   firmware (all Phase 13), and the ADR-015 revisit trigger for Phase 10, none of which this phase
   touches. Confirm explicitly that SSH password authentication is **closed**, since Phase 01 named
   it the principal open risk.
4. **Unsatisfied controls**, including ADR-016's DHCP reservation and how ADR-019 supersedes it, and
   Phase 01's unconfirmed ISO checksum.
5. **Must not be silently inherited** — the new third-party dependency on Tailscale, and the
   disabled node key expiry, which is a deliberate trade-off a later hardening phase should revisit
   rather than discover.
6. **Ground already covered** — Phase 03 will incidentally exercise more Phase 02 syllabus: file
   permissions and ownership on `~/.ssh`, apt repositories and keyrings, systemd units for
   `tailscaled`, drop-in configuration files, and `journalctl` for diagnosing sshd. Phase 02 should
   build on these as worked examples, exactly as it was told to for Phase 01's.
7. **Phase 02 must still write and commit its own brief first** (ADR-017). Nobody else will.
