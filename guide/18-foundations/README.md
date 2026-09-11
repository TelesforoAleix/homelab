# Phase 18 — Giving the Machine a Way Back

## What we are trying to achieve

Your server should be able to die without taking anything irreplaceable with it.

That is the whole phase. It sounds like a small thing to bolt on at the end, and it
is the reason this phase exists before the interesting work rather than after it.

## The uncomfortable audit

By this point the node has accumulated a surprising amount that exists in exactly
one place:

| Thing | Where it came from | In git? |
|---|---|---|
| Two OAuth credentials | Phase 06, one interactive login each | No |
| A Telegram bot token | Phase 07, issued once by BotFather | No |
| Three allowlists | Phase 08, hand-edited per deployment | No |
| A polkit rule | Phase 08, 3.7 KB of authorisation logic | No |
| A unit file with 22 hardening directives | Phase 07 | No |
| Service account UIDs | Created implicitly at install time | No |

Phase 04 gave the *repository* an offsite copy and it felt like the backup problem
was handled. It was not. **The repository was never the part at risk.** GitHub has
your code. Nothing anywhere has your bot token.

## Start by measuring, because your instincts are wrong

The obvious move is to back up the home directory. Do that and you get this:

```console
$ du -sh ~/.codex ~/.claude
366M    /home/aleix/.codex
440K    /home/aleix/.claude
```

366 megabytes. Then look at where it actually is:

```console
$ du -sh ~/.codex/* | sort -rh | head -3
320M    /home/aleix/.codex/packages
27M     /home/aleix/.codex/plugins
18M     /home/aleix/.codex/cache
```

All three reinstall from the network. The credential in that directory is **3,924
bytes**. Excluding those three directories takes `~/.codex` from 366 MB to 236 KB
with no loss of anything you cannot get back.

**The lesson generalises:** before designing a backup, measure what is actually
irreplaceable. It is usually a tiny fraction of what looks essential, and the
difference decides whether your backup is something you can verify in seconds or
something you quietly stop running.

Our whole node came to roughly 300 KB.

## The rule that shaped everything: don't build a second way to be root

The tempting design is a cron job on the server that tars things up and pushes them
somewhere. Resist it.

A backup needs to read everything — the token, both credentials, the polkit rule.
Automating that means either a `NOPASSWD` sudoers entry or a stored key. Either one
is **a standing privilege that exists whether or not anyone is backing anything
up**, and it is exactly as powerful as root.

So this backup is **pull-based and interactive**. Your laptop reaches out, the
server asks for your password, and nothing on the server gains any capability it
did not already have:

```text
Mac  ──ssh──▶  node:  sudo tar ...
     ◀─────────       (streamed back; never written to the node's disk)
Mac: encrypt → removable media
```

You type a password once a week. That is the price of not creating a second root,
and it is cheap.

## Your filesystem metadata is part of the backup

Here is a failure that looks like success. The node's bot token:

```text
-rw-------  root root  /etc/homelab-telegram-bot/token
-rw-r-----  root homelab-bot  /etc/homelab-telegram-bot/allowlist
```

Those modes are not decoration. The service runs as `homelab-bot`, which **cannot
read the token at all** — systemd reads it as root via `LoadCredential=` and hands
the process a copy at mode 0400. Restore that file world-readable and you have
either broken the service or quietly widened who can read a credential.

Now: our backup target is a microSD card, which is exFAT, which **stores no POSIX
permissions, no ownership and no symlinks.** Copy those files onto it directly and
the metadata is simply gone.

The fix is that everything goes into a tarball and the tarball goes onto the card:

```bash
sudo tar --numeric-owner -czf archive.tar.gz /etc/homelab-telegram-bot ...
```

`--numeric-owner` matters separately. `homelab-bot` is uid 999, gid 982. A rebuilt
machine that creates accounts in a different order gives it different numbers, and
the socket's `SocketGroup=homelab-bot` stops matching. Storing numbers rather than
names means the restore is explicit about it.

## Encrypt for the machine you will restore onto

The archive holds every secret on the node, and it is going on a card that leaves
the house. It must be encrypted. The choice of tool is less obvious than it looks.

macOS offers encrypted disk images, which are excellent and one command away. They
are also **useless here**, because the machine you will be restoring onto is a
freshly installed Ubuntu server that cannot open one.

> Encrypt for the machine you will restore **onto**, not the machine you back up
> **from**.

