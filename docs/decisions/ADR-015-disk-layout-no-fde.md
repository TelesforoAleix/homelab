# ADR-015: Whole-disk LVM without full-disk encryption on the reference node

- **Status:** Accepted
- **Date:** 2026-09-08
- **Supersedes:** none
- **Superseded by:** none

## Context

The reference node has a single 256 GB SSD carrying a used Windows installation of no value to the
project. The Ubuntu Server installer offers guided plain, guided LVM, guided LVM with LUKS
encryption, ZFS, and fully manual layouts.

Two properties of this specific machine drive the decision:

1. It is **headless and always on**. After initial setup there is no monitor or keyboard attached.
2. It is expected to **recover unattended from power loss** — a home power cut must not require
   physical attendance to bring the lab back.

## Decision

Erase the disk entirely, removing Windows, and use the installer's **guided whole-disk LVM layout
with no full-disk encryption**.

## Alternatives considered

- **LVM + LUKS full-disk encryption.** Rejected for this machine, not on principle. LUKS halts the
  boot for a passphrase, on a machine with no console to type it into. A power cut would leave the
  entire lab down until someone physically visits it, directly contradicting the always-on role in
  ADR-002. The workarounds — TPM-backed automatic unlock, or an initramfs SSH unlock via dropbear —
  are legitimate but would introduce substantial complexity in the phase that installs the operating
  system, before the project has any working remote access at all (that is Phase 03).
- **Plain single ext4 partition, no LVM.** Simplest to reason about, and a fair choice. Rejected
  because LVM costs essentially nothing to adopt now while making snapshots and volume resizing
  available later, which Phase 05 (Docker) and Phase 10 (knowledge storage) are likely to want.
  Retrofitting LVM onto a running server is far more disruptive than enabling it at install time.
- **ZFS.** Rejected: more memory pressure on an 8 GB node, and more new concepts than this phase's
  learning budget justifies.

## Consequences

- The machine boots unattended to a working state, which is the behaviour the node's role requires.
- **Data at rest is not protected.** Physical possession of the machine or its SSD yields everything
  on it. That explicitly includes the Wi-Fi passphrase stored by netplan, and any credentials later
  phases place on the disk. This is an accepted risk for a home environment, not an oversight.
- Because of the above, decisions about *where secrets live* in later phases carry more weight than
  they would on an encrypted host.
- LVM adds a layer of indirection: the operating system's usable space sits inside a volume group
  rather than directly on a partition, which must be understood before resizing anything.

## Validation / revisit trigger

Revisit if the machine moves to a physically untrusted location, if it begins storing personal or
sensitive data at rest, or during Phase 13 hardening — at which point TPM-backed unlock becomes a
reasonable option, since remote access will exist by then.
