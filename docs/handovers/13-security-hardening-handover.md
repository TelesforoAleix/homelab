# Phase 13 Handover — Security hardening

- **Phase:** 13 — Security hardening
- **Brief:** [`13-security-hardening.md`](13-security-hardening.md) (corrected during S1: §2, §4.2,
  §6.4, §8 row 6 — IPv6 `FORWARD` was already `DROP`; "every unit" means every service unit)
- **Executed:** 2026-09-12 (S1, S2) and 2026-09-13 (S3, S4)
- **Addressed to:** Phase 15.0 (model registry — next), Phase 23.0 (the endpoint), Phase 14 (backup
  and restore), and whoever next touches the firewall, a unit file, or the bot token
- **Guide:** [`guide/13-security-hardening/README.md`](../../guide/13-security-hardening/README.md)
  — the debt table with every outcome and its evidence; the three runbooks beside it

## Outcome

**Complete.** Twenty-seven inherited items walked one by one — closed, narrowed or declined, each
with an OBSERVED state and a written reason. Twenty rows of the brief's validation table; eighteen
OBSERVED, two PREDICTED and named below. No capability added; the node's documents now describe it
truthfully; a written baseline exists for every later unit.

## What the next phase inherits

### Phase 15.0 — model registry — by name

1. **The baseline your units meet on day one:**
   [`docs/standards/service-security-baseline.md`](../standards/service-security-baseline.md).
   `systemd-analyze security` ≤ 2.0 or a `# WHY` per finding in the unit file; own account; secrets
   by `LoadCredential=`; loopback + socket-table row. The score table in §1 is the measured normal.
   Two measured limits you would otherwise rediscover: `SystemCallFilter=@system-service` **kills
   the Claude CLI with SIGSYS** — never on a unit that spawns the AI CLIs; `RestrictAddressFamilies=AF_NETLINK`
   alone breaks anything calling `if_nametoindex()`.
2. **Where a paid API key lives:** `/etc/homelab-<service>/<name>`, `root:root 0600`,
   `LoadCredential=<name>:<path>`, and a row in ADR-046's table with the provider console where it is
   revoked — in the same commit as the unit. It is a *revocable* secret, so ADR-046's acceptance
   covers it. Optionally sealed like the bot token: `systemd-creds encrypt --with-key=tpm2
   --tpm2-pcrs=""` + `LoadCredentialEncrypted=` (`scripts/server/p13-s3.sh creds-encrypt` is the
   worked example). Read ADR-046's amendment first: the seal narrows a **pulled disk only**, adds a TPM
   dependency, and the plaintext in the password manager is the real backup.
3. **The account you run as:** your own system account, never `aleix` (ADR-047 says why the two
   exceptions are exceptions). If the registry must read the OAuth files, it goes *through the model
   helper's socket* like the bot does, not by running as `aleix`.
4. **The socket baseline is seven** (`sshd` ×2, `resolved` ×2, `tailscaled` ×2, Workbench
   `127.0.0.1:8765`). Your listener, if any, is the eighth row in `current-architecture.md`'s table,
   bound to loopback, reached through `ssh -L` on `homelab-workbench` or a new alias — never `homelab`.
   If it must be reached from another tailnet device directly, its port goes into
   `config/tailscale/acl.hujson` in the same commit.
5. **`systemd-creds` is available:** `systemd-analyze has-tpm2` → yes, all components; TPM 2.0
   (Intel PTT); Secure Boot on. Proved to load unattended across a reboot and a cord-pull.

### Phase 23.0 — the endpoint — by name

1. **ADR-047:** the Workbench keeps `User=aleix`; its boundary is the sandbox (`ProtectHome`, strict,
   no `AF_UNIX`, `NoNewPrivileges`). Your endpoint runs as **its own account** and reaches the
   Workbench **over loopback**; it needs no membership in `aleix`. If it needs the volume for its own
   state, that is ADR-047's trigger 3 — reopen the account question, do not add a group.
