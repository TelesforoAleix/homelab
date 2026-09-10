# Publication security review — 2026-09-10

**Question asked:** does publishing this repository, and publishing a second public repository
alongside it, create a security problem for the reference node?

**Short answer: the disclosed configuration is not the risk. The repository's own integrity is.**

The node has no public IP, no port bound to a routable address, and SSH that refuses passwords. Every
weakness this repository documents requires network access to exploit, and the repository does not
provide that. What the repository *does* provide is **fourteen scripts the owner runs with `sudo` on
the node** — and until today, nothing verified that those scripts were the ones the owner wrote.

## Method

Node state was verified live rather than read from documentation. Repository settings were read from
the GitHub API. Two of the reviewer's own intermediate readings were wrong and were corrected before
they reached a conclusion; both are recorded in §5, because a review that hides its own false starts
is teaching the wrong lesson.

## 1. Finding — repository integrity (highest, and specific to being public)

| Control | State before this review |
|---|---|
| Branch protection on `main` | **None.** API returned `Branch not protected` |
| Commit signing | **None.** 20 of 20 sampled commits unsigned; `gpg` not installed |
| GitHub Actions | **Enabled**, with no workflows present |
| Collaborators | One — the owner, admin |
| Deploy keys / webhooks | **0 / 0** |

**The attack:** an attacker who obtains the GitHub account modifies `scripts/server/install-*.sh`.
The owner pulls, runs it with `sudo`, and the attacker has root on a machine with no console.
Publication raises this risk because it makes the repository discoverable and pull-requestable.

Actions being enabled with no workflows is a second path: a pushed workflow runs with a repository
token and a runner, and nothing here needs that capability.

Phase 04 declined branch protection and signing deliberately, with the reasoning recorded in
`docs/reference/git-workflow.md`. **That decision was correct when it was made and is not correct
now** — it was taken when the repository was new and carried documentation. It now carries
privileged install scripts at a public URL.

## 2. Finding — SSH reachable from the whole LAN, no firewall

Verified on the node:

```text
0.0.0.0:22      [::]:22        <- all interfaces, not tailnet-only
wlp1s0 192.168.1.57/21         <- home Wi-Fi
ufw installed, not active
```

Any device on the home network — an IoT device, a guest's phone, a compromised laptop — can reach
SSH. This is **exposure, not vulnerability**: authentication is public-key only, with passwords,
keyboard-interactive and root login all refused (ADR-018).

Publishing `192.168.1.57` tells a LAN-adjacent attacker where to look. That is a small addition to
what a port scan would tell them anyway.

**Not verified, and it matters more than anything else here:** whether the home router forwards any
port to the node. If port 22 is forwarded, this finding changes from LAN exposure to internet-facing
SSH and becomes the top item. The router cannot be inspected from the repository.

## 3. Finding — the published weakness inventory

This repository accurately documents: no firewall, Tailscale node key expiry disabled, `aleix`
root-equivalent through the `docker` group, one SSH key with no backup, no encryption at rest,
asymmetric IPv6 forwarding, and the exact version of every installed component.

That is a map of the node's weaknesses, published deliberately.

**No redaction is recommended.** The teaching purpose is the point of the project, every item
requires network access the repository does not grant, and the honest fix is to close the items —
Phase 18 for backup and encryption, Phase 13 for firewalling and node key expiry. Hiding them would
substitute obscurity for the controls that are actually planned.

## 4. Cleared

| Item | Verdict |
|---|---|
| Tailnet addresses `100.71.62.71`, `100.69.244.33` | **Fine.** CGNAT; routable only inside the tailnet. Knowing them grants nothing |
| **Tailnet name** | **Clean.** Only `CHANGE-ME.ts.net` appears. This is the network identifier that would actually matter |
| Wi-Fi SSID and passphrase | **Absent.** Only discussion of them, never values |
| 64-character hex strings | SHA-256 checksums of the Ubuntu ISO (ADR-014). Correct to publish |
| `/home/aleix/` paths | Username disclosure. Low value against key-only SSH |
| Secret scanning / push protection | **Already enabled** by GitHub for this public repository |
| Deploy keys, webhooks, extra collaborators | **None** |
| The second public repository | **Clean.** One browser-side JavaScript file, nothing privileged, no credentials, no private URLs |