We used [`age`](https://github.com/FiloSottile/age): one command, cross-platform,
nothing to misconfigure. With a **passphrase** rather than a key file — a key file
stored on the laptop dies with the laptop, and surviving the laptop's loss is the
entire point of an offsite copy.

Keep the passphrase in a password manager. Never on the card. A card that carries
its own key is a card with no encryption.

## A backup that has only ever been written is unvalidated

This is the part most guides skip, and it is the part that matters.

"The backup job completed successfully" is not evidence. It tells you a program ran,
not that the bytes are recoverable. So this phase ships a second script whose only
job is to disbelieve the first one:

```console
$ ./scripts/macos/verify-node-backup.sh
    ok    decrypted 312K
    ok    sha256 matches the value recorded before encryption
    ok    extracted 111 files
    ok    every compared file matches the live node in content and numeric owner
    ok    12/12 critical files present
```

It decrypts, checks the archive against a checksum recorded **before** encryption,
extracts it, and compares every file against the running server — content hash and
numeric owner, one by one.

### And then it tries to fail

Everything above said "ok". That is precisely the situation where a broken checker
is indistinguishable from a working one. So the last step corrupts a copy of the
archive by a single byte and **requires its own check to notice**:

```console
=== 5/5  Planted positive control  --  the check must fail on purpose
    ok    checksum check fires on a one-byte corruption
```

If that planted failure goes undetected, the script exits non-zero and tells you
that every "ok" above it was unsupported.

> A detector that has only ever reported "clean" is unvalidated. Make it fire on
> purpose before you trust it.

This project has recorded nine occasions where a check reported a result it could
not support. The control is there because of them.

## What we got wrong, which is the most useful part of this chapter

We wrote both scripts carefully and they were wrong four times. Every bug was found
by **running** them, not by reading them.

**1. The password prompt vanished.** The command ended in `2>/dev/null`, meant to
hide `tar`'s harmless "Removing leading /" warnings. It also discarded `sudo`'s
password prompt. The script hung, then died with no message.

The mechanism is worth knowing. When `ssh -t` allocates a pseudo-terminal, it folds
the remote command's stdout, its stderr, **and anything written to `/dev/tty`** into
a single stream. Proved rather than assumed:

```console
$ ssh -t host 'echo A; echo B >/dev/tty; echo C >&2' > file
$ cat file
A
B
C
Connection to host closed.
```

`sudo` writes its prompt to `/dev/tty`. So redirecting the output of an interactive
`ssh -t` into a file writes the password prompt into that file, where you cannot
see it.

> **Never redirect the stdout of an `ssh -t` that needs to prompt.**

The fix: the interactive step writes the archive to the server's `/dev/shm` — which
is RAM, so no unencrypted copy of your secrets ever touches the disk you are trying
to protect — and a second connection without a TTY fetches the bytes.

**2. `printf` refused a string.** A format beginning `--` is read by bash as an
option. Use `printf '%s\n' '--- heading ---'`.

**3. The verifier condemned a perfect backup.** It looked for the checksum by
finding a line ending in `node-state.tar.gz`. The manifest's own help text —
`Inspect: tar -tvzf node-state.tar.gz` — matched first, so it compared the real hash
against the word `Inspect:` and reported corruption.

**4. And then it condemned all 111 files.** GNU tar prints numeric owners as
`0/982`. BSD tar, which macOS ships, prints them as two columns: `0  982`. The
comparison matched the GNU form against BSD output, so **every ownership check
failed while every content hash passed.**

That last one is the one to remember. A checker that fails everything is as useless
as one that passes everything, and considerably more alarming. If your verifier
reports total failure, suspect the verifier first.

## The other half: should the disk be encrypted?

The node has no encryption at rest. That was decided in Phase 01 on a stated
premise — an always-on home machine holding nothing sensitive — with an explicit
promise to revisit before that stopped being true.

**The question is not "should I encrypt".** It is:

> What is encryption protecting against here, and what does it cost on this
> machine?

Full-disk encryption protects a **powered-off disk in someone else's hands**:
theft, disposal, a warranty return. It does nothing for a running machine. If your
server sits in your home and runs continuously, be honest that this is the threat
you are buying protection against.

### Check your premises before you decide

Ours were wrong, three times over, and checking took minutes.

**"The node has no console."** Phase 03 recorded the monitor as removed, and every
document repeated it. In fact:

```console
$ systemctl is-active getty@tty1
active
```

A login prompt had been running the entire time. The monitor was unplugged, not
absent. That single correction changed the decision: a passphrase typed at boot
stops being impossible and becomes a walk across a room.

**"The TPM is too old."** It was 1.2, which rules out self-unlocking. A visit to
the firmware and a switch from *Discrete TPM* to *Firmware TPM* (Intel PTT) made it
2.0, at a measured cost of 2.8 seconds of boot time.

**"`systemd-cryptenroll` says TPM2 support is not installed."** It is a *tooling*
message, not a hardware one. One missing library — and not the one the documentation
named, because Ubuntu's 64-bit `time_t` transition renamed it `libtss2-rc0t64`.
Installing `tpm2-tools` pulls it in:

```console
$ systemd-cryptenroll --tpm2-device=list
PATH        DEVICE      DRIVER
/dev/tpmrm0 MSFT0101:00 tpm_crb
```

### Then test the thing rather than reading about it

Whether the TPM can actually seal a disk key is answerable in ninety seconds,
without touching your real disk, using a throwaway volume in RAM:

```bash
sudo dd if=/dev/zero of=/dev/shm/luks-test.img bs=1M count=32
sudo cryptsetup luksFormat --batch-mode /dev/shm/luks-test.img
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/shm/luks-test.img
sudo rm -f /dev/shm/luks-test.img
```

Ours answered clearly, and not the way we expected:

```text
TPM2 device lacks support for SHA256 PCR bank, but SHA1 bank is supported and
SHA1 PCRs are valid, falling back to SHA1 bank. This reduces the security level
substantially.
New TPM2 token enrolled as key slot 1.
```

It works — sealed to SHA-1, which systemd itself flags as substantially weaker.
And the SHA-256 bank cannot be fixed from Linux:

```text
ERROR: Esys_PCR_Allocate(0x9A2) - tpm:session(1):authorization failure
```

`TPM2_PCR_Allocate` is a platform-hierarchy command, and UEFI firmware sets a
random platform password and throws it away before booting you — specifically so a
running OS cannot reconfigure the TPM under a measured boot. **That is the firmware
working correctly.** Allocating the bank means visiting the BIOS.

### The decision, and why "no change" is still a decision

We reaffirmed the existing choice: the node stays unencrypted. Not by default —
**by decision**, recorded in ADR-032, with the previously-implicit premise turned
into an enforceable rule:

> Until this is revisited and encryption is executed, the node may not hold the
> knowledge base, any project repository, any private repository, or personal
> documents.

The reasoning: the content that made encryption urgent had been deferred to a later
phase, so the node was not about to receive anything private; every encrypting
option required reinstalling the machine *that day*; and the strongest option
(passphrase at boot) was named as the one to choose when the gate lifts.

> Reaffirming a decision is a decision. **Silently leaving it is not.**

Write down what you chose *and* what it now forbids. An unwritten premise cannot be
enforced and will be forgotten by whoever arrives next — including you.

## How to verify it worked

```bash
# The backup exists and is real
ls -l "/Volumes/SD Card/homelab-backup/$(date +%F)/"
head -c 22 "/Volumes/SD Card/homelab-backup/$(date +%F)/node-state.tar.gz.age"
# → age-encryption.org/v1

# It matches the live machine, and the checker can fail
./scripts/macos/verify-node-backup.sh
# → PASS, including the planted corruption

# Ownership survived the round trip
grep -E "token|allowlist" "/Volumes/SD Card/homelab-backup/$(date +%F)/MANIFEST.txt"
# → -rw-------  0 0      0    47 ... token       uid 0,  gid 0    (root:root)
# → -rw-r-----  0 0    982   851 ... allowlist   uid 0,  gid 982  (root:homelab-bot)
#     columns are: mode, links, uid, gid, size
```

## What can go wrong

| Symptom | Cause |
|---|---|
| Script dies silently at the first step | A `\|\| fail` is missing and `set -e` exited without a message |
| No password prompt ever appears | You redirected the stdout of an `ssh -t` — the prompt went into your output file |
| Verifier reports every file wrong | Suspect the verifier. GNU and BSD `tar` format numeric owners differently |
| `tpm2_pcrallocate` fails with `0x9A2` | Expected. Platform authority is held by firmware; use the BIOS |
| Restored service will not start | The service account was recreated with a different uid/gid |
| Archive decrypts but is empty | A glob in the path list matched nothing and nobody checked the entry count |

## What this phase deliberately did not do

- **No firewall, `fail2ban`, Tailscale ACLs or rootless Docker.** Those are
  hardening; this phase is *recoverability*. Different goal, different phase.
- **No automation of the backup.** Manual by design, so it never becomes a standing
  root-equivalent privilege.
- **No Tailscale state or SSH host keys in the backup.** Re-authenticating a rebuilt
  machine is cleaner than restoring a dead machine's identity, and regenerating host
  keys is more honest than suppressing the warning that the machine changed.

## The honest loose end

**No bare-metal restore has been performed.**

The archive has been decrypted, extracted, and compared against the running server
file by file. That proves the bytes are good. It does **not** prove that a wiped
machine rebuilt from this archive boots and runs — and those are different claims
that fail for different reasons.

The restore procedure is written down. It has never been executed. Until it is, the
right description of this backup is "verified", not "proven", and the two are not
the same word by accident.

If you follow this guide, schedule the real thing: wipe a spare disk, rebuild from
the archive, and find out what the procedure forgot. It will have forgotten
something. Better to learn that on a Sunday afternoon than on the day you need it.