2. **The Tailscale ACL is the outer boundary:** `autogroup:member → homelab tcp:22` and nothing else.
   A listener that must be reachable from the MacBook without the tunnel gets its port added there
   (`"ip": ["tcp:22", "tcp:<port>"]`) in the commit that adds its socket-table row; applied by hand in
   the admin console; the console fallback and the recovery note are in `s2-runbook.md` step 7.
   Two things the ACL does not do: it does not filter tailscaled's PeerAPI port (36121/57273 —
   reachable to any peer with any grant; a bad negative test), and it has no `tests` block
   (`autogroup:member` is not a valid test source).
3. **If the endpoint is ever a container:** `DOCKER-USER` drops anything from `wlp1s0`/`eno1` and
   returns for `tailscale0`, `lo`, `docker0`, `br-+`. A published port is therefore reachable from
   the tailnet (subject to the ACL) and not from the LAN. Bind `127.0.0.1:port:port` anyway.
   **`apply-firewall.sh` resets ufw and erases the block — run `apply-docker-user-rules.sh` after it.**
4. **You owe a socket-table row and an ACL line**, or a sentence saying why neither.

### Phase 14 — backup and restore — by name

1. **New `/etc` paths this phase created or changed**, all now in `backup-node.sh` and
   `verify-node-backup.sh` (same commit `e9efc41`): `/etc/ssh/sshd_config.d/10-homelab-hardening.conf`
   (**and it had never been in the backup — nor had ufw's rule files**; both are now),
   `/etc/ufw/after.rules`, `/etc/ufw/after6.rules`, `/etc/ufw/user{,6}.rules`,
   `/etc/profile.d/homelab-console-timeout.sh`, `/etc/systemd/system/wifi-powersave-off.service`, the
   three `credential.conf` drop-ins, `/etc/homelab-telegram-bot/token.cred`.
2. **The bot token is no longer in the archive in usable form.** `token.cred` is TPM2-sealed and
   useless off this machine; the plaintext `token` no longer exists on the node; the **password
   manager is the real backup**. The restore runbook must say: re-create `/etc/homelab-telegram-bot/token`
   from the password manager (`root:root 0600`), then `p13-s3.sh creds-encrypt`, then shred — or
   `@BotFather /revoke` and a new token if the manager entry is missing. `verify-node-backup.sh` now
   **fails if the plaintext token is present**.
3. **The recovery SSH key** is at `homelab-backup/recovery-key/id_ed25519_homelab_recovery.age` on
   the card, next to the LUKS header backup; its `.pub` beside it. Its passphrase is in the password
   manager with the header's. The private half is never on the node or the MacBook; the verifier fails
   if it appears in an archive.
4. **The BIOS password exists** (not its value). A rebuilt node on this hardware needs it entered at
   the box to change boot order or boot from USB — the Phase 18.1 rescue-USB path now requires the
   password first. It is in the password manager only.
5. **A lesson to design around — the same-day backup overwrite.** `p13-s2.sh`'s first version wrote
   `<file>.bak-<date>` and a second round on the same day overwrote the first round's backup (harmless
   here because the first round had restored the original, but only by luck). Fixed: a backup is never
   overwritten within a day. The general form for your phase: **a verifier that passes against a backup
   taken minutes earlier proves less than it looks** — it proves the archive matches *now*, not that
   the thing you would need in a restore was captured *before* the change that broke it. Verify against
   the previous backup as well as the fresh one, or keep both.
6. **Restore must also re-apply what lives outside files:** the Tailscale ACL (admin console; the
   policy is in `config/tailscale/`), the BIOS settings, and — because the node's TPM is different on
   other hardware — the token seal (item 2).

### Whoever next touches the firewall, a unit, or the token

- Firewall: `apply-firewall.sh` then `apply-docker-user-rules.sh`, always, under
  `safe-changes-headless.md`; `iptables -S DOCKER-USER` shows eight rules before you stand down.
