# Phase 18.1 — Locking Half the Disk

## What we are trying to achieve

Split the disk in two. Root stays as it is — plain, unencrypted, working the instant the machine
boots. Everything the node is actually *for* — the knowledge base, the projects, the private
repositories — moves into a second volume that is encrypted, and that volume waits for a human to
unlock it after every boot.

That trade only makes sense once you see why *both halves* of it are deliberate.

## Contents, box, shelf

The three layers this phase touches nest inside each other, and mixing them up is how a filesystem
dies:

- The **filesystem** is the contents — the files, the directories, the bytes you actually care about.
- The **logical volume (LV)** is the box the filesystem sits in.
- The **volume group (VG)** is the shelf the boxes sit on.

You can make a box bigger without touching what's in it — there's just more empty space at the end.
You can never make a box *smaller* than what's already in it without cutting the contents off. That
asymmetry is the entire safety argument for this phase, and it is why the order below is not a style
preference:

```
e2fsck -f  →  shrink the filesystem (below the target)  →  shrink the box (to the target)
           →  grow the filesystem to fill the box        →  e2fsck -f
```

Shrink the contents *first*, and shrink them *past* the target before cutting the box down to size.
That margin exists because a human types two numbers and might get one wrong — with the filesystem
already smaller than the final box, a final "fill whatever's there" resize can't overshoot.

## Why one number beats two: `lvreduce --resizefs`

You could type the shrink as three separate commands — shrink the filesystem, shrink the box, grow
the filesystem back to fill it. That's the *fallback* in the runbook, and it exists so you can see
what the tool is doing. But it asks a human to keep two sizes consistent across three commands typed
at a rescue-shell prompt, on the single most dangerous operation this project has attempted.

`lvreduce --resizefs -L 64G ubuntu-vg/ubuntu-lv` does the same three steps as one command with one
number. It computes the filesystem's target size *from* the LV size, so the two numbers structurally
cannot disagree. Its failure modes are safe: if the filesystem resize fails, the box is never touched;
if the box resize fails afterward, the filesystem is simply smaller than its box, which costs nothing.
The one thing it does not protect you from is a box specified *below* what the filesystem already
occupies going in — which is why the runbook checks that inequality by arithmetic (`filesystem bytes
≤ LV bytes`) before ever rebooting, rather than trusting the tool's own backstop.

## The sizing decision: leave room to have been wrong

The numbers: root gets **64 GiB** (was the whole 235 GiB disk), the new encrypted volume gets
**128 GiB**, and **43.42 GiB is left unallocated** in the volume group.

Root's 64 GiB is seven times what it uses today and holds nothing that's expected to grow — this
project's decision is that everything with real growth potential lives in the encrypted volume, not
on root. The volume's 128 GiB is an order of magnitude past any credible near-term projection.

The interesting number is the 43 GiB left *empty*. Growing either side later is an online operation —
minutes, no reboot, no console. **Shrinking either side is this phase again** — a rescue boot, a
monitor, the dangerous step. Handing out every free byte today is a one-way door in the expensive
direction: whichever side turns out not to need it, getting the space back means repeating the
riskiest thing this project has done. Free space costs nothing to hold and everything to create after
the fact, so the reserve is bought while it's cheap. It also happens to be the first free space this
project's volume group has ever had — without it, nothing can ever be snapshotted before a risky
change, which is a real cost of allocating 100% of a disk on day one.

## What a LUKS2 header is, and why it leaves the machine once

Encrypting the volume with LUKS2 doesn't just scramble the bytes with your passphrase — it writes a
**header** at the start of the device that holds the encryption parameters and up to 32 "keyslots,"
each one a different way to unlock the same underlying key. Your passphrase doesn't encrypt the data
directly; it unlocks a keyslot, and the keyslot holds the real key.

