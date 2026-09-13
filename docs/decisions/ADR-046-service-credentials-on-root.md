# ADR-046: Service credentials stay on the unencrypted root — an accepted risk

- **Status:** Accepted — **amended 2026-09-13 by Phase 13** (§Amendment below: sixth table row, the
  token row rewritten, trigger 3 fired twice, check 2 corrected, all three checks re-run)
- **Date:** 2026-09-12
- **Supersedes:** none. **Closes the gap ADR-037 §6 recorded and explicitly did not close.** Extends
  ADR-032 §3's naming of what root holds into a decision about it. Proposed alongside the Phase 18.1
  brief (`docs/handovers/18.1-encryption-execution.md`); accepted or revised by the orchestrator, not
  by the phase.
- **Superseded by:** none

## Context

ADR-037 puts knowledge and project content into an encrypted volume and leaves the root filesystem
as it is. Its §6 then says, in as many words, what that does not do:

> Those credentials live on **root**, which stays unencrypted, so encrypting the data volume leaves
> them exactly where they are. […] Closing that gap needs either root encryption (a reinstall), moving
> service credentials into the encrypted volume and accepting that those services cannot start until
> it is unlocked, or a BIOS password to raise the cost of the USB-boot path. **None of the three is
> decided here**, and the gap should be closed deliberately rather than left implied by this ADR's
> existence.

The roadmap makes Phase 18.1 the place that decision must not be skipped. This is that decision.

### What is actually on root

ADR-037 §6 quoted the Phase 18 handover's four. The full inventory of credential-shaped state on the
unencrypted filesystem, so nobody discovers a fifth later:

| Credential | Where | What holding it lets someone do | Revoked how, from the MacBook |
|---|---|---|---|
| Claude OAuth | `/home/aleix/.claude/.credentials.json`, `0600` | Use the owner's Claude subscription until revoked | Sign out of the session at claude.ai; re-authenticate the node |
| Codex OAuth | `/home/aleix/.codex/auth.json`, `0600` | Use the owner's ChatGPT subscription until revoked | Same, at chatgpt.com |
| Telegram bot token | ~~`/etc/homelab-telegram-bot/token`, `root:root 0600`, via `LoadCredential=`~~ **Since 2026-09-13:** `/etc/homelab-telegram-bot/token.cred`, `root:root 0600`, **sealed to this machine's TPM2** (`systemd-creds encrypt --with-key=tpm2 --tpm2-pcrs=""`), via `LoadCredentialEncrypted=` in the bot, the notifier **and the watchdog**; no plaintext on the node | *Be* the bot — **only from this machine**: a pulled disk yields a blob the TPM is not there to unseal; a USB boot on the same machine still can (same TPM, no PCRs, by design — see §Amendment) | `@BotFather` → `/revoke`; the old token dies instantly; the plaintext for re-sealing is in the owner's password manager, not on the node |
| Wi-Fi passphrase | `/etc/netplan/`, `0600` | Join the home network | Change it on the router; re-run netplan on the node |
| Tailscale node identity | `/var/lib/tailscale/tailscaled.state` | Present a machine as `homelab` on the tailnet until removed | Delete the node in the Tailscale admin console; re-authenticate |
| **GitHub node key** (added 2026-09-13, Phase 13 — existed since 18.2) | `/home/aleix/.ssh/id_ed25519_github`, `0600 aleix:aleix`, **passphrase-less**, account-level, selected by `Host github.com` + `IdentitiesOnly yes` | Pull all five repositories; **push to `oncla`, `factory-ops`, `brain`** as the owner. Blast radius: those repositories' contents and history; not the node | GitHub → Settings → SSH and GPG keys → `homelab node — 2026-09-12` → Delete. Audited by title from the MacBook: `gh api user/keys` (one key, OBSERVED 2026-09-12). Not in the backup (`backup-node.sh` excludes it); a rebuilt node makes a new one |

Two things are true of all five. **Each is revocable from the laptop in minutes**, and the revocation
is complete — none is a durable secret whose exposure survives the revocation. And **none of them can
open the encrypted volume.** The volume's key derives from a passphrase that exists in the owner's
password manager and head and nowhere on the machine — a constraint §3 below makes binding.

### The owner's threat model, in the owner's framing

The machine is not expected to be stolen. It sits in the owner's room, in the owner's home, and the
credible ways it leaves are disposal, RMA or a drive pulled from a powered-down box — ADR-037 §6's list.
And **proper secrets are not stored there by design**: the content going into the volume is mostly
general knowledge and personal notes; what would be catastrophic to lose is not put on this node in
the first place. ADR-032 §3 named the credentials, called the exposure accepted, and called it the
strongest argument for revisiting encryption sooner. Encryption has now been revisited and is being
executed — for the *content*. This ADR says what happens to the credentials, deliberately.

