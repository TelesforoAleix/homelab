# Phase 23.0 — S4 runbook (close)

Two parts. **A** runs before the orchestrator merges: the closing check and row 19's backup +
verify. **B** runs after both merges are confirmed: the node's factory clone back to `main`, one
Workbench restart, the final check. No model call in either part. Every step prints before it
waits; `sudo -v` once per part.

Terminals: **T** — MacBook, `/Users/home/Code/homelab-p230` (part A) then `/Users/home/Code/homelab`
(part B, after the merge). **S1** — `ssh homelab`. The backup card mounted at `/Volumes/SD Card`.

## A — Pre-merge: closing check and row 19

```bash
# S1 — the closing check
[ "$(hostname)" = homelab ] || { echo "NOT ON THE NODE -- ssh homelab first"; false; } && {
echo "== refreshing sudo (password prompt follows) =="; sudo -v
echo "== units: none failed, running =="; systemctl --failed; systemctl is-system-running
echo "== the eight sockets =="; sudo ss -tlnp | grep -c LISTEN; sudo ss -tlnp | grep -E ':876[56]\b'
echo "== the endpoint and the helper through it =="; curl -sS http://127.0.0.1:8766/health; echo; curl -sS http://127.0.0.1:8766/health/helper; echo
echo "== the boundary: account, group, socket =="; id homelab-harness; getent group homelab-model; stat -c '%U:%G:%a' /run/homelab-model-helper.sock
echo "== scores (expect 1.3 and 3.8) =="
sudo systemd-analyze security homelab-harness.service --no-pager | grep -i 'overall'
sudo systemd-analyze security 'homelab-model-helper@probe.service' --no-pager | grep -i 'overall'
echo "== the harness verify, once more (64/64, no spend) =="; sudo bash /tmp/homelab-phase230/install-homelab-harness.sh verify | grep -E '^(ok|FAIL|UNKNOWN|All)'
echo "== the helper verify (19/19) =="; sudo bash /tmp/homelab-phase09/install-model-helper.sh verify | grep -E '^(ok|FAIL|UNKNOWN|All)'
echo "== audit file: lines, and no content (expect 0) =="; sudo wc -l /var/lib/homelab-harness/audit.jsonl; sudo grep -c 'socket unit' /var/lib/homelab-harness/audit.jsonl || true
echo "== scratch copies from S3 removed =="; rm -rf /tmp/second-adapter-*; ls -d /tmp/second-adapter-* 2>/dev/null || echo "none"
echo "== the factory clone (expect phase/23.0-adapter @ 9986188 until the merge) =="; git -C /srv/homelab/factory log --oneline -1
}
```

If `/tmp/homelab-phase230` is gone (a reboot clears it), skip the two `verify` lines — both were
OBSERVED in S2 and their checks are unchanged.

```bash
# T — row 19: backup and verify, card in. Two prompts: the node's sudo password, the age passphrase.
ls "/Volumes/SD Card/homelab-backup/"
mv "/Volumes/SD Card/homelab-backup/2026-09-13" "/Volumes/SD Card/homelab-backup/2026-09-13-p13-p150"
./scripts/macos/backup-node.sh
./scripts/macos/verify-node-backup.sh "/Volumes/SD Card/homelab-backup/2026-09-13"
```

Why the `mv`: today's directory already holds Phase 13/15.0's close, and `backup-node.sh` refuses a
same-day overwrite without `--force` (correctly). A phase-named `DEST` was tried first and refused
too — the script requires `DEST` to be a mount point (OBSERVED). Renaming the morning's directory
keeps both archives. **Pass the path to `verify-node-backup.sh`:** with no argument it takes the
alphabetically last `20*` directory, and `2026-09-13-p13-p150` sorts after `2026-09-13` — the first
run verified the morning's archive against the live node and reported today's changes as 13
mismatches (OBSERVED; a correct result about the wrong archive). The date-only directory name is the same lesson as the `.bak-<date>` collision, for
Phase 14.

Expected in the verify: `etc/systemd/system/homelab-harness.service`, `…/homelab-harness.service.d/onfailure.conf`,
`etc/homelab-harness/config.json`, `etc/systemd/system/homelab-model-helper@.service.d/runtime.conf`
present; `var/lib/homelab-harness/audit.jsonl` in the archive; the GitHub key, the plaintext token
and the recovery key **absent**; the planted control fires; **PASS**.

**Paste back:** the closing-check block; the backup's summary lines (size, files); the verify's
PASS line and its path list.

## B — Post-merge: the node's clone back to `main`

Run only after the orchestrator confirms **both** merges and gives the two hashes:

- homelab `main` merge commit: `HOMELAB_MERGE=<hash>`
- factory `main` merge commit: `FACTORY_MERGE=<hash>`

```bash
# S1 — factory clone to merged main; the Workbench imports the changed modules, so one restart
[ "$(hostname)" = homelab ] || { echo "NOT ON THE NODE -- ssh homelab first"; false; } && {
FACTORY_MERGE="<hash>"   # <- fill in from the orchestrator
echo "== refreshing sudo (password prompt follows) =="; sudo -v
echo "== clone as it stands (expect phase/23.0-adapter, clean) =="; git -C /srv/homelab/factory status --short --branch | head -3
echo "== back to main, pull =="
git -C /srv/homelab/factory checkout main && git -C /srv/homelab/factory pull --ff-only
echo "== the hash must be the merge commit =="; git -C /srv/homelab/factory rev-parse --short HEAD; echo "expected ${FACTORY_MERGE}"
[ "$(git -C /srv/homelab/factory rev-parse HEAD)" = "$(git -C /srv/homelab/factory rev-parse "$FACTORY_MERGE")" ] && echo "hash OK" || echo "HASH MISMATCH -- stop"
echo "== the merged code imports (no model call) =="
cd /srv/homelab/factory && PYTHONDONTWRITEBYTECODE=1 python3 -c 'import workbench.cli, workbench.adapters.homelab, workbench.adapters.select; print("import ok:", workbench.adapters.homelab.HomelabAdapter.name)'; cd ~
echo "== Workbench restart =="; sudo systemctl restart homelab-workbench.service; sleep 3
systemctl is-active homelab-workbench.service; curl -sS -o /dev/null -w 'dashboard http %{http_code}\n' http://127.0.0.1:8765/
echo "== the homelab clone on the node, for completeness (it runs nothing) =="
git -C /srv/homelab/homelab checkout main && git -C /srv/homelab/homelab pull --ff-only && git -C /srv/homelab/homelab log --oneline -1
echo "== final: none failed, running, eight sockets =="; systemctl --failed; systemctl is-system-running; sudo ss -tlnp | grep -c LISTEN
}
```

Expected: `hash OK`, `import ok: homelab`, Workbench `active`, `http 200`, homelab clone at
`HOMELAB_MERGE`, 0 failed, `running`, `8`.

**Paste back:** the block. That closes the phase on the node.

## Rollback

- **A:** nothing to roll back — it reads and backs up.
- **B:** `git -C /srv/homelab/factory checkout phase/23.0-adapter && sudo systemctl restart homelab-workbench.service`
  puts the node back where S3 left it. The merged `main` is the orchestrator's to revert.
