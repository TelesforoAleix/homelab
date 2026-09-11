# Phase 18 Handover — Foundations

- **Phase:** 18 — Foundations (recoverability, not defence)
- **Completed:** 2026-09-11
- **Brief:** [`18-foundations.md`](18-foundations.md), committed before implementation per ADR-017
- **Addressed to:** whichever phase runs next, and specifically to Phase 21 and Phase 13

## Outcome

**All five functional objectives met.** The node now has a second way in, a backup, a proved
restore, a recorded encryption decision, and a resolved `eno1` question. It had none of these on
2026-09-10.

The Definition of Done is satisfied in full, including `guide/18-foundations/`, which was
written after the phase was first declared complete.

## What the next phase inherits

**A hard precondition, not a preference.** ADR-032 gates what the node may hold. Until encryption is
revisited and executed, the node **must not hold** the knowledge base in any form (including a
derived index or embeddings), any project repository, any private repository, or personal documents.
**Phase 21 cannot clone `brain` or any project onto this node.** Phase 10 inherits the same
constraint for anything it would store.

**A recovery path that is a physical console, not a second key.** It survives network, firewall, SSH
and Tailscale failure alike — which matters unusually much here, because Wi-Fi is the node's only
network path and always will be.

**A weekly backup that is manual by design.** `scripts/macos/backup-node.sh` prompts for the node's
sudo password every run. That is deliberate: ADR-022 records that `aleix` is root-equivalent via the
`docker` group, and the brief §5 requires that the backup must not become a *second* root-equivalent
path. A NOPASSWD rule or a stored key would create exactly that. Do not "improve" this into
automation without replacing the control it provides.

**A restore that has been verified but never performed end to end.** See §Open issues.

## What was implemented

| Item | Where |
|---|---|
| Backup | `scripts/macos/backup-node.sh` |
| Verifier, with a planted positive control | `scripts/macos/verify-node-backup.sh` |
| Encryption decision | `docs/decisions/ADR-032-…md` |
| ADR-015 forward pointer (reaffirmed, not superseded) | `docs/decisions/ADR-015-disk-layout-no-fde.md` |
| `eno1` resolved as permanent | `docs/decisions/ADR-016-wifi-reference-link.md` |

## Final architecture / state

```
Console          attached; getty@tty1 active; login authenticated at seat0/tty1
Network          Wi-Fi only, permanently. eno1 DOWN, NO-CARRIER, and staying that way
Disk             sda3 LVM2_member 235.4G -> single LV 235.4G. No crypto_LUKS. Zero free extents
TPM              2.0 (Intel PTT). /dev/tpmrm0 visible to systemd-cryptenroll
PCR banks        sha1 allocated; sha256 SUPPORTED BUT UNALLOCATED, and unallocatable from Linux
Backup           /Volumes/SD Card/homelab-backup/<date>/ — 2 age archives + plaintext MANIFEST
Health           running, 0 failed units, 6 listeners, Secure Boot enabled
Repositories     0 on the node — the ADR-032 gate holds
```

## Validation performed

Real output, not assertions.

**Second way in** — display connected on `card1-DP-1`; `loginctl` shows session 29,
`aleix seat0 … tty1`. The owner authenticated. *A console you cannot log into is not a recovery
path*, so the login was the test, not the prompt.

**Backup** — 182 entries, 312 KB node state, 20 MB repository mirrors, both valid
`age-encryption.org/v1` files.

**Restore, proved** —
```
decrypted 312K
sha256 matches the value recorded before encryption
extracted 111 files
compared 111 files
every compared file matches the live node in content and numeric owner
12/12 critical files present
checksum check fires on a one-byte corruption
PASS
```
Ownership survives inside the tar where exFAT cannot represent it: token `0/0` mode 0600, the three
allowlists `0/982` mode 0640 — which matters because `LoadCredential=` depends on those modes.

**TPM** — `systemd-cryptenroll --tpm2-device=list` → `/dev/tpmrm0 MSFT0101:00 tpm_crb`. A throwaway
LUKS volume in `tmpfs` enrolled successfully against the SHA-1 bank. `tpm2_pcrallocate` fails
`0x9A2`. Real disk untouched throughout; no persistent TPM state created.

**Gate** — 0 repositories on the node, 0 LUKS layers.

## ADRs

- **ADR-032** (new) — encryption at rest reaffirmed, with an explicit content gate.
- **ADR-015** — forward pointer added. **Reaffirmed, not superseded.**
- **ADR-016** — resolved: Wi-Fi is permanent, not initial.

## Tested versions

| | |
|---|---|
| `age` | 1.3.2 (macOS, Homebrew) |
| `tpm2-tools` | 5.7-1build1 |
| `libtss2-rc0t64` | 4.1.3-6 |
| `sudo-rs` | 0.2.13-0ubuntu1.2 |
| `systemd` | 259 (259.5-0ubuntu3.4), built `+TPM2` |

## Security notes

**Named rather than glossed:** two OAuth credentials, the Telegram bot token and the Wi-Fi
passphrase sit on an unencrypted filesystem, on a machine with **no BIOS password**. Physical access
already yields a USB boot in about a minute. This is the strongest argument for revisiting ADR-032
sooner rather than later.

**The backup is secret material.** It contains all of the above. The card must be treated
accordingly, and the passphrase lives in a password manager and never on the card.

