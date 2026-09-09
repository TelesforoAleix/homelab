# 03 — Remote Access

## Goal

By the end of this guide your server has no monitor, no keyboard, and no password login. You reach
it by typing `ssh homelab` from your laptop — from anywhere, not just from home — and it lets you in
with a key you hold rather than a secret you can be persuaded to give away.

## Why this matters

Phase 01 left the server accepting **password authentication**. That was a deliberate, time-boxed
decision: you have to be able to log in before you can install a key. But it means that until this
phase, anyone who could reach the machine could try passwords at it, forever, for free.

Passwords have a specific weakness that has nothing to do with how long they are. **You have to send
one to prove you know it.** Every login hands the secret to whatever is on the other end. If that is
not the machine you meant, you have just given it away.

Public-key authentication removes the problem rather than making it harder:

- You generate a **pair** of keys. The **private** key stays on your laptop, always.
- The **public** key goes on the server, in a file called `authorized_keys`.
- To log in, the server sends a challenge; your laptop signs it with the private key; the server
  checks the signature with the public key.

The private key is never transmitted. Not on the first login, not ever. Someone recording the entire
conversation learns nothing they can reuse, and the public key on the server is not a secret — if
someone steals it, they have the lock, not the key.

That is the whole idea. Everything else in this guide is detail.

### The second problem: the address

Your server has whatever address the router handed it — `192.168.1.57` today. ADR-016 wanted a DHCP
reservation to pin it, and Phase 01 could not make one: no router admin access. A reservation would
only have helped at home anyway.

**Tailscale** solves the general version. It builds an encrypted private network (a WireGuard mesh)
between machines you own. Each gets a permanent address in the `100.x` range and a name, and those
follow the machine anywhere. `ssh homelab` works from your kitchen, from an office, from another
country, without exposing anything to the public internet.

## Reference-build choice

| Decision | Choice | ADR |
|---|---|---|
| Key type | Ed25519, passphrase-protected | ADR-018 |
| Password authentication | Disabled | ADR-018 |
| Root login | Disabled outright | ADR-018 |
| Remote network | Tailscale, Google identity | ADR-005, ADR-019 |
| Tailscale SSH | **Not** enabled — OpenSSH keys stay the mechanism | ADR-019 |
| Node key expiry | Disabled on the server | ADR-019 |
| Primary route | MagicDNS name; LAN address kept as fallback | ADR-019 |

## Alternatives

**Port-forward SSH and rely on keys.** Works, and with key-only auth it is not reckless. But it puts
your server in every internet-wide scan within hours, and a future OpenSSH vulnerability becomes
your emergency. Rejected in ADR-005.

**Run your own WireGuard.** You would learn more. You would also have to solve key distribution, NAT
traversal, and keeping a public endpoint reachable. This project's rule is to build simple mechanisms
manually first (ADR-006) — but the thing being learned here is *remote access*, not *VPN
implementation*. Worth an experiment later.

**ZeroTier, Nebula, OpenVPN.** All fine. No reason to depart from ADR-005.

**Tailscale SSH**, letting Tailscale handle authentication by identity instead of keys. Genuinely
convenient. Declined here because it moves SSH authentication into someone else's control plane, on
top of a key setup that already works. Phase 13 revisits it.

**RSA instead of Ed25519.** Only if you must talk to something very old. Otherwise larger, slower,
and easier to configure badly.

## Prerequisites

- Phase 01 complete: Ubuntu Server installed, reachable, password login working.
- Monitor and keyboard **still attached**. You remove them at the very end, and not before.
- A Tailscale-compatible identity (Google, GitHub, Microsoft, Apple).

## Implementation

### The order is the safety mechanism

Do these in order. Each step leaves you a way back in if the next one goes wrong.

```text
1. Make a key                     ← no risk
2. Install it on the server       ← no risk; passwords still work
3. Prove key login works          ← still no risk
4. THEN disable passwords         ← the dangerous step, now de-risked
5. Add Tailscale                  ← additive
6. Remove the monitor             ← last, once everything else is proven
```

