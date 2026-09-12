# 18.2 — Migration to the server

## Goal

Everything the system is made of — the infrastructure repo, Factory, the two project workspaces and
the knowledge base — lives on the node inside the encrypted volume, and the Factory Workbench runs
there as a service you reach from the MacBook through an SSH tunnel. The MacBook is a client and a
terminal. Nothing runs from it.

## Why this matters

**Clone, don't copy.** The whole migration is five `git clone` commands. That is not laziness; it is
the point. A clone is a complete copy of the history whose origin is written into it, so the node's
copy and the MacBook's copy are peers of the same remote, and the remote is the recovery path for
both. Copying directories with `scp` would have produced five trees with no provenance, no way to
tell whether they matched anything, and a backup problem on day one.

**The remote is the backup — for what is in the remote.** This is the clause people skip. A clone is
recoverable because the remote has it. Anything written on the node *after* the clone is recoverable
only once it has been committed and pushed. This phase found, by reading the code, that the
Workbench never commits: it writes record files into `ops/` and appends to an audit log, and leaves
them there for a person to commit. Until that person does, "the remote is the backup" is false for
those files. Phase 14 owns that gap by name.

**A service tied to a volume that may not be there.** The volume is `noauto` and locked at every
boot until someone types the passphrase. A service that needs it has two honest states on a fresh
boot — *skipped, the volume is locked* and *running, it was unlocked* — and must never have a third,
*failed*. Four systemd directives make that true, and one directive you would naturally write breaks
it silently. Both are in [`docs/standards/volume-dependent-services.md`](../../docs/standards/volume-dependent-services.md),
the contract this phase wrote after finding the trap the hard way (below).

**And the unit that must not carry that contract.** The watchdog's job is to say "the volume is
locked" after a boot. If it depended on the volume, a locked volume would skip the one unit whose job
is to report a locked volume. So the standard has a negative clause naming the watchdog, its timer and
the notifier — they observe the volume from outside and depend on nothing in it. Row 11 of this
phase's validation is the proof: node rebooted, volume locked, Workbench skipped, watchdog said so.

**Loopback plus a tunnel beats a tailnet address plus a login.** The Workbench has no login. That
sounds alarming until you ask what the alternative buys. Binding it to the tailnet and adding a
password would put a web login form on a network interface and make the Workbench responsible for
authentication. Binding it to `127.0.0.1` and reaching it through `ssh -L` means: Tailscale
authenticates the device, sshd authenticates the key, the tunnel lands as `aleix`, and loopback is
unreachable from any interface. The Workbench never sees an unauthenticated packet. ADR-038 §4 says
what would justify the weaker shape — a client that is genuinely not local — and nothing here is.

**A node-side key to GitHub.** Cloning private repositories and pushing from the node needs a
credential on the node. It is an ed25519 SSH key, passphrase-less (a service may one day commit with
it and nobody is there to type), registered on the owner's GitHub account. It can pull all five
repositories and push to the three private ones. It cannot do anything else on GitHub. It is a
secret on the node — the first one that grants write access to something off the node — and Phase 13
(hardening) and Phase 14 (restore) are both told about it by name.

**"Every listening socket accounted for" replaced "no listening sockets."** Before this phase the
rule was that the node listens on nothing but sshd, DNS and Tailscale. Now it also listens on
`127.0.0.1:8765`. The rule that survives contact with a real service is ADR-038 §5's: every socket in
`ss -tlnp` has a name, a process and a stated interface, and anything that cannot be named is a
finding. The table is below.

## Reference-build choice