That header is a single point of failure independent of the passphrase: damage it, and the volume is
gone *even though you still remember the passphrase perfectly*, because there's nothing left to unlock
into. So a copy of the header is taken once, right after the volume is created, encrypted, and stored
somewhere that isn't this disk. It is only ever re-taken if a keyslot changes later. This copy is
treated as secret material in its own right — a header plus *any* passphrase that was ever valid for
it (even one you've since changed) can still open the volume, so it lives alongside the other things
this project already treats as secrets, and nowhere else.

## `noauto`: the two words standing between this and a bricked boot

Ubuntu tracks encrypted volumes in `/etc/crypttab` and their mountpoints in `/etc/fstab`. Left to
their defaults, both files make boot **wait** for the volume: crypttab prompts for a passphrase at the
console, fstab then tries to mount what crypttab unlocked. That's fine on a desktop with someone
sitting in front of it. It is fatal on a machine that reboots itself after a power cut with nobody
there to type anything — the boot simply hangs at a passphrase prompt forever, on a display nobody is
watching.

`noauto` in **both** files is what stops that: it tells systemd not to add the device or the mount to
the units that run automatically at boot. The volume isn't unlocked or mounted until something asks it
to be — in this project's case, a human running `data-volume.sh unlock` over SSH once the node is
already up and reachable. Miss `noauto` in *either* file and the other one drags the boot into waiting
anyway, which is why the runbook checks both, not just one.

## `Condition`, not `Assert`: why "locked" reads as normal, not broken

Once the volume can be locked at boot, every service that depends on it needs to behave sensibly when
it isn't there yet. systemd gives you two ways to express a dependency's precondition, and they
produce very different outcomes:

- An **`Assert`** that fails marks the unit **failed**. `systemctl --failed` lists it, and
  `systemctl is-system-running` reports `degraded`. That's the right shape for something that's
  actually broken.
- A **`Condition`** that fails **skips** the unit instead — it goes `inactive`, with the reason
  recorded in the journal and in `systemctl status`, and nothing counts it as a failure.

Every unit in this phase uses `ConditionPathIsMountPoint=/srv/homelab`. The result: a node that boots
with the volume locked reports `running`, zero failed units, exactly as if nothing were unusual —
because, by this project's own decision, nothing is. "Degraded until unlocked" is the *expected*
state after any unattended reboot, and the tooling needs to agree with that framing or every ordinary
power cut looks like an incident.

One sharp edge worth knowing: `systemctl start` of a *skipped* unit still returns exit code **0**.
Anything that scripts against these units — a monitoring check, a status script — has to ask
`systemctl is-active`, never trust `start`'s exit code, or it will report "started fine" about a unit
that never actually ran.

## The power-cut test: what "unattended" actually has to mean

None of the above is worth much until it's tested the way it will actually fail — by pulling power,
not by asking politely. The test here: unplug the machine at the wall, wait, plug it back in, and
touch nothing. No keyboard, no power button.

For that to count as passing, several things all have to be true at once: the node boots itself back
up without anyone flipping a switch (validated in an earlier phase); it becomes reachable over the
network unattended; the volume comes back **locked** because nothing auto-unlocks it; every unit that
depends on the volume is skipped, not failed; and — critically — **something on the machine can still
tell you it's back**, because a node that boots to a locked, silent state you can't distinguish from a
node that never came back at all is not meaningfully "recovered." That last property is why the
service that answers status queries lives on the *unencrypted* side of this split rather than inside
the volume it reports on.

## Why root stays unencrypted, and what that does and doesn't protect

The obvious "more secure" move is to encrypt the whole disk. This project doesn't, on purpose.
Encrypting root means a passphrase prompt at *every* boot, which brings back exactly the problem
`noauto` exists to avoid — an unattended reboot that hangs waiting for someone who isn't there. Once
you need the machine to recover from a power cut with nobody home, root encryption and unattended
recovery are mutually exclusive, and this project chose recovery.

The consequence, named rather than glossed over: a handful of credentials — two AI service logins, a
messaging bot's token, the Wi-Fi password — stay in plaintext on that unencrypted root. What makes
this an *accepted* risk rather than a hole is that every one of those credentials is **revocable from
a laptop in minutes** and **none of them can open the encrypted volume** — the volume's key lives only
in a passphrase that has never existed anywhere on the machine itself. So someone who gets the disk
gets those five things and nothing else; a five-step checklist undoes all of it, and the actual
content — the knowledge base, the projects — was never on that side of the line to begin with.

What this setup does **not** protect against: a machine that's running and already unlocked, or a
machine physically taken while it's on. It protects data **at rest** — a powered-off disk pulled from
a dead or disposed-of machine. That is a narrower promise than "encrypted," and it's worth being able
to say precisely, rather than assuming encryption means more than it does.

## How to verify it worked

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS         # the volume, sized as above
sudo data-volume.sh status                          # unprivileged: mapper, mount, target, units
sudo cryptsetup status homelab-data                 # LUKS2, discards enabled
systemctl list-dependencies cryptsetup.target \
  local-fs.target multi-user.target | grep -c homelab-data   # all three: 0
```

The real test isn't any single command, though — it's whether the machine still answers after you
pull its power cord for a minute. If you haven't done that, you haven't tested this phase.

## What this phase deliberately did not do

- **No TPM.** A TPM could unlock the volume automatically at boot with no human involved, which
  sounds better than typing a passphrase over SSH — but on this hardware it only binds to a weak PCR
  bank, and it protects against a narrower threat (the disk being physically removed) than the human
  unlock does. Removing it removed a question rather than answering it weakly.
- **No BIOS password.** Physical possession of the machine still yields a USB boot and, from there,
  the same five root credentials this phase already accepts as revocable. A BIOS password raises the
  cost of that path; it doesn't close it, and it's handed to a later hardening phase rather than
  bundled in here.
- **Nothing moved into the volume yet.** It exists, empty, ready. Moving the actual knowledge base and
  projects onto it is the next phase's job, deliberately kept separate because an offline disk-shrink
  and a repository migration are different kinds of risk.

## The honest loose end

This phase proves the *archive* restores byte-for-byte. It has never proven that a wiped machine,
rebuilt from nothing but that archive, actually boots back into a working node. That's a stronger
claim than this phase makes, and it's written down as unproven rather than assumed — a later phase's
job to actually attempt.
