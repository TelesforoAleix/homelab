"""
Home Lab model helper — Phase 09, ADR-025.

THIS PROCESS EXISTS TO HOLD A CREDENTIAL THE BOT MUST NOT HAVE
--------------------------------------------------------------
Phase 07 proved, by attempting it, that `homelab-bot` cannot read
/home/aleix/.claude/.credentials.json or /home/aleix/.codex/auth.json. Phase 09
had to make model calls anyway. There were three ways to do that and two of them
were wrong:

  copy the credential to homelab-bot ......... rejected outright
  add homelab-bot to a group that can read it  rejected outright
  let the bot run something as another user .. rejected: the bot would need an
                                               escalation mechanism, and the
                                               thing it escalates to is a shell
  ---
  put the CALL where the credential already is, and let the bot ASK  <-- this

So this runs as `aleix`, who already has both credentials, and the bot talks to
it over a UNIX socket. The bot gains no group, no sudoers entry, and no read
access to /home/aleix. `id homelab-bot` is unchanged by this phase.

The socket is the entire attack surface, so it is deliberately tiny:

  IT IS NOT A SHELL. Two operations, `ping` and `ask`. `ask` takes a string and
  returns a string. There is no operation that names a file, a command, a model,
  a provider or a path -- the caller cannot choose ANY of those. Everything the
  CLI is invoked with comes from a root-owned config file, never from the wire.

WHO MAY CONNECT IS NOT DECIDED HERE
-----------------------------------
It is decided by systemd, in the .socket unit, before this process exists:
SocketMode=0660 with SocketGroup=homelab-bot. Filesystem permissions on the
socket inode are the access control. That is deliberate -- an access rule in a
committed unit file is reviewable; an access check in a Python process is a
thing that can be bypassed by a bug in the same Python process.

WHAT LEAVES THE MACHINE
-----------------------
The owner's question, and the literal output of /status: hostname, uptime, load,
memory, disk. Five figures the owner can already read on their phone. Nothing
else -- no logs, no journal, no file contents, no unit files, no allowlists.

That is a security boundary, not a scoping accident. Journal lines are written
by other software, some of it reachable from the network. Feeding them to a
model would mean an unbounded amount of host data leaving the machine, chosen by
whatever could write a log line rather than by the owner. Five numeric fields
cannot carry an instruction.
"""

from __future__ import annotations

import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from limits import Limiter          # noqa: E402
from providers import BY_NAME       # noqa: E402

CONFIG = os.environ.get("HOMELAB_MODEL_HELPER_CONFIG",
                        "/etc/homelab-model-helper/config.json")

# A hard ceiling that does not depend on the config being sane. The bot caps the
# question too; this is the backstop for anything that reaches the socket.
MAX_REQUEST_BYTES = 16 * 1024


def log(msg: str) -> None:
    """stderr goes to the journal under the unit name."""
    print(msg, file=sys.stderr, flush=True)


def load_config() -> dict:
    with open(CONFIG, encoding="utf-8") as fh:
        cfg = json.load(fh)

    order = cfg.get("providers") or []
    if not isinstance(order, list) or not order:
        raise ValueError("config: 'providers' must be a non-empty list")
    for name in order:
        if name not in BY_NAME:
            raise ValueError(f"config: unknown provider {name!r}")
        entry = cfg.get(name)
        if not isinstance(entry, dict) or not entry.get("bin") or not entry.get("model"):
            raise ValueError(f"config: {name} needs 'bin' and 'model'")
        if not os.path.isabs(entry["bin"]):
            raise ValueError(f"config: {name} 'bin' must be an absolute path")
    return cfg


def build_providers(cfg: dict) -> list:
    timeout = int(cfg.get("timeout_seconds", 120))
    out = []
    for name in cfg["providers"]:
        entry = cfg[name]
        out.append(BY_NAME[name](entry["bin"], entry["model"], timeout))
    return out


def read_request() -> dict:
    """
    One JSON object, one line. Bounded before parsing.

    Reading from stdin works because the unit is Accept=yes: systemd hands the
    accepted connection to this process as stdin and stdout. There is no socket
    code here at all, which is the point -- the smallest thing that can be wrong.
    """
    raw = sys.stdin.buffer.readline(MAX_REQUEST_BYTES + 1)
    if len(raw) > MAX_REQUEST_BYTES:
        raise ValueError("request too large")
    return json.loads(raw.decode("utf-8"))


def reply(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def handle_ask(req: dict, cfg: dict) -> dict:
    question = req.get("question")
    context = req.get("context", "")
    user = req.get("user_id", "unknown")

    if not isinstance(question, str) or not question.strip():
        return {"ok": False, "kind": "error", "message": "empty question"}
    if not isinstance(context, str):
        return {"ok": False, "kind": "error", "message": "bad context"}

    max_q = int(cfg.get("max_question_chars", 500))
    question = question.strip()[:max_q]
    context = context[:2000]

    limiter = Limiter(cfg["state_file"],
                      int(cfg["caps"]["per_hour"]),
                      int(cfg["caps"]["per_day"]))

    spent: list[str] = []
    for provider in build_providers(cfg):
        allowed, note = limiter.check_and_reserve(provider.name)
        if not allowed:
            log(f"ask user={user} provider={provider.name} outcome=capped")
            spent.append(note)
            continue

        started = time.monotonic()
        answer = provider.ask(question, context)
        took = time.monotonic() - started

        # The question itself is NOT logged. It is the owner's own text and the
        # journal is not the place for it; the length is enough to debug with.
        log(f"ask user={user} provider={answer.provider} model={answer.model} "
            f"qlen={len(question)} took={took:.1f}s "
            f"outcome={'ok' if answer.ok else answer.kind} {note}")

        if answer.ok:
            max_a = int(cfg.get("max_answer_chars", 3000))
            return {"ok": True, "provider": answer.provider,
                    "model": answer.model, "text": answer.text[:max_a]}

        if answer.kind == "exhausted":
            hint = f" (retry at {answer.retry_hint})" if answer.retry_hint else ""
            spent.append(f"{answer.provider}: usage limit reached{hint}")
            continue

        # A real error is not a reason to spend the other subscription too.
        return {"ok": False, "kind": "error", "provider": answer.provider,
                "message": answer.detail}

    return {"ok": False, "kind": "exhausted",
            "message": "no provider could answer",
            "detail": spent}


def main() -> int:
    try:
        cfg = load_config()
    except Exception as exc:                      # noqa: BLE001
        log(f"config error: {exc}")
        reply({"ok": False, "kind": "error", "message": "helper misconfigured"})
        return 1

    try:
        req = read_request()
    except Exception as exc:                      # noqa: BLE001
        log(f"bad request: {exc}")
        reply({"ok": False, "kind": "error", "message": "bad request"})
        return 1

    op = req.get("op")
    if op == "ping":
        # Deliberately makes NO model call. The install-time connectivity proof
        # must not cost the owner a slice of their allowance.
        reply({"ok": True, "op": "ping", "providers": cfg["providers"]})
        return 0
    if op == "ask":
        reply(handle_ask(req, cfg))
        return 0

    reply({"ok": False, "kind": "error", "message": f"unknown op {op!r}"})
    return 1


if __name__ == "__main__":
    sys.exit(main())