| Decision | Choice | Why |
|---|---|---|
| Layout in the volume | Mirrors the MacBook: `/srv/homelab/{homelab,factory,brain,projects/oncla,projects/factory}` | Paths transfer mentally; `lab.code-workspace` habits carry over |
| Owner of the volume's contents | `aleix:aleix`, mountpoint `0750` | The Workbench runs as the account that owns the repos so its writes are commit-able by the same person; a second account would need its own key and ownership for no boundary gain today. The immutable bit is on the *underlying* directory; the mounted root is an ordinary inode and `chown` works on it |
| GitHub credential | One ed25519 key on the owner's account, not five deploy keys | GitHub refuses one deploy key on several repos; five keys are five things to revoke |
| How the Workbench runs | System unit `homelab-workbench.service`, `User=aleix`, `NoNewPrivileges` | A user unit dies with the session unless lingering is on, and lingering is a second mechanism for what a system unit does directly |
| Module path | `Environment=PYTHONPATH=/srv/homelab/factory`, **not** `WorkingDirectory=` | `WorkingDirectory=` on the volume adds an implicit `RequiresMountsFor=` that runs before the Condition (see the lesson) |
| PyYAML | The Ubuntu package, already installed | `python3-yaml 6.0.3` was present as a dependency of netplan; `apt-mark manual` so autoremove cannot take it |
| Docker `data-root` | Stays on root | Nothing in Docker holds volume content; moving it makes Docker wait on unlock for nothing |
| Backup scope | Remotes back the clones; the new unit files join `backup-node.sh`; the node key is excluded | Contents are recoverable from GitHub; the key is a secret a restore should regenerate, not restore |
| The tunnel | `Host homelab-workbench` carries `LocalForward` + `ExitOnForwardFailure`; `Host homelab` carries nothing | The brief put the forward on `homelab`; that broke every scripted `ssh homelab` while a tunnel was open (see the lesson) |
| The MacBook's clones | Kept as working copies | Nothing runs from them; the editing path is VS Code Remote SSH into `/srv/homelab/...` |

## Alternatives

- **Copy the directories with `rsync`.** Faster to type, and wrong — no provenance, and any local
  uncommitted state on the MacBook would have moved to the node as if it were canonical.
- **A dedicated `workbench` account owning the projects.** The right shape once a second person or an
  automated client exists. Recorded for Phase 13 to take or decline; 23.0's endpoint runs as its own
  account and reaches the Workbench over loopback, not the filesystem.
- **A fine-grained GitHub token in a credential helper** instead of a key. Trades a file for a token
  with an expiry. Not taken unless the key approach fails; it did not.
- **Bind the Workbench to the tailnet and add a login.** ADR-038 §4's weaker position, for a client
  that is not local. None exists.
- **Move Docker's `data-root` into the volume.** Only when a container holds content from the volume
  and cannot bind-mount it. That is the ADR the 18.1 handover asked for; not this phase.

## Prerequisites

Phase 18.1 complete — the volume built, `homelab-data.target` and `data-volume.sh` installed. Phase 12
complete — watchdog, notifier, `OnFailure=` drop-in pattern. On the MacBook, five clones with
GitHub remotes. On the node, `git` and `python3` present, nothing else.

## Implementation

Canonical files: [`config/systemd/homelab-workbench.service`](../../config/systemd/homelab-workbench.service),
[`config/systemd/homelab-workbench.service.d/onfailure.conf`](../../config/systemd/homelab-workbench.service.d/onfailure.conf),
[`config/ssh/homelab.ssh-config.example`](../../config/ssh/homelab.ssh-config.example),
[`docs/standards/volume-dependent-services.md`](../../docs/standards/volume-dependent-services.md).
The unit file's comments are the explanation of every directive; this section is the order.

**1. Ownership** (once, root, volume unlocked):
```bash
sudo chown aleix:aleix /srv/homelab && sudo chmod 0750 /srv/homelab
lsattr -d /srv/homelab          # --------------e------- : the mounted root is not immutable
```
The underlying directory keeps its `i` bit (`sudo data-volume.sh lock; lsattr -d /srv/homelab` →
`----i---------e-------`). Never `chattr -i` it.

**2. The node key** (as `aleix`):
```bash
ssh-keygen -t ed25519 -N '' -C 'homelab node — 2026-09-12' -f ~/.ssh/id_ed25519_github
printf 'Host github.com\n    User git\n    IdentityFile ~/.ssh/id_ed25519_github\n    IdentitiesOnly yes\n' >> ~/.ssh/config
chmod 600 ~/.ssh/config
cat ~/.ssh/id_ed25519_github.pub   # → GitHub → Settings → SSH and GPG keys → New SSH key, title "homelab node — <date>"
ssh -T git@github.com              # compare the host fingerprint with docs.github.com before "yes"
git config --global user.name "…" && git config --global user.email "<github noreply>"
```
Verify with `git ls-remote git@github.com:TelesforoAleix/<repo>.git HEAD` for each of the five —
never `git remote -v`, which prints a string without contacting anything.

