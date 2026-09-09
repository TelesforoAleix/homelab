# Cost Ledger

Track actual reference-build costs first. Add rough reproduction estimates only when researched for the relevant guide.

## Actual reference-build spending

| Date | Item | Category | One-time / recurring / usage | Actual DKK | EUR equivalent | Notes |
|---|---|---|---|---:|---:|---|
| 2026-09 | Lenovo ThinkCentre M700 Tiny | Hardware | One-time | 700 | ~94 | Used; canonical orchestration node |
| 2026-09-08 | DisplayPort→HDMI cable | Hardware | One-time | 199 | ~27 | Needed to attach a monitor for installation. The M700 Tiny outputs DisplayPort; most monitors take HDMI. |
| | **Running total** | | | **899** | **~121** | |

### Phase 01 — Ubuntu Server

Ubuntu Server is free and the installation reused existing hardware, but the phase was **not**
zero-cost: attaching a monitor required a DisplayPort→HDMI cable.

This is worth recording precisely because it is the kind of cost that gets forgotten — an accessory
needed to do the work rather than a component of the machine. Anyone reproducing this build on an
M700 Tiny with an HDMI monitor will face the same purchase.

| Date | Item | Category | One-time / recurring / usage | Actual DKK | EUR equivalent | Notes |
|---|---|---|---|---:|---:|---|
| 2026-09-08 | USB flash drive for installer | Hardware | One-time | **0** | **0** | None — reused an existing stick |
| 2026-09-08 | RAM upgrade | Hardware | One-time | **0** | **0** | **Not required.** Part A confirmed 1 × 8 GB with a free slot; 8 GB is sufficient for Phase 01. |

**Phase 01 actual spend: 199 DKK**, entirely the DisplayPort→HDMI cable. Ubuntu Server itself is
free, and no subscription or usage-based cost was introduced.
| 2026-09-08 | RAM upgrade | Hardware | One-time | **0** | **0** | **Not required.** Part A confirmed 1 × 8 GB with a free slot; 8 GB is sufficient for Phase 01. Upgrade to 16 GB deferred until real services justify it. |

### Phase 03 — Remote Access

**Phase 03 actual spend: 0 DKK.** Recorded explicitly rather than omitted, because "no cost" is a
finding and an absent row is an oversight.

| Date | Item | Category | One-time / recurring / usage | Actual DKK | EUR equivalent | Notes |
|---|---|---|---|---:|---:|---|
| 2026-09-09 | Tailscale | Service | Recurring | **0** | **0** | Personal plan. Covers this tailnet, MagicDNS, and disabling node key expiry — the two features Phase 03 depends on (ADR-019). Verified at implementation, as ADR-005 required. |
| 2026-09-09 | SSH keys, OpenSSH, VS Code Remote SSH | Software | One-time | **0** | **0** | All already-owned or free software. |

Revisit if the tailnet outgrows the Personal plan's limits, or if a feature Home Lab depends on
moves behind a paid tier (ADR-019).

**Note on the DisplayPort→HDMI cable.** The 199 DKK cable bought in Phase 01 became redundant in
Phase 03 Part F, when the monitor was removed. It is not re-recorded here and the running total is
unchanged — it was genuinely spent, and it was genuinely needed to install the machine. But anyone
reproducing this build who installs headless from the start may not need it at all.

## Existing subscriptions used by the project

These should be recorded as costs even when they pre-date Home Lab. The exact subscription prices have not yet been supplied by the owner; record them in the phase that first depends on them (Phase 06, AI CLI access).

| Service | Category | Billing model | Actual cost | Project-specific incremental cost | Notes |
|---|---|---|---|---|---|
| ChatGPT subscription | AI | Recurring | TBD | TBD | Intended for Codex CLI where officially supported |
| Claude subscription | AI | Recurring | TBD | TBD | Intended for Claude Code CLI where officially supported |

## Usage-based services

None recorded yet.

When APIs/gateways are introduced, record provider/model, billing unit, token/input/output costs where relevant, usage period, and actual project spend.

## EUR conversion basis

The Danish krone is pegged to the euro within a narrow band around **7.46 DKK/EUR**. EUR figures in
this ledger are converted at that rate and rounded, not taken from transaction records. They are
indicative; the DKK column is the actual paid amount.

## Accounting rules

- Use actual paid price for the reference build.
- Do not label an existing subscription as "free" simply because it was already being paid for.
- If EUR values are estimates, record the conversion basis/date where useful.
- Separate one-time, recurring, and usage-based costs.
- Keep reproduction estimates visibly separate from actual spend.
