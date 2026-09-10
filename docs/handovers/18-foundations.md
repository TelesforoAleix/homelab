# Phase 18 Brief — Foundations

- **Phase:** 18 — Foundations
- **Written:** 2026-09-10
- **Status:** Brief, committed before implementation per ADR-017
- **Predecessor:** Phase 09 — Model Executor (`09-model-executor-handover.md`, addressed to
  "the foundations phase")

## 0. Governance note

### 0.1 A new number, not a renumbering

Phase 18 is added rather than inserted, per the roadmap rule that phase numbers stay stable while
running order remains flexible. It is the fourth time this project has run phases out of numeric
order (03 before 02; voice moved 09 → 17).

The Phase 09 handover was explicitly addressed to "the **foundations** phase — backup, plus the
ADR-015 encryption decision". This is that phase, and it also absorbs two debts Phase 03 created
that Phase 13 inherited but which should not wait for a full hardening phase.

**Phase 13 remains the dedicated hardening phase.** Phase 18 is narrower and different in kind: it
is about **recoverability**, not defence. Firewall, `fail2ban`, Tailscale ACLs, node-key expiry and
rootless Docker all stay with Phase 13.

### 0.2 What this phase inherits from 2026-09-10's architecture decisions

Four ADRs were accepted the day this brief was written and are carried in per ADR-017: ADR-026
(multi-provider model access), ADR-027 (the agent contract), ADR-028 (the project contract) and
ADR-029 (repository topology).

**None of them change what Phase 18 does.** They are recorded here because ADR-017 requires
cross-phase decisions to be carried into the next brief rather than discovered later, and because
one of them raises this phase's stakes: ADR-029 confirms that a private knowledge base is coming to
this node, which is what makes the ADR-015 decision urgent rather than theoretical.

### 0.3 The order inside this phase is load-bearing

**Backup first. Prove the restore. Only then decide and execute encryption.**

This is not sequencing preference. If the ADR-015 decision comes out as "encrypt the root
filesystem", executing it means a reinstall — and a reinstall is safe only once a restore has
actually been performed. Doing encryption first would put at risk exactly the state this phase
exists to protect.

## 1. Purpose

The node has accumulated enough that it is expensive to rebuild — two OAuth credentials, a bot
token, a polkit grant, three service accounts, a working service stack and a per-deployment Telegram
allowlist — and it **has no backup of any kind**. Phase 04 gave the *repository* an offsite copy. It
did nothing for the machine.

At the same time, Phase 10 will put a private knowledge base on this node, which ends the premise
ADR-015 was accepted on. That decision cannot be deferred past Phase 10 because converting an
unencrypted root filesystem afterwards generally means a reinstall.

### 1.0 Correction, 2026-09-10: the node has a console after all

**The premise this brief was written on was wrong, and the correction improves every option below.**

Phase 03 recorded the console as *removed* and `project-state.md` says `Console: None`. Verified on
the node today:

```text
card0-DP-1..3, card0-HDMI-A-1..3   present, status: disconnected
getty@tty1                         enabled AND active
usbhid                             present
```

The machine is in the owner's room and a monitor and keyboard are available. **The console is
unplugged, not absent** — a login prompt is already running and a USB keyboard is picked up on
plug-in. Attaching one is a walk across a room, not a rebuild.

**What this changes:**

1. **Lockout stops being unrecoverable.** ADR-020's checklist is still correct practice, but its
   stated consequence — that a mistake strands a machine nobody can reach — does not hold. The
   phrase "the reference node has no console" should read "has no *attached* console".
2. **The second SSH recovery path (§4.1) drops in priority.** The console *is* a recovery path, and
   a better one than a second key: it survives network, firewall, SSH and Tailscale failure alike.
3. **Two encryption options come back**, and §6.1 is amended accordingly.

### 1.1 This phase is lockout-class throughout

Almost everything in scope is on the ADR-020 list: bootloader, disk layout, authentication, and the
admin account. **The node has no console** — monitor, keyboard and cable were physically removed in
Phase 03, and all DRM connectors report `disconnected`.

`docs/standards/safe-changes-headless.md` applies to every step. Classifying the change is the
control; the checklist only helps once the classification has happened.

This is the most dangerous phase since Phase 03, and unlike Phase 03 there is currently no second
way in if it goes wrong. Establishing that second way in is itself part of the scope, which means
**it should be done first, before anything riskier**.

## 2. Starting state

Verified on the node 2026-09-10 by direct read-only inspection, not copied from documentation.

