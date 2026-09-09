# Build Log — Phase 03 Parts D–F (Tailscale, VS Code Remote SSH, going headless)

- **Date:** 2026-09-09
- **Phase:** 03 — Remote Access
- **Branch:** `feature/03-remote-access`
- **Status:** Complete — all ten functional objectives validated

## Starting state

Parts A–C complete (see `2026-09-09-phase-03-ssh-keys.md`): Ed25519 key installed, `ssh homelab`
working over the LAN, password authentication disabled and proven refused by the running daemon.
Monitor and keyboard still attached. No Tailscale anywhere.

## Objective

Give the node an identity independent of its LAN address, connect VS Code to it, and then remove the
console — proving the machine is genuinely headless rather than merely capable of being.

## Actions taken

1. Re-verified Tailscale's `resolute` repository directly, as ADR-014 requires: HTTP 200 on the
   `Release`, `.noarmor.gpg` and `.list` URLs, with `Origin: Tailscale`, `Codename: resolute`,
   `amd64` present, dated 2026-09-03.
2. Wrote `scripts/server/install-tailscale.sh` and installed Tailscale 1.102.3 on the server.
3. `sudo tailscale up` — no `--ssh` — authenticated against the owner's Google account.
4. Installed Tailscale 1.102.3 on the MacBook via the Homebrew cask `tailscale-app`.
5. Disabled node key expiry for the server in the admin console.
6. Repointed `~/.ssh/config` `homelab` at the MagicDNS name, keeping `homelab-lan` as fallback.
7. Installed VS Code Remote SSH and opened a remote folder over the `homelab` alias.
8. Wrote `scripts/server/verify-remote-access.sh`.
9. Powered down, removed monitor, keyboard and the DisplayPort→HDMI cable, powered on, and verified
   remotely with no physical interaction.

## Validation

| Check | Result |
|---|---|
| Repository publishes for `resolute` | `Origin: Tailscale`, `Codename: resolute`, `amd64`, 2026-09-03 |
| Tailscale version, both machines | 1.102.3 |
| `tailscaled` | `active`, `enabled` |
| Mesh | Both nodes visible from both sides |
| **Route actually used** | `ssh homelab` arrives from `100.69.244.33` — the MacBook's *tailnet* address, not `192.168.1.112` |
| LAN fallback | `ssh homelab-lan` arrives from `192.168.1.112` |
| MagicDNS | `homelab.<tailnet>.ts.net` → `100.71.62.71` |
| Host identity on the new name | ED25519 `SHA256:179vQE/Qy4jUYiyto723F5NtfkHX3OoYU9esRvsQsBc` — identical to the key already trusted for `192.168.1.57` |
| Key expiry | Was `2027-03-08T12:37:31Z`; now `none` |
| VS Code Remote SSH | `~/.vscode-server` created, 3 processes running |
| **Headless cold boot** | Reachable over MagicDNS on the first poll |
| **Console physically gone** | All six DRM connectors (`DP-1..3`, `HDMI-A-1..3`) report `disconnected` |
| Boot time, headless | 25.8s total |
| Passwords after reboot | `Permission denied (publickey)` |
| Effective config after reboot | `permitrootlogin no`, `passwordauthentication no`, `kbdinteractiveauthentication no`, `authenticationmethods publickey` |
| System health after reboot | `running`, no failed units |

## Problems / failed approaches

### 1. `Host key verification failed` on the MagicDNS name

Expected, but worth recording because the tempting fix is wrong. `known_hosts` is keyed by
*hostname*, so a server trusted as `192.168.1.57` is unknown as `homelab.<tailnet>.ts.net` even
though it is the same machine with the same host key.

The lazy fix is `StrictHostKeyChecking=accept-new`, which is trust-on-first-use all over again. The
correct one is to check the key offered on the new name against the key already trusted for the old
one:

```bash
ssh-keygen -l -F 192.168.1.57
ssh-keyscan -t ed25519 homelab.<tailnet>.ts.net | ssh-keygen -lf -
```

Both returned `SHA256:179vQE/Qy4jUYiyto723F5NtfkHX3OoYU9esRvsQsBc` — the same fingerprint the owner
had seen during the very first `ssh-copy-id`. Same host, verified rather than assumed.

### 2. Two bugs in `verify-remote-access.sh`, both caught by running it

**It reported a correctly-reloaded daemon as stale.** The staleness check compared config mtime
against `ActiveEnterTimestamp`, which a *reload* does not move — only a restart does. Since reload is
the supported way to apply sshd configuration, the check flagged the correct state as wrong.
`StateChangeTimestamp` is the property that tracks reloads (12:32:56, matching the reload) and is now
used.

**It printed the owner's account email into a report whose own footer says to paste it into the
repository.** `tailscale status` prints the owning identity against every node. The script now
redacts both the account and the tailnet suffix.

That second one is also a **deviation from the phase brief**, which stated MagicDNS names were safe
to commit. They are not, for a repository intended to become public: the suffix is globally unique
and tied to the account. Committed material now says `<tailnet>` and `<account>`; the real name
exists only in the owner's `~/.ssh/config`, which is not committed.

### 3. `brew install --cask tailscale-app` could not be automated

The cask wraps a `.pkg` requiring an admin password, and a non-interactive shell cannot supply one.
Run by the owner. Not a fault — worth noting that Mac-side installs in later phases will need the
same, and that `sudo` on the server also has no `NOPASSWD`, so every privileged step in this phase
was performed by the owner rather than automated.

## What we learned

- **`Accept=no` socket activation is not per-connection spawning.** The single most useful thing
  this phase taught, and it generalises: systemd socket units come in two flavours and they behave
  completely differently.
- **`known_hosts` is keyed by name, not by machine.** Renaming how you reach a host is a new trust
  decision, and there is a correct way to make it that is barely more work than the lazy way.
- **Write the redaction before the first report, not after.** The script leaked an email because
  masking was designed for the tailnet suffix only. Anything that prints third-party output into a
  document should assume that output contains identity.
- **Scripts that verify are worth more than scripts that configure.** `apply-ssh-hardening.sh` ran
  correctly and still left the system in the wrong state, because it validated the file rather than
  the server. The verifier is what caught it.
- **A brief can be wrong, and saying so is cheaper than working around it.** The MagicDNS secrecy
  call was recorded as a deviation rather than quietly ignored.

## Decisions / ADRs

- **ADR-018** — SSH access policy. Written and Accepted.
- **ADR-019** — Tailscale tailnet configuration. Written and Accepted. Explicitly supersedes
  ADR-016's unsatisfied DHCP-reservation control, and carries two Phase 13 revisit triggers:
  Tailscale SSH, and the disabled node key expiry.

## Costs

**None.** Tailscale's Personal plan covers this tailnet including MagicDNS and disabling key expiry —
the two features relied on. Verified at implementation, as ADR-005 required, and recorded as an
explicit zero in `docs/reference/costs.md`.

The Phase 01 DisplayPort→HDMI cable (199 DKK) became redundant at Part F. Not re-recorded; the money
was genuinely spent and genuinely needed.

## Next

Phase 02 — Linux Fundamentals, deferred behind this phase. It must write and commit its own brief
first (ADR-017). See `docs/handovers/03-remote-access-handover.md`, especially the note that the
console is gone and recovery options have changed.
