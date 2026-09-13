#!/usr/bin/env python3
"""
A local stand-in for the node's endpoint — Phase 23.0 S3, the §8.1.3 check.

Runs the REAL harness.py on 127.0.0.1:8766 (the adapter's fixed URL) in front
of the fixture's stub helper socket, which spawns the REAL helper.py per
connection against a fixture config with stub CLIs. So a Workbench `run` on the
MacBook goes through the same code the node runs, answers "STUB-ANSWER", and
spends nothing. The audit file lands in a temp dir that is printed.

Usage:  python3 services/homelab-harness/dev-stub.py [--port 8766] [--role execution-agent]
Stop with ctrl-c. Not installed anywhere; a developer tool.
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import sys
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

spec = importlib.util.spec_from_file_location("fixture_tests", os.path.join(HERE, "fixture-tests.py"))
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)  # type: ignore[union-attr]
import harness  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8766)
    ap.add_argument("--role", default="execution-agent",
                    help="the one agent role given a route in the fixture config")
    args = ap.parse_args()

    if fixture.HELPER_DIR is None:
        print("helper.py not found (set HOMELAB_HELPER_DIR)")
        return 1
    fixture.ROLE = args.role
    bench = fixture.Bench()
    bench.port = args.port
    bench.helper.config = bench.helper_config("dev", unattended=True)
    server = harness.Harness(bench.harness_config())
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print(f"dev-stub: endpoint on 127.0.0.1:{args.port}; routed role {args.role!r}; "
          f"helper = real helper.py with stub CLIs; audit at {bench.audit_path}", flush=True)
    try:
        threading.Event().wait()
    except KeyboardInterrupt:
        print("\ndev-stub: stopped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