| Fact | Value | How |
|---|---|---|
| OS | Ubuntu 26.04.1 LTS | `hostnamectl` |
| Uptime at check | 15h 42m | `uptime` |
| Health | `running`, **no failed units** | `systemctl is-system-running`, `systemctl --failed` |
| Services | `homelab-telegram-bot.service` **active**; `homelab-model-helper.socket` **active** | `systemctl is-active` |
| Root filesystem | `/dev/mapper/ubuntu--vg-ubuntu--lv`, 232 G, 8.9 G used, 212 G available (5%) | `df -h /` |
| Encryption at rest | **None.** `sda3` → `LVM2_member` → `ubuntu--vg-ubuntu--lv` `ext4`. No `crypto_LUKS` layer anywhere | `lsblk -o NAME,FSTYPE,TYPE,MOUNTPOINT` |
| Volume group headroom | **None.** `sda3` is 235.4 G and the single LV is 235.4 G | `lsblk /dev/sda3` |
| Memory | 7.1 Gi total, 6.5 Gi available | `free -h` |
| Secure Boot | **enabled** | `mokutil --sb-state` |
| Listeners | **6**, unchanged | `ss -tln` |
| `eno1` | Present, state **DOWN**, `NO-CARRIER` — no cable attached | `ip -br link show eno1` |

### 2.1 The finding that reshapes this phase: the TPM is version 1.2

`/dev/tpm0` exists, which initially looks like good news for encrypted-but-unattended boot. It is
not. The device is **TPM 1.2**:

```text
/sys/class/tpm/tpm0/tpm_version_major   -> 1
PCR banks present                       -> pcr-sha1 only   (2.0 would expose pcr-sha256)
TPM 1.2-only attributes present         -> pubek, owned, temp_deactivated, durations, timeouts
systemd-cryptenroll --tpm2-device=list  -> "TPM2 support is not installed."
```

The first three are hardware evidence and are conclusive. The fourth is about tooling rather than
hardware and is merely consistent — it is recorded that way rather than as proof.

**Why this matters:** `systemd-cryptenroll --tpm2-device=` requires **TPM 2.0**. The standard route
to a LUKS volume that unlocks itself at boot without a console is therefore **not available on this
machine as it currently stands**. That removes the option that would otherwise have made "encrypt
the root filesystem" compatible with a headless node, and it is why §6 below is a genuine decision
rather than a formality.

## 3. Learning objectives

By the end of this phase the owner should be able to explain:

1. What a backup of a *service node* actually has to contain to be worth having, and why "copy the
   home directory" is not it — unit files, allowlists, polkit rules, and account UIDs matter.
2. Why a backup that has never been restored is a hypothesis, not a backup.
3. How LUKS full-disk encryption works well enough to know **what it protects against and what it
   does not** — specifically that it protects a powered-off disk, not a running machine.
4. Why unattended boot and full-disk encryption are in tension, and the three ways that tension is
   normally resolved (a human types a passphrase, a TPM releases the key, or a network service
   releases it).
5. What a TPM is for in this context, and why the 1.2 → 2.0 distinction is decisive rather than
   incremental.
6. What recovery options exist for a machine with no console, and why one SSH key is a single point
   of failure rather than a credential.

## 4. Functional objectives

1. **A second way into the machine exists**, established and tested *before* any riskier change.
2. **A backup exists**, covering what §3.1 identifies as necessary.
3. **A restore has actually been performed and proved.** Not a backup job reporting success.
4. **The ADR-015 decision is made, recorded as an ADR, and executed** — including if the decision is
   to change nothing, which must then be a decision rather than an omission.
5. **The `eno1` question is resolved** — either a cable is attached and the interface is configured
   as a second path, or it is deliberately left down with the reason recorded.

## 5. Decisions already fixed

Not reopened by this phase:

- **ADR-018** — SSH access policy: key-only, `PermitRootLogin no`. A second key does not change the
  policy; it adds a key under it.
- **ADR-019** — tailnet configuration, including node key expiry deliberately disabled. Phase 13
  revisits that, not this phase.
- **ADR-020** — change safety on a console-less node. **Binding on every step here.**
- **ADR-021** — the repository is public. Anything recorded in this phase is published.
- **ADR-022** — `aleix` is in the `docker` group and this is root-equivalent. A backup process must
  not quietly become a second root-equivalent path.
- **ADR-026 / 027 / 028 / 029** — carried in per §0.2; not implemented here.

