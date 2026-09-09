"""
Call caps — Phase 09.

WHAT THIS PROTECTS
------------------
Not money. Both subscriptions are already paid for and `/ask` adds no charge.
What it protects is CAPACITY: every call the bot makes spends allowance out of
the same bucket the owner needs for their own work. Phase 06 lost an evening to
an exhausted Claude window, and Codex was already exhausted when the Phase 09
brief was written. A bot that can burn the owner's afternoon from a phone is a
denial of service the owner built themselves.

So the caps are not a billing control. They are there so a stuck finger on a
phone cannot cost the owner their next working session.

WHY THE STATE IS A FILE, AND WHY IT IS LOCKED
---------------------------------------------
The helper is socket-activated with Accept=yes: systemd spawns ONE PROCESS PER
CONNECTION. There is no long-lived process to hold a counter in memory, and two
connections can overlap. An in-memory counter would reset on every call and
count nothing.

So the counter is a file, and every read-modify-write takes an exclusive
flock(2). Without the lock, two simultaneous requests both read "9 calls used",
both decide there is room, and both call. The window for that is small and it
would be invisible when it happened -- which is exactly the kind of bug that
does not show up until the day it matters.

The reservation is taken BEFORE the call, and it is not refunded if the provider
turns out to be exhausted. An attempt is an attempt: it was made, it took time,
and counting it is the honest accounting. A fallback that tries Claude and then
Codex therefore spends one call from each -- which is what actually happened.
"""

from __future__ import annotations

import fcntl
import json
import os
import time

HOUR = 3600
DAY = 86400


class Limiter:
    def __init__(self, path: str, per_hour: int, per_day: int) -> None:
        self.path = path
        self.per_hour = per_hour
        self.per_day = per_day

    def _load(self, fh) -> dict:
        fh.seek(0)
        raw = fh.read()
        if not raw.strip():
            return {}
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            # A corrupt counter must not become an unlimited counter. Start
            # from empty and say so; fail-closed would mean the bot never
            # answers again after one bad write, fail-open would mean no cap.
            # Empty is the middle: the caps still apply, the history is lost.
            return {}
        return data if isinstance(data, dict) else {}

    def check_and_reserve(self, provider: str) -> tuple[bool, str]:
        """
        Returns (allowed, message). On success the call is already counted.

        Opened O_RDWR|O_CREAT rather than "w" -- "w" truncates before the lock
        is taken, which would erase the counter of whoever holds it.
        """
        now = time.time()
        fd = os.open(self.path, os.O_RDWR | os.O_CREAT, 0o600)
        with os.fdopen(fd, "r+", encoding="utf-8") as fh:
            fcntl.flock(fh, fcntl.LOCK_EX)
            try:
                data = self._load(fh)
                stamps = [t for t in data.get(provider, [])
                          if isinstance(t, (int, float)) and now - t < DAY]

                in_hour = sum(1 for t in stamps if now - t < HOUR)
                in_day = len(stamps)

                if in_hour >= self.per_hour:
                    oldest = min(t for t in stamps if now - t < HOUR)
                    return False, (
                        f"{provider}: hourly cap reached "
                        f"({in_hour}/{self.per_hour}). "
                        f"Room again in {_mins(oldest + HOUR - now)}."
                    )
                if in_day >= self.per_day:
                    oldest = min(stamps)
                    return False, (
                        f"{provider}: daily cap reached "
                        f"({in_day}/{self.per_day}). "
                        f"Room again in {_mins(oldest + DAY - now)}."
                    )

                stamps.append(now)
                data[provider] = stamps
                fh.seek(0)
                fh.truncate()
                json.dump(data, fh)
                fh.flush()
                os.fsync(fh.fileno())
                return True, f"{provider}: {in_hour + 1}/{self.per_hour} this hour"
            finally:
                fcntl.flock(fh, fcntl.LOCK_UN)

    def snapshot(self) -> dict:
        """Read-only view for /ask --status style reporting. Takes a shared lock."""
        now = time.time()
        out = {}
        try:
            fd = os.open(self.path, os.O_RDONLY)
        except FileNotFoundError:
            return out
        with os.fdopen(fd, "r", encoding="utf-8") as fh:
            fcntl.flock(fh, fcntl.LOCK_SH)
            try:
                data = self._load(fh)
            finally:
                fcntl.flock(fh, fcntl.LOCK_UN)
        for provider, stamps in data.items():
            if not isinstance(stamps, list):
                continue
            good = [t for t in stamps if isinstance(t, (int, float)) and now - t < DAY]
            out[provider] = {
                "hour": sum(1 for t in good if now - t < HOUR),
                "day": len(good),
            }
        return out


def _mins(seconds: float) -> str:
    m = max(0, int(seconds // 60))
    if m >= 60:
        return f"{m // 60}h {m % 60}m"
    return f"{m}m" if m else "under a minute"
