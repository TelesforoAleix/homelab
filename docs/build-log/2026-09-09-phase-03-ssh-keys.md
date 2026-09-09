# Build Log — Phase 03 Parts A–C (SSH keys, alias, password authentication disabled)

- **Date:** 2026-09-09
- **Phase:** 03 — Remote Access
- **Branch:** `feature/03-remote-access`
- **Status:** Complete — Parts A–C validated; Tailscale (D–E) and going headless (F) still to do

## Starting state

Verified on the day, not taken from the Phase 01 handover:

- Server answering on `192.168.1.57`, offering `publickey,password`, with nothing behind the
  `publickey` offer.
- MacBook with **no SSH keys at all**, no `~/.ssh/config`, no Tailscale. `known_hosts` only.
- `sudo` on the server requires a password (no `NOPASSWD`), so every privileged step in this phase
  was run by the owner rather than automated.

## Objective

Replace SSH password authentication with key authentication, reduce the connection to `ssh homelab`,
and prove passwords are refused — closing the risk Phase 01 named as its principal open item.

## Actions taken

1. Wrote and committed the phase brief **before** any implementation (ADR-017), plus the sequencing
   decision to run Phase 03 ahead of Phase 02.
2. Committed the SSH artifacts up front: `config/ssh/10-homelab-hardening.conf`,
   `config/ssh/homelab.ssh-config.example`, `config/ssh/README.md`, and key patterns in `.gitignore`.
3. Generated an Ed25519 key pair on the MacBook, passphrase-protected. (Second attempt — see below.)
4. `ssh-copy-id` installed the public key into `aleix`'s `authorized_keys`.
5. Loaded the key into the agent with `ssh-add --apple-use-keychain`.
6. Created `~/.ssh/config` from the committed example, with `homelab` and a `homelab-lan` fallback.
7. Wrote `scripts/server/apply-ssh-hardening.sh` and applied the drop-in with it.
8. Corrected the script after discovering the change was not live, and re-applied.

## Validation

| Check | Command | Result |
|---|---|---|
| Key login | `ssh -o BatchMode=yes homelab` | `KEY_LOGIN_OK` — BatchMode forbids any password fallback |
| Auth method | `ssh -v homelab` | `Server accepts key: ... ED25519 SHA256:mAJV6WNJ...` |
| Key is protected | `ssh-keygen -y -P "" -f <key>` | Rejected — the key has a passphrase |
| Permissions | `ls -l` on server | `~/.ssh` `700`, `authorized_keys` `600`, one entry, `aleix:aleix` |
| Drop-in ownership | `ls -l /etc/ssh/sshd_config.d/` | `-rw------- root root` |
| Config parses | `sudo sshd -t` | Silent |
| Effective config | `sudo sshd -T` | `passwordauthentication no`, `kbdinteractiveauthentication no`, `permitrootlogin no`, `authenticationmethods publickey` |
| **Advertised methods** | `ssh -o PreferredAuthentications=none homelab` | **`Permission denied (publickey)`** — password no longer offered |
| Password attempt | `ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no homelab` | `Permission denied (publickey)` |
| File integrity in transit | `sha256sum` both ends | Identical — `0aa06460f6eb...` |
| System health | `systemctl is-system-running` | `running`, no failed units |

## Problems / failed approaches

### 1. The key pair was generated on the wrong machine

The owner was handed two commands prefixed with `!`, meaning "run this at the Claude Code prompt".
They were pasted instead into a terminal that was already SSH'd into the server. Bash accepted them
regardless, because a leading `!` is its negation operator rather than a syntax error, so nothing
looked wrong. The output even ends with a plausible success message.

Result: the key pair was created at `/home/aleix/.ssh/` on the server, and `ssh-copy-id` authorised
the server to log into itself. The MacBook still had nothing.

Caught by reading the shell prompt (`aleix@homelab:~$`) and the path in the output — a macOS home
directory is `/Users/home`, not `/home/aleix`. Recovery: deleted the stray key pair, truncated
`authorized_keys`, removed the `known_hosts` entry the server had learned about itself, and started
again on the MacBook. No lockout risk existed at any point, because password authentication was
still enabled.

