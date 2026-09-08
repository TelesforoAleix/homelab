# Phase 01 Brief — Ubuntu Server

- **Status:** Proposed by the Phase 01 working context, 2026-09-08. **Pending ratification by Project Planning.**
- **Phase:** 01 — Ubuntu Server
- **Depends on:** Phase 00 (hardware verification items still open)

## 0. Provenance note

This brief did not exist when Phase 01 work began. `docs/reference/project-state.md` listed
"Create a dedicated Phase 01 Ubuntu Server brief/handover" as the *immediate next planning action*,
and that action had not been carried out.

Per `PROJECT.md` §13, Project Planning owns phase briefs. This document was therefore drafted by the
phase working context to avoid implementing against an unwritten specification, and is marked
**Proposed** rather than accepted. Project Planning should ratify, amend, or replace it. If it is
amended, the phase work must be reconciled against the amended version before the phase is declared
complete.

## 1. Purpose

Convert the reference node from a used Windows machine into the project's canonical Ubuntu Server
installation: reproducible, documented, headless-capable, and verified against what is actually
running rather than what was intended.

This phase deliberately performs the installation **manually**. Per ADR-012, automation follows
understanding; a one-off OS install repeated once per machine lifetime does not yet justify
automated provisioning. Unattended/automated installation is Phase 14 work.

## 2. Starting state

Verified from the repository and from planning sources on 2026-09-08:

| Fact | State |
|---|---|
| Repository bootstrap | Complete (`main` at `c85ac11`) |
| Software stack | Every component marked *Planned*; nothing installed via this repository |
| Reference node OS | Original Windows installation, to be removed |
| RAM module layout | **Unknown** (1×8 GB vs 2×4 GB) — open Phase 00 item |
| Wi-Fi adapter model | **Unknown** — newly identified as a phase risk, see §6 |
| Port / fan / peripheral checks | Not performed |
| Accepted ADRs | ADR-001 … ADR-013 |

Phase 00 hardware verification is therefore **not** complete, and its remaining checks are folded
into this phase as Part A because they must happen before the disk is wiped.

## 3. Learning objectives

By the end of this phase the owner should be able to explain:

- what an LTS release is, and how a support horizon should influence a version choice;
- what verifying an image checksum does and does not prove;
- what UEFI, Secure Boot, boot order and AC-power-recovery settings control, and why the last of
  these matters specifically for an always-on headless machine;
- what partitioning and LVM are, and the trade-off against a plain single-filesystem layout;
- why full-disk encryption conflicts with unattended headless boot;
- how Linux names network interfaces and how netplan declares network configuration;
- why `systemd-networkd` needs `wpasupplicant` to drive Wi-Fi;
- what a server installation deliberately omits relative to a desktop installation;
- the difference between the system's actual state and the repository's recorded state, and why
  the second must be derived from the first.

## 4. Functional objectives

1. Outstanding Phase 00 hardware facts are captured **before** Windows is destroyed.
2. An Ubuntu Server 26.04.1 LTS image is downloaded and checksum-verified on the MacBook.
3. A bootable installation USB is produced reproducibly.
4. Firmware is configured for headless operation (boot order, AC power recovery, Secure Boot decision).
5. Ubuntu Server is installed: whole-disk LVM, no full-disk encryption, Wi-Fi networking,
   `openssh-server` enabled, Windows entirely removed.
6. The machine boots unattended to a network-reachable state.
7. Base packages are updated and automatic security updates are confirmed active.
8. The resulting real state is captured into repository documentation via a verification script.

## 5. Decisions already fixed

Binding for this phase:

- **ADR-002** — the node is an orchestration/infrastructure server, not a workstation or inference host.
- **ADR-003** — Ubuntu Server LTS, headless, no desktop environment.
- **ADR-004** — the MacBook is the development interface; the server is an execution environment.
- **ADR-011** — privilege separation; user-facing services must not run as root later.
- **ADR-012** — manual first, automate once understood.
- **ADR-013** — `main` must represent a known-working state.

Decisions taken at the start of this phase, to be recorded as new ADRs (§13):

- Ubuntu **26.04.1 LTS** as the pinned reference release.
- Whole-disk **LVM without full-disk encryption**.
- **Wi-Fi** as the reference network link.

## 6. Decisions still open

Resolvable inside this phase:

- hostname and administrative username convention;
- Secure Boot enabled or disabled, depending on observed firmware behaviour;
- swap strategy (installer default vs. explicit sizing);
- whether to add a router-side DHCP reservation for a stable address.

**Escalate to Project Planning if:** the wireless adapter is not detected by the installer, or Wi-Fi
proves unreliable for an always-on node. That outcome invalidates the Wi-Fi ADR and has direct
consequences for Phase 03 (Remote Access), so it is a cross-phase change rather than a local fix.

## 7. Implementation scope

| Part | Work | Executed by |
|---|---|---|
| A | Windows-side hardware verification (RAM layout, wireless adapter, storage, ports, fan) | Owner, on the M700 |
| B | ISO download and checksum verification | Script, on the MacBook |
| C | USB creation | Script, on the MacBook |
| D | Firmware/BIOS configuration | Owner, on the M700 |
| E | Ubuntu Server installation | Owner, on the M700 |
| F | First-boot validation and state capture | Script, on the server |