**3. Clone** (as `aleix`), SSH URLs — the MacBook's clones use HTTPS and would prompt for
credentials the node does not have:
```bash
mkdir -p /srv/homelab/projects
git clone git@github.com:TelesforoAleix/homelab.git     /srv/homelab/homelab
git clone git@github.com:TelesforoAleix/factory.git     /srv/homelab/factory
git clone git@github.com:TelesforoAleix/brain.git       /srv/homelab/brain
git clone git@github.com:TelesforoAleix/oncla.git       /srv/homelab/projects/oncla
git clone git@github.com:TelesforoAleix/factory-ops.git /srv/homelab/projects/factory
```
Prove `brain` is the private one, not a stale redirect: anonymous HTTPS
`git ls-remote https://github.com/TelesforoAleix/brain.git HEAD` must demand credentials
(`could not read Username`), while the same against `homelab.git` answers a ref.

**4. PyYAML and the Workbench's own test:**
```bash
dpkg -l python3-yaml | tail -1          # ii  python3-yaml  6.0.3-1build1
sudo apt-mark manual python3-yaml
cd /srv/homelab/factory && python3 acceptance/synthetic_project.py   # PASSED — fourteen steps and seven planted refusals
```
The project workspace must be Workbench-initialised (`ops/project.json`); `factory-ops` was not, and
one `python3 -m workbench.cli init … --project-id factory-ops` commit in that repository fixed it,
proved additive on a scratch copy first (156 pre-existing files byte-identical, three added).

**5. The unit** (root; second idle SSH session open — this is a `WantedBy=` on a boot-time target):
```bash
sudo install -m 644 -o root -g root homelab-workbench.service /etc/systemd/system/homelab-workbench.service
sudo install -d -m 755 /etc/systemd/system/homelab-workbench.service.d
cd /etc/systemd/system/homelab-workbench.service.d && sudo install -m 644 /path/to/onfailure.conf onfailure.conf
sudo install -m 755 -o root -g root homelab-notify.sh /usr/local/sbin/homelab-notify.sh   # gains the "workbench" alias
sudo systemctl daemon-reload
systemd-analyze verify homelab-workbench.service
systemctl show -p RequiresMountsFor,Requires --value homelab-workbench.service   # empty; no srv-homelab.mount
sudo systemctl enable homelab-workbench.service      # symlink under homelab-data.target.wants/
sudo systemctl start homelab-workbench.service && systemctl is-active homelab-workbench.service
```

**6. Retire the probe** — the Workbench is the canary now:
```bash
sudo systemctl disable --now homelab-data-probe.service
sudo rm /etc/systemd/system/homelab-data-probe.service && sudo systemctl daemon-reload
```

**7. The tunnel** (MacBook): add the `Host homelab-workbench` block from the example to
`~/.ssh/config`. Then `ssh homelab-workbench` in one terminal, `http://127.0.0.1:8765/` in the
browser. `ssh homelab` for everything else — scripts, `scp`, VS Code, the backup. Only one
`homelab-workbench` session at a time: a second cannot bind the port and refuses to connect.

**8. Backup lists:** both unit files are in `backup-node.sh`'s `NODE_PATHS` and
`verify-node-backup.sh`'s `CRITICAL`; the probe is removed from both; the node key is excluded.

## Validation

The brief's sixteen rows, every one observed on 2026-09-12. The refusals have positive controls.

