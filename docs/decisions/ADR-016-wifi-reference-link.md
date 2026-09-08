# ADR-016: Wi-Fi as the reference node's network link

- **Status:** Accepted
- **Date:** 2026-09-08
- **Supersedes:** none
- **Superseded by:** none

## Context

The reference node's physical location cannot practically be reached by an Ethernet cable. The
machine has built-in Wi-Fi, and the project's planning documents had left the network link as
"wired capability to be validated/used as appropriate" without resolving it.

For an always-on server this is not a neutral choice. Ethernet is technically preferable in every
respect that matters here: no association step at boot, no passphrase stored on disk, no radio
interference, and far more predictable reconnection behaviour. The decision is being driven by a
physical constraint, and the documentation should say so plainly rather than presenting Wi-Fi as an
equal option.

Two technical facts shape the implementation (verified against netplan documentation, 2026-09-08):

- Ubuntu Server's default renderer is `systemd-networkd`, which has **no native Wi-Fi support** and
  requires `wpasupplicant` to be installed to drive a wireless link.
- netplan stores the Wi-Fi passphrase in **cleartext** in its YAML configuration.

## Decision

Use Wi-Fi as the reference node's network link, configured declaratively through netplan's `wifis`
key, and treat its reliability as something to be **validated rather than assumed**.

Required accompanying controls:

- the netplan configuration file must be mode `0600`;
- the real configuration must never be committed; only a redacted example belongs in the repository;
- a router-side DHCP reservation should give the node a stable address;
- Wi-Fi power saving should be disabled, since it is a common cause of idle disconnection on servers;
- the phase is not complete until the node has survived an unattended power cycle and reconnected on
  its own.

## Alternatives considered

- **Ethernet.** Preferred on technical merit; unavailable at the intended location. If that changes,
  this decision should change with it.
- **Powerline or MoCA adapter.** A realistic way to obtain a wired link without new cabling. Rejected
  for now because it adds cost and another failure-prone component, but retained as the first
  fallback if Wi-Fi proves unreliable.
- **USB Wi-Fi dongle.** Not a preference, but the fallback if the internal wireless adapter turns out
  not to be supported by the installer.

## Consequences

- Phase 03 (Remote Access) and everything built on it — Tailscale, VS Code Remote SSH, and later the
  Telegram interface — sit on top of a link that is less reliable than a wire. Intermittent
  unreachability must be diagnosed with that in mind before deeper causes are assumed.
- The Wi-Fi passphrase becomes a plaintext secret on an unencrypted disk (see ADR-015). The two
  decisions compound, and Phase 13 should consider them together.
- There is a real possibility the installer will not detect the wireless adapter at all. The adapter
  model must therefore be captured from Windows *before* the disk is wiped, while that information is
  still cheap to obtain.

## Validation / revisit trigger

Revisit immediately if the adapter is undetected, or if the node repeatedly fails to reconnect
unattended. Per the Phase 01 brief §6, either outcome is a cross-phase change and must be escalated
to Project Planning rather than patched locally, because it affects the Phase 03 approach.

Revisit voluntarily if the machine ever relocates within reach of a cable.