Explicitly **out of scope**, deferred to their own phases:

- SSH key authentication and SSH hardening → Phase 03;
- Tailscale and VS Code Remote SSH → Phase 03;
- Git configuration on the server → Phase 04;
- Docker / Compose → Phase 05;
- firewall rules, auditing, backups → Phase 13;
- automated/unattended provisioning → Phase 14.

## 8. Validation / tests

The phase is not validated by "the installer finished". Required evidence:

1. `lsb_release -a` reports the expected release.
2. The machine survives a full power cycle and returns to a reachable state with no keyboard or
   monitor attached.
3. Wi-Fi reconnects automatically after that power cycle.
4. `ssh` from the MacBook reaches the server.
5. `systemctl is-active ssh` and the unattended-upgrades timer are confirmed active.
6. No Windows partition remains.
7. RAM module layout is recorded from `dmidecode`, closing the open Phase 00 unknown.
8. Recorded versions in `docs/reference/software-stack.md` match live command output.

## 9. Security considerations

| Item | Position in this phase |
|---|---|
| SSH password authentication | Enabled at install; **interim risk**, accepted only until Phase 03 replaces it with key-only auth. Must be recorded as an open risk, not silently ignored. |
| No full-disk encryption | Accepted trade-off for unattended headless boot. Data at rest is unprotected against physical theft. Revisit in Phase 13. |
| Wi-Fi PSK on disk | netplan stores the passphrase in cleartext. The file must be `0600`, and **must never be committed**. Only redacted examples belong in the repository. |
| Root account | No direct root login; administration via a `sudo`-capable user. |
| Automatic security updates | Verified active in this phase rather than deferred. |
| Physical access | Physical access to the machine equals full access. Documented, not mitigated, at this stage. |

## 10. Repository changes expected

- `guide/01-ubuntu-server/README.md`
- `scripts/macos/download-ubuntu-iso.sh`
- `scripts/macos/write-ubuntu-usb.sh`
- `scripts/server/verify-install.sh`
- `config/netplan/50-wifi.example.yaml` (redacted example only)
- new ADRs under `docs/decisions/`
- build-log entry under `docs/build-log/`
- updates to `docs/reference/*`, `docs/architecture/current-architecture.md`, `ROADMAP.md`,
  `CHANGELOG.md`, `guide/README.md`

## 11. Guide documentation required

`guide/01-ubuntu-server/README.md`, following `docs/templates/guide-template.md`: explanation before
commands, realistic alternatives, validation steps, security notes, and a reference-build experience
section populated from what actually happened rather than what was expected.

## 12. Project documentation required

- `docs/reference/project-state.md` — current phase and resolved unknowns
- `docs/reference/hardware.md` — verified RAM layout and wireless adapter
- `docs/reference/software-stack.md` — Ubuntu and OpenSSH moved from *Planned* to *Active* **only
  once real version output exists**
- `docs/reference/costs.md` — new spending, or an explicit statement of none
- `docs/build-log/` — including problems and dead ends
- `docs/architecture/current-architecture.md` — first entry of a genuinely deployed component

## 13. ADRs required / possible

| ADR | Subject |
|---|---|
| ADR-014 | Pin the reference release to Ubuntu Server 26.04.1 LTS (refines ADR-003) |
| ADR-015 | Whole-disk LVM without full-disk encryption on the reference node |
| ADR-016 | Wi-Fi as the reference network link, with its risks stated |
| ADR-017 | *Conditional* — only if Wi-Fi fails and the network approach must change |

## 14. Costs

No new recurring or usage-based cost is expected. Possible one-time cost: a USB flash drive, if one
had to be purchased. Record actual spend or explicitly record none.

## 15. Definition of Done

- [ ] Functional objective works — server installed, headless, reachable.
- [ ] Configuration/setup is reproducible.
- [ ] Validation/tests have passed with recorded output.
- [ ] Important security implications were considered and open risks named.
- [ ] Relevant repository files are committed.
- [ ] Human-facing guide is updated.
- [ ] Project/internal documentation is updated.
- [ ] ADRs are created or updated where necessary.
- [ ] Actual costs are recorded where applicable.
- [ ] Problems, failed approaches, and lessons are recorded.
- [ ] Tested versions are recorded from live output.
- [ ] No unexplained critical AI-generated component remains.
- [ ] `main` represents a known-working state.
- [ ] A structured handover is returned to Project Planning.

## 16. Return handover requirements

Project Planning must receive a completed `docs/templates/phase-handover-template.md` containing:

1. verified hardware facts, closing the Phase 00 RAM-layout unknown;
2. exact installed versions from live command output;
3. validation evidence, especially the unattended power-cycle recovery test;
4. the status of the three new ADRs;
5. remaining security risks carried into Phase 03, explicitly listed;
6. any Wi-Fi reliability finding that would change the Phase 03 remote-access approach;
7. actual costs or an explicit "none";
8. problems and reversals, preserved in assumption → event → learning → change form.