- A unit: the baseline standard, and `systemd-analyze security` recorded in the guide. `systemd-run`
  probes that are meant to fail take `--collect`.
- The token: `scripts/server/p13-s3.sh` (`creds-check`, `creds-encrypt`, `creds-shred`,
  `creds-undo`). A TPM change makes the bot silent at the next boot; `creds-undo` from the console
  is the recovery; the password manager is the source.

### Open risks — not to be inherited silently

- **Row 8's other-device negative is PREDICTED.** The tailnet has two devices, both the owner's;
  no device outside the allow list exists to test with. The positive half and a port-level negative
  (tcp/2222 times out where ufw alone would refuse) are OBSERVED.
- **Row 6's published-port LAN negative is PREDICTED.** The `DOCKER-USER` rules are OBSERVED present
  and persisted; the live test could not exercise them because the building Wi-Fi isolates clients —
  the MacBook's packet to `192.168.1.57:8080` got `No route to host` and the drop counter stayed 0.
  Corollary worth knowing: **no host of ours can reach the node on the LAN at all**, which also means
  the `homelab-lan` fallback alias has been dead for reasons beyond ufw.
- **The GitHub node key is still passphrase-less and account-level** (6.2b). Controls: ADR-046 row 6
  with its revocation path; an audit by title from the MacBook; the helper can no longer read it. If
  Phase 14 picks unattended push, 6.2(a) — a passphrase held by `ssh-agent` — is the recorded change.
- **Key expiry stays disabled** (declined, revisit if the machine leaves the home). **Rootless
  Docker declined** (nothing to protect; the first phase shipping a container decides).
  **`fail2ban` declined** (no passwords; inbound only from `tailscale0`).
- **The running machine is not protected** — ADR-046 §4, unchanged and restated: whoever has the
  running box has the running services and, if unlocked, the volume.
- **The model helper scores 3.8** with four written waivers; the syscall filter that would lower it
  kills the Claude CLI. A later phase that wants it bisects the group; this phase's budget was one
  round.

### Ground already covered

- ADR-046's three checks are a script (`scripts/server/security-audit.sh` blocks A and I) and were
  re-run; the check-2 pattern was corrected.
- `systemd-analyze security` for all six service units is in the guide; the baseline's table is the
  measured normal.
- The `# WHY` idiom now covers every waived directive in every project unit.
- The audit script and the three runbooks are re-runnable at any phase close.

## What was implemented

S2 (2026-09-12): sshd drop-in gains `AllowUsers aleix`, `MaxAuthTries 3`, `X11Forwarding no`,
`AllowAgentForwarding no`; `DOCKER-USER` block in ufw `after{,6}.rules` via
`apply-docker-user-rules.sh`; `/etc/profile.d/homelab-console-timeout.sh`;
`homelab-model-helper@.service` + `InaccessiblePaths=-/home/aleix/.ssh`, `SystemCallArchitectures=native`;
`wifi-powersave-off.service` bounded (`CAP_NET_ADMIN`, strict, `AF_NETLINK AF_UNIX AF_INET`);
`aleix` removed from `lxd`; recovery SSH key (node `authorized_keys` + card); Tailscale ACL.

S3 (2026-09-13): `token.cred` sealed to the TPM2, `credential.conf` on bot/notifier/watchdog,
plaintext shredded; BIOS supervisor password, Boot Order Lock, PXE off; console timeout proved on the
tty; a real reboot and a cord-pull power-cycle, both reported by the watchdog unattended.

S4: `docs/standards/service-security-baseline.md`; ADR-047; ADR-046 amended; backup scripts;
project docs.

## Final architecture / state

Relative to the 18.2 close: no new account, no new listening socket (**seven, unchanged, re-measured
at close**), no new package, no new subscription. One fewer group on `aleix` (`lxd`). One plaintext
secret fewer on disk (the bot token), one sealed blob more. Two `authorized_keys` lines. Four sshd
directives. Eight `DOCKER-USER` rules. One `profile.d` file. Two hardened units, three drop-ins. A
Tailscale policy. A BIOS password. See `current-architecture.md` §"The security boundary".