**ADR-015 is explicitly *not* on this list.** Revisiting it is the point.

## 6. Decisions still open

### 6.1 The ADR-015 encryption decision

The real question is not "should the disk be encrypted" but **"what is encryption protecting against
here, and what does it cost on a machine with no console?"**

The threat FDE addresses is a powered-off disk in someone else's hands: theft, disposal, or an RMA.
It does nothing for a running machine, and this node runs continuously in the owner's home.

Options, with their actual constraints on **this** hardware:

| # | Option | Unattended boot survives? | Verdict going in |
|---|---|---|---|
| A | Stay unencrypted; constrain what the node stores | Yes | Honest fallback. Requires saying what the node may not hold |
| B | Full-disk LUKS, passphrase typed at boot | No, but | **Viable** (§1.0). Cost: a power cut leaves the node down until someone types the passphrase. The machine is in the owner's room, so that is minutes, not days |
| C | Full-disk LUKS, TPM-released key | Yes, **but** | Needs TPM 2.0; this is 1.2. Reaching 2.0 means a firmware visit — **which is now cheap** (§1.0). Check whether the M700 offers Intel PTT |
| D | Network-bound unlock (Clevis/Tang) | Yes, **but** | Needs a second always-on machine that does not exist, and its failure mode is an unbootable node |
| E | **Encrypt a separate data volume, unlocked after boot** | Yes | Strongest fit — see below |
| F | Filesystem-level encryption (`fscrypt`) on chosen directories | Yes | Same key-bootstrap problem as C/D, weaker protection, more moving parts |

**Option E deserves the most attention.** It separates the two requirements that conflict:

- the **OS** must boot unattended to a reachable state — today it does so in 24.4 s;
- the **knowledge content and its indexes** must be encrypted at rest.

Those need not be the same volume. The OS stays as it is; brain content and derived indexes live on
a LUKS volume unlocked after boot, over SSH. The cost is explicit and acceptable: **after every
reboot the knowledge service is down until the owner unlocks it.** The node reboots rarely.

Two obstacles must be faced honestly if E is chosen:

1. **The volume group has no free extents** (§2). A separate LV requires either shrinking the root
   LV — offline, and genuinely risky on a console-less machine — or **adding a second disk**.
   Whether the M700 Tiny has a free M.2 slot or drive bay is a *physical* question that cannot be
   answered over SSH.
2. **The two OAuth credentials stay on the unencrypted root** under E, in `/home/aleix`. They are
   the highest-value secrets on the machine. Either `/home` moves onto the encrypted volume — which
   reintroduces a boot-order problem for `homelab-model-helper` — or the decision explicitly accepts
   that they remain unencrypted, and says so.

**Option C's price was overstated and is now corrected.** Reaching TPM 2.0 means enabling Intel PTT
in firmware, or a Lenovo TPM firmware update. This brief originally called that "a day of physical
work" on the premise that the console was gone. Per §1.0 it is a firmware visit to a machine in the
owner's room. **The first thing this phase should do is look in the BIOS and find out whether PTT is
offered**, because if it is, Option C — encrypted root with unattended boot — becomes available and
is strictly better than B.

**This phase must produce an ADR either way**, superseding or explicitly reaffirming ADR-015.
Reaffirming is a valid outcome; silently leaving it is not.

### 6.2 What "a second way in" should be

Candidates, to be decided in-phase: a second Ed25519 key held on separate physical media; a
recovery key enrolled with a different passphrase; Tailscale SSH as a parallel path (declined in
ADR-019, worth re-examining here with a narrower question); or a console reattached permanently.

The requirement is that it **does not share a failure mode with the existing key**. A second key in
the same keychain on the same laptop is not a second way in.

### 6.3 What the backup actually covers, and where it goes

Open: whether the target is another local disk, removable media, a remote host, or an object store;
whether it is file-level or image-level; and how the two OAuth credentials and the bot token are
handled, given ADR-021 makes this repository public and those must never appear in it.

## 7. Implementation scope

Expected shape rather than exact commands, and in this order:

1. **The second way in**, established and tested from a cold state, before anything else.
2. **Inventory what must survive.** Unit files, `/etc` configuration, polkit rule, allowlists,
   service account UIDs and group membership, the model-helper config and its call-count state,
   the Telegram token, and both OAuth credentials.
3. **Backup mechanism**, chosen for comprehensibility over sophistication per ADR-006.
4. **A real restore**, to prove it. Ideally to different media, so the restore is not merely reading
   back the same disk.
