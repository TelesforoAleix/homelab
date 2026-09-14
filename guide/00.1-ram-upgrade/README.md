# Phase 00.1 — Thirty-Two Gigabytes

## What we are trying to achieve

Take the reference node from one 8 GB module to 32 GB, and — this is the part that makes it a
phase rather than a chore — **prove** the result on Linux before a single document says "32 GB".
A machine that boots after a memory change has told you almost nothing. The questions that matter
are: does the firmware see both modules, in both channels, at the speed you expect; does the kernel
agree; and does the memory hold a pattern for two hours without a single bit going wrong.

## Why 32 GB and not 16

The earlier plan said 16 GB — add one 8 GB module to the free slot — and said, sensibly, that the
upgrade should follow measured pressure rather than a round number. At the time of this upgrade the
node used under 1 GiB of its 7.1. There was no pressure.

What decided it was the shape of the machine, not the shape of the workload. The M700 Tiny has two
SO-DIMM slots, so 32 GB is the ceiling, and any step short of it means a *second* trip into a
headless box that lives in a cupboard: opening it, moving the drive bracket, and this time throwing
a module away. Doing it once, to the ceiling, costs 700 DKK. Doing it twice costs 700 DKK plus an
afternoon plus a spare 8 GB module you can no longer use. The rule about round numbers is still a
good rule; it just lost to a better-quantified one here. Both are written down.

## What the numbers on the box mean

The modules are rated **DDR4-2666**. The node runs them at **2133**. This is not a fault and not a
BIOS setting to hunt for: the i5-6600T's memory controller tops out at DDR4-2133, and a faster JEDEC
module simply runs at the controller's speed. The 2016 BIOS reports `Speed: 2133 MT/s` — the running
speed — rather than the module's rated maximum, so the 2666 appears nowhere except the label. If you
buy 2133-rated modules instead, nothing changes; they were just harder to find.

**Dual-channel** is what you get when both channels have a module; the controller interleaves
across them for roughly double the bandwidth. Nothing on Linux prints "dual-channel". What
`dmidecode` prints is the slot each module sits in — `ChannelA-DIMM0` and `ChannelB-DIMM0` — and
two identical modules in those two slots is the definition.

## Opening the Tiny

From the Lenovo Hardware Maintenance Manual (M700/M900/M900x Tiny, chapter 9). The memory slots
are **under the 2.5-inch storage-drive bracket**, so the SSD comes out on its bracket first.

1. Shut down cleanly (`sudo systemctl poweroff`), unplug the power adapter and every cable, and
   **wait several minutes** — the manual says so, and the heat sink agrees.
2. Lay it flat, cover up. Touch bare chassis metal before touching anything else.
3. One screw at the rear secures the cover. Remove it; slide the cover **forward** a little; lift.
4. If a front Wi-Fi antenna cable runs to the wireless card and is in the way of the bracket,
   unclip it at the card and remember which connector. **This cable is the node's only network
   path.** Forgetting it on the way back means a machine that boots and cannot be reached.
5. One screw secures the drive bracket. Remove it; slide the bracket; lift it out with the SSD on it.
6. Open the retaining clips on the old module; it springs up at an angle; pull it out by the edges.
7. Each new module goes in **notched end first, at an angle**, then presses down until both clips
   snap. It should not move. Both slots.
8. Bracket back: align its three slots with the standoffs, slide until the screw hole lines up
   *and the SSD seats on its SATA connector*. Screw. Antenna cable back on.
9. Cover on. This is the step that will bite: the cover is a **slide-and-hook** fit. Set it down a
   full centimetre *forward* of closed, flat, with the rear lip *under* the rear panel edge, then
   slide it back until it stops flush. Set down too far back it jams a few millimetres short — on
   this build, 4 mm, one side higher than the other. Do not force it; lift, move forward, repeat.

The old module goes in an anti-static bag as a spare. It is the rollback.

## Proving it

Over SSH, after the boot:

```bash
free -h                       # total ~30 GiB (32 GB decimal ≈ 29.8 GiB binary)
grep MemTotal /proc/meminfo   # 31701556 kB on the reference node
sudo dmidecode -t 16          # Maximum Capacity: 32 GB, Number Of Devices: 2
sudo dmidecode -t 17          # one block per slot: Size, Locator, Speed, Configured Memory Speed,
                              # Manufacturer, Part Number, Rank
journalctl -b -k | grep -i -E 'mce|edac|memory error'   # nothing beyond "EDAC ie31200: No ECC support"
systemctl is-system-running; systemctl --failed          # running; empty
```

`free` says 30, not 32, for the usual reason: the module is 32 × 10⁹ bytes and the kernel counts in
2³⁰, less a little the firmware reserves. `dmidecode -t 17` is the one that names the modules and
slots — read it before trusting anything else.

Then the stability test. `memtester` allocates a block, locks it into RAM so the kernel cannot page
it out, and writes and reads patterns through it — stuck addresses, random values, walking ones and
zeroes, bit flips. One loop over most of the memory:

```bash
sudo apt install -y memtester
sudo nohup memtester 20G 1 > /tmp/memtester.log 2>&1 &
```

Every test must say `ok` and the log must end in `Done.`. On the reference node one loop over
20 GiB took **2 h 07 min**. Afterwards, re-run the kernel-log check above; a memory fault under load
shows up there even if memtester's own comparison somehow missed it.

**Run it from the console, not over SSH.** On this node, locking 24 of 30 GiB made the DHCP
renewal fail, and the shared building network issues 3-minute leases — so within a lease lifetime
`systemd-networkd` removed the address and the machine was unreachable on both routes for ten
minutes until the test was killed. Nothing was wrong with the memory. The lesson is about the test:
a memory-stress test on this node *is* a network outage, and the console is the session that
survives one.

## What the watchdog said

This was the first time the node was shut down with `poweroff` rather than `reboot` since Phase 12's
watchdog existed. Its boot message read `Home Lab back up. Down ~41m, clean reboot. Data volume:
LOCKED` — "clean" because PID 1 wrote `Shutting down.` to the journal, which is the marker the
classifier looks for, and a power-off writes it too. The 41 minutes are the time the box was open.

## What was not done

- **Swap** stays at 4 GB. It has never been used; `vm.swappiness` is 10. Resizing it would be work
  without an observed need.
- **The BIOS** was not touched. Secure Boot, the boot-order lock, PXE-off and the supervisor
  password are exactly as Phase 13 left them; nothing about a memory change needs Setup.
- **The firmware update** `fwupdmgr` reports is still not applied. It is a separate decision with a
  separate risk, and bundling it into a RAM swap would have been the wrong kind of efficient.
- **The console** was not attached for the first boot, although the plan asked for it. The boot
  had nothing to say — POST halts on a memory *decrease* (code 0164), not an increase — so it
  worked. Twenty minutes later the console was needed anyway. Keep it near the machine.