**Deliberately excluded from the backup, with reasons in the script:** `/var/lib/tailscale`
(re-authenticating a rebuilt machine is cleaner than restoring a dead machine's identity) and
`/etc/ssh/ssh_host_*` (regenerating is honest; suppressing the changed-fingerprint warning is not).

## Costs

**Zero new recurring cost.** `age` is free; the microSD and USB were already owned. No paid
dependency was created.

## Problems / failures / lessons

**Three of the brief's own premises were wrong, and finding that out was most of the phase's value.**

1. *"The node has no console."* It always had one — `getty@tty1` active, connectors present, monitor
   merely unplugged. This single correction made passphrase-at-boot viable and downgraded every
   lockout risk in the phase.
2. *"Package: `libtss2-rc0`."* The name is `libtss2-rc0t64` (Ubuntu's 64-bit `time_t` rename), and
   `tpm2-tools` depends on it anyway.
3. *"Allocate the SHA-256 bank and Option C becomes available."* It cannot be allocated from Linux
   at any privilege level. UEFI sets a random platform authValue and discards it before boot, by
   design. Option C exists only on SHA-1.

**The recurring failure family produced four more instances, all in the backup scripts, all found by
running rather than reading:**

1. A remote `2>/dev/null` discarded sudo-rs's password prompt. With a pty, ssh folds stdout, stderr
   and `/dev/tty` into one stream, so redirecting the stdout of an interactive `ssh -t` writes the
   prompt into the output file. **Rule: never redirect the stdout of an `ssh -t` that must prompt.**
2. A `printf` format beginning `--` is read by bash as an option.
3. The manifest's own help line ends in `node-state.tar.gz`, so a filename match recovered
   `"Inspect:"` instead of a checksum — and condemned a backup that was perfectly good.
4. GNU tar renders numeric owners `0/982`; BSD tar, which macOS ships, uses two columns. Matching
   the GNU form against BSD output failed **all 111 files while every content hash passed**.

**The standing lesson, reinforced twice over.** Three mechanisms were asserted confidently and
disproved by testing — pty newline translation, stderr merging, and a `set -e` exit that does not
occur. In each case the first test was itself invalid because it ran without a pty. *A test that
cannot observe the thing it is testing is not evidence.* `script -q /dev/null` produced a real pty
and the answer immediately.

**A verifier that fails everything is as useless as one that passes everything**, and more alarming.
Defect 4 above produced 111 confident failures against a correct backup. That is why step 5 plants a
one-byte corruption and requires its own check to fire.

## Deviations from phase brief

- **§7.6 `eno1`** — the brief expected either a cable attached or the interface left down. Resolved
  in the second branch, and made **permanent** rather than pending: wired Ethernet is unavailable at
  the location and will not become available. Recorded on ADR-016.
- **§2.1 the TPM reboot never happened.** The brief scheduled `tpm2_pcrallocate` plus a reboot. The
  allocation is impossible from Linux, so there was nothing to reboot for. No reboot was performed
  in this phase.
- **§1.1** states "the node has no console" and is contradicted by §1.0 of the same brief. §1.0 is
  correct. Both are left as written, per `PROJECT.md` §11.

## Open issues / technical debt

1. **No bare-metal restore has been performed.** The archive is verified against the live node file
   by file, which is a weaker claim than "a rebuild boots". The procedure is documented in this
   session but untested. Whichever phase executes encryption will perform that restore by necessity.
2. **The SD card is an interim target.** A second USB and a permanent arrangement come later. Flash
   is not archival: cells leak charge unpowered, so this copy must be refreshed, not trusted
   indefinitely.
3. **Offsite is unsolved in practice.** The card *can* leave the room, which is why it was chosen —
   but it has not yet been stored anywhere other than beside the node.
4. **SHA-256 PCR bank needs firmware.** If Option C is ever wanted properly, allocation must happen
   in the Lenovo BIOS, not from Linux.
5. **No BIOS password.** Physical access implies a USB boot. Phase 13's territory.
6. ~~**No `guide/` material**~~ — **closed 2026-09-11.** `guide/18-foundations/` was written after
   the phase was first declared complete. See §Definition of Done.

## Recommended roadmap changes

None. Phase 13 remains the dedicated hardening phase and inherits items 4 and 5 above.

## Definition of Done

| Item | State |
|---|---|
| Functional objective works | ✅ all five |
| Configuration/setup reproducible | ✅ two committed scripts |
| Validation/tests passed | ✅ with a planted positive control |
| Security implications considered | ✅ §Security notes |
| Relevant repository files committed | ✅ |
| Human-facing guide updated | ✅ `guide/18-foundations/` (2026-09-11) |
| Project/internal documentation updated | ✅ |
| ADRs created/updated | ✅ ADR-032; ADR-015 and ADR-016 pointers |
| Actual costs recorded | ✅ zero |
| Problems, failed approaches, lessons recorded | ✅ at length |
| Tested versions recorded | ✅ |
| No unexplained critical AI-generated component | ✅ both scripts carry rationale headers |
| `main` represents a known-working state | ✅ on merge |
| No failed units, no degraded state | ✅ running, 0 failed |
| Structured handover written | ✅ this document |

**Closed 2026-09-11.** `guide/18-foundations/` was written after the phase was first declared
complete, and the Definition of Done is now satisfied in full. It covers the measuring exercise that
shaped the backup, the standing-privilege rule, the filesystem-metadata trap, encrypting for the
restore target, the planted positive control, the four scripting defects, and the encryption
decision asked as a threat-model question rather than a yes/no.

The gap was recorded as outstanding rather than quietly ticked, and is recorded as closed here for
the same reason: the point of the Definition of Done is that it is applied literally.
