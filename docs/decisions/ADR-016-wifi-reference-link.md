# ADR-016: Wi-Fi as the reference node's initial network link

- **Status:** Accepted
- **Date:** 2026-09-08
- **Amended:** 2026-09-08 — Project Planning ratification of the Phase 01 brief, amendment 4
  (clarify as the *initial* connection; state the Ethernet preference; add an installer fallback path)
- **Supersedes:** none
- **Superseded by:** none

## Context

The reference node's physical location cannot practically be reached by an Ethernet cable. The
machine has built-in Wi-Fi, and the project's planning documents had left the network link as
"wired capability to be validated/used as appropriate" without resolving it.

For an always-on server this is not a neutral choice. **Wired Ethernet is preferable wherever it is
practical for a stationary server**, in every respect that matters here: no association step at
boot, no passphrase stored on disk, no radio interference, lower latency, and far more predictable
reconnection behaviour. The decision below is driven by a physical constraint, and the documentation
says so plainly rather than presenting Wi-Fi as an equal option.

Two technical facts shape the implementation (verified against netplan documentation, 2026-09-08):

- Ubuntu Server's default renderer is `systemd-networkd`, which has **no native Wi-Fi support** and
  requires `wpasupplicant` to be installed to drive a wireless link.
- netplan stores the Wi-Fi passphrase in **cleartext** in its YAML configuration.

## Decision

Use Wi-Fi as the reference node's **initial** network link, configured declaratively through
netplan's `wifis` key, and treat its reliability as something to be **validated rather than
assumed**.

"Initial" is deliberate. This records the reference build's starting point under a physical
constraint; it does not establish Wi-Fi as the project's preferred or permanent transport. If a
wired link becomes practical, moving to it is an improvement rather than a deviation, and needs no
new ADR — only a build-log entry.

Required accompanying controls:

- the netplan configuration file must be mode `0600`;
- the real configuration must never be committed; only a redacted example belongs in the repository;
- a router-side DHCP reservation should give the node a stable address;
- Wi-Fi power saving should be disabled, since it is a common cause of idle disconnection on servers;
- the phase is not complete until the node has survived an unattended power cycle and reconnected on
  its own.

## Fallback path if the installer cannot use the Wi-Fi adapter

The wireless adapter model is not yet known, and there is a real possibility the Ubuntu installer
will not detect it — which would strand the installation with no network at all. **Installation must
not be blocked by Wi-Fi.** In priority order:

1. **Temporary wired Ethernet.** Move the machine next to the router for the install, or run a cable
   temporarily. Simplest and most reliable; the machine returns to its permanent location afterwards.
2. **USB-Ethernet adapter.** Most common USB Ethernet chipsets are supported by the Ubuntu installer
   out of the box. Useful when the machine cannot move.
3. **USB tethering from a phone.** Presents as a wired USB network device and is usually recognised
   without configuration. Adequate for completing an install and fetching updates.
4. **Complete the install, then fix wireless support afterwards.** With any temporary link in place,
   install the system, apply a full update (which may bring a newer kernel and `linux-firmware`),
   identify the chipset with `lspci -nnk` or `lsusb`, and resolve driver/firmware support on a
   running system with working networking and package access — a far better position than the
   installer environment.
5. **USB Wi-Fi dongle with known Linux support**, if the internal card turns out to be unsupportable.

Whichever path is taken must be recorded in the build log, including the chipset identifier. If Wi-Fi
ultimately proves unworkable or unreliable, this ADR must be revisited and the change escalated to
Project Planning, because it affects Phase 03.

## Alternatives considered

- **Ethernet.** Preferred on technical merit; unavailable at the intended location. If that changes,
  this decision should change with it.
- **Powerline or MoCA adapter.** A realistic way to obtain a wired link without new cabling. Rejected
  for now because it adds cost and another failure-prone component, but retained as the first
  permanent fallback if Wi-Fi proves unreliable in service.
- **USB Wi-Fi dongle.** Not a preference, but a fallback if the internal wireless adapter turns out
  not to be supported.

## Consequences

- Phase 03 (Remote Access) and everything built on it — Tailscale, VS Code Remote SSH, and later the
  Telegram interface — sit on top of a link that is less reliable than a wire. Intermittent
  unreachability must be diagnosed with that in mind before deeper causes are assumed.
- The Wi-Fi passphrase becomes a plaintext secret on an unencrypted disk (see ADR-015). The two
  decisions compound, and Phase 13 should consider them together.
- The adapter model must be captured from Windows *before* the disk is wiped (Phase 01 Part A),
  while that information is still cheap to obtain.

## Validation status (2026-09-08)

Phase 01 Part A identified the reference node's wireless adapter as an **Intel Dual Band
Wireless-AC 8260 (802.11ac)**.

This materially reduces — but does not eliminate — the main risk recorded above:

- the adapter uses the in-tree `iwlwifi` driver, present in the Linux kernel since well before this
  project's target release;
- its firmware series, `iwlwifi-8000C`, ships in Ubuntu's `linux-firmware` package
  (`iwlwifi-8000C-34.ucode` and `-36.ucode`), and that package is present on the Ubuntu Server
  installer image.

So the specific failure this ADR worried about — *the installer cannot see the card* — is now
unlikely. The fallback path above is **retained unchanged**: it costs nothing to keep, and the claim
is a documentation-based expectation rather than a test result. It is not validated until the
installer actually brings the interface up on this machine.

The reliability question is untouched by this finding. An adapter being well supported says nothing
about whether it reconnects dependably after a power cut, which remains the phase's real test.

## Validation / revisit trigger

Revisit immediately if the adapter is undetected and cannot be made to work, or if the node
repeatedly fails to reconnect unattended. Per the Phase 01 brief §6, either outcome is a cross-phase
change and must be escalated to Project Planning rather than patched locally, because it affects the
Phase 03 approach.

Revisit voluntarily if the machine ever relocates within reach of a cable — moving to Ethernet is an
improvement, not a deviation.
