# 01 — Ubuntu Server

## Goal

Turn the reference node — a used Lenovo ThinkCentre M700 Tiny still running Windows — into a
headless Ubuntu Server that starts on its own after a power cut, joins the network over Wi-Fi
without anyone touching it, and can be reached over SSH from the MacBook.

By the end, the monitor and keyboard come off and never go back on.

## Why this matters

Four ideas do most of the work in this phase.

**A server installation is defined by what it leaves out.** Ubuntu Server ships no desktop, no
display manager, no browser. On an 8 GB machine that is not a small saving, but the real benefit is
narrower: fewer installed packages means fewer things listening on the network, fewer things to
update, and fewer moving parts to reason about when something breaks. Everything you interact with
will be a command, which is exactly the skill Phase 02 goes on to build.

**LTS is a promise about time, not about features.** Ubuntu publishes a Long Term Support release
every two years with five years of free security updates. A normal release gets nine months. For a
machine meant to sit in a corner and stay useful, the support window matters far more than having
newer package versions, because the alternative to a long support window is reinstalling the
foundation of your lab every year.

**A checksum catches accidents; a signature catches attackers.** Comparing the SHA256 of a
downloaded ISO against the published value proves the file you have is the file the project
documented. It does not prove the file came from Canonical — anyone who could serve you a modified
ISO could serve a matching checksum alongside it. Verifying the GPG signature on the checksum file
is what closes that gap. Both are shown below; understanding the difference is the point.

**Headless changes what "secure" means.** Full-disk encryption is normally the obvious choice. On a
machine with no keyboard attached it is close to the opposite: every boot would stop and wait for a
passphrase nobody is there to type, so a power cut would take the whole lab offline until someone
physically visited it. This phase chooses availability over encryption at rest, deliberately and
with the cost written down. See ADR-015.

## Reference-build choice

| Decision | Choice | Recorded in |
|---|---|---|
| Operating system | *Tested with* Ubuntu Server 26.04.1 LTS (amd64) | ADR-014 |
| Support horizon | Standard support to April 2031 | ADR-014 |
| Disk layout | Whole disk, guided LVM, **no** full-disk encryption | ADR-015 |
| Network link | Wi-Fi initially; Ethernet preferable where practical | ADR-016 |
| Remote access | `openssh-server` installed now, hardened in Phase 03 | Phase 01 brief §7 |
| Windows | Removed entirely | ADR-003 |

The version choice deserves one note. The usual reason to avoid the newest LTS is that third-party
package repositories take months to publish for a new codename — which would have blocked Tailscale
in Phase 03 and Docker in Phase 05. Both were checked before committing: Docker's install
documentation lists "Ubuntu Resolute 26.04 (LTS)" as supported, and Tailscale's package repository
publishes a `resolute` distribution. The risk was measured, not assumed. ADR-014 records the sources.

> **"Tested with" is not "Requires".** This project's version policy (`PROJECT.md` §9) separates the
> version the reference build actually used from a hard compatibility requirement. The only real
> requirement here is **Ubuntu Server LTS, amd64, still in standard support**. 26.04.1 is what this
> guide was written and tested against; the exact ISO and checksum are pinned so the reference build
> can be reproduced exactly, not to constrain you. If you prefer 24.04 LTS, that is a supported
> choice — expect small differences in installer wording and package versions, and please record any
> you hit in your own build log.

> **On Wi-Fi.** The reference build uses Wi-Fi because no cable reaches the machine's location — not
> because it is the better choice. For a stationary always-on server, **wired Ethernet is preferable
> wherever it is practical**: nothing to associate at boot, no passphrase on disk, and far more
> predictable reconnection. If you can run a cable, do. See ADR-016.

## Alternatives

- **Ubuntu 24.04 LTS instead of 26.04.** More mature, and a much larger pool of blog posts and forum
  answers when something goes wrong — a real advantage while learning. Costs two years of support
  life. A defensible choice; ADR-014 explains why the longer runway won.
- **Ethernet instead of Wi-Fi.** Better in every technical respect and the recommended choice for a
  stationary server wherever a cable is practical. Rejected here only because no cable reaches the
  machine's location — a physical constraint, not a technical judgement. Moving to Ethernet later is
  an improvement rather than a deviation, and needs no new decision record. A powerline or MoCA
  adapter is a realistic middle path if running cable is impossible.
