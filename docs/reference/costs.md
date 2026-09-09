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

## Phase 02 — Linux Fundamentals

**0 DKK.** Recorded as an explicit zero rather than omitted: an omitted cost is indistinguishable
from a forgotten one.

`tree`, `ncdu` and `ripgrep` all come from Ubuntu's own repositories (1,671 kB downloaded). No new
hardware, no subscription, no paid service. Reference-build running total unchanged at
**899 DKK (~121 EUR)**.

## Phase 04 — Git & GitHub Fundamentals

**0 DKK.** Recorded as an explicit zero.

GitHub public repositories are free — but so are private ones, so **cost did not drive the
visibility decision** and this ledger should not let a future reader infer a constraint that did not
exist. The choice was made on the project's purpose, not its budget (ADR-021).

`gitleaks` 8.30.1 was installed on the MacBook via Homebrew; free and open source. No new hardware,
no subscription, no paid service. Reference-build running total unchanged at **899 DKK (~121 EUR)**.

## Phase 05 — Docker & Docker Compose

**0 DKK.** Recorded explicitly.

Docker Engine 29.8.0, Docker Compose v5.5.1, Buildx and containerd 2.3.5 were installed from
Docker's official apt repository. All are free and open source. No new hardware, subscription, paid
service, hosted account, or usage-based dependency was introduced.

Reference-build running total unchanged at **899 DKK (~121 EUR)**.

## Phase 06 — AI CLI Access

**0 DKK incremental project spend.** Claude Code `2.1.236`, Codex CLI `0.153.4`, and Ubuntu's
`bubblewrap` package were installed without a licence or package charge. No API key, usage credit,
or paid-overage path was enabled.

The phase uses two subscriptions that the owner already paid for before Home Lab. They are recorded
below as recurring project dependencies, but do not change the one-time reference-build total of
**899 DKK (~121 EUR)**.

## Existing subscriptions used by the project

These are costs even though they pre-date Home Lab. The owner supplied the actual billed EUR amounts
on 2026-09-09; DKK values are approximate conversions at the ledger's 7.46 DKK/EUR reference rate.

| Service | Category | Billing model | Actual cost | Project-specific incremental cost | Notes |
|---|---|---|---|---|---|
| ChatGPT subscription used for Codex | AI | Recurring | **23.00 EUR/month (~172 DKK/month)** | **0 DKK** | Existing subscription; owner did not supply the account's plan label. Codex reports `Logged in using ChatGPT`. |
| Claude Pro | AI | Recurring | **22.50 EUR/month (~168 DKK/month)** | **0 DKK** | Existing subscription; Claude reports subscription type `pro`. |
| **Combined existing AI subscriptions** | AI | Recurring | **45.50 EUR/month (~339 DKK/month)** | **0 DKK** | Finite subscription allowance, not an availability SLA. |

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