5. **The ADR-015 decision**, taken with the owner against §6.1, recorded as an ADR, then executed.
6. **`eno1`** resolved.

### 7.1 Not in scope

Firewall, `fail2ban`, Tailscale ACLs, node key expiry, rootless Docker, user-namespace remapping,
alerting on the bot, and the RAM upgrade. The first six are Phase 13. Alerting is worth its own
decision and is not recoverability. The RAM upgrade is physical and belongs with whichever phase
needs it.

## 8. Validation / tests

Every check follows the project's standing rule: **a check that cannot determine an answer reports
`UNKNOWN`, never a plausible-looking result**, and a detector that has only ever reported "clean" is
unvalidated.

1. **The second access path is proved by using it while the primary is deliberately unavailable** —
   not by confirming it exists.
2. **The restore is proved by restoring**, and by then asserting on the restored system that
   `id homelab-bot` is byte-identical, the polkit rule is present, and both services start.
3. **The backup is proved to be incomplete-proof**: deliberately omit a known file, run the
   verification, and confirm it **fails**. A backup verifier that has only ever passed is
   unvalidated.
4. **If encryption is implemented:** a full cold boot to a reachable state, timed against the
   current 24.4 s baseline, with the result recorded whether or not it is favourable.
5. **`ss -tln` still reports 6 listeners** and `systemd-analyze security homelab-telegram-bot`
   still reports 1.3 OK. Neither should change; if either does, something in this phase widened the
   attack surface and that must be explained rather than accepted.
6. **`systemctl is-system-running` reports `running` with no failed units** at phase close, per the
   Definition of Done.

## 9. Security considerations

- **A backup is a copy of every secret on the machine.** Wherever it lands inherits the security of
  the original. Both OAuth credentials, the bot token and the SSH host keys will be in it. Backup
  media is now a high-value target, and if the backup is not encrypted then encrypting the source
  disk achieves considerably less than it appears to.
- **A backup process must not become a second root-equivalent path.** If it runs as root or as a
  member of `docker`, then compromising the backup compromises the host. ADR-022's rule stands.
- **Restoring is a privileged, destructive operation** and must be treated as one under ADR-020.
- **This repository is public.** No key, passphrase, MAC address, backup target credential or Wi-Fi
  detail may be recorded in it. A new secret committed from here on is a disclosure, not a mistake
  that can be quietly amended.
### 9.1 Finding, recorded 2026-09-10: `scan-history.sh` had no Telegram bot token class

Discovered while validating the scanners before committing this brief, by planting a positive case
rather than trusting a "clean" result. **Closed the same day** — see the correction below, which is
part of the finding rather than a footnote to it.

| Scanner | Telegram bot token | Status |
|---|---|---|
| `scripts/macos/scan-history.sh` | **Was not detected** | **Fixed 2026-09-10.** A `Telegram bot tokens` class was added and validated in both directions |
| `gitleaks` 8.30.1, default ruleset | **Detected** | No gap. See the correction below |

**Why the gap existed:** `scan-history.sh` was written in Phase 04. The bot token arrived in
Phase 07. **The scanner predated the secret**, and nothing prompted a re-check when the secret was
introduced — so for three phases the repository's own gate was blind to the single credential this
project handles most often. Its catch-all high-entropy class did not cover it either: that requires
a 48-character run of `[A-Za-z0-9+/]`, and a Telegram token's longest such run is 34.

**This is the generalisable lesson, and it is not about Telegram:** *introducing a new class of
secret should trigger a re-validation of the scanner.* Nothing in the process does that today.
Phase 07 added a credential and no gate noticed.

#### The correction, recorded rather than tidied away

The first version of this finding also claimed gitleaks was blind to Telegram tokens. **That was
wrong.** The test token used to establish it had a 34-character auth segment; the real format is
**exactly 35**. gitleaks correctly declined to match a malformed token, and the malformed token was
then read as a scanner defect.

The error surfaced only because the *new* `scan-history.sh` check also failed its positive control —
using the same bad token. Two failing checks agreeing looked at first like confirmation of a real
gap. It was one bad fixture, used twice.

Retested with a correctly-formed token, against a GitHub PAT control in the same harness: gitleaks
**detects** it. `scan-history.sh` genuinely did not, and now does.

