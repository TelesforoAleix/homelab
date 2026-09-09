# ADR-018: SSH access policy — key-only authentication

- **Status:** Accepted
- **Date:** 2026-09-09
- **Phase:** 03 — Remote Access
- **Supersedes:** none. Tightens the Phase 01 baseline recorded in ADR-014's install.
- **Superseded by:** none

## Context

Phase 01 installed `openssh-server` with password authentication enabled, and its handover named
that **the phase's principal open risk**, time-boxed to Phase 03. The machine was reachable on the
LAN by anyone who could guess or obtain the account password, and the phase brief forbade
port-forwarding SSH until this was closed.

Phase 03 is where it closes.

## Decision

SSH to the reference node authenticates **by public key only**.

| Setting | Value | Why |
|---|---|---|
| Key type | **Ed25519** | Modern elliptic-curve; small, fast, and no parameter choices to get wrong. RSA needs an explicit `-b 4096` to be respectable; ECDSA depends on NIST curves many people distrust. |
| Passphrase | **Required** | Without one the private key is a plaintext credential on disk. Held in the macOS login keychain via `ssh-add --apple-use-keychain`, so it is typed once per machine rather than once per connection. |
| `PasswordAuthentication` | `no` | Closes the Phase 01 risk. |
| `KbdInteractiveAuthentication` | `no` | PAM can otherwise ask for a password by another route. Disabling only the first leaves the door open — the usual reason someone "disabled passwords" and still gets a prompt. |
| `PubkeyAuthentication` | `yes` | Stated explicitly rather than relying on the default holding across future OpenSSH releases. |
| `PermitRootLogin` | `no` | Phase 01 left `prohibit-password`, which permits root login by key. No root key exists and none should; administration is `aleix` + `sudo` (ADR-011). |
| `AuthenticationMethods` | `publickey` | Requires public key and nothing else, so a future package dropping in a permissive config cannot re-enable another method. |

The private key **never leaves the MacBook**. Only the public half is transferred, and neither half
is ever committed.

### The configuration ships as a numbered drop-in, and the number is a control

The settings live in `config/ssh/10-homelab-hardening.conf`, installed to
`/etc/ssh/sshd_config.d/10-homelab-hardening.conf` as `root:root`, `0600`.

`sshd_config` ends with `Include /etc/ssh/sshd_config.d/*.conf`, which expands in lexical order, and
**sshd takes the first value it sees for a keyword** — not the last. Ubuntu ships
`50-cloud-init.conf` containing exactly `PasswordAuthentication yes` (27 bytes; verified, not
assumed). A file named `99-` would be read *after* it and silently ignored, leaving passwords
enabled while the repository claimed otherwise.

**The `10-` prefix is therefore a security control and must not be renumbered.**

### Configuration is not a control until the daemon has re-read it

Ubuntu 26.04 enables `ssh.socket`, which invites the conclusion that `sshd` starts per connection and
re-reads its configuration each time. That is true of inetd-style activation (`Accept=yes`,
`sshd -i`). **Ubuntu does not do that:**

```text
ssh.socket    Accept=no
ssh.service   ExecStart=/usr/sbin/sshd -D $SSHD_OPTS
```

With `Accept=no`, systemd holds port 22, starts **one** long-running `sshd` on the first connection
and hands it the listening socket. Every later connection is a fork of that daemon, inheriting the
configuration it parsed at *its* start time.

Phase 03 hit this directly: `sshd -T` reported `passwordauthentication no` while the running server
still accepted passwords, because the daemon had started four hours before the file was written.

Therefore:

1. **Applying this configuration requires `systemctl reload ssh`.** Reload, not restart:
   `ExecReload` runs `sshd -t` before `kill -HUP`, and `KillMode=process` leaves established
   sessions alone. `scripts/server/apply-ssh-hardening.sh` does this.
2. **`sshd -T` is not sufficient evidence.** It re-parses the files on the spot and answers "what
   would sshd conclude if it read these now" — a different question from "what is the server doing".
   The authoritative check is what the server advertises to a client:

   ```bash
   ssh -o PreferredAuthentications=none aleix@homelab
   # Permission denied (publickey)           <- correct
   # Permission denied (publickey,password)  <- passwords still accepted
   ```

`scripts/server/verify-remote-access.sh` performs that probe, and separately warns when any sshd
config file is newer than the daemon's last start or reload.

### Changes are applied by script, not by typed commands

`scripts/server/apply-ssh-hardening.sh` refuses to run when the invoking user has no
`authorized_keys` entry, and reverts itself if `sshd -t` rejects the result. Those are the two ways
this change locks people out of a headless machine, and neither is realistic to ask of someone
typing four commands from a guide.

## Alternatives considered

- **Keep passwords as a fallback "just in case".** Rejected. A fallback that accepts passwords is
  not a fallback, it is the risk. The real fallbacks are the LAN route (`homelab-lan`), and — until
  Part F of this phase — the attached console.
- **`PasswordAuthentication no` written directly into `sshd_config`.** Works, but is overwritten by
  package upgrades and hides the drop-in ordering problem rather than solving it.
- **Tailscale SSH**, authenticating by tailnet identity and ACL instead of by key. Declined — see
  ADR-019.
- **RSA 4096.** Interoperable with very old clients, which is not a constraint here, and larger and
  slower for no benefit.
- **No passphrase, relying on FileVault.** Rejected. It makes the key's security depend on a control
  outside this project's scope, and offers nothing once the Mac is unlocked.
- **`fail2ban`.** Largely moot with passwords disabled. Phase 13.

## Consequences

- The MacBook's private key becomes a **single point of access**. Losing it means losing remote
  entry; a second key, or console access, is the recovery path. Adding a backup key is Phase 13.
- Anyone reproducing Home Lab must install a working key **before** applying this configuration. The
  script enforces it rather than trusting the reader.
- `PermitRootLogin no` means no automation may ever SSH in as root. This is intended (ADR-011).
- **This is not a firewall.** Port 22 is still open on the LAN and still answers. Phase 13.

## Validation

Performed 2026-09-09, and again after the headless reboot in Part F:

| Check | Result |
|---|---|
| Key login | `ssh -o BatchMode=yes homelab` succeeds — BatchMode forbids password fallback |
| Server advertises | `Permission denied (publickey)` — password absent from the list |
| Effective config | `passwordauthentication no`, `kbdinteractiveauthentication no`, `permitrootlogin no`, `authenticationmethods publickey` |
| Permissions | `~/.ssh` `700`, `authorized_keys` `600`, drop-in `root:root 0600` |
| Survives reboot | Re-verified after a cold boot with no console attached |

## Revisit trigger

- A second admin key, or a backup key, becomes necessary.
- A second factor is introduced — it is expressed through `AuthenticationMethods`, set here.
- Any future Ubuntu release changes `ssh.socket` to `Accept=yes`, which would make the reload
  requirement obsolete and this ADR's reasoning misleading.