| Claim | Command | Observed |
|---|---|---|
| Five clones at the remote's HEAD, private ones private | `git status -sb`, `ls-remote --get-url`, `ls-remote <url> HEAD` vs `rev-parse HEAD` | all `## main...origin/main`, SSH URLs, HEADs equal; `brain` over anonymous HTTPS demands credentials, `homelab` answers |
| Acceptance run on the node | `python3 acceptance/synthetic_project.py` | `PASSED`, 14 steps, 7 refusals, exit 0, **0.4 s** |
| Refuses while locked | `lock; start; echo $?; is-active; journalctl` | `0`, `inactive`, `skipped, unmet condition check ConditionPathIsMountPoint…`, **no alert** |
| Starts on unlock | `unlock; is-active` | `active`, no manual start — twice |
| Loopback only | `ss -tlnp \| grep 8765` | `127.0.0.1:8765 python3` |
| Not over the tailnet | MacBook `curl -m 5 http://homelab.<magicdns>:8765/` | `(7) Failed to connect … after 7 ms` |
| Through the tunnel, one real action | `curl 127.0.0.1:8765/`; `POST /api/status` on a `release_ready` ticket | HTML; `{"ok": true …}`; the record file changed, `git log -1` unchanged (the Workbench does not commit) |
| Every socket accounted for | `sudo ss -tlnp` | the table below |
| Lid closed 2 min | `is-active; uptime` | `active`; `up 2:02` |
| Watchdog unaffected | `systemctl show -p After,Requires,Wants,PartOf,ConditionPathIsMountPoint` | nothing names `srv`, `homelab-data`, `workbench`, the bot |
| Locked boot | `sudo reboot` → Telegram → checks → unlock | 19:42 UTC `Home Lab back up. Down ~0m, clean reboot. Data volume: LOCKED …`; no failed units; Workbench `inactive`; `running`; unlock → `active` |
| Probe gone | `list-unit-files`, `ls` | `0 unit files listed.`; no such file |
| Hardening | `systemd-analyze security` | **1.3 OK** |
| Bot untouched | `id homelab-bot`; bot's score; helper socket | `uid=999 gid=982 groups=982`; `1.3 OK`; `active` |
| Crash loop | 6 × `kill -s SIGKILL`, 11 s apart | `failed` after kill **5** (the unlock's start counted in the 300 s window); `NRestarts=5`, `Result=signal`; **5 alerts** (four crashes + the start-limit hit); `stop` → no alert |
| Backups | `backup-node.sh`; `verify-node-backup.sh` | 130 files (was 121); both units `ok`; no probe; `id_ed25519_github` absent; `PASS` |

**The socket table**, `sudo ss -tlnp` on the node after the phase — the measured statement of
ADR-038 §5:

| Address | Process | What it is | Interface |
|---|---|---|---|
| `0.0.0.0:22`, `[::]:22` | `sshd` (socket-activated by `systemd`) | The way in | All — but `ufw` drops it everywhere except `tailscale0` (`security-shared-network`, 2026-09-10) |
| `127.0.0.53%lo:53`, `127.0.0.54:53` | `systemd-resolve` | The stub resolver every local process uses for DNS | Loopback only |
| `100.71.62.71:36121`, `[fd7a:…:3ed6]:57273` | `tailscaled` | Tailscale's own listener on its own addresses | The tailnet interface only |
| `127.0.0.1:8765` | `python3` as `aleix` | **The Workbench** | Loopback only — reached through `ssh homelab-workbench` |

Seven sockets, seven names. The MacBook's `curl` against the MagicDNS name on 8765 is the proof the
last row means what it says.

## Security notes

- **A new secret on the node**: `~aleix/.ssh/id_ed25519_github`, `0600`, passphrase-less, write to
  three private repositories. Blast radius: their contents and history — not the node. Revoke it at
  GitHub → Settings → SSH and GPG keys → the entry titled `homelab node — 2026-09-12`; that is one
  click and the key is dead everywhere. It is **not** in the backup, by an explicit `--exclude`; a
  restored node generates a new one.
- **The Workbench has no login**, and that is the design: device (Tailscale) → key (sshd) → user
  (`aleix`) → loopback. The `LocalForward` binds `127.0.0.1` on the MacBook side too.
- **It runs as the sudo-capable admin account.** `NoNewPrivileges=yes` means no process in its tree
  can gain privilege; `ProtectSystem=strict` with `ReadWritePaths=/srv/homelab` means it can write
  nothing else; no `AF_UNIX` means it cannot reach the model helper socket even though the account
  could at the file-permission layer. Score 1.3, the same as the bot. Phase 13 decides whether a
  dedicated account is warranted.
- **`ufw` unchanged.** One new socket, loopback; nothing to open.
- **Nothing destructive.** Clones into an empty volume; a unit removal; no keyslot change, no
  `chattr -i`, no `rm -rf`.
- **During validation the owner's sudo password was typed into a script's silent pause and echoed
  into a pasted transcript.** It was rotated the same evening and the local transcript scrubbed;
  the script gets a progress line as a recorded issue. Written up here because a security note that
  omits the one real exposure of the day is not a security note.

## Reference-build experience

**Timings.** Five clones, 12 s total (36 MB for `brain`, the rest under 5 MB each). Acceptance run
0.4 s. Locked boot to the watchdog's Telegram message: ~2 min. `systemd-analyze security`: 1.3.
Crash loop: tripped on kill 5, five alerts in 43 s.

**The false alert, and the directive that caused it.** *Assumption:* `WorkingDirectory=/srv/homelab/factory`
is the obvious way to make `python3 -m workbench.cli` find the package, and it is harmless. *What
happened:* the unit installed, enabled and started perfectly; the locked boot passed. Then row 3 —
lock the volume, start the unit by hand — returned rc 1, `A dependency job for
homelab-workbench.service failed`, and the owner's phone buzzed with `Home Lab alert:
homelab-workbench.service failed` for a volume that was merely locked. `systemctl show` had
`RequiresMountsFor=/srv/homelab/factory` and `srv-homelab.mount` in `Requires=`. *What was learned:*
systemd derives an implicit `RequiresMountsFor=` from `WorkingDirectory=` (and `RootDirectory=`,
`StateDirectory=`, …), and **dependency jobs run before conditions are evaluated** — the mount job
failed on the locked LUKS volume and `ConditionPathIsMountPoint=` was never consulted. A locked boot
hides this completely because nothing pulls the unit until the target starts; only a manual start
while locked — exactly the canary test — exposes it. *What changed:* `WorkingDirectory=` went;
`Environment=PYTHONPATH=/srv/homelab/factory` replaced it (the Workbench writes nothing relative to
its cwd); the standard gained a row and a post-edit check (`systemctl show -p
RequiresMountsFor,Requires` → empty, no mount); the fix was bisected unprivileged with throwaway user
units — `ReadWritePaths=`, `ProtectSystem=`, `Environment=`, `ExecStart=` naming the volume add
nothing; only `WorkingDirectory=` does.

**The alias split.** *Assumption:* one alias, `homelab`, with the forward on it, is simplest.
*What happened:* row 16's `backup-node.sh` died at its first `ssh homelab` — `bind
[127.0.0.1]:8765: Address already in use … Could not request local forwarding` — because the
owner's interactive tunnel session already held the port and `ExitOnForwardFailure` did exactly what
it says. Same for the verifier, and it would be the same for `scp`, VS Code Remote and git.
*Learned:* a forward belongs on the alias whose only job is the forward. *Changed:* `Host
homelab-workbench` carries it; `Host homelab` carries nothing.

**What the Workbench actually writes.** The brief assumed it commits and pushes through
`gitops.py`. Reading `engine.py` showed it never calls git — only the acceptance script does. So
row 7's "lands as a commit" became "lands as a modified file, `git log -1` unchanged", §6.6 was
rewritten, and Phase 14 got the uncommitted `ops/` writes by name. Related: the workspace had no
`ops/project.json`, so `serve` would have refused at start; and the one real action wrote a *new*
file `TICKET-2026-0023.yaml` beside the legacy `TICKET-2026-0023-interaction-schema.yaml`, because
the Workbench names files by ID and the legacy records carry a slug. Both are `factory-ops` findings,
with the 93 legacy-status validation problems, recorded for that repository.

**Things that just worked.** PyYAML was already there. The mounted root was not immutable, as the
brief predicted. `MemoryDenyWriteExecute=yes` is fine with Python 3.14. The watchdog needed nothing.
The kill loop tripped one kill earlier than predicted because the start limit counts the unlock's
start too — correct, and now written down.

**Two smaller traps.** `systemctl show -p A,B` prints in systemd's order, not yours. Python
block-buffers stdout to the journal; without `PYTHONUNBUFFERED=1` the "Factory Workbench — project …"
line appears at exit, not at start.

## Tested versions

Tested with: Ubuntu Server 26.04.1 LTS, kernel 7.0.0-31-generic; systemd 259.5 (`259.5-0ubuntu3.4`);
git 2.53.0; Python 3.14.4; PyYAML 6.0.3 (`python3-yaml 6.0.3-1build1`); OpenSSH client 9.9p2
(LibreSSL 3.3.6) on the MacBook; Factory at `2e82f51`, `factory-ops` at `66283c2`.

Requires: Python ≥ 3.11 and PyYAML ≥ 6.0 (Factory's own stated floor). systemd ≥ 246 for the
`journalctl -u` glob the notifier uses.

## Next phase

Phase 13 — security hardening, promoted to next: the node now runs a web service.
[`docs/handovers/18.2-migration-to-the-server-handover.md`](../../docs/handovers/18.2-migration-to-the-server-handover.md)
says what it, Phase 23.0 and Phase 14 inherit, by name.
