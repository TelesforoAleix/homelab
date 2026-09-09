"""
Executors — Phase 08.

Each executor does one thing and declares what it needs. The router decides
whether the caller is entitled to it; nothing here re-decides that.

THE READ EXECUTORS STILL NEVER FORK
-----------------------------------
Every figure comes from /proc, /etc/hostname or os.statvfs(). That was a Phase 07
property and it is kept: a process that cannot execute a program cannot be talked
into executing the wrong one.

THE PRIVILEGED EXECUTOR BREAKS THAT, DELIBERATELY
-------------------------------------------------
`restart` execs /usr/bin/systemctl. That is a real loss of a Phase 07 guarantee
and it is recorded rather than glossed. What replaces it:

  - NoNewPrivileges=yes is RETAINED, so the exec cannot gain privilege via
    setuid. This is why polkit is used instead of sudo -- sudo is setuid and
    is refused outright under no_new_privs:
        "sudo: The "no new privileges" flag is set, which prevents sudo from
         running as root."
  - CapabilityBoundingSet is empty.
  - The authority comes from a polkit rule scoped to ONE user, ONE unit and ONE
    verb -- evaluated by polkit inside PID 1, not by anything in this process.
  - The unit name is checked against an explicit allowlist here as well, so a
    bug in this file cannot reach a unit the rule would have permitted.

Two independent gates, in two different processes, neither trusting the other.
"""

from __future__ import annotations

import os
import socket
import subprocess

from router import Capability, Executor

SYSTEMCTL = "/usr/bin/systemctl"

# The exact path matters. /bin/systemctl is the same binary via a symlink, but
# polkit and any audit record see the argv you actually passed. Keep the string
# used here identical to the one named in the polkit rule and the documentation.


# --------------------------------------------------------------------------
# Host state. /proc and statvfs only. No subprocess.
# --------------------------------------------------------------------------

def _fmt_duration(seconds: float) -> str:
    s = int(seconds)
    d, s = divmod(s, 86400)
    h, s = divmod(s, 3600)
    m, _ = divmod(s, 60)
    if d:
        return f"{d}d {h}h {m}m"
    if h:
        return f"{h}h {m}m"
    return f"{m}m"


def _fmt_bytes(n: float) -> str:
    for unit in ("B", "K", "M", "G", "T"):
        if abs(n) < 1024:
            return f"{n:.1f}{unit}"
        n /= 1024
    return f"{n:.1f}P"


def host_uptime() -> str:
    with open("/proc/uptime", "r", encoding="utf-8") as fh:
        return _fmt_duration(float(fh.read().split()[0]))


def host_load() -> str:
    with open("/proc/loadavg", "r", encoding="utf-8") as fh:
        one, five, fifteen = fh.read().split()[:3]
    return f"{one} {five} {fifteen}"


def host_memory() -> str:
    vals = {}
    with open("/proc/meminfo", "r", encoding="utf-8") as fh:
        for line in fh:
            key, _, rest = line.partition(":")
            vals[key] = int(rest.split()[0]) * 1024
    total = vals.get("MemTotal", 0)
    available = vals.get("MemAvailable", 0)
    used = total - available
    pct = (used / total * 100) if total else 0
    return f"{_fmt_bytes(used)} / {_fmt_bytes(total)} used ({pct:.0f}%)"


def host_disk(path: str = "/") -> str:
    """
    Report usage the way `df` does.

    used = total - f_bfree, available = f_bavail. The naive
    `used = total - available` counts the filesystem's root-reserved blocks as
    used and reported 19.3G where df said 8.9G (Phase 07 build log).
    """
    st = os.statvfs(path)
    total = st.f_blocks * st.f_frsize
    used = (st.f_blocks - st.f_bfree) * st.f_frsize
    avail = st.f_bavail * st.f_frsize
    pct = (used / (used + avail) * 100) if (used + avail) else 0
    return f"{_fmt_bytes(used)} used, {_fmt_bytes(avail)} free of {_fmt_bytes(total)} ({pct:.0f}%)"


