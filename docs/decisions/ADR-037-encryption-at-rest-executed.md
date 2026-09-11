# ADR-037: Encryption at rest, executed — an encrypted data volume

- **Status:** Accepted
- **Date:** 2026-09-11
- **Supersedes:** ADR-032's content gate, which it discharges for the encrypted volume only. Revisits
  ADR-015, which ADR-032 reaffirmed.
- **Superseded by:** none

## Context

ADR-032 reaffirmed that the node stays unencrypted and turned ADR-015's implicit *"no sensitive data
at rest"* premise into an explicit gate: no knowledge base, no project content, no private repository
on the node until encryption is revisited and executed.

The target architecture then made that gate untenable. It states that Home Lab is **always running**
and **holds the knowledge**, and the gate says the knowledge cannot be on the machine that is always
running. Every workaround inherits the contradiction — putting the knowledge on the owner's laptop
produces a personal tool with a server attached, not a central system.

This ADR executes the revisit ADR-032 deferred.

## Decision

### 0. Verify the filesystem before anything else

```bash
findmnt -no FSTYPE /
```

**Verified 2026-09-11 on the node: `ext4`.** The shrink path exists and this ADR stands.
`/boot` is a second ext4 volume and the EFI partition is vfat — a normal Ubuntu layout.

**If this had returned `xfs`, this ADR would be void and would need rewriting.** XFS cannot be shrunk by any tool;
it is a permanent property of the filesystem. The shrink path below would not exist and the options
would collapse to a second disk or a reinstall. The repository does not currently record which
filesystem the root volume uses, and this decision must not be accepted on an assumption.

### 1. Shrink the root LV; put a LUKS volume in the freed extents

`sda3` is 235.4 G and the single logical volume is 235.4 G — the volume group has zero free extents,
so a second volume has nowhere to live. ADR-032 named the two ways out: a second disk, or an offline
shrink.

**Shrink first; add a second disk later.** The shrink is reversible in the sense that matters (the
space can be given back), and it needs no hardware that may not exist — whether the M700 Tiny has a
free M.2 slot is still unanswered.

### 2. Only the data volume is encrypted. Root stays as it is

Full-disk encryption is **not** adopted. LUKS on root halts boot for a passphrase, which breaks
unattended recovery from a power cut — the property Phase 01 tested deliberately and the architecture
depends on.

### 3. No TPM. The volume is unlocked over SSH after boot

The node boots unattended to a reachable state. The owner then unlocks the data volume over SSH via
Tailscale.

This removes the TPM from the design entirely, and with it the finding that made ADR-032 uneasy:
enrolment works only against the **SHA-1** PCR bank, which systemd itself reports *"reduces the
security level substantially"*. That weakness was never in the encryption — it was in the strength of
the binding that decides whether to release the key automatically. Requiring a human removes the
question rather than answering it.

### 4. Degraded-until-unlocked is a normal operating state

After any unplanned reboot the node is up, reachable, and **the AI system is not running**. That is
expected behaviour, not a fault. Services that depend on the volume must wait and say why; they must
not crash, and they must not start in a half-configured state.

### 5. What lives where

| Unencrypted root | Encrypted volume |
|---|---|
| Telegram bot · watchdog · notifier | Harness · Workbench · Factory · projects · `brain` |
| Works the moment the node boots | Waits for unlock |

Factory's own code is public and could sit on root. It goes in the volume anyway, because **one
boundary is easier to reason about than two**, and because nothing in the AI system is useful while
the projects it operates on are locked.

The side that always works is the side that can tell the owner what happened — which is the
separation the recovery notification needs regardless.

### 6. What this protects, stated honestly

It protects data at rest when the machine is **off**, or when the disk leaves the building: disposal,
RMA, cold imaging, a drive pulled from a powered-down machine.

It does **not** protect a running machine, and it does not protect against the whole machine being
taken while the volume is unlocked. The owner has assessed the content as mostly general knowledge
and personal notes rather than secrets, and proper secrets are not stored there.

**Its larger value is governance.** It discharges ADR-032's gate, which is what allows `brain` and the
projects onto the always-running server. That is the reason to do it, and recording the modest
security value is more useful than overstating it.

### 7. ADR-032's gate is discharged for the encrypted volume only

The unencrypted root still may not hold the knowledge base, project content or any private
repository. The gate moves; it does not disappear.

## Alternatives considered

**TPM auto-unlock.** Rejected. It would survive a power cut without the owner, which is a real
benefit, but it binds to the SHA-1 bank on this hardware and it protects only against the disk being
removed — not against the machine being taken and booted. Once SSH unlock is accepted, the TPM adds
a firmware dependency and a weak binding for a convenience.

**Full-disk encryption via reinstall.** Rejected for now, not on principle. It is the cleanest end
state and it costs a reinstall of a working machine, and a passphrase at boot removes unattended
recovery.

**A second disk first.** Deferred rather than rejected. It avoids the shrink entirely and it depends
on hardware that has not been confirmed to exist.

**Do nothing; keep knowledge off the node.** Rejected — it contradicts the target architecture's own
definition of the system.

## Consequences

**This is the most dangerous operation this project has attempted.** The shrink is offline: a mounted
root filesystem cannot be shrunk. The filesystem must be reduced **before** the logical volume, and
an `lvreduce` that cuts below the filesystem's new size destroys it. Order errors are not recoverable
by retrying.

Two things make it survivable and both came from Phase 18: **the console works**, which is the class
of operation ADR-020 exists for, and **a backup verified by restoring**. The restore must be
re-verified immediately before the operation rather than relied on from the earlier test.

**Newly required:** one manual unlock after every unplanned reboot; a notification that reports lock
state; and services that treat "volume locked" as a first-class state.

**Constrained:** root may still hold no private content. Secrets remain out of the repository and off
the node regardless of encryption.

**Deferred:** the second disk; whether the root filesystem is eventually encrypted too.

## Validation / revisit trigger

Before the operation:

1. `findmnt -no FSTYPE /` returns a shrinkable filesystem (§0). If not, stop.
2. The backup is **restored** and verified, immediately before — not trusted from Phase 18.

After:

3. `fsck` on the shrunk filesystem is clean.
4. The LUKS volume opens, and **fails to open with a wrong passphrase** — proved by attempt.
5. A service that depends on the volume, started while locked, **refuses legibly** and does not
   partially start.
6. A full power-cut test: the node returns unattended, is reachable over Tailscale, the bot works,
   the AI system is not running, and the volume unlocks over SSH afterwards.
7. `lsblk`/`cryptsetup status` show the volume encrypted and nothing else changed.

**Revisit if:** a second disk becomes available, which removes the shrink from the design; the manual
unlock proves intolerable in practice, which would reopen the TPM question on better hardware; or the
content stored there changes character enough that the threat model in §6 no longer describes it.
