#!/usr/bin/env python3
"""Phase 15.1 S3 ledger helper. Run as aleix, no sudo, helper stopped.

  p151-s3-ledger.py restore            copy S3LEDBAK over spend.json (cp -p)
  p151-s3-ledger.py add day|week|month|unattended   append one labelled synthetic record
  p151-s3-ledger.py final              restore, then re-add the real S3 lines (non-synthetic, index>=2)
  p151-s3-ledger.py dump               content-free field dump for reconciliation
"""
import json, os, shutil, sys, time
P = "/var/lib/homelab-model-helper/spend.json"
BAK = "/var/lib/homelab-model-helper/spend.json.bak-2026-09-13-p151-s3"
KEEP = "/home/aleix/p151-s3-real-lines.json"
SYN = {  # label, budget, age seconds, amount
    "day":        ("p151-s3-synthetic-day", "attended", 2*3600, "1.000000000"),
    "week":       ("p151-s3-synthetic-week", "attended", 2*86400, "4.000000000"),
    "month":      ("p151-s3-synthetic-month", "attended", 10*86400, "8.000000000"),
    "unattended": ("p151-s3-synthetic-unattended-hour", "unattended", 0, "0.100000000"),
}
def load(): return json.load(open(P))
def save(d):
    with open(P, "w") as fh: json.dump(d, fh, separators=(",", ":")); fh.write("\n")
def restore():
    shutil.copy2(BAK, P); print("restored from", BAK, os.path.getsize(P), "bytes")
def add(which):
    label, budget, age, amt = SYN[which]
    d = load(); now = time.time()
    assert not any("synthetic" in c for c in d["calls"]), "a synthetic record is still present"
    d["calls"].append({"ts": now-age, "completed_ts": now-age, "reservation_id": label,
        "request_id": label, "route": "utility", "provider": "gateway", "model": "luna",
        "budget": budget, "usage": None, "reserved_usd": amt, "settled_usd": amt,
        "status": "settled", "synthetic": label})
    save(d); print("calls:", len(d["calls"]), "last:", label, "ts:", int(now-age))
def final():
    d = load(); real = [c for c in d["calls"][2:] if "synthetic" not in c]
    json.dump(real, open(KEEP, "w")); print("kept", len(real), "real S3 lines:", [c["status"] for c in real])
    restore(); d = load(); d["calls"] += real
    assert not any("synthetic" in c for c in d["calls"]); save(d)
    print("ledger calls:", len(d["calls"]), [c["status"] for c in d["calls"]])
def dump():
    for c in load()["calls"]:
        print({k: c.get(k) for k in ("request_id","budget","status","reserved_usd","settled_usd","gateway_cost","settle_note","release_reason","usage","synthetic")})
cmd = sys.argv[1:]
if cmd == ["restore"]: restore()
elif len(cmd) == 2 and cmd[0] == "add" and cmd[1] in SYN: add(cmd[1])
elif cmd == ["final"]: final()
elif cmd == ["dump"]: dump()
else: print(__doc__); sys.exit(2)
