# ADR-014: Ubuntu Server release for the reference build

- **Status:** Accepted
- **Date:** 2026-09-08
- **Amended:** 2026-09-08 — Project Planning ratification of the Phase 01 brief, amendments 1 and 6
  (distinguish *Tested with* from *Requires*; add authoritative references)
- **Supersedes:** none (refines ADR-003, which chose "Ubuntu Server LTS" without naming a release)
- **Superseded by:** none

## Context

ADR-003 committed the project to Ubuntu Server LTS but deliberately did not pin a release. Phase 01
must install a specific image, so the reference build has to choose one and record it.

Two LTS releases were in standard support when this decision was taken:

| Release | Codename | Released | Standard support ends |
|---|---|---|---|
| 26.04.1 LTS | Resolute Raccoon | 2026-04-23 | April 2031 |
| 24.04.4 LTS | Noble Numbat | 2024-04 | April 2029 |

The reference node is intended to run continuously for years, and reinstalling it is disruptive, so
the support horizon carries real weight.

The standard argument *against* adopting the newest LTS is that third-party APT repositories lag the
new codename. For this project that argument is concrete rather than theoretical: Phase 03 needs
Tailscale and Phase 05 needs Docker, and neither can be installed from a repository that has not yet
published for the release. That risk was therefore measured before committing — see
*Authoritative references* below. Both repositories publish for `resolute`.

## Decision

This ADR deliberately separates two different statements, per the version policy in `PROJECT.md`
§9 and `docs/standards/documentation.md`.

### Requires — hard compatibility requirement

> **Ubuntu Server LTS, amd64, on a release currently within standard support.**

That is the whole requirement, and it is inherited from ADR-003. **No component of this project
currently requires Ubuntu 26.04 specifically.** Someone reproducing Home Lab on 24.04 LTS is not
doing anything unsupported.

### Tested with — the reference build

> **Ubuntu Server 26.04.1 LTS (amd64).**

Pinned for reproducibility of the reference build:

| Artefact | Value |
|---|---|
| Image | `ubuntu-26.04.1-live-server-amd64.iso` |
| SHA256 | `cc8a95cde20f6ced61a322420de00f10cc3c90ced545daa46cb9c1a117f1d927` |
| Source | `https://releases.ubuntu.com/26.04/` |

The `.1` point release is chosen over the original `26.04` media because a point release rolls
roughly four months of fixes and updated hardware enablement into the installer itself, which
matters when installing onto ten-year-old hardware.

### Why the pin exists

The exact ISO and checksum are pinned so that the reference build can be reproduced byte-for-byte
and so that `scripts/macos/download-ubuntu-iso.sh` can refuse an unverified file. **The pin is a
reproducibility mechanism, not a constraint on followers.** It says "this is what was tested", not
"this is what you must use".

If a genuine hard dependency on a specific release ever appears, it must be recorded as **Requires**
in `docs/reference/software-stack.md` and this ADR superseded — not quietly implied by the pin.

## Guidance for reproduction

- Any Ubuntu Server LTS still in standard support should work.
- 24.04 LTS is the most likely alternative and a reasonable choice, particularly for someone who
  wants the largest pool of existing troubleshooting material.
- Anything other than 26.04.1 is **untested by this project**. Guides may differ in small details
  such as installer wording or default package versions.
- Deviations should be recorded in the build log, so the project learns where its guides are
  release-specific.

## Alternatives considered

- **Ubuntu 24.04.4 LTS as the reference.** The most mature option, with the largest body of existing
  tutorials and forum answers — a genuine benefit for a learning-first project. Rejected as the
  *reference* because it surrenders two years of support life on a machine meant to stay in service,
  and because the maturity advantage narrowed once the two dependencies that actually matter were
  confirmed to support 26.04. It remains a fully supported choice for followers.
- **Ubuntu 25.10 (interim).** Rejected: nine months of support would force a reinstall or release
  upgrade cycle onto an always-on node for no benefit.
- **A different distribution.** Out of scope; settled by ADR-003.

## Consequences

- Support runway to April 2031, extendable to 2036 via Ubuntu Pro (free for personal use on up to
  five machines) if that is ever wanted.
- Fewer community answers exist for a release this young. When a problem is hit, the primary sources
  are official Ubuntu documentation and upstream project documentation rather than blog posts.
- Vendor *documentation* may lag vendor *packages* — as it currently does for Tailscale. Verifying
  the repository directly is more reliable than reading an install page.
- If some future third-party repository has no `resolute` build, the fallbacks are the upstream
  generic installation method or deliberately pinning that vendor's `noble` repository. Either is
  acceptable, but it must be recorded in the build log as a problem rather than quietly worked around.
- Guides in this repository are written and tested against 26.04.1 unless stated otherwise.

## Authoritative references

All checked on **2026-09-08**.

### Ubuntu 26.04.1 LTS release and status

| Reference | What it establishes |
|---|---|
| <https://releases.ubuntu.com/26.04/> | 26.04.1 LTS (Resolute Raccoon) is published; lists `ubuntu-26.04.1-live-server-amd64.iso`, dated 2026-08-26 |
| <https://releases.ubuntu.com/26.04/SHA256SUMS> | Source of the pinned SHA256 above; cross-checked by the download script on every run |
| <https://documentation.ubuntu.com/release-notes/26.04/> | Official release notes; server minimum 1.5 GB RAM / 4 GB storage; 5 years standard support, 10 with Ubuntu Pro |
| <https://ubuntu.com/about/release-cycle> | Canonical's release and support lifecycle |

Release date 2026-04-23; standard support to April 2031.

### Docker Engine support for Ubuntu Resolute 26.04

| Reference | What it establishes |
|---|---|
| <https://docs.docker.com/engine/install/ubuntu/> | Officially lists supported versions as "Ubuntu Resolute 26.04 (LTS)", Noble 24.04, Jammy 22.04 |
| <https://download.docker.com/linux/ubuntu/dists/resolute/Release> | The repository itself exists — `Origin: Docker`, `Suite: resolute`, `amd64` among architectures |

### Tailscale package support for Ubuntu Resolute

| Reference | What it establishes |
|---|---|
| <https://pkgs.tailscale.com/stable/ubuntu/dists/resolute/Release> | `Origin: Tailscale`, `Codename: resolute`, `amd64` present, dated 2026-09-03 |
| <https://pkgs.tailscale.com/stable/ubuntu/resolute.tailscale-keyring.list> | The keyring/source list for `resolute` is published (HTTP 200) |

> **Note for Phase 03.** Tailscale's *documentation* has not caught up with its *packages*. Its
> Linux download pages still reference Noble 24.04 and there is no 26.04-specific KB article — the
> URL pattern `tailscale.com/kb/1187/install-ubuntu-2604` returns HTTP 200 but serves a generic docs
> index, not an Ubuntu 26.04 guide. Do not cite it as evidence of support. The package repository
> above is the authoritative source, and Phase 03 should follow the generic Ubuntu install path
> using the `resolute` codename.

## Validation / revisit trigger

Revisit if:

- a required project dependency has no 26.04 support and no reasonable workaround;
- the release proves unstable on this generation of Intel hardware;
- a genuine hard version requirement emerges, in which case *Requires* must be updated and this ADR
  superseded.

The download script re-verifies the pinned checksum against upstream on every run, so a stale pin
surfaces as a hard failure rather than a silent drift.