def host_name() -> str:
    try:
        with open("/etc/hostname", "r", encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return socket.gethostname()


# --------------------------------------------------------------------------
# READ executors
# --------------------------------------------------------------------------

def _status(_args: list[str]) -> str:
    return (
        f"host:   {host_name()}\n"
        f"uptime: {host_uptime()}\n"
        f"load:   {host_load()}\n"
        f"memory: {host_memory()}\n"
        f"disk /: {host_disk()}"
    )


def _disk(_args: list[str]) -> str:
    return f"disk /: {host_disk()}"


def _uptime(_args: list[str]) -> str:
    return f"uptime: {host_uptime()}\nload:   {host_load()}"


# --------------------------------------------------------------------------
# PRIVILEGED executor
# --------------------------------------------------------------------------

def make_restart(allowed_units: set[str], log) -> Executor:
    """
    Restart one service, from an explicit allowlist.

    The allowlist here is the SECOND gate, not the only one. polkit is the first
    and it lives in another process. Either alone would be a single point of
    failure; a bug in this file cannot reach a unit polkit would refuse, and a
    mistake in the polkit rule cannot reach a unit this list does not name.
    """

    def handler(args: list[str]) -> str:
        if not args:
            listing = ", ".join(sorted(allowed_units)) or "(none configured)"
            return f"usage: /restart <service>\nallowed: {listing}"

        unit = args[0]
        if not unit.endswith(".service"):
            unit = f"{unit}.service"

        if unit not in allowed_units:
            log(f"REFUSED restart: {unit} is not in the restart allowlist")
            listing = ", ".join(sorted(allowed_units)) or "(none configured)"
            return f"'{unit}' is not permitted.\nallowed: {listing}"

        # Exact argv. No shell, no string interpolation, nothing the caller
        # supplied reaches a shell at any point.
        try:
            proc = subprocess.run(
                [SYSTEMCTL, "restart", unit],
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
        except subprocess.TimeoutExpired:
            log(f"restart {unit}: TIMEOUT")
            return f"restart {unit}: timed out after 30s"
        except OSError as exc:
            log(f"restart {unit}: could not execute systemctl: {exc}")
            return f"restart {unit}: could not run systemctl ({exc})"

        if proc.returncode == 0:
            log(f"restart {unit}: ok")
            return f"restarted {unit}"

        # Fails closed and says so. A polkit denial arrives here as a non-zero
        # exit with a message on stderr; it is reported rather than swallowed.
        detail = (proc.stderr or proc.stdout or "").strip().splitlines()
        first = detail[0] if detail else f"exit {proc.returncode}"
        log(f"restart {unit}: FAILED rc={proc.returncode}: {first}")
        return f"restart {unit} failed: {first}"

    return Executor(
        name="/restart",
        capability=Capability.PRIVILEGED,
        handler=handler,
        summary="restart an allowlisted service",
        usage="/restart <service>",
    )


# --------------------------------------------------------------------------
# UNAVAILABLE executor — the model interface
# --------------------------------------------------------------------------

def _model(_args: list[str]) -> str:
    """
    The model executor is registered and deliberately not wired.

    This is a licensing decision, not a missing feature, and the reply says so
    rather than pretending to be a bug someone should fix.

    ADR-008 authorises subscription-backed INTERACTIVE access. It does not
    authorise unattended use, and whether automating a personal Claude Pro or
    ChatGPT subscription behind a service is within either provider's terms is
    something this project has not established. Wiring `claude -p` would work
    today and cost nothing, which is exactly why the decision needs making
    deliberately rather than by default.

    Phase 09 needs real transcription and will decide on its merits --
    subscription, API key, or local model -- and record it as an ADR.
    """
    return (
        "The model executor is registered but not connected.\n\n"
        "This is deliberate. ADR-008 authorises subscription-backed interactive\n"
        "access; it does not authorise unattended use, and whether automating a\n"
        "personal subscription behind a service is permitted by the provider is\n"
        "not something this project has established.\n\n"
        "Phase 09 needs a real model call and will decide on its merits."
    )


# --------------------------------------------------------------------------
# Registration
# --------------------------------------------------------------------------

def build_help(router) -> Executor:
    """
    /help, generated from the registry.

    Hand-maintained help text is how an undocumented command survives. Adding an
    executor changes this output without anyone editing prose.
    """

    def handler(_args: list[str]) -> str:
        lines = ["Home Lab bot — commands:", ""]
        for ex in router.unique_executors():
            mark = {
                Capability.READ: " ",
                Capability.PRIVILEGED: "*",
                Capability.UNAVAILABLE: "-",
            }[ex.capability]
            label = ex.usage or ex.name
            lines.append(f" {mark} {label:<22} {ex.summary}")
        lines += [
            "",
            " * privileged — requires authorisation",
            " - registered but not connected",
        ]
        return "\n".join(lines)

    return Executor(
        name="/help",
        capability=Capability.READ,
        handler=handler,
        summary="this message",
    )


def register_all(router, *, allowed_units: set[str], log) -> None:
    router.register(Executor("/status", Capability.READ, _status,
                             "host, uptime, load, memory, disk"))
    router.register(Executor("/disk", Capability.READ, _disk,
                             "root filesystem usage"))
    router.register(Executor("/uptime", Capability.READ, _uptime,
                             "uptime and load average"))
    router.register(make_restart(allowed_units, log))
    router.register(Executor("/model", Capability.UNAVAILABLE, _model,
                             "model access — registered, not connected"))
    router.register(build_help(router), "/start")
