# Build Log — Phase 01 Preparation

- **Date:** 2026-09-08
- **Phase:** 01 — Ubuntu Server
- **Branch:** `feature/01-ubuntu-server`
- **Status:** In progress — preparation complete and ratified; installation not yet performed

## Starting state

Phase 00 had produced the repository, governance and initial ADR set. `main` was at `c85ac11`. The
reference node still ran its original Windows installation, and no software had been installed
through this repository's workflow.

## Objective

Prepare everything Phase 01 needs so the installation itself can be performed as a deliberate,
documented operation rather than improvised: a phase brief, a guide, reproducible scripts, and the
architectural decisions the install depends on.

## Actions taken

1. Read the governance set (`AGENTS.md`, `PROJECT.md`, `ROADMAP.md`, `project-state.md`, ADRs) and
   discovered the Phase 01 brief did not exist (see *Problems* below).
2. Verified externally, rather than assuming, which Ubuntu LTS releases were current and whether the
   project's future dependencies support the newest one.
3. Resolved four open decisions with the owner: release version, machine state, network link, disk
   layout. Two of them (network link, disk layout) turned out to be architectural.
4. Drafted `docs/handovers/01-ubuntu-server.md` and marked it **Proposed**.
5. Wrote ADR-014 (Ubuntu 26.04.1 LTS), ADR-015 (LVM without full-disk encryption), ADR-016 (Wi-Fi as
   the reference link).
6. Wrote `guide/01-ubuntu-server/README.md` covering hardware capture, image verification, USB
   creation, firmware configuration, installation, and first-boot validation.
7. Wrote three scripts (`scripts/macos/`, `scripts/server/`) and a redacted netplan example.
8. Updated project state, roadmap, hardware, software stack, cost ledger and the relevant READMEs.

## Validation

What was actually tested, on the MacBook, today:

| Check | Result |
|---|---|
| Ubuntu publishes 26.04.1 LTS and 24.04.4 LTS as current | Confirmed against `releases.ubuntu.com` |
| Pinned ISO SHA256 matches upstream `SHA256SUMS` | Confirmed — `cc8a95cd…f1d927` |
| Docker publishes a `resolute` APT distribution | Confirmed in the repository listing |
| Tailscale serves a `resolute` keyring | Confirmed — HTTP 200 |
| Ubuntu CD Image signing key fingerprint | Confirmed against `keyserver.ubuntu.com` as `Ubuntu CD Image Automatic Signing Key (2012)` |
| All three scripts parse | `bash -n` clean |
| `diskutil` field parsing works | Confirmed against real `diskutil info` output |
| USB writer refuses an internal disk | **Tested** against `disk0` — refused, exit 1 |
| USB writer rejects a partition identifier | **Tested** with `disk4s1` — refused, exit 1 |
| USB writer requires arguments | **Tested** — exit 64 |

What could **not** be tested: everything requiring the M700. The installation, the Wi-Fi
association, the unattended power-cycle recovery, and every version number remain unverified.

## Problems / failed approaches

**1. The phase brief did not exist.**

- *Assumption:* Phase 01 work would begin from a brief prepared by Project Planning, as
  `PROJECT.md` §13 and `docs/handovers/README.md` both describe.
- *What happened:* `docs/handovers/` contained only `README.md` and `project-planning.md`.
  `project-state.md` listed creating the brief as the *immediate next planning action* — it had
  simply never been carried out.
- *What we learned:* The governance model has a gap between "Project Planning defines the brief" and
  the phase context starting work. Nothing detects a missing brief; the phase context is the first
  to notice.
- *What changed:* The brief was drafted by the phase context and explicitly marked **Proposed,
  pending ratification**, rather than either inventing an accepted specification or stalling.

**2. Wi-Fi-only turned out to be a constraint, not a preference.**

- *Assumption:* Planning documents left the link as "wired capability to be validated/used as
  appropriate", implying Ethernet.
- *What happened:* No cable can reach the machine's location.
- *What we learned:* This is not a detail. It puts a cleartext passphrase on an unencrypted disk,
  adds an association step to every unattended boot, and places Phase 03's remote access on a less
  reliable link.
- *What changed:* ADR-016 was written to record it as a decision with named risks and a validation
  requirement, instead of leaving it as an unstated assumption. The wireless adapter model was added
  to `project-state.md` as a tracked unknown, because an undetected card blocks the install.

**3. Tailscale's repository has no browsable directory index.**