## Decision

### 1. The credentials stay on root. This is an accepted risk, not a resolved problem

All five items in the table remain where they are, on the unencrypted root filesystem. The risk is
accepted with the reasoning below and recorded so a future reader knows it was **decided**, in the
same spirit as ADR-040 §3.

### 2. Why moving them into the volume is rejected — the substantive part

The Telegram bot token is **how the node reports for duty**. After an unattended reboot — a power cut,
a kernel update — the node comes up with the volume locked (ADR-037 §4). The bot starts from root,
polls Telegram, and is the one component that can say *"I am back, and the volume is locked"* — which
Phase 12 makes into a push notification, and which the `/status` command answers already. That is the
entire recovery story ADR-037 §5 rests on: *the side that always works is the side that can tell the
owner what happened.*

Move the token into the volume and the token is not there when the bot starts. **The node comes back
silent.** No bot, no notification that it needs unlocking, nothing to answer `/status` — a machine
that is up, reachable only to someone who already knows to look for it, and telling no one. Phase
18.1's own power-cut test (ADR-037 validation 6: *"the bot works"*) could not pass as written, and the
unlock reminder Phase 12 exists to send would have nothing to send it with.

The Wi-Fi passphrase and the Tailscale identity are one step further back in the same chain: without
them the node does not reach the network at all, so nothing — not the bot, not SSH — is reachable, and
the volume cannot be unlocked from anywhere but the console. That would leave the node *worse* than
today: encrypted content nobody can reach without walking to it, which is the passphrase-at-boot
design ADR-037 §2 rejected, arrived at sideways.

The two OAuth credentials are the only ones that *could* move without breaking recovery; nothing
about reporting for duty needs them. They stay for three reasons, weaker than the first and stated as
such: they are consumed by interactive CLIs and by `homelab-model-helper` on root, so moving them
reintroduces the boot-ordering problem ADR-032 already noted; the harness that will eventually hold
model access lives in the volume (ADR-037 §5) and ADR-034 §13's transition changes who holds
credentials at all, so deciding their home now pre-empts Phase 23.3; and they are the most easily
revoked of the five. **They are the pair most likely to be moved when this ADR is revisited** (§Validation,
trigger 4).

### 3. Nothing on root may be able to open the volume — the constraint that makes §1 acceptable

The reason the accepted risk is small is that the credentials on root are all revocable and none of
them touches the volume. That second half is a property only for as long as it is kept:

- **No keyfile** for the volume on root, in `/etc/crypttab`, `/root`, `/home` or anywhere else.
- **No TPM enrolment** of the volume's key (ADR-037 §3 already removes the TPM from the design; this
  makes it a rule rather than a design choice).
- **No cached or scripted passphrase** — no `--key-file`, no `echo … |`, no environment variable, no
  password-store on the node.
- **The LUKS header backup lives off the node**, `age`-encrypted on the backup card (Phase 18.1
  brief §7.4 C6), never on root.

A future phase that finds it wants any of these — a keyfile for convenience, say — is not tuning this
decision. It is reversing it, and needs a superseding ADR.

### 4. What this protects, stated honestly — ADR-037 §6's standard

**A pulled or imaged disk yields the five credentials and nothing from the volume.** The consequence
is five revocations from the laptop, each complete, followed by re-authenticating a rebuilt or
recovered node. It is a nuisance with a written procedure (§Consequences), not a compromise of
anything the owner cannot take back.

**A running machine is not protected**, by this ADR or by ADR-037. Whoever has the running machine has
the running services and, if the volume is unlocked, the volume. This ADR does not pretend otherwise.

**The USB-boot path on the same machine is not protected.** No BIOS password (Phase 18 handover, open
item 5) means a USB stick and a minute yields root on the installed system — the same path Phase 18.1
uses legitimately for its rescue shell. That yields the five credentials as above. It does **not**
yield the volume, because of §3.

**What is protected is small and worth naming precisely:** the content the whole exercise is for — the
knowledge, the projects, the private repositories — is not exposed by any of the credentials that
are. The boundary ADR-037 §5 draws between *what always works* and *what waits for unlock* is also the
boundary between *revocable* and *the thing itself*, and that is not an accident.

### 5. A BIOS password is complementary, and belongs to Phase 13

It would raise the cost of the USB-boot path without protecting a pulled disk, and it costs a
firmware visit. It narrows this risk; it does not close it, and nothing in this ADR depends on it. The
Phase 18 handover already routes it to Phase 13; this ADR does not pull it forward and does not
reject it.

