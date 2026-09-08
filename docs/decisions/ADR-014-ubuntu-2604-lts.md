# ADR-014: Pin the reference build to Ubuntu Server 26.04.1 LTS

- **Status:** Accepted
- **Date:** 2026-09-08
- **Supersedes:** none (refines ADR-003, which chose "Ubuntu Server LTS" without naming a release)
- **Superseded by:** none

## Context

ADR-003 committed the project to Ubuntu Server LTS but deliberately did not pin a release. Phase 01
must install a specific image, so the release has to be chosen and recorded.

Two LTS releases were in standard support when this decision was taken (verified 2026-09-08 against
`releases.ubuntu.com`):

| Release | Codename | Released | Standard support ends |
|---|---|---|---|
| 26.04.1 LTS | Resolute Raccoon | 2026-04-23 | April 2031 |
| 24.04.4 LTS | Noble Numbat | 2024-04 | April 2029 |

The reference node is intended to run continuously for years, and reinstalling it is disruptive, so
the support horizon carries real weight.

The standard argument *against* adopting the newest LTS is that third-party APT repositories lag the
new codename. For this project that argument is concrete rather than theoretical: Phase 03 needs
Tailscale and Phase 05 needs Docker, and neither can be installed from a repository that has not yet
published for the release.

That risk was therefore measured rather than assumed:

- Docker's Ubuntu repository publishes a `resolute` distribution.
- `https://pkgs.tailscale.com/stable/ubuntu/resolute.tailscale-keyring.list` returns HTTP 200.

Both were checked on 2026-09-08. The blocking risk does not exist.

## Decision

Install **Ubuntu Server 26.04.1 LTS (amd64)** on the reference node.

- Image: `ubuntu-26.04.1-live-server-amd64.iso`
- SHA256: `cc8a95cde20f6ced61a322420de00f10cc3c90ced545daa46cb9c1a117f1d927`

The `.1` point release is chosen over the original `26.04` media because a point release rolls
roughly four months of fixes and updated hardware enablement into the installer itself, which
matters when installing onto ten-year-old hardware.

## Alternatives considered

- **Ubuntu 24.04.4 LTS.** The most mature option, with the largest body of existing tutorials and
  troubleshooting answers — a genuine benefit for a learning-first project. Rejected because it
  surrenders two years of support life on a machine meant to stay in service, and because the
  maturity advantage is smaller once the two dependencies that actually matter were confirmed to
  support 26.04.
- **Ubuntu 25.10 (interim).** Rejected: nine months of support would force a reinstall or release
  upgrade cycle onto an always-on node for no benefit.
- **A different distribution.** Out of scope; settled by ADR-003.

## Consequences

- Support runway to April 2031, extendable to 2036 via Ubuntu Pro (free for personal use on up to
  five machines) if that is ever wanted.
- Fewer community answers exist for a release this young. When a problem is hit, the primary sources
  are official Ubuntu documentation and upstream project documentation rather than blog posts.
- If some future third-party repository has no `resolute` build, the fallbacks are the upstream
  generic installation method or deliberately pinning that vendor's `noble` repository. Either is
  acceptable, but it must be recorded in the build log as a problem rather than quietly worked around.
- All guides in this repository are written and tested against 26.04.1 unless stated otherwise.

## Validation / revisit trigger

Revisit if a required project dependency has no 26.04 support and no reasonable workaround, or if
the release proves unstable on this generation of Intel hardware.
