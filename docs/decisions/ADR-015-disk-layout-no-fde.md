# ADR-015: Whole-disk LVM without full-disk encryption on the reference node

- **Status:** Accepted
- **Date:** 2026-09-08
- **Amended:** 2026-09-08 — Project Planning ratification of the Phase 01 brief, amendment 3
  (frame as a reference-build trade-off; add a Second Brain revisit trigger)
- **Supersedes:** none
- **Superseded by:** none
- **Revisited by:** [ADR-032](ADR-032-encryption-at-rest-reaffirmed-with-a-content-gate.md)
  (2026-09-11, Phase 18) — this decision is **reaffirmed**, its "no sensitive data at rest"
  premise made an explicit content gate, and its trigger 1 restated as the arrival of private
  content rather than a phase number. Not superseded; the choice here still stands.

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

## Scope of this decision

**This is a reference-build trade-off, not a universal recommendation.**

It is the right answer for *this* machine because of *this* machine's role: an always-on,
physically-secured-at-home orchestration node that must boot unattended. Change any of those
premises and the answer changes with it:

| Situation | Appropriate choice |
|---|---|
| Laptop, or any machine that leaves the home | **Encrypt.** The availability argument does not apply. |
| Server in a shared, rented, or co-located space | **Encrypt**, and solve unattended unlock properly. |
| Machine storing significant personal or sensitive data | **Reconsider** — see the revisit trigger below. |
| Always-on home node, physically controlled, no sensitive data at rest | The choice made here. |

Anyone reproducing Home Lab should make this decision against their own threat model rather than
copying it because the reference build did. The guide states the trade-off rather than presenting
unencrypted disks as best practice.

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
  on it. That explicitly includes the Wi-Fi passphrase stored by netplan (ADR-016), and any
  credentials later phases place on the disk. This is an accepted risk for a home environment, not
  an oversight.
- Because of the above, decisions about *where secrets live* in later phases carry more weight than
  they would on an encrypted host.
- LVM adds a layer of indirection: the operating system's usable space sits inside a volume group
  rather than directly on a partition, which must be understood before resizing anything.

## Validation / revisit trigger

Revisit this decision when **any** of the following becomes true:

1. **Phase 10 — Knowledge / Second Brain.** This is the explicit trigger required by Project
   Planning. Once the node begins storing significant sensitive or personal Second Brain data —
   documents, notes, correspondence, anything the owner would not hand to a stranger — the
   "no sensitive data at rest" premise of this decision no longer holds and encryption at rest must
   be reconsidered on its merits. Phase 10 must not silently inherit this ADR.
2. The machine moves to a physically untrusted location.
3. **Phase 13 — Security Hardening**, as a scheduled review. By then remote access exists, which
   makes TPM-backed unlock or initramfs SSH unlock realistic options rather than premature complexity.

Note that revisiting after the fact is more expensive than choosing encryption at install time:
converting an unencrypted root filesystem to LUKS in place is possible but risky, and the practical
path is usually a reinstall. Phase 10 planning should account for that.
