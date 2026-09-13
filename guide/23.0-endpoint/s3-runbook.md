# Phase 23.0 — S3 runbook (row 17: the second adapter on the node)

Ordinary class: a `git checkout` in the factory clone on the volume, one Workbench restart, one
scratch run. Nothing under `/etc`, no unit change, no sudo except the Workbench restart. **Every
step prints before it waits.** One session is enough; keep S2 open anyway out of habit.

**What this proves.** The same check that passed locally against the stub (`s3-8.1.3-local.txt`)
run on the node against the **real** endpoint and the real helper: `run` on `fake`, `run` on
`homelab`, records byte-identical apart from the `Result` fields, a real answer recorded on the
item, and the endpoint's `request_id` present in **both** audit trails.

**Costs.** One real model call (the `homelab` leg of the check). The `fake` leg calls nothing. The
factory tests call nothing (stub endpoints on ephemeral ports).

**The clone is on the volume** (`/srv/homelab/factory`, `aleix`), so the volume must be unlocked
— it is, since S2's last step. The Workbench serves from that clone and **never pulls**; after the
checkout its running process still holds the old `workbench/*` modules, so it is restarted once.

Terminals: **T** — MacBook, in `/Users/home/Code/factory` (note: *factory*, not homelab).
**S1** — `ssh homelab`. **Browser** — optional, `ssh homelab-workbench` then `http://127.0.0.1:8765/`.

## 0 — Publish the branch (T)

The node pulls from GitHub; the branch has to be there first. Not merged — the orchestrator merges
with the homelab merge.

```bash
# T — in /Users/home/Code/factory
echo "== the branch and its two commits =="; git -C /Users/home/Code/factory log --oneline main..phase/23.0-adapter
echo "== tests locally (expect 55 OK) =="; (cd /Users/home/Code/factory && python3 -m unittest tests.test_workbench 2>&1 | tail -3)
echo "== push the branch =="; git -C /Users/home/Code/factory push -u origin phase/23.0-adapter
```

Note the top hash (`git log --oneline -1 phase/23.0-adapter`); the runbook calls it `HASH`.

## 1 — Check out the branch on the node, restart the Workbench (S1)

```bash
# S1
[ "$(hostname)" = homelab ] || { echo "NOT ON THE NODE -- ssh homelab first"; false; } && {
echo "== refreshing sudo (password prompt follows) =="; sudo -v
echo "== volume unlocked? (expect mapper present) =="; data-volume.sh status | sed -n '2,3p'
echo "== the factory clone as it stands =="; git -C /srv/homelab/factory status --short --branch | head -5
echo "== fetch and check out the branch =="
git -C /srv/homelab/factory fetch origin
git -C /srv/homelab/factory checkout phase/23.0-adapter
git -C /srv/homelab/factory log --oneline -1
echo "== the Workbench imports workbench/*: restart it so it runs the new code =="
sudo systemctl restart homelab-workbench.service; sleep 3
systemctl is-active homelab-workbench.service; curl -sS -o /dev/null -w 'dashboard http %{http_code}\n' http://127.0.0.1:8765/
echo "== factory tests on the node (row 15; no model call) =="
cd /srv/homelab/factory && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.test_workbench 2>&1 | tail -3; cd ~
}
```

Expected: `HASH` on the node equals the pushed hash; Workbench `active`, `http 200`; `Ran 55 tests … OK`.
If `git status` showed local changes in the clone, **stop** — the Workbench writes into
`projects/factory/ops/`, never into `factory/`, so a dirty clone is unexpected.

## 2 — Row 17: the check against the real endpoint (S1). One real call.

`--keep` keeps the two scratch copies so the records can be read afterwards.

```bash
# S1
[ "$(hostname)" = homelab ] || { echo "NOT ON THE NODE"; false; } && {
echo "== endpoint up? =="; curl -sS http://127.0.0.1:8766/health/helper; echo
echo "== the second-adapter check, on the node, real endpoint, real helper (ONE real call) =="
cd /srv/homelab/factory && PYTHONDONTWRITEBYTECODE=1 python3 acceptance/second_adapter_check.py \
  --source /srv/homelab/projects/factory --item TASK-2026-0001 --agent execution-agent --keep \
  --objective "What is the difference between a socket unit and a service unit in systemd, in two sentences?" \
  | tee /tmp/p230-row17.txt; cd ~
}
```