- **Full-disk encryption.** Right for a laptop, wrong for an unattended headless server, unless you
  add TPM-backed unlock or an initramfs SSH unlock — both worth revisiting in Phase 13, once remote
  access actually exists.
- **Automated installation** (autoinstall / cloud-init). This is the reproducible way to install a
  fleet. It is deliberately *not* used here: per ADR-012 the project performs a process manually
  while that teaches something, and automates once the mechanism is understood. Phase 14 revisits it.

## Prerequisites

- The M700, its power supply, and a temporary monitor, keyboard and HDMI/DisplayPort cable.
- A USB stick of **at least 4 GB** that you are willing to erase completely.
- The MacBook, on the same Wi-Fi network the server will join.
- The Wi-Fi SSID and passphrase.
- Access to the router's admin page (for a DHCP reservation later).

---

## Implementation

### Part A — Record the hardware before erasing Windows

Windows is about to be destroyed, and with it the easiest way to read certain hardware facts. Two of
them matter to this project:

1. **The memory module layout.** `docs/reference/hardware.md` records this as an open unknown: 8 GB
   could be one module (leaving a free slot for a cheap upgrade) or two (meaning any upgrade means
   discarding both). This single fact decides the upgrade path.
2. **The wireless adapter model.** ADR-016 makes Wi-Fi the only network link, so if the Ubuntu
   installer cannot see the card, the install stalls with no network. Knowing the chipset now lets
   you prepare a fallback — a USB Wi-Fi dongle, or a temporary cable — instead of discovering the
   problem halfway through.

Boot Windows and open PowerShell:

```powershell
# Memory: one row per physical module. Two rows means both slots are occupied.
Get-CimInstance Win32_PhysicalMemory |
  Select-Object BankLabel, DeviceLocator, Capacity, Speed, Manufacturer, PartNumber

# Wireless adapter model and driver
Get-NetAdapter | Where-Object { $_.Name -match 'Wi-Fi|Wireless' } |
  Select-Object Name, InterfaceDescription, LinkSpeed

# Storage device model and size
Get-PhysicalDisk | Select-Object FriendlyName, MediaType, Size

# CPU confirmation
Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors
```

While the machine is open and running, also check the physical things a command cannot tell you:
that all USB ports work, that the DisplayPort output works, and how loud the fan is under load.

Write the results into `docs/reference/hardware.md`. Two of these are recoverable later if you skip
this step — `sudo dmidecode -t memory` reads the module layout from Linux, and `lspci -nnk` reads
the wireless chipset — so this is a convenience step, not an irreversible gate. It is still much
cheaper to do now.

#### What the reference build found

Performed 2026-09-08 on the M700, from Windows Task Manager:

| Item | Result |
|---|---|
| CPU | Intel Core i5-6600T @ 2.70 GHz, 4 cores / 4 logical processors |
| RAM | 8 GB DDR4 SO-DIMM @ 2133 MHz |
| **RAM slots** | **1 of 2 used — a single 8 GB module, one slot free** |
| Storage | Samsung `MZ7TY256HDHP-000L7` SATA SSD, 256 GB nominal / ~239 GiB usable |
| **Wi-Fi** | **Intel Dual Band Wireless-AC 8260, 802.11ac** |
| CPU virtualization | **Disabled** in firmware |

Three of these changed something:

- **The free RAM slot** settles the upgrade path: adding one 8 GB module gives 16 GB, and 8+16 = 24 GB
  stays available if pricing ever favours it. Nothing needs upgrading for this phase — 8 GB is far
  above Ubuntu Server's 1.5 GB minimum, and upgrades should follow observed pressure from real
  services, not round numbers.
- **The Wi-Fi adapter is a mainstream Intel part.** The AC 8260 uses the in-tree `iwlwifi` driver,
  and its `iwlwifi-8000C` firmware ships in Ubuntu's `linux-firmware` package, which is on the
  installer image. The fallback section below is therefore unlikely to be needed here — though it
  stays documented, because "should work" is not "did work".
- **Virtualization was found disabled**, which added a firmware task to Part D.

If the 256 GB drive reporting ~239 GB looks like missing space: it is not. Manufacturers count
decimal gigabytes (10⁹ bytes), operating systems report binary gibibytes (2³⁰). 256 × 10⁹ ≈ 238.4 GiB.

#### Part A completion checklist

