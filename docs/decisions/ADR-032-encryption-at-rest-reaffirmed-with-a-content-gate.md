# ADR-032: Encryption at rest — ADR-015 reaffirmed, with an explicit content gate

- **Status:** Accepted
- **Date:** 2026-09-11
- **Supersedes:** none. This is the **revisit** ADR-015 required, performed in Phase 18. ADR-015
  stands, with its premise narrowed from implicit to explicit.
- **Superseded by:** none

## Context

ADR-015 chose whole-disk LVM without full-disk encryption on the reference node, on a stated
premise: *an always-on home node, physically controlled, no sensitive data at rest*. It armed three
revisit triggers, the first being Phase 10 — the point at which the node begins storing personal
knowledge.

Phase 18 ran that revisit early and deliberately, because converting an unencrypted root filesystem
in place is impractical and the honest path is a reinstall. Deciding late means deciding expensively.

Everything below was **measured on the node on 2026-09-11**, not assumed.

### What changed in favour of encryption

**The console exists.** ADR-015 rejected LUKS largely because *"LUKS halts the boot for a passphrase,
on a machine with no console to type it into."* That premise was wrong: `getty@tty1` was enabled and
active the whole time, the DRM connectors were present, and the monitor was merely unplugged. A
display was attached and a console login authenticated at `seat0`/`tty1`. Passphrase-at-boot is
therefore viable, and its real cost is a walk across a room after a power cut.

**The TPM is now 2.0.** The firmware's `TCG Feature Setup` was switched from Discrete TPM to
Firmware TPM (Intel PTT). `tpm_version_major` reports 2, `/dev/tpmrm0` exists, and after installing
`libtss2-rc0t64` — the only missing library, and the real cause of systemd's misleading
*"TPM2 support is not installed"* — `systemd-cryptenroll --tpm2-device=list` reports
`/dev/tpmrm0 MSFT0101:00 tpm_crb`.

### What changed against urgency

**The knowledge base is no longer imminent.** ADR-015's trigger 1 anticipated Phase 10 placing
personal knowledge on this node. ADR-031 deferred the knowledge work into Phase 21 and coupled it to
the ingestion and retrieval design. Nothing private is about to arrive. The trigger has not fired;
it has moved.

### What the hardware will and will not allow

**TPM-sealed unlock works, but only on SHA-1.** The SHA-256 PCR bank is *supported and unallocated*
(`tpm2_getcap pcrs` shows `sha256: [ ]`). Allocating it requires `TPM2_PCR_Allocate`, a
platform-hierarchy command. `phEnable` is 1, but per the TCG specification UEFI firmware sets a
random platform authValue and discards it before handing off, precisely so a running OS cannot
reconfigure the TPM beneath a measured boot. `tpm2_pcrallocate` fails with
`0x9A2 — authorization failure`. **This is the firmware working correctly, not a misconfiguration.**

Tested rather than argued: a throwaway LUKS volume in `tmpfs` enrolled successfully, and systemd
said what it was doing:

> *TPM2 device lacks support for SHA256 PCR bank, but SHA1 bank is supported and SHA1 PCRs are
> valid, falling back to SHA1 bank. **This reduces the security level substantially.***

**A separate encrypted volume has nowhere to live.** `sda3` is 235.4 G and the single logical volume
is 235.4 G. The volume group has **zero free extents**. A second volume needs either a second disk —
whether the M700 Tiny has a free M.2 slot or bay is unanswered — or an offline shrink of the root LV.

## Decision

### 1. The node stays unencrypted. ADR-015 is reaffirmed, not superseded.

The threat full-disk encryption addresses is a powered-off disk in someone else's hands: theft,
disposal, RMA. The node runs continuously in the owner's home. Against that threat, on this
hardware, today, no available option improves matters enough to justify a reinstall.

Reaffirming is a decision. Per the Phase 18 brief, leaving it undecided would not have been.

### 2. The premise becomes an explicit gate, not an assumption

ADR-015 rested on *"no sensitive data at rest"*. That was left implicit and therefore unenforceable.
It is now a stated constraint. **Until this ADR is revisited and encryption is executed, the
reference node must not hold:**