Reversing 3 and 4 is how people lock themselves out of headless machines.

### Part A — Generate a key (on the laptop)

**On the laptop.** Not on the server. If you are in an SSH session, type `exit` first.

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_homelab -C homelab
```

Check the output path before continuing. On macOS it must start `/Users/`; on Linux, `/home/`. If it
says `/home/<you>` and you are on a Mac, you generated it on the server — see *Reference-build
experience*, where exactly that happened.

**Give it a passphrase.** It feels redundant, since the key is already a secret. It protects the one
case that matters: someone getting a copy of the file. Without a passphrase the private key is a
plaintext credential sitting in your home directory.

Then load it into the agent, so you type the passphrase once rather than once per connection:

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_homelab   # macOS
ssh-add ~/.ssh/id_ed25519_homelab                        # Linux
```

On macOS this stores the passphrase in the login keychain, so it survives a reboot.

### Part B — Install the public key on the server

```bash
ssh-copy-id -i ~/.ssh/id_ed25519_homelab.pub aleix@192.168.1.57
```

It asks for your **server password** — one of the last times that will work. It copies only the
`.pub` file, and creates `~/.ssh` with the right permissions if needed.

Watch for `1 key(s) remain to be installed`. `0 key(s) remain` means the key is already there.

### Part C — Make `ssh homelab` work

Copy the example from this repository into your SSH config:

```bash
cat config/ssh/homelab.ssh-config.example >> ~/.ssh/config
chmod 600 ~/.ssh/config
```

Edit the `HostName` placeholders. Until Tailscale is running, point `homelab` at the LAN address.

This is more than typing convenience. `scp`, `rsync`, `git` over SSH, and VS Code Remote SSH all
read the same file, so they all get the alias for free.

Prove it works **before** going further:

```bash
ssh -o BatchMode=yes homelab true && echo "key login works"
```

`BatchMode=yes` forbids any interactive prompt, so this cannot silently succeed via a password. That
is what makes it proof rather than encouragement.

### Part D — Disable password authentication

**Keep your current SSH session open in another window.** An established connection is unaffected by
configuration changes, so it is your way back in.

Copy the configuration and the script from the repository:

```bash
scp config/ssh/10-homelab-hardening.conf homelab:/tmp/
scp scripts/server/apply-ssh-hardening.sh homelab:/tmp/
ssh homelab
sudo bash /tmp/apply-ssh-hardening.sh
```

Configuration is **copied from the repository, never pasted into a terminal**. Phase 01 lost a
systemd unit to a paste that broke at ~65 characters. Checksums on both ends confirm the file
arrived intact.

The script refuses to run if you have no key installed, and reverts itself if the result does not
parse. It ends by reloading `sshd`.

#### Two things worth understanding here

**1. The filename starts with `10-` and that is a security control.**

`sshd_config` ends with `Include /etc/ssh/sshd_config.d/*.conf`, read in alphabetical order. And
`sshd` takes the **first** value it sees for a keyword — not the last. This is the opposite of most
configuration systems.

Ubuntu ships `50-cloud-init.conf`, which contains exactly `PasswordAuthentication yes`. A file named
`99-hardening.conf` would be read *after* it and **silently ignored**. Your documentation would say
passwords were off; your server would still accept them.

**2. A config file is not a control until the daemon has re-read it.**

Ubuntu enables `ssh.socket`, so it is tempting to conclude `sshd` starts fresh per connection. It
does not. Ubuntu uses `Accept=no`, meaning systemd holds port 22 and starts **one** long-running
`sshd` that inherits it; later connections are forks of that one process, using the configuration it
read when it started.

So the file has no effect until you reload — and `sshd -t` will *not* warn you, because it re-parses
the files on the spot. It answers "what would sshd conclude if it read these now", not "what is the
server doing".

### Validation for Part D