Expected, at the end: `the adapter interface is proved`, and the raw-difference block showing only
`ops/audit/audit.jsonl` (`detail.backend`, `detail.model`), `ops/project.json` (`adapter`) and
`ops/runs/RUN-2026-0001.json` (`adapter`, `request_id`, `model`, `output`). The `homelab` leg's
`output` is a real answer; `model` is whatever the helper reported (Codex if Claude is still
exhausted — the fallback, not a failure). If the `homelab` leg says `REFUSED … exhausted`, both
subscriptions are out this hour: wait, do not loop.

## 3 — Both audit lines, one request id (S1)

```bash
# S1
[ "$(hostname)" = homelab ] || { echo "NOT ON THE NODE"; false; } && {
RID=$(grep -o 'request_id=[0-9a-f]\{32\}' /tmp/p230-row17.txt | tail -1 | cut -d= -f2); echo "request_id = $RID"
SCRATCH=$(grep -o 'scratch copies: [^ ]*' /tmp/p230-row17.txt | cut -d' ' -f3); echo "scratch = $SCRATCH"
echo "== the run record on the item (the real answer, recorded by the client) =="
cat "$SCRATCH/homelab/ops/runs/RUN-2026-0001.json"
echo "== the item links the run =="; grep -A2 '^run_ids' "$SCRATCH/homelab/ops/tickets/TICKET-2026-9001.yaml"
echo "== the Workbench's audit line for the execute (backend, model, budget; the request id is on the run record) =="
grep '"execute"' "$SCRATCH/homelab/ops/audit/audit.jsonl"
echo "== the endpoint's audit line for the same request id (expect client_declared=workbench, role=execution-agent, priority=normal, outcome=ok, lengths only) =="
sudo grep "$RID" /var/lib/homelab-harness/audit.jsonl
echo "== the helper's journal line (expect user=harness:workbench route=execution-agent outcome=ok) =="
sudo journalctl -u 'homelab-model-helper@*' --since '-10 min' --no-pager -o cat | grep 'harness:workbench'
echo "== the question text is in neither audit file (expect 0 and 0) =="
sudo grep -c 'socket unit and a service unit' /var/lib/homelab-harness/audit.jsonl
grep -c 'socket unit and a service unit' "$SCRATCH/homelab/ops/audit/audit.jsonl"
echo "== ...but IS on the client's records: the question on the ticket, the answer on the run (expect 1 and 1) =="
grep -c 'socket unit and a service unit' "$SCRATCH/homelab/ops/tickets/TICKET-2026-9001.yaml"
grep -c 'socket unit' "$SCRATCH/homelab/ops/runs/RUN-2026-0001.json"
echo "== nothing failed =="; systemctl --failed; systemctl is-system-running
}
```

The Workbench's `audit.jsonl` does **not** carry the request id: `Result` has no field for it, so
`run` records it on the `run` object instead (`adapter.last_request_id`) — the named ADR-035 §4
finding. "Both audit lines with the same request id" is therefore: the endpoint's audit line, and
the Workbench's **run record** that its audit line's `execute` entry points at. Say so in the paste.

**Browser (optional):** `ssh homelab-workbench`, open `http://127.0.0.1:8765/` — the dashboard
serves `/srv/homelab/projects/factory`, not the scratch copy, so nothing new appears there; this
confirms the restarted Workbench is healthy, nothing more.

## 4 — Paste back

1. Step 0: the two-commit log, `55 OK`, the push line and `HASH`.
2. Step 1: the node's `git log -1`, `active`, `http 200`, `Ran 55 … OK`.
3. Step 2: `/tmp/p230-row17.txt` in full.
4. Step 3: everything.

## Cleanup and rollback

- The scratch copies live under `/tmp/second-adapter-*` on the node; `/tmp` clears at boot.
  `rm -rf /tmp/second-adapter-*` when the paste is in.
- **Rollback:** `git -C /srv/homelab/factory checkout main && sudo systemctl restart homelab-workbench.service`.
  `factory-ops` (`/srv/homelab/projects/factory`) was read, never written — the check copies it.
- The branch stays unmerged until the orchestrator merges it with homelab's.