## Alternatives considered

**Encrypt root, via reinstall.** The cleanest end state and a passphrase at every boot, which is the
unattended-recovery cost ADR-037 §2 rejected. Rejected here for the same reason, and because it costs
a reinstall of a working machine to protect five revocable credentials.

**Move all credentials into the volume.** Rejected: §2. The node comes back silent, or does not come
back on the network at all.

**Move only the OAuth pair into the volume.** Possible, and the most defensible partial move.
Rejected *for now* — boot ordering for `homelab-model-helper`, and it pre-empts Phase 23.3's decision
about who holds model credentials. Named as the likeliest change on revisit.

**Move `/home/aleix` into the volume.** ADR-032's alternative E already noted the boot-ordering
problem for the model helper; it also puts the admin account's shell configuration behind an unlock,
which makes recovering the machine harder at exactly the moment recovery is needed. Rejected.

**Encrypt the bot token at rest with `systemd-creds --with-key=tpm2`, via `LoadCredentialEncrypted=`.**
The most interesting alternative, recorded so it is not re-derived. systemd can store the token
encrypted, sealed to the machine's TPM, and decrypt it at unit start with no human — unattended boot
survives. What it protects: a disk pulled and read elsewhere (the TPM is not there to unseal). What it
does not: a USB boot on the same machine, which has the same TPM. It reintroduces a TPM dependency
ADR-037 §3 removed from the design, and the SHA-1 PCR bank makes any PCR-bound variant weak. **It is
the cheapest narrowing available for the one credential that matters most, and it is handed to Phase
13 as a candidate**, not adopted here — it protects against the least likely path in the owner's
threat model and adds a firmware dependency to the component whose whole value is that it always
works.

**A BIOS password now.** §5. Complementary; Phase 13's.

## Consequences

**Accepted:** physical possession of the SSD, or a USB boot of the machine, yields five revocable
credentials. Not the volume.

**Newly required — a loss procedure**, written here so it exists before it is needed. If the machine
or its disk is lost or leaves the owner's control:

1. Tailscale admin console → remove the node `homelab`.
2. `@BotFather` → `/revoke` the bot's token.
3. Sign out the node's sessions at claude.ai and chatgpt.com.
4. Change the Wi-Fi passphrase on the router.
5. Treat the volume as **intact**: its passphrase was never on the machine. Change it anyway if the
   header backup's whereabouts are in any doubt (a header plus an old passphrase opens a volume).

Five steps, from the laptop, in minutes. The procedure is the reason the risk is acceptable.

**Constrained:** §3. No key material for the volume on root, ever. The Phase 18.1 brief's §9 carries
this as an operating rule; this ADR is where it is decided.

**Constrained:** ADR-037 §7 still holds — root holds no knowledge, project content or private
repository. This ADR is about *credentials*, and does not widen what root may hold.

**Easier:** Phase 12 can build the recovery notification on a bot that always starts. Phase 18.1's
power-cut test can pass as written. The Phase 18 handover's item *"whether `/home/aleix` and the two
OAuth credentials are encrypted"* has a plain answer every later phase can rely on: **no, and by
decision.**

**Harder, in one place:** anyone extending the bot (ADR-023) or adding a root-resident service must
keep asking whether the credential they are adding is *revocable* — the property this ADR leans on. A
non-revocable secret on root would not be covered by this acceptance and would need its own decision.

**Deferred:** the OAuth pair's home (Phase 23.3, with ADR-034 §13); the BIOS password and
`systemd-creds` narrowing (Phase 13); root encryption (with a reinstall, if one ever happens for
another reason — at which point it is nearly free, and this ADR should be revisited on the spot).

## Validation / revisit trigger

**The check that this decision is holding**, run at any phase close:

1. `sudo cryptsetup luksDump /dev/ubuntu-vg/data` shows only passphrase keyslots — no token,
   no TPM2 token, no keyfile-shaped slot — and `/etc/crypttab`'s key field is `none`.
2. `sudo grep -rlE '^[^#]*(key-file|keyfile)' /etc/crypttab /etc/systemd/system /usr/local/sbin`
   on the node returns nothing. *(Corrected 2026-09-13: the original pattern without the
   comment guard matched its own explanation in `homelab-watchdog.sh` line 71 — a false positive
   found by Phase 13 S1.)*
3. Every credential on root is in the table above; a new one is added to the table with its revocation
   path, or this ADR is reopened. The inventory that decides it: `find /etc /root /home /var/lib/tailscale /usr/local -xdev -type f \( -name '*.pem' -o -name '*.key' -o -name 'id_*' -o -name '*token*' -o -name '*secret*' -o -name '*.credentials*' -o -name 'auth.json' \)` — anything credential-shaped not in the table is a finding.