Ask the server itself, from another terminal:

```bash
ssh -o PreferredAuthentications=none homelab
```

```text
Permission denied (publickey)             ← correct: passwords are gone
Permission denied (publickey,password)    ← passwords are STILL accepted
```

The list in the parentheses is what the server offers. This is the only check that matters.

### Part E — Tailscale

On the server:

```bash
scp scripts/server/install-tailscale.sh homelab:/tmp/
ssh homelab
sudo bash /tmp/install-tailscale.sh
sudo tailscale up
```

`tailscale up` prints a URL. Open it and sign in with the identity recorded in ADR-019 — **that
account becomes the root of trust for your whole network**, and changing it later means rebuilding.

> **Do not follow Tailscale's Ubuntu documentation for this release.** As of 2026-09-09 it still
> references Noble 24.04, and the plausible-looking URL
> `tailscale.com/kb/1187/install-ubuntu-2604` returns HTTP 200 while serving a generic index. The
> package repository is the authoritative source (ADR-014). The script checks it directly and
> refuses to continue if Tailscale does not publish for your release.

No `--ssh` flag: Tailscale provides the *network*, your key provides the *authentication*.

On the laptop, install Tailscale and sign in with the same account:

```bash
brew install --cask tailscale-app
```

**Then disable key expiry on the server node.** In the admin console, Machines → your server → `⋯` →
Disable key expiry.

By default the node's key expires after 180 days, and when it does the machine silently leaves the
network. On a headless server that means plugging a monitor back in. This is a real security control
being switched off deliberately (ADR-019) — Phase 13 revisits it.

Now repoint `homelab` at the MagicDNS name in `~/.ssh/config`.

The first connection to the new name will say **Host key verification failed**. That is correct
behaviour, not a fault: `known_hosts` is keyed by *hostname*, and this name is new. Do not blindly
accept it — check it is the same machine:

```bash
ssh-keygen -l -F 192.168.1.57
ssh-keyscan -t ed25519 homelab.<tailnet>.ts.net | ssh-keygen -lf -
```

If the fingerprints match, it is the same server and you can accept the new name.

### Part F — Go headless

Everything is proven. Now remove the console.

```bash
ssh homelab
sudo poweroff
```

Unplug the monitor, the keyboard, and the DisplayPort→HDMI cable. Press the power button. **Do not
touch it again** — that is the test.

## Validation

Run the verification script:

```bash
scp scripts/server/verify-remote-access.sh homelab:/tmp/
ssh homelab
sudo bash /tmp/verify-remote-access.sh
```

| # | Check | Expected |
|---|---|---|
| 1 | What the running daemon offers | `Permission denied (publickey)` |
| 2 | Daemon newer than its config | PASS — otherwise reload |
| 3 | Effective config | `passwordauthentication no`, `permitrootlogin no`, `authenticationmethods publickey` |
| 4 | `authorized_keys` | `~/.ssh` 700, file 600, key material never printed |
| 5 | Tailscale | Both nodes online; `key expiry: none` |
| 6 | System health | `running`, no failed units |

And from the laptop, after the machine is back up with nothing plugged into it:

```bash
ssh homelab 'uptime -p; cat /sys/class/drm/*/status | sort -u'
```

Every connector reporting `disconnected` is your proof the console is genuinely gone rather than
merely ignored.

## Security notes

- **The private key never leaves your laptop.** Never commit either half; `.gitignore` carries
  patterns for both as a safety net.
- **Lockout is the realistic failure mode, not intrusion.** Hence the ordering, the open second
  session, `sshd -t` before applying, and the console staying attached until the very end.
- **You now have one key.** Losing it means losing remote access. A backup key is Phase 13.
- **Tailscale is new third-party trust.** Its coordination server brokers connections and holds node
  identity and public keys; traffic itself is end-to-end WireGuard. Worth stating rather than
  adopting silently.
- **Disabling key expiry trades security for availability**, deliberately. Recorded in ADR-019 and
  flagged for Phase 13.
