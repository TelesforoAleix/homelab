#!/usr/bin/env python3
"""
Socket probe — Phase 09.

Proves that a caller can reach the helper socket, and NOTHING ELSE. It sends
`op: ping`, which the helper answers without making a model call, so this can be
run as often as you like without spending a slice of the owner's subscription.

WHY THIS EXISTS AS A SEPARATE FILE
----------------------------------
Because the question it answers cannot be answered from a shell prompt. The bot
runs inside a systemd sandbox with ProtectSystem=strict, which mounts the whole
filesystem read-only -- including /run, where the socket lives. Whether connect(2)
to a socket on a read-only mount succeeds is a property of the kernel, not of
this project, and the honest way to find out is to try it AS the service user,
INSIDE the same sandbox. A test run as root from a login shell would pass and
prove nothing about the service.

So the installer runs this under `systemd-run` with the bot's own directives.

Exit status: 0 if the helper answered, 1 otherwise. The message goes to stdout.
"""

from __future__ import annotations

import json
import socket
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "/run/homelab-model-helper.sock"

try:
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(10)
    sock.connect(path)
    sock.sendall(b'{"v":1,"op":"ping"}\n')
    sock.shutdown(socket.SHUT_WR)
    raw = sock.recv(8192)
    sock.close()
except OSError as exc:
    # errno is the whole point of this probe. EACCES means the socket's mode or
    # group is wrong; EROFS would mean the sandbox blocked the connect;
    # ENOENT means the socket is not there at all. They need different fixes,
    # so the reason is printed rather than a bare failure.
    print(f"PROBE FAIL: {type(exc).__name__} errno={exc.errno} {exc.strerror}")
    sys.exit(1)

if not raw.strip():
    print("PROBE FAIL: connected, but the helper said nothing")
    sys.exit(1)

try:
    reply = json.loads(raw.decode("utf-8", errors="replace").splitlines()[0])
except (json.JSONDecodeError, IndexError):
    print(f"PROBE FAIL: unreadable reply: {raw[:200]!r}")
    sys.exit(1)

if reply.get("ok") and reply.get("op") == "ping":
    print(f"PROBE OK: helper answered, providers={reply.get('providers')}")
    sys.exit(0)

print(f"PROBE FAIL: helper replied {reply}")
sys.exit(1)
