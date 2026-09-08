# Scripts

Reproducible helper and administration scripts belong here. Prefer scripts after the underlying
manual process is understood (ADR-012).

Scripts are organised by **where they run**, which is not always where they are edited.

## `macos/` — run on the MacBook

| Script | Purpose |
|---|---|
| `download-ubuntu-iso.sh` | Downloads the pinned Ubuntu Server image and verifies it two ways: against the checksum recorded in ADR-014, and against the checksum Ubuntu publishes today. Refuses to hand you an unverified file. |
| `write-ubuntu-usb.sh` | Writes a verified ISO to a USB stick. **Destructive.** Refuses to target an internal disk, rejects partition identifiers, and requires you to retype the disk identifier before writing. |

## `server/` — run on the Ubuntu server

| Script | Purpose |
|---|---|
| `verify-install.sh` | Produces a Markdown report of the server's real state — hardware, LVM layout, network, services, versions — for pasting into `docs/`. Deliberately never prints netplan file contents, which hold the Wi-Fi passphrase in cleartext. |

## Conventions

- `set -euo pipefail` unless a script must survive missing optional tools, in which case say why.
- Destructive operations require an explicit target and an explicit confirmation. Never a default.
- Anything whose output is meant to be pasted into the repository must be safe to paste: no secrets.