## Validation performed

Brief §8, all rows. OBSERVED unless stated; evidence verbatim in the guide.

| # | Test | Result |
|---|---|---|
| 1 | `systemd-analyze security` every service unit | bot 1.3, watchdog 1.3, notify@ 1.3, Workbench 1.3, helper 3.8 (waivers in unit), wifi 5.1 (waivers in unit) |
| 2 | `sudo ss -tlnp` | Seven, identical to 18.2's list, at S1, S2 close and S4 close |
| 3 | `sshd -T` | `no` / `no` / `aleix` / `3` / `no`, plus `x11forwarding no`, `allowagentforwarding no` |
| 4 | Two aliases concurrently | rc 0 with the tunnel open, HTTP 200 — after sshd, after the ACL, after the power-cycle |
| 5 | Second key | rc 0 with `-o IdentityAgent=none`; private half `age`-encrypted on the card, re-derived and matched; absent from `~/.ssh` |
| 6 | `DOCKER-USER`; `ip6tables -P FORWARD` | Eight rules v4+v6; `DROP`. **Negative half PREDICTED** (LAN unreachable at L2) |
| 7 | `nc <LAN IP> 22` from a non-tailnet path | `No route to host` — closed (and unreachable) |
| 8 | ACL | Owner device: ssh rc 0, tunnel 200; tcp/2222 times out. **Other device: PREDICTED** |
| 9 | Console TMOUT | tty session ended after 900 s; idle SSH session alive |
| 10 | BIOS | Setup asks for the password; boot proceeds without it |
| 11 | Power-cycle | Booted by itself after a cord pull; watchdog reported locked; unlock; Workbench active |
| 12 | `LoadCredentialEncrypted`; reboot; `/status` | Present on three units; bot answered at uptime 1 min with no manual step |
| 13 | ADR-046 checks 1–3 | PASS / PASS (corrected pattern) / PASS (six rows) |
| 14 | GitHub key hygiene | `1`; `600`; title present once (`gh api user/keys`) |
| 15 | unattended-upgrades | `Automatic-Reboot` absent (default false); `enabled` |
| 16 | `docker system df` | Zero after the 2b probe; `data-root` `/var/lib/docker` |
| 17 | Lock/unlock cycle | Exercised twice by real boots: Workbench inactive while locked, active after unlock, no alert |
| 18 | Closing check | *(S4 close — see §Closing check)* |
| 19 | Backup + verify | *(S4 close — see §Closing check)* |
| 20 | `# WHY` per changed directive | Read: helper (4), wifi (3), Workbench (`User=` → ADR-047), credential drop-ins (header) |

### Closing check (S4)

*Filled from the owner's paste at close.*

## Files changed

New: `docs/standards/service-security-baseline.md`, `docs/decisions/ADR-047-workbench-account-boundary.md`,
`docs/handovers/13-security-hardening-handover.md`, `guide/13-security-hardening/{README,s2-runbook,s3-runbook}.md`,
`scripts/server/{security-audit,apply-docker-user-rules,p13-s2,p13-s3}.sh`,
`scripts/macos/security-audit-macbook.sh`, `config/tailscale/acl.hujson`,
`config/profile.d/homelab-console-timeout.sh`, `config/systemd/{homelab-telegram-bot,homelab-notify@,homelab-watchdog}.service.d/credential.conf`.
Modified: `config/ssh/10-homelab-hardening.conf`, `config/systemd/homelab-model-helper@.service`,
`config/systemd/wifi-powersave-off.service`, `config/systemd/homelab-workbench.service` (comment),
`scripts/macos/{backup-node,verify-node-backup}.sh`, `docs/decisions/ADR-046-…`, `docs/decisions/README.md`,
`docs/handovers/13-security-hardening.md` (corrections), `ROADMAP.md`, `docs/reference/{project-state,software-stack,costs}.md`,
`docs/architecture/current-architecture.md`, `docs/handovers/README.md`.

