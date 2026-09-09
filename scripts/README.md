# Scripts

Reproducible helper and administration scripts belong here. Prefer scripts after the underlying
manual process is understood (ADR-012).

Scripts are organised by **where they run**, which is not always where they are edited.

## `macos/` — run on the MacBook

| Script | Purpose |
|---|---|
| `download-ubuntu-iso.sh` | Downloads the pinned Ubuntu Server image and verifies it two ways: against the checksum recorded in ADR-014, and against the checksum Ubuntu publishes today. Refuses to hand you an unverified file. |
| `write-ubuntu-usb.sh` | Writes a verified ISO to a USB stick. **Destructive.** Refuses to target an internal disk, rejects partition identifiers, and requires you to retype the disk identifier before writing. |
| `scan-history.sh` | Scans every blob reachable from every ref for secrets — the pre-publication gate required by ADR-021. Deliberately scans *objects*, not the working tree, because `.gitignore` is not retroactive and a secret deleted in a later commit is still in history. States its own limits in its header. |
| `preflight.sh` | Checks the safety preconditions from `docs/standards/safe-changes-headless.md` before a lockout-class change (ADR-020). Runs on the Mac deliberately: it proves both access routes from outside, the way a real connection arrives, which a script on the server cannot do. |

## `server/` — run on the Ubuntu server

| Script | Purpose |
|---|---|
| `verify-install.sh` | Produces a Markdown report of the server's real state — hardware, LVM layout, network, services, versions — for pasting into `docs/`. Deliberately never prints netplan file contents, which hold the Wi-Fi passphrase in cleartext. |
| `apply-ssh-hardening.sh` | Installs the key-only sshd configuration (ADR-018). Refuses to run if the invoking user has no `authorized_keys` entry, reverts itself if `sshd -t` rejects the result, and reloads sshd — because the running daemon does not re-read its configuration on its own. |
| `install-tailscale.sh` | Adds Tailscale's apt repository and installs it. Derives the codename from `/etc/os-release` and refuses to continue unless the repository declares `Origin: Tailscale` and the running architecture, so an unsupported release becomes a recorded problem rather than a silent fallback (ADR-014). |
| `lab-sandbox.sh` | Creates and destroys the disposable Phase 02 practice environment — a passwordless `nologin` user, a group, a setgid directory, and a systemd unit with no `[Install]` section so it can never run at boot. Refuses to create anything colliding with a real account, and refuses to delete any account not carrying the marker it writes. |
| `verify-remote-access.sh` | Reports the live remote-access posture. Probes the **running** SSH daemon over the network rather than trusting `sshd -T`, warns when configuration is newer than the daemon, and redacts the Tailscale account and tailnet suffix so its output is safe to paste. |

## Conventions

- `set -euo pipefail` unless a script must survive missing optional tools, in which case say why.
- Destructive operations require an explicit target and an explicit confirmation. Never a default.
- Anything whose output is meant to be pasted into the repository must be safe to paste: no secrets.
  That includes identity leaking in from third-party tools — `verify-remote-access.sh` redacts the
  Tailscale account and tailnet name, which `tailscale status` prints against every node.
- A script that changes a security control should verify the **running system**, not the file it
  just wrote. Phase 03 shipped a correct configuration to a daemon that never re-read it.
- A check that cannot determine an answer must say **unknown**, never a plausible-looking zero.
  Phase 02's session check first used `who`, which reports no sessions and exits 0 on Ubuntu 26.04
  because systemd 257 removed utmp support. Being confidently wrong is worse than erroring.
- **An error is not a negative result.** `grep` exit 2 is not exit 1. Phase 04's private-key check
  passed a pattern beginning with dashes, so grep parsed it as options and failed — and because the
  code discarded stderr and treated any non-match as clean, the most important class in the scanner
  was silently dead. Inspect exit status; refuse to produce a verdict a check could not support.
- **A detector that has only ever reported "clean" is unvalidated.** It has been shown it can say
  *fine*; it has never been shown it can say *not fine*. Plant a positive case somewhere disposable
  and confirm it fires. That is how the bug above was found, four checks into the same failure family
  across three phases.
- **Report what was actually examined**, not just the conclusion. Phase 04's scanner reported all
  sixteen classes clean while having searched zero of 213 blobs. It now prints the count and refuses
  to report a verdict on an empty corpus.