## 5. Reviewer errors, recorded

Two intermediate readings in this review were wrong. Both were caught before they reached a
conclusion, and both are the project's familiar failure shape.

1. **Three invalid validations of branch protection**, recorded in §6. Each would have reported
   a result it could not support.

2. **"Three SSH signing keys are registered."** They are not. `gh api /user/ssh_signing_keys`
   returned a **404 error object**, and counting its length counted the error's three JSON fields —
   `message`, `documentation_url`, `status`. The token lacks the scope to read signing keys, so
   their status is **UNKNOWN**, which is what this review reports.

3. **"Neither scanner detects a Telegram bot token."** Corrected the same day. That rested on a test
   token whose auth segment was 34 characters instead of 35, so `gitleaks` correctly declined a
   malformed token and the malformed token was read as a scanner defect. `scan-history.sh` genuinely
   had no Telegram class and now does.

**The generalisable lesson:** a positive control validates the detector. Nothing was validating the
fixture, and in both cases the fixture was what was wrong. A confident negative from a bad input is
indistinguishable from a finding.

## 6. Controls applied today

| Control | Rationale |
|---|---|
| Branch protection on `main`: force pushes blocked | History cannot be rewritten under the owner, including by a stolen token |
| Branch protection on `main`: deletion blocked | The branch cannot be removed |
| Enforced on administrators | A control an admin silently bypasses is not a control. Disabling it is a deliberate, visible act |
| Pull requests **not** required | The owner is the sole maintainer; a self-approved review is theatre, and requiring one would break the documented `feature/*` → `--no-ff` workflow for no gain |

### The control was proved, and it took four attempts

Branch protection was **verified by attempting a violation**, not by reading the setting back. The
first three attempts were invalid, and each looked like a pass:

| # | Attempt | Why it proved nothing |
|---|---|---|
| 1 | `git push --dry-run --force` | `--dry-run` never triggers the server-side hook. Exit 0 meant "the client thinks it could", not "the server would allow it" |
| 2 | Force-push `main` to its own current value | Git short-circuited with `Everything up-to-date` and sent no pack. The hook never ran |
| 3 | Force-push a descendant commit onto a protected canary | A **fast-forward**. `--force` was inert, so the block under test was never engaged. It succeeded, which looked like the control failing |
| 4 | Rewind a protected canary to an **ancestor** | A genuine non-fast-forward. **Rejected** |

The passing evidence:

```text
POSITIVE CONTROL  (protected branch, non-fast-forward rewind)
  remote: error: GH006: Protected branch update failed for refs/heads/...
  remote: - Cannot force-push to this branch
  ! [remote rejected] ... (protected branch hook declined)
  branch did NOT move

NEGATIVE CONTROL  (identical rewind, unprotected branch)
  + e03063a...b514682 ... (forced update)
  branch DID move
```

**The negative control is what makes the positive one mean anything.** Without it, a rejection
caused by a malformed refspec is indistinguishable from a rejection caused by the control. Attempt 3
in particular would have been reported as "protection is not working" had it not been re-examined.

Both canary branches were deleted afterwards and the remote's branch list was confirmed unchanged.

## 7. Recommended, not applied

- **Verify the router forwards no port to the node** (§2). Highest-value unverified item.
- **Commit signing.** The correct mitigation for §1's attack, because it lets the owner confirm a
  script came from them before running it with `sudo`. Requires a signing key registered with
  GitHub, which needs a token scope this session does not have.
- **Disable GitHub Actions** while no workflow exists. Phase 04 declined CI; leaving the capability
  enabled keeps a path that nothing uses.
- **Verify before running.** No repository control replaces reading a privileged script before
  executing it. This is the control that does not depend on anyone else's infrastructure.