- the knowledge base, in whole or in part, in any form including a derived index or embedding;
- any project repository, product source, or `ops/` record;
- any private repository whatsoever;
- personal correspondence, documents, or notes.

This does not add a constraint. ADR-031 already gates cloning private repositories onto the node.
It makes an existing boundary legible and gives it one address.

### 3. What the node *does* hold at rest is named, not glossed

Two OAuth credentials, the Telegram bot token, and the Wi-Fi passphrase in netplan (ADR-016) are on
an unencrypted filesystem, on a machine with **no BIOS password** — so physical access already
yields a USB boot in about a minute. This is accepted, and it is the strongest argument for
revisiting sooner rather than later. It is recorded here so that no later phase discovers it with
surprise.

### 4. Option C is recorded as available-but-weakened, so a future revisit need not re-derive it

TPM-sealed unlock is proven working on this hardware. It seals against SHA-1, which systemd itself
describes as substantially reducing the security level, and the key releases automatically — so its
protection rests entirely on a boot measurement that SHA-1 undermines. Should a future revisit want
Option C properly, the SHA-256 bank must be allocated from **firmware**, not from Linux.

## Alternatives considered

**B — LUKS with a passphrase typed at boot.** The strongest option available: the key never exists on
the machine unless a human types it, so a stolen box yields nothing regardless of SHA-1, PCRs or
firmware behaviour. Rejected *for now*, not on merit. It requires a reinstall today to protect
content the node does not yet hold, and its running cost — the node stays down after a power cut
until someone attends it — is a real reduction in the always-on role ADR-002 gives it. **This is the
option to choose when the gate in §2 is lifted.**

**C — LUKS with a TPM-released key.** Attractive because unattended boot survives. Rejected: on this
firmware it can only seal to SHA-1, and a disk key released automatically on the strength of a
SHA-1 measurement is a weaker guarantee than it appears. Choosing it would mean a reinstall today to
obtain protection that is difficult to characterise honestly.

**E — encrypt a separate data volume, unlocked over SSH after boot.** The best fit in principle: the
OS boots unattended while content stays encrypted. Rejected on hardware. There are no free extents,
so it needs a second disk that may not be installable, or an offline shrink of the root LV — which
is the riskiest operation of the three on a machine whose restore has never been performed
end to end. It also leaves both OAuth credentials on the unencrypted root unless `/home` moves too,
which reintroduces a boot-ordering problem for `homelab-model-helper`.

**Converting in place.** Not seriously available. ADR-015 already records that the practical path is
a reinstall.

## Consequences

**Accepted:** data at rest is unprotected, including the two OAuth credentials, the bot token and
the Wi-Fi passphrase. Physical possession of the machine or its SSD yields all of it.

**Newly constrained:** the node cannot receive the knowledge base or any project content. Phase 21
and Phase 10 inherit this as a hard precondition, not a preference.

**Cheaper than it was:** Phase 18 produced a verified backup and a verifier proved against planted
corruption. The reinstall that encryption requires is now a far less frightening operation than it
was this morning, when the node had no backup of any kind. **Executing encryption later is no longer
gated on courage; it is gated on scheduling an evening.**

**Still unproved:** no bare-metal restore has been performed. The backup has been verified against
the live node file by file, which is not the same claim. Whichever future phase executes encryption
will perform that restore by necessity, and should treat it as the proof it is.

## Validation / revisit trigger

ADR-015's triggers stand. This ADR sharpens and re-arms them:

1. **Before any private content reaches the node** — the gate in §2. This supersedes ADR-015's
   "Phase 10" wording, since ADR-031 moved that work into Phase 21. The trigger is the *content*,
   not the phase number.
2. **Phase 13 — Security Hardening**, as a scheduled review, unchanged.
3. **If the machine leaves the home**, unchanged.
4. **New:** if a BIOS password is set, or a second disk is installed, two of the constraints above
   change and the comparison is worth redoing.

The check that this decision is holding: `find / -name '.git' -not -path '*/node_modules/*'` on the
node returns nothing, and no knowledge-base or project file exists outside a repository.