- Requesting `https://pkgs.tailscale.com/stable/ubuntu/` returned 404, which momentarily looked like
  "no Ubuntu support". Requesting the concrete file `resolute.tailscale-keyring.list` returned 200.
- *Lesson:* absence of a directory listing is not absence of a package. Test for the artefact you
  actually need.

**4. A key fingerprint was nearly shipped from memory.**

- The guide's optional GPG verification step initially carried a fingerprint written from prior
  knowledge. It was checked against `keyserver.ubuntu.com` before the guide was finalised, and was
  correct — but publishing an unverified fingerprint in a security instruction would have been a
  meaningful error, since a reader would trust it.
- *Lesson, worth generalising:* key material and checksums get verified against a live source before
  they enter this repository. Never from recall.

**5. macOS `dd` has no progress output.**

- `status=progress` is a GNU extension and errors out on BSD `dd`. The script and guide use Ctrl-T
  (SIGINFO) instead.

## What we learned

- Choosing the newest LTS is normally a risk because third-party repositories lag the codename. That
  risk is *checkable in about a minute*, and checking it converted a judgement call into a decision
  with evidence behind it.
- Full-disk encryption and headless operation are in direct conflict. The right answer depends
  entirely on the machine's role, which is exactly what an ADR is for.
- The most valuable validation in this phase is not "did the installer finish" but "does it come
  back on its own after being unplugged". That test is the one that proves the machine is a server.

## Decisions / ADRs

- [ADR-014](../decisions/ADR-014-ubuntu-2604-lts.md) — pin Ubuntu Server 26.04.1 LTS. Refines ADR-003.
- [ADR-015](../decisions/ADR-015-disk-layout-no-fde.md) — whole-disk LVM, no full-disk encryption.
- [ADR-016](../decisions/ADR-016-wifi-reference-link.md) — Wi-Fi as the reference network link.

## Costs

None. No new spending was incurred by preparation. A USB flash drive is the only possible one-time
cost for this phase and is pending confirmation in `docs/reference/costs.md`.

## Ratification (Project Planning, 2026-09-08)

The brief was **ratified subject to six amendments**, all reconciled in this branch. Full list in
`docs/handovers/01-ubuntu-server.md` §0.1. Substantive effects:

- **ADR-014 restructured** around the project's `Tested with` vs `Requires` standard. The previous
  draft pinned 26.04.1 without saying whether that was a requirement — which would have quietly
  told followers they needed an exact point release. The requirement is now stated as "Ubuntu Server
  LTS in standard support"; the ISO/checksum pin is explicitly a reproducibility mechanism.
- **ADR-015 reframed** as a reference-build trade-off rather than a recommendation, with a table of
  situations where the opposite answer is correct, and a hard revisit trigger at Phase 10.
- **ADR-016 clarified** as the *initial* link, with the Ethernet preference stated plainly and a
  five-option installer fallback path so a missing wireless driver cannot block the install.
- **Phase 00 closed out properly.** Its remaining hardware checks are Phase 01 Part A, with a
  completion checklist and an explicit closure condition, rather than an open standalone phase.
- **The power-loss test hardened** into a prerequisite (firmware setting configured first) plus four
  named proof points, so it cannot pass vacuously.

### Problem found while adding references (amendment 6)

- *Assumption:* Tailscale would have a 26.04 install page to cite, since its packages support
  `resolute`.
- *What happened:* `tailscale.com/kb/1187/install-ubuntu-2604` returns **HTTP 200** but serves a
  generic documentation index with no Ubuntu 26.04 content — a soft 404. Tailscale's Linux download
  pages still reference only Noble 24.04, while the package repository carries
  `Origin: Tailscale, Codename: resolute` dated 2026-09-03.
- *What we learned:* an HTTP 200 is not evidence a page says what you expect. Vendor documentation
  can lag vendor packages by months, and citing the docs would have been weaker evidence than citing
  the repository.
- *What changed:* ADR-014 cites the package repository metadata as authoritative, and carries an
  explicit warning for Phase 03 not to cite that KB URL.

## Next

1. ~~Project Planning ratifies or amends the Phase 01 brief.~~ Done 2026-09-08.
2. Perform Parts A–F on the M700 following the guide. Part A closes the Phase 00 prerequisite.
3. Record real output into the guide's *Reference-build experience* and *Tested versions* sections,
   `hardware.md`, `software-stack.md`, and a completion build-log entry.
4. Complete the phase handover. Phase 01 is **not** complete until the unattended power-cycle test
   passes.