**Lesson.** When instructions are meant for a specific machine, say which machine in the instruction
itself and give a way to tell them apart from the output. "The path should start `/Users/home`" is
worth more than "run this on the MacBook", because it can be checked *after* the fact.

### 2. `sshd -T` agreed with us while the running server disagreed

The most valuable failure of the phase. After installing the drop-in, `sudo sshd -T` reported
`passwordauthentication no`. But an external check showed the server still advertising
`Permission denied (publickey,password)` — passwords were still accepted.

The reasoning that led there was wrong in a specific, tempting way. Ubuntu 26.04 enables
`ssh.socket`, and it is easy to conclude that `sshd` therefore starts per connection and re-reads its
configuration each time. That is true of inetd-style activation (`Accept=yes`, `sshd -i`). Ubuntu
does not do that:

```text
ssh.socket    Accept=no
ssh.service   ExecStart=/usr/sbin/sshd -D $SSHD_OPTS
```

With `Accept=no`, systemd holds port 22, starts **one** long-running `sshd` on the first connection
and hands it the listening socket. Every later connection is a fork of that daemon, inheriting the
configuration parsed at *its* start time. The evidence was unambiguous once looked for: the daemon
(PID 1512) started at 08:01:54; the drop-in was written at 12:28:52.

`sshd -T` did not lie. It re-parses the configuration files on the spot and reports what they now
say. It answers "what would sshd conclude if it read these files now", which is a different question
from "what is the running server doing" — and only the second one is a security control.

Fixed with `systemctl reload ssh`, now performed by the script. Reload rather than restart:
`ExecReload` runs `sshd -t` before `kill -HUP`, and `KillMode=process` leaves established sessions
alone.

### 3. Two errors of mine, corrected in place

- The drop-in was documented as mode `0644`, justified with the claim that sshd needs it
  world-readable. That is false — sshd reads it as root, and Ubuntu's own `50-cloud-init.conf` in
  the same directory is `0600`. Corrected to `0600`.
- A `set -e` "bug" was reported in the script and a fix applied, then the demonstration written to
  prove it disproved it: `set -e` ignores a failing non-final command in an `&&` list, so the
  original line was safe where it stood. The `if` form was kept because it behaves identically
  wherever it is moved to, but the comment claiming a bug was rewritten to say what is actually true.

## What we learned

- **A configuration file is not a control until the process holding it has re-read it.** Verify what
  the server does, from outside, not what its config checker reports from inside.
- **`Accept=no` socket activation is not per-connection spawning.** Worth knowing before Phase 05,
  where the same systemd concepts return for containers.
- **`sshd` takes the first value it sees for a keyword.** The `10-` prefix beat Ubuntu's
  `50-cloud-init.conf`; a `99-` file would have been silently ignored while the repository claimed
  passwords were off. This was verified in practice, not assumed: `50-cloud-init.conf` is 27 bytes,
  exactly `PasswordAuthentication yes`.
- **`scp` beats pasting, measurably.** The drop-in's SHA256 matched on both machines. Phase 01 lost a
  systemd unit to a paste that split at ~65 characters.
- **A script can encode safety a guide cannot.** `apply-ssh-hardening.sh` refuses to run when the
  invoking user has no authorized key, and reverts itself if `sshd -t` fails. Neither is realistic to
  ask of someone typing four commands.

## Decisions / ADRs

ADR-018 (SSH access policy) is required and still to be written. It must record the Ed25519 choice,
the passphrase requirement, `AuthenticationMethods publickey`, `PermitRootLogin no`, the drop-in
ordering rule as a control, and the reload requirement.

## Costs

None.

## Next

Part D — Tailscale on the server from the `resolute` repository (ADR-014; do not cite Tailscale's
Ubuntu documentation). Then Part E (MacBook + VS Code Remote SSH), then Part F: remove the monitor
and prove an unattended headless reboot.