## Guide updates

`guide/13-security-hardening/README.md` — S1 observations, S2 and S3 write-ups, the 27-row debt
table, the six new decisions with outcomes, corrections to the brief, everything that went wrong.

## Project documentation updates

`project-state.md` (current phase; every Phase 13 bullet struck or rewritten), `current-architecture.md`
(security boundary, deployed rows, Phase 13 additions), `ROADMAP.md` (status block; sequencing item
3 struck; 15.0 next), `software-stack.md`, `costs.md`, `docs/handovers/README.md`.

## ADRs

- **ADR-047** created, Accepted — the Workbench's trust boundary is its sandbox.
- **ADR-046** amended, not superseded — sixth row, token row rewritten, check 2 corrected, trigger 3
  fired twice, which control narrows which threat, checks re-run.
- Not ADRs, by the brief: `fail2ban` declined, rootless Docker deferred, key expiry kept, the ACL
  (recorded in the guide and the standard; it sits beside ADR-019, it does not change its reasoning).

## Tested versions

Ubuntu 26.04.1 LTS, kernel 7.0.0-31-generic, systemd 259.5-0ubuntu3.4, Tailscale 1.102.3 (both
ends), OpenSSH (Ubuntu 26.04 package; `sshd -T` semantics as recorded), Docker 29.8.0, Python
3.14.4, `age` v1.3.2, `gh` 2.90.0, TPM 2.0 (Intel PTT), Lenovo M700 firmware (version not recorded —
`fwupdmgr` reports one upgrade available; not applied, out of scope).

## Security notes

Controls introduced and what each does and does not protect are in the guide's table and ADR-046's
amendment. Three points restated because they will be misread:

- **"TPM-bound" is not "protected from physical access."** The seal narrows a pulled disk. A USB
  boot on the same machine unseals it. The BIOS password narrows the USB boot. Neither protects the
  running machine.
- **No secret entered the repository.** Checked: `git grep -nE 'AAAAC3NzaC1lZDI1NTE5|BEGIN OPENSSH|[0-9]{8,10}:[A-Za-z0-9_-]{35}|age-encryption|-----BEGIN'` over the branch → only the
  MacBook's *public* key line in `config/ssh/…example` and this sentence. The BIOS password, the
  token, the age passphrase and both private keys exist only in the password manager, the TPM, or
  the card.
- **The sudo-password lesson is a rule** (baseline §7), and this phase's three runbooks were written
  under it. No exposure occurred.

## Costs

0 DKK. Running total unchanged at 899 DKK.

## Problems / failures / lessons

Per PROJECT.md §11 — initial choice → what happened → learned → changed:

1. **Helper syscall filter.** Chose the Workbench/bot allow-list → the Claude CLI died with SIGSYS on
   the first `/ask` → a Node.js CLI needs a syscall outside `@system-service` → removed after the one
   round budgeted; recorded in the unit and the standard.
2. **Wifi unit round 1.** Chose `RestrictAddressFamilies=AF_NETLINK` → `iw` failed with ENOENT and
   the runner auto-reverted → `if_nametoindex()` uses an ordinary socket → `AF_UNIX AF_INET` added;
   round 2 passed and survived two cold boots.
3. **The watchdog loads the token.** The brief said "bot and notifier" → S1's `systemctl show` said
   three units → sealing two would have silenced the recovery notice on the first unattended reboot
   → all three sealed; the brief's assumption corrected in the ADR.
4. **A probe that must fail lingered as a failed unit** (`systemd-run` without `--collect`) and
   turned `is-system-running` to `degraded` until `reset-failed` → `--collect` in every such probe.