- **There is still no firewall.** Port 22 is open on the LAN and answers. Phase 13.
- **Do not port-forward SSH.** Tailscale makes it unnecessary.

## Reference-build experience

Two mistakes and one wrong assumption, all worth repeating because none of them announced itself.

### The key was generated on the wrong machine

The instructions were prefixed with `!`, meaning "run at the Claude Code prompt". They were pasted
instead into a terminal already logged into the server. Bash ran them without complaint — a leading
`!` is its negation operator, not a syntax error — and the output looked like success.

The key pair was created on the **server**, and `ssh-copy-id` authorised the server to log into
itself. The laptop had nothing.

Two tells: the shell prompt read `aleix@homelab`, and the path was `/home/aleix/.ssh/` when a Mac
home directory is `/Users/`. Recovery cost nothing because password login still worked.

**Lesson:** when an instruction targets a specific machine, give a way to check the output
afterwards. "The path should start `/Users/`" beats "run this on your laptop".

### `sshd -T` said passwords were off while the server still accepted them

The important one. After installing the drop-in, `sudo sshd -T` reported `passwordauthentication no`
— but the server still advertised `Permission denied (publickey,password)`.

The reasoning that led there was wrong in a tempting way. `ssh.socket` is enabled, so surely `sshd`
starts per connection and re-reads its config? That is inetd-style activation. Ubuntu uses
`Accept=no`: one long-running daemon, started at 08:01:54, still serving the configuration it read
then. The drop-in was written at 12:28:52.

`sshd -T` was not lying. It answers a different question than the one being asked.

Fixed with `systemctl reload ssh` — reload, not restart, because `ExecReload` validates first and
`KillMode=process` leaves your session alone. The script now does it, and the verification script
warns whenever the config is newer than the running daemon.

### Two errors in this repository's own material

- The drop-in was documented as mode `0644`, justified by claiming `sshd` needs it world-readable.
  False: `sshd` reads it as root, and Ubuntu's own file in that directory is `0600`. Corrected.
- A `set -e` bug was reported in the apply script and "fixed" — then the demonstration written to
  prove it disproved it. `set -e` ignores a failing non-final command in an `&&` list, so the
  original was safe where it stood. It only bites as the final line of a script or function. The
  code was kept for clarity; the comment claiming a bug was rewritten to say what is true.

### Timings

| Event | Result |
|---|---|
| Cold boot, no console, to SSH-reachable | ~26s (`12.4s` firmware + `3.7s` loader + `0.8s` kernel + `3.0s` initrd + `6.0s` userspace) |
| Tailscale rejoin after reboot | Reachable on the first poll |
| Tailscale install | 38.7 MB, ~6s download |

## Tested versions

| Component | Tested with |
|---|---|
| OpenSSH server | OpenSSH_10.2p1 Ubuntu-2ubuntu3.6 (OpenSSL 3.5.5) |
| OpenSSH client (macOS) | OpenSSH_9.9p2, LibreSSL 3.3.6 |
| Tailscale (Ubuntu) | 1.102.3, from the `resolute` repository |
| Tailscale (macOS) | 1.102.3, Homebrew cask `tailscale-app` |
| VS Code Remote SSH | 0.124.0 |
| Ubuntu Server | 26.04.1 LTS, kernel 7.0.0-31-generic |

**Requires:** nothing version-specific. Any current OpenSSH supports Ed25519 and drop-in
configuration. The `Accept=no` socket-activation behaviour is Ubuntu's packaging choice — check it
on your own release rather than assuming, with `systemctl cat ssh.socket`.

## Next phase

[Phase 02 — Linux Fundamentals](../../ROADMAP.md), deferred behind this phase and now carried out
over key-based remote access. Read
[`docs/handovers/03-remote-access-handover.md`](../../docs/handovers/03-remote-access-handover.md)
first — particularly the part about the console being gone, which changes what recovering from a
mistake looks like.