Both scripts that run these live in the repository: `scripts/server/security-audit.sh` blocks A and I.

**Re-run 2026-09-12/13 (Phase 13):** check 1 **PASS** (keyslots 0 and 1, argon2id, `Tokens:` empty,
crypttab `none`); check 2 **PASS** with the corrected pattern (the old one hit the comment); check 3
**FAILED as written** — the GitHub key was on root and not in the table — and **passes now** that the
sixth row exists. Nothing on root can open the volume: unchanged, re-verified, and the `systemd-creds`
seal below is of the *bot token*, not the LUKS key — the TPM still has no part in the volume.

**Revisit if:**

1. **The machine leaves the home** — ADR-032's trigger 3, unchanged. The threat model in §Context no
   longer describes it.
2. **A credential that is not revocable, or that could open the volume, lands on root.** §3 says this
   must not happen; if a phase finds it needs to, that is the trigger, not a tuning.
3. ~~**Phase 13 sets a BIOS password or adopts `systemd-creds` for the token.**~~ **Fired, both halves,
   2026-09-13.** The acceptance stands; §4's consequences narrow as the Amendment states.
4. **The harness moves model access into the volume** (Phase 23.3 / ADR-034 §13). The OAuth pair's
   reasons for staying on root weaken to one — revocability — and moving them should be reconsidered.
5. **A reinstall happens for any other reason.** Root encryption is then a checkbox in the installer
   rather than a project, and ADR-037 §2's cost argument should be re-run with that price.
6. **The owner's threat model changes** — the content in the volume, or what root's services can do,
   changes character enough that *"revocable in minutes"* stops being a sufficient description of the
   downside.

## Amendment — Phase 13, 2026-09-13

Trigger 3 fired twice in one phase. What each control narrows, stated so nobody later reads
"TPM-bound" as "protected from physical access":

**The sealed token narrows the pulled-disk threat only.** `token.cred` is
`systemd-creds encrypt --with-key=tpm2 --tpm2-pcrs=""`: sealed to this machine's TPM2 and bound to
**no PCRs**. A disk pulled and read elsewhere yields a blob without the TPM to unseal it. **A USB
boot on the same machine still unseals it** — same TPM, no PCR policy — and that is by design: PCR 7
(Secure Boot policy) would add nothing against either threat (a signed rescue USB leaves PCR 7 as
it is) and would turn a firmware update or a Secure Boot toggle into a silent bot, the failure mode
§2 exists to prevent. The host key is not mixed in (`auto` would), because it lives on the pulled
disk. Proved: the bot, the notifier and the watchdog all loaded the sealed credential across a real
reboot and a cord-pull power-cycle with no hand on the box; the watchdog reported the locked volume
both times. **The watchdog was found to load the token only by the S1 audit** — the brief said "bot
and notifier"; sealing those two alone would have left the recovery notice reading a file that no
longer existed, on the first unattended reboot after a power cut.

**The BIOS supervisor password narrows the USB-boot threat.** Setup now asks for it; the boot order
is locked to the internal disk (`BootOrder 0001,0004,0005,0000`); PXE is off (the two network entries
are gone); Secure Boot stays on as found; **no power-on password** — the box booted unattended
through a real power-cycle afterwards. It does not protect a pulled disk. The password is in the
owner's password manager and nowhere in this repository or on the node.

**Complementary, and which does which:** TPM seal → pulled disk. BIOS password → same-machine USB
boot. Neither protects the running machine (§4, unchanged). The other four credentials on root are
where they were; the two OAuth files are also no longer visible to the model helper's neighbour,
`~/.ssh` (`InaccessiblePaths`, Phase 13 §6.12), which is the sixth row's own narrowing.

**Failure mode added, and its rollback:** a TPM state change (firmware update that clears it, a
board swap, "clear TPM" in setup) makes `token.cred` unreadable and the bot silent at the next boot.
Rollback: `p13-s3.sh creds-undo` restores the plaintext from the sealed copy while this TPM still
unseals it; otherwise the plaintext comes from the password manager by editor, and the same script
re-seals. The `.cred` in the backup archive is useless off this TPM; **the password manager is the
real backup of the token** (Phase 14 restore runbook).

**Loss procedure (§Consequences) — one step changes:** step 2 stays `@BotFather → /revoke`; the
replacement token is sealed with `p13-s3.sh creds-encrypt`, never written to `token` in plaintext
except transiently on the way in.