Part A is the remaining Phase 00 hardware validation, carried out here because it has to happen
before the disk is erased. There is no separate hardware phase; **completing this checklist closes
the Phase 00 prerequisite.**

- [x] RAM module layout recorded (how many slots occupied, and each module's capacity)
- [x] Storage device model and size recorded
- [x] **Wireless adapter model and driver recorded** — the single most important item, because it
      determines whether the installer can bring up a network at all
- [x] CPU model and core count confirmed against `docs/reference/hardware.md`
- [x] Essential hardware validated: USB ports, video output, fan noise under load
- [x] Results written into `docs/reference/hardware.md`

*(All items complete on the reference build as of 2026-09-08. **This closed the Phase 00
prerequisite.**)*

Once these are recorded, update `ROADMAP.md` and `docs/reference/project-state.md` to mark the
Phase 00 hardware prerequisite **satisfied**, so it does not linger as an open future phase.

### Part B — Download and verify the image

On the MacBook, from the repository root:

```bash
./scripts/macos/download-ubuntu-iso.sh
```

The script downloads `ubuntu-26.04.1-live-server-amd64.iso` into `~/Downloads` and performs the two
checks described earlier: it confirms the checksum pinned in ADR-014 still matches what Ubuntu
publishes today, then confirms the file on disk matches that checksum. Any mismatch aborts.

Downloading manually instead is fine; the point is that a 2.7 GB file arriving over the network is
verified before it becomes the base of everything else.

**Optional but instructive — verify the signature, not just the checksum.** This is the step that
proves Canonical published the checksums:

```bash
brew install gnupg     # if you do not already have it

cd ~/Downloads
curl -fLO https://releases.ubuntu.com/26.04/SHA256SUMS
curl -fLO https://releases.ubuntu.com/26.04/SHA256SUMS.gpg

# Fetch Canonical's signing key, then check the signature over the checksum file
gpg --keyserver keyserver.ubuntu.com --recv-keys "843938DF228D22F7B3742BC0D94AA3F0EFE21092"
gpg --verify SHA256SUMS.gpg SHA256SUMS
```

Expect `Good signature from "Ubuntu CD Image Automatic Signing Key (2012)"`. A warning that the key
is not certified with a trusted signature is normal and expected — it means you have not personally
vouched for Canonical's key, not that the signature failed.

### Part C — Write the USB stick

Plug the stick in and identify it. Run this **before and after** plugging it in and look for the
line that appears:

```bash
diskutil list external physical
```

Then write it:

```bash
./scripts/macos/write-ubuntu-usb.sh ~/Downloads/ubuntu-26.04.1-live-server-amd64.iso disk4
```

Replace `disk4` with your actual identifier. The script refuses to run against a disk that reports
as internal, rejects partition identifiers like `disk4s1`, and requires you to retype the disk
identifier before writing — because the classic unrecoverable mistake in this whole phase is
pointing `dd` at your own laptop's drive.

Writing takes several minutes and prints nothing while it works. Press **Ctrl-T** to see progress;
macOS's `dd` has no progress flag. When macOS afterwards complains that the disk is unreadable,
that is expected — it cannot read the Linux filesystem. Eject, do not initialise.

### Part D — Configure the firmware

Connect monitor and keyboard to the M700, power it on, and press **F1** repeatedly at the Lenovo
logo to enter firmware setup. (**F12** gives a one-time boot menu instead, which is often quicker.)

Exact menu wording varies between ThinkCentre firmware versions, so navigate by meaning rather than
by an exact path:

| Setting | Set to | Why |
|---|---|---|
| **After Power Loss** / AC power recovery | **Power On** | The single most important setting in this phase, usually under a `Power` menu. Without it, a power cut leaves the lab off until you physically press the button — and the final validation test below cannot pass. **Configure this now**; do not defer it. |
| **Intel Virtualization Technology** (VT-x, and VT-d if listed separately) | **Enable** | Disabled by default on the reference node. See the note below — it is not required by anything on the roadmap, but this is the cheapest moment to turn it on. |
| Boot order / boot mode | **UEFI** — preserve it; do not enable legacy/CSM. USB first, or use F12 | Needed to boot the installer, and the installed system must keep booting the same way. |
| Secure Boot | **Leave enabled** | Ubuntu is signed and installs fine with it on. It only becomes awkward later if you need unsigned kernel modules, which this project does not currently plan. |
| Wake on LAN | Optional | Of limited use on Wi-Fi; ignore for now. |

> **Do all firmware changes in this one sitting.** After this phase the machine is headless. Every
> later firmware change means finding a monitor, a keyboard and a cable, and physically going to the
> machine. That is the real reason to enable virtualization now rather than when something needs it.

**Why enable virtualization if nothing needs it?** Nothing on the roadmap requires it today. Linux
containers — Docker in Phase 05 — use kernel namespaces and cgroups, *not* hardware virtualization,
and run perfectly well with VT-x off. It is worth enabling anyway because the CPU supports it, it
costs nothing, and it is what KVM/QEMU virtual machines would need if a later phase ever wants them.
The alternative is a physical trip to a headless machine.

Setting a firmware supervisor password is worth doing eventually, but it belongs to Phase 13
hardening — and note that a forgotten ThinkCentre supervisor password is not trivially recoverable.

> **Do not skip the power-loss setting.** The phase's final validation deliberately tests unattended
> recovery from AC power loss. That test is only meaningful once `After Power Loss -> Power On` is
> actually configured — otherwise it just measures a firmware default, and the machine stays dark.

Save and exit, leaving the USB stick inserted.

### Part E — Install Ubuntu Server

The installer is text-based; navigate with arrow keys, Tab and Enter. Work through it as follows.

1. **Language, then keyboard layout.** Choose the layout that matches the keyboard physically in
   front of you. This matters more than it looks: the password you set later is typed with this
   layout, and getting it wrong is a common cause of "the password I just set does not work."
2. **Installer update.** If it offers to update itself, either answer is fine.
3. **Type of install.** Choose the full **Ubuntu Server**, not "minimized". Minimized strips out
   tooling that is genuinely useful while learning, for a saving that does not matter here.
4. **Network connections.** This is the step to watch closely.
   - Look for a `wl…` interface (for example `wlp2s0`). Its presence means the kernel recognised
     your wireless card.
   - Select it, choose the Wi-Fi configuration option, enter the SSID and passphrase.
   - Wait until the interface shows an IP address before continuing. Do not move on without one.
   - **If no wireless interface is listed**, the card is not usable by the installer. Do not push
     forward — an install with no network is a dead end. Go to *If the installer cannot use the
     Wi-Fi adapter*, immediately after this section. Installation is **not** blocked by this; there
     are several straightforward ways through it.
5. **Proxy.** Leave blank.
6. **Mirror.** Accept the default.
7. **Storage.** Choose **"Use an entire disk"**, select the 256 GB SSD, and tick **"Set up this disk
   as an LVM group"**. Leave the LUKS encryption option **unticked** (ADR-015).
   - On the summary screen, check the size of the root logical volume against the disk size. The
     guided LVM layout does not necessarily hand the whole volume group to the root volume, and
     ending up with a root filesystem far smaller than the disk is a well-known surprise. You can
     edit the logical volume size here, or fix it after boot — Part F shows how.
   - The next confirmation is the destructive one. Windows is gone after this point.
8. **Profile.** Set your name, a server hostname, a username and a strong password. The reference
   build uses a short, memorable hostname; you will type it often in Phase 03.
9. **Ubuntu Pro.** Skip for now. It is free for personal use on up to five machines and extends
   security coverage; it can be enabled at any later time.
10. **SSH.** Tick **"Install OpenSSH server"**. Leave "Import SSH identity" set to no — SSH keys are
    the subject of Phase 03, and doing them there is deliberate rather than an oversight. This does
    mean the server temporarily accepts password logins; see *Security notes*.
11. **Featured snaps.** Select none. Docker arrives properly in Phase 05.

Let the installation finish, choose **Reboot Now**, and remove the USB stick when prompted.

### If the installer cannot use the Wi-Fi adapter

There is a genuine chance the installer will not drive a given wireless chipset. This does not block
the installation.

> **On the reference build specifically:** Part A identified an Intel Wireless-AC 8260, which is
> well supported by the in-tree `iwlwifi` driver with firmware shipped in `linux-firmware`. This
> section is therefore unlikely to be needed on the M700 — keep reading only if the interface does
> not appear. It matters more if you are reproducing Home Lab on different hardware. Work down this list — the aim is
simply to get *any* network link long enough to finish installing, after which the problem is far
easier to solve on a running system with working package management.

1. **Temporary wired Ethernet.** Move the machine next to the router for the install, or run a cable
   temporarily. Simplest and most reliable; it goes back to its permanent spot afterwards.
2. **USB-Ethernet adapter.** Most common USB Ethernet chipsets work in the installer with no
   configuration. Useful when the machine cannot be moved.
3. **USB tethering from a phone.** Connect the phone by USB and enable USB tethering; it appears as
   a wired network device and is usually recognised immediately.
4. **Install first, fix wireless afterwards.** With any temporary link, complete the installation and
   then run a full update — a newer kernel and `linux-firmware` package frequently add support that
   the installer image lacked. Then identify the chipset and work from there:

   ```bash
   sudo apt update && sudo apt full-upgrade -y
   sudo reboot

   # After reboot, identify the wireless hardware:
   lspci -nnk | grep -iA3 'network\|wireless'   # internal (PCIe) cards
   lsusb                                          # USB adapters
   dmesg | grep -i firmware                       # missing firmware complaints
   ```

   The `[1234:5678]` vendor/device identifier from `lspci -nnk` is the thing to search for; it
   identifies the chipset exactly, where a marketing name often does not.
5. **USB Wi-Fi dongle with known Linux support**, if the internal card cannot be made to work.

Record which path you used, and the chipset identifier, in the build log. If Wi-Fi cannot be made
reliable at all, that is a cross-phase finding: ADR-016 needs revisiting and the question goes back
to Project Planning, because it changes Phase 03.

### Part F — First boot, updates, and state capture

Log in at the console with the username and password you set.

**Bring the system up to date.** A freshly installed system is already behind on security updates,
because the ISO was built months ago:

```bash
sudo apt update
sudo apt full-upgrade -y
```

**Install the small tools this phase's checks need:**

```bash
sudo apt install -y dmidecode iw
```

**Check that the disk is fully allocated.** Compare the free space in the volume group against the
root volume:

```bash
sudo vgs        # look at VFree — if it is large, the disk is not fully used
sudo lvs
df -h /
```

If the volume group has substantial free space, claim it:

```bash
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
sudo resize2fs /dev/ubuntu-vg/ubuntu-lv
df -h /          # confirm the root filesystem grew
```

This is LVM earning its place already: growing a live root filesystem with no reboot and no
repartitioning is exactly the flexibility ADR-015 chose it for.

**Check the Wi-Fi passphrase is protected.** netplan stores it in cleartext, so the file's
permissions are the only thing keeping it from every user on the machine:

```bash
ls -l /etc/netplan/
```

On the reference build the installer had already written
`/etc/netplan/00-installer-config.yaml` as `-rw-------` (mode `0600`), which is correct — owner-only.
**Verify rather than assume**; if yours is more permissive, tighten it:

```bash
sudo chmod 600 /etc/netplan/*.yaml
```

A redacted example is kept at `config/netplan/50-wifi.example.yaml`. The real file must never be
committed. Note that `0600` protects the passphrase from other users on the machine, not from anyone
holding the disk — the volume is unencrypted by ADR-015, and these two decisions compound.

**Stop Wi-Fi power saving from dropping the link.** Wireless drivers idle the radio to save power.
On a laptop that is sensible; on an always-on server it shows up as a machine that becomes
unreachable when nobody is using it.

The unit file lives in the repository at `config/systemd/wifi-powersave-off.service` rather than
being typed at a terminal. Copy it across from the MacBook:

```bash
scp config/systemd/*.service <user>@<server-ip>:
```

Then on the server:

```bash
sudo mv wifi-powersave-off.service /etc/systemd/system/
sudo chown root:root /etc/systemd/system/wifi-powersave-off.service
sudo systemctl daemon-reload
sudo systemctl enable --now wifi-powersave-off
iw dev wlp1s0 get power_save     # expect: Power save: off
```

> **Why the `chown`.** `scp` copies the file as *you*, and `sudo mv` preserves that ownership — so
> without this the unit ends up owned by your user inside `/etc/systemd/system/`. systemd executes
> unit files **as root**, so one writable by a non-root user is a privilege-escalation path. Harmless
> if you are the only (sudo-capable) user, genuinely dangerous otherwise. Always `chown root:root`
> after moving a file into a system directory.

Check the interface name in the unit matches your own from `ip -br address` — the reference build
uses `wlp1s0`.

> **Why not just paste a here-document?** An earlier version of this guide did exactly that, and it
> failed on the reference build: the terminal split the pasted command at ~65 characters, `tee` ran
> without its here-document, and wrote a corrupt file. Configuration that belongs in the repository
> should be *copied* from the repository — it is reproducible, reviewable, and immune to how a
> terminal handles a paste. See the build log for the full story.

**Stop boot waiting two minutes for an unplugged Ethernet port.** This one is easy to miss, because
the machine works perfectly well despite it. Check:

```bash
systemctl is-system-running
```

If that says `degraded` rather than `running`, look at what failed:

```bash
systemctl --failed
networkctl
```

On the reference build, `systemd-networkd-wait-online.service` had failed. The cause is visible in
`networkctl`: the unused Ethernet port sits at `no-carrier / configuring`, and `wait-online` waits
for *every* managed link before releasing `network-online.target`. With no cable it waits the full
120-second timeout, then fails — on every single boot.

The consequences are worse than the cosmetic `degraded` flag suggests: two minutes added to every
startup, and anything ordered `After=network-online.target` — including the Wi-Fi power-save unit
above — starts two minutes late.

The fix marks that interface optional. Copy the file from the repository:

```bash
scp config/netplan/99-*.yaml <user>@<server-ip>:
```

Then on the server:

```bash
sudo mv 99-eno1-optional.yaml /etc/netplan/
sudo chown root:root /etc/netplan/99-eno1-optional.yaml
sudo chmod 600 /etc/netplan/99-eno1-optional.yaml
sudo netplan generate
sudo reboot
```

The `chown` matters for the same reason as the systemd unit above: a network configuration file that
a non-root user can rewrite is a file that lets them influence what root applies at boot.

After it comes back, `systemctl is-system-running` should report `running`. Change `eno1` in the
file if your Ethernet interface is named differently.

> Note this is a *second* netplan file rather than an edit to the installer's. netplan merges every
> file in `/etc/netplan/` in filename order, so a separate file keeps this non-secret configuration
> in version control while the installer's file — which holds the Wi-Fi passphrase — stays untouched
> and uncommitted.

**Give the server a stable address.** On the router's admin page, add a DHCP reservation binding the
server's MAC address (from `ip -br link`) to a fixed IP. Doing it at the router rather than as a
static address on the server keeps one source of truth for addressing, and avoids the classic
conflict where a statically-assigned address gets handed to another device.

**Capture the real state into the repository:**

```bash
./scripts/server/verify-install.sh --out server-state.md
```

Copy the results into `docs/reference/hardware.md`, `docs/reference/software-stack.md` and the phase
handover. The script never prints the netplan file contents, so its output is safe to paste — it
reports permissions instead.

---

## Validation

The install is not finished when the installer says so. It is finished when the machine behaves the
way an always-on headless node has to.

```bash
# 1. The right release is running
lsb_release -a

# 2. SSH is up
systemctl is-active ssh

# 3. Automatic security updates are actually scheduled
systemctl list-timers --all | grep apt-daily

# 4. Windows is gone — this must return nothing
lsblk -o NAME,FSTYPE | grep -i ntfs

# 5. Reachable from the MacBook (run this on the MacBook)
ssh <username>@<server-ip>
```

### The test that actually matters — unattended AC power-loss recovery

Everything above can pass on a machine that still needs a human present. This is the test that
proves otherwise, and it is a required item in the Definition of Done.

**Prerequisite:** `Power -> After Power Loss -> Power On` must already be configured in the firmware
(Part D). Without it this test measures nothing — the machine simply stays off, which tells you
about the firmware setting rather than about the operating system.

Method:

1. `sudo poweroff`
2. **Unplug the power cable** — this simulates a real power cut, which is not the same as pressing
   the power button.
3. Plug the power back in. **Do not press the power button, and do not touch the keyboard.**
4. From the MacBook, wait a couple of minutes, then `ssh <username>@<server-ip>`.

You may leave the monitor attached for this test. What the test forbids is *interaction* — a
keypress, a power-button press, starting anything by hand — not the presence of a display. Keeping
the screen connected is in fact useful: if the machine fails to come back, the console shows you
where it stopped, which an unreachable headless box cannot. Re-confirm the test once more after the
machine actually goes headless in Phase 03.

The test passes only if **all four** of these are true:

| # | Must be true | What it proves |
|---|---|---|
| 1 | The machine boots with **no physical interaction** | Firmware AC power recovery is correctly configured |
| 2 | It **reconnects to the network** on its own | netplan/wpa_supplicant bring the Wi-Fi link up unattended |
| 3 | **SSH starts** unattended | The service is enabled, not merely running from your last login |
| 4 | It is **remotely reachable** from the MacBook | The whole chain works end to end, with nobody in the room |

If any of the four fails, that is the phase's real finding and belongs in the build log. Do not work
around it by leaving a keyboard attached, starting a service by hand, or pressing the power button —
those hide exactly the failure this test exists to catch.

## Security notes

| Risk | Status in this phase |
|---|---|
| **SSH accepts passwords** | Known and time-boxed. Phase 03 replaces this with key-only authentication. Until then the server is only as protected as your password and the fact that it is not exposed to the internet. Do not port-forward SSH from the router. |
| **No encryption at rest** | Accepted trade-off (ADR-015). Anyone with physical possession of the SSD has everything on it. |
| **Wi-Fi passphrase in cleartext** | Mitigated to `0600` file permissions — which protects it from other users on the machine, but not from someone holding the unencrypted disk. These two risks compound; Phase 13 should treat them together. |
| **No firewall yet** | The server is behind the router's NAT and exposes only SSH on the LAN. UFW arrives in Phase 13. |
| **Root login** | Not used. Administration goes through a `sudo`-capable user. |
| **Physical access** | Equals full access. Documented, not mitigated, at this stage. |

## What can go wrong

**No wireless interface appears in the installer.** The card is not usable by the installer's
kernel. This is expected often enough to have its own section: see *If the installer cannot use the
Wi-Fi adapter*, between Parts E and F.

**The machine boots back into Windows.** The USB stick was not selected at boot, or the firmware is
still in legacy/CSM mode. Use F12 for the one-time boot menu and pick the UEFI entry for the stick.

**The password does not work at first login.** Almost always a keyboard layout mismatch between the
installer and the running system. Try typing the password into the username field once, so you can
see the characters that actually appear.

**The root filesystem is much smaller than the disk.** Expected with guided LVM; see the
`lvextend` / `resize2fs` steps in Part F.

**SSH works, then stops when idle.** Wi-Fi power saving. See the systemd unit in Part F.

**The server does not come back after a power cut.** The firmware's "After Power Loss" setting is
not set to Power On. Re-enter setup with F1 and check.

## Reference-build experience

### Part A — hardware identification (2026-09-08)

Completed on the M700 from Windows, before erasing anything. Results are in the table under Part A
above and in `docs/reference/hardware.md`.

Two long-standing project unknowns closed here: the RAM module layout (1 × 8 GB, one slot free) and
the wireless adapter model (Intel AC 8260). Both had been open since project bootstrap, and both took
minutes to resolve from Windows Task Manager — a good argument for doing this pass before wiping
rather than reconstructing it afterwards from Linux.

Physical validation passed: USB ports and video output work, and fan noise is unobtrusive — worth
confirming for a machine that will live in a home rather than a rack.

One thing was found that nobody had thought to look for: **CPU virtualization was disabled in
firmware.** It was not on the original checklist. Nothing on the roadmap needs it, but finding it
now — while a monitor is attached — is worth much more than finding it later on a headless machine.
The checklist has been amended to look for it.

### Parts B–F — installation

> **Not yet recorded.** The installation has not been performed at the time of writing. This section
> must be filled in from what actually happened — including anything that went wrong — before
> Phase 01 can be declared complete. See `docs/build-log/`.

## Tested versions

> **Not yet recorded.** Per `docs/standards/documentation.md`, software is not documented as
> installed until real version output exists. Populate this table from
> `scripts/server/verify-install.sh` output after the install.

These are **Tested with** values, not requirements. The only hard requirement is Ubuntu Server LTS
on a release still in standard support (ADR-014).

| Component | Tested with | Notes |
|---|---|---|
| Ubuntu Server | *pending install* | Target: 26.04.1 LTS (ADR-014) |
| Linux kernel | *pending install* | |
| OpenSSH server | *pending install* | |
| netplan | *pending install* | |
| wpasupplicant | *pending install* | Required by the networkd renderer for Wi-Fi |

## Next phase

[Phase 02 — Linux Fundamentals](../../ROADMAP.md), which takes the shell you now have and builds the
operating knowledge to use it safely, followed by Phase 03 — Remote Access, which closes this
phase's open SSH risk.