**The lesson is about the shape of the mistake**, and it belongs with the other nine instances: a
test fixture that does not match the real format produces a confident negative that looks exactly
like a finding. **A positive control validates the detector; nothing was validating the fixture.**
The reason this was caught at all is that the check was run in both directions — a detector that
only ever reports "clean" is unvalidated, and so is one that only ever reports a hit.

#### Validation performed

| Case | Expected | Result |
|---|---|---|
| Correctly-formed token planted in a fixture repository | CRITICAL, non-zero exit | `1 MATCHES -- CRITICAL`, `VERDICT: DO NOT PUBLISH`, exit 1 |
| The repository's real `token.example` placeholder | clean, zero exit | clean, exit 0 |
| The homelab repository itself | clean | clean |

**Why it mattered for this phase:** the repository is public (ADR-021), the token is live on the
node, and **Phase 18's backup will contain it**.

#### Still open, and not fixed here

`scan-history.sh` reports **one pre-existing critical false positive**: the systemd template
instance name `homelab-model-helper@probe.service` matches the email-address class. By the script's
own reasoning — *"a gate that is permanently red is a gate people wave through"* — this should be
adjudicated and allow-listed. It is pre-existing and outside this change's scope, but it should not
survive to the ADR-029 repository split.

- **Encryption changes what a lost node means, not what a compromised one means.** The brief should
  not let FDE be mistaken for protection against a running-system compromise.

## 10. Repository changes expected

- `docs/handovers/18-foundations.md` — this brief.
- `docs/handovers/18-foundations-handover.md` — the handover.
- `scripts/server/` — a backup script and a verification script; the verifier must be validated
  against a deliberately incomplete backup.
- `config/systemd/` — any timer or unit introduced.
- A new ADR for the ADR-015 outcome, and possibly one for the recovery path.
- `docs/reference/project-state.md`, `ROADMAP.md`, `CHANGELOG.md`.

## 11. Guide documentation required

`guide/18-foundations/README.md`, covering: what to back up on a service node and why; how to test a
restore; what FDE does and does not protect; why headless and encrypted are in tension; and what the
TPM 1.2 finding meant in practice. Written to the standard in `PROJECT.md` §7 — explain the
alternatives and the reasoning, not only the commands that worked.

## 12. Project documentation required

`project-state.md` starting-state table refreshed from live output; the "no backup of any kind" and
"no encryption at rest" risks closed or restated with their new shape; `docs/reference/hardware.md`
updated with the TPM finding, which is a durable hardware fact this project did not previously
record.

## 13. ADRs required / possible

- **Required:** the ADR-015 outcome — superseding or explicitly reaffirming it.
- **Likely:** the backup design, if it introduces a recurring cost or a new trust relationship.
- **Possible:** the recovery path, if it revisits ADR-019's decline of Tailscale SSH.

## 14. Costs

Expected new costs, to be recorded in the budget ledger per `PROJECT.md` §10:

- backup media or remote storage — likely the first recurring cost this phase introduces;
- possibly a second internal disk, if Option E is chosen and a slot exists;
- no new AI or subscription cost. ADR-026 anticipates metered model spending, but **not in this
  phase**.

## 15. Definition of Done

The project-wide checklist in `PROJECT.md` §12, applied literally item by item, plus:

- [ ] A restore has been **performed**, not simulated.
- [ ] The backup verifier has been proved to fail on an incomplete backup.
- [ ] The second access path has been used while the primary was unavailable.
- [ ] The ADR-015 decision exists as an ADR, whichever way it went.
- [ ] `id homelab-bot` is byte-identical to Phase 07.
- [ ] `ss -tln` reports 6 listeners; bot still 1.3 OK.
- [ ] Cold boot time recorded against the 24.4 s baseline, favourable or not.

## 16. Return handover requirements

The handover must state explicitly:

1. **Whether the node is now recoverable, and from what.** Disk failure, accidental deletion,
   theft, and total loss are different questions with different answers. Say which are covered.
2. **What the ADR-015 decision was and what it costs.** If encryption was declined, say what the
   node may therefore not store — because Phase 10 will otherwise store it.
3. **Whether `/home/aleix` and the two OAuth credentials are encrypted**, plainly, because every
   later phase will assume one answer or the other.
4. **What the recovery path is and how it was tested**, in enough detail that it can be used under
   stress by someone who has lost the primary key.
5. **The TPM 1.2 finding and its consequences**, so no later phase rediscovers it while planning
   TPM-based work.
6. **Whether the backup covers the knowledge base**, which does not yet exist on this node but will
   by Phase 10 — and whether derived indexes are deliberately excluded as regenerable.