5. **A bad ACL negative** — port 36121 is tailscaled's PeerAPI, exposed to any peer with any grant;
   it "succeeded" and proved nothing → 2222.
6. **`ssh-keygen -y -f /dev/stdin`** refuses a pipe (0660) → decrypt to a 0600 temp file.
7. **Same-day backup overwrite** in `p13-s2.sh` → never overwrite a backup within a day; handed to
   Phase 14 as a design lesson.
8. **`/tmp` is cleared at boot** and S3 staged its script there → re-copy after each boot; runbook
   fixed.
9. **2b could not be exercised**: the LAN test packet never reached the node (client isolation) →
   PREDICTED, and a corollary about the `homelab-lan` alias recorded.
10. **A phantom double boot**: two watchdog messages read as two boots; the journal showed one boot
    per event (the row-10 boot, then the owner's poweroff for the cord pull). Withdrawn, recorded.
11. **Two `systemctl show` calls on template names** in the scripts failed cosmetically; the
    substantive checks passed; noted, not fixed further.
12. **The brief's IPv6 `FORWARD` claim was stale** — closed since 09-10 by ufw; corrected in S1.

## Deviations from phase brief

- §6.12 (new): `RestrictNamespaces` **not** set on the helper (Phase 09's `# WHY`: codex's sandbox);
  syscall filter tried and removed (SIGSYS).
- §6.13 (new): address families widened after round 1.
- §6.4: `DOCKER-USER` is `apply-docker-user-rules.sh`, not inside `apply-firewall.sh`, because that
  script's `ufw reset` would erase it; the self-revert pattern kept.
- §6.6: three units, not two. No PCR binding (the brief did not specify; the ADR says why).
- §6.7: the policy's `tests` block dropped (rejected by the console).
- §8 rows 6 and 8: half PREDICTED each, as above.
- §7.1: `systemctl show` used with labels, not `--value`.

## Open issues / technical debt

- The two PREDICTED halves (rows 6, 8).
- The GitHub key's scope (6.2b) — Phase 14's call.
- The model helper at 3.8 — a bisect of the syscall groups if anyone wants it below 2.0.
- `fwupdmgr` reports a firmware upgrade available; not applied (a firmware update could change TPM
  state — now the sealed token's failure mode; apply it with `creds-undo` typed in a second session
  and the plaintext at hand).
- `homelab-lan` is dead for a second reason (L2 isolation); the alias and the standard's §3 "both
  routes" check describe a route that does not exist on this network. Nobody owns fixing the
  standard's wording; recorded.

## Recommended roadmap changes

Actioned: Phase 13 status block; sequencing item 3 struck; **15.0 next**. No other change.

## Definition of Done

- [x] Functional objective works — every inherited item has an OBSERVED outcome; the node passes its closing check.
- [x] Configuration/setup is reproducible — every change is a file under `config/` or a script under `scripts/`; the BIOS steps are a checklist; the ACL is committed.
- [x] Validation/tests have passed — 18 of 20 rows OBSERVED, 2 PREDICTED and named.
- [x] Important security implications were considered — the phase is that; ADR-046's amendment states what is and is not protected.
- [x] Relevant repository files are committed — on `phase/13-work`, listed above.
- [x] Human-facing guide is updated — `guide/13-security-hardening/`.
- [x] Project/internal documentation is updated — project-state, architecture, roadmap, stack, costs, handovers index.
- [x] ADRs are created or updated where necessary — ADR-047; ADR-046 amended.
- [x] Actual costs are recorded — 0 DKK.
- [x] Problems, failed approaches, and lessons are recorded — twelve, above.
- [x] Tested versions are recorded — above.
- [x] No unexplained critical AI-generated component remains — every script has a WHY header; every waived directive a `# WHY`.
- [x] `main` represents a known-working state — merge after the closing check.
- [x] The system reports no failed units and no degraded state — closing check.
- [x] A structured handover is written into `docs/handovers/`, stating what the next phase inherits — this document.
