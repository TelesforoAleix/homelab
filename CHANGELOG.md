# Changelog

This project uses this file for meaningful repository-level milestones rather than logging every commit.

## Unreleased

### Added

- Initial Home Lab repository bootstrap structure.
- Project governance and contributor rules.
- Initial ADR set based on pre-development planning.
- Guide, build-log, budget, architecture, and handover templates.
- Phase 01 brief, guide, ADRs (014 release, 015 disk layout, 016 network link), and
  install/verification scripts. The installation itself has not yet been performed.
- Phase 01 brief ratified by Project Planning (2026-09-08) with six amendments, reconciled across
  the brief, all three ADRs, the guide and project documentation. Remaining Phase 00 hardware
  validation is now Phase 01 Part A rather than a standalone phase.
- **Phase 01 complete.** Ubuntu Server 26.04.1 LTS installed on the reference node, validated by
  live output including unattended power-loss recovery. Guide corrected five times by using it;
  boot time reduced from ~145s to 23s by fixing a failed `systemd-networkd-wait-online` unit.
- Phase 01 Part A hardware identification recorded. Resolves two unknowns open since bootstrap: RAM
  layout (1 x 8 GB, one slot free) and wireless adapter (Intel Wireless-AC 8260). Adds a firmware
  task to enable CPU virtualization, found disabled. No software installed or marked as tested.

### Changed

- Repository bootstrap moved into Phase 00 so implementation history can be documented from the beginning.
