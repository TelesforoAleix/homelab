# SSH configuration

Files here are applied to the machine by copying them **from this repository**, never by pasting
their contents into a terminal. That convention came out of Phase 01, where a pasted systemd unit
arrived corrupted because the owner's terminal splits pasted lines at roughly 65 characters. It is
the right pattern regardless: what is running should be traceable to a committed file.

| File | Side | Destination |
|---|---|---|
| `10-homelab-hardening.conf` | Server | `/etc/ssh/sshd_config.d/10-homelab-hardening.conf`, `root:root`, `0644` |
| `homelab.ssh-config.example` | MacBook | appended to `~/.ssh/config`, `0600` |

## Applying the server drop-in

```bash
scp config/ssh/10-homelab-hardening.conf aleix@homelab:/tmp/
ssh aleix@homelab
sudo mv /tmp/10-homelab-hardening.conf /etc/ssh/sshd_config.d/
sudo chown root:root /etc/ssh/sshd_config.d/10-homelab-hardening.conf
sudo chmod 644 /etc/ssh/sshd_config.d/10-homelab-hardening.conf
sudo sshd -t
```

**`chown root:root` is not optional.** `scp` writes the file as `aleix`, and `sudo mv` preserves
that ownership. A file that root parses but a non-root user can rewrite is a privilege-escalation
path. Phase 01 shipped this exact bug in its own guide and `scripts/server/verify-install.sh` now
detects it.

**`sshd -t` before restarting, every time.** It parses the configuration and says nothing if it is
valid. Skipping it is how people lock themselves out of a headless machine.

## Order of operations matters

Install the key and prove key login works **before** disabling password authentication, and keep an
existing SSH session open while you do it. If the new configuration is wrong, that already-open
session is the way back in — an established connection is unaffected by changes to sshd. See
`docs/handovers/03-remote-access.md` §7.

## What is never committed here

Private keys, public keys, `authorized_keys`, `known_hosts`, real `~/.ssh/config`, Tailscale auth
keys, and the tailnet name where it would identify the owner's account. The drop-in contains no
secret; the client example contains placeholders.
