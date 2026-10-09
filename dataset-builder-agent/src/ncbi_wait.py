#!/usr/bin/env python3
"""Non-spinning host-side waits for DeepClause's table dataset builder.

This deliberately shares the lock directory and timestamp file used by
``dataset_pipeline:ncbi_rate_limit_at/3`` in native SWI-Prolog, so host
reservations and native reservations cannot interleave unsafely.

Only internal, numeric DML parameters are passed through the shell. No
untrusted URL, PMC ID, search text, or path enters the command line.
"""

from __future__ import annotations

import argparse
import math
import os
from pathlib import Path
import sys
import tempfile
import time

LOCK_ATTEMPTS = 300
LOCK_RETRY_SECONDS = 0.1
MIN_GAP = 0.34
MAX_GAP = 60.0
MAX_WAIT = 300.0


class WaitFailure(RuntimeError):
    """Validation or shared-limiter failure: a request must not proceed."""


def bounded_seconds(value: str, minimum: float, maximum: float) -> float:
    try:
        seconds = float(value)
    except (TypeError, ValueError) as exc:
        raise WaitFailure(f"invalid wait duration: {value!r}") from exc
    if not math.isfinite(seconds) or not minimum <= seconds <= maximum:
        raise WaitFailure(f"wait duration outside [{minimum}, {maximum}]: {value!r}")
    return seconds


def wait(seconds: float) -> None:
    # time.sleep() releases the OS thread and lets the host event loop
    # resume the WASM engine when exec(bash/1) completes.
    time.sleep(seconds)


def read_timestamp(path: Path) -> float:
    if not path.exists():
        return 0.0
    try:
        raw = path.read_text(encoding="utf-8").strip()
        stamp = float(raw)
    except (ValueError, UnicodeError) as exc:
        raise WaitFailure(f"invalid shared NCBI timestamp at {path}") from exc
    if not math.isfinite(stamp) or stamp < 0:
        raise WaitFailure(f"invalid shared NCBI timestamp at {path}")
    return stamp


def write_timestamp(path: Path, stamp: float) -> None:
    # Atomic replace, under the shared lock, prevents truncated state.
    fd, temporary = tempfile.mkstemp(prefix=".ncbi-last-request.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(f"{stamp:.16f}\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def reserve(cache_root: Path, gap: float) -> float:
    cache_root.mkdir(parents=True, exist_ok=True)
    lock = cache_root / ".ncbi-request.lock"
    stamp_path = cache_root / ".ncbi-last-request"

    for attempt in range(LOCK_ATTEMPTS + 1):
        try:
            lock.mkdir()
            break
        except FileExistsError:
            if attempt >= LOCK_ATTEMPTS:
                raise WaitFailure(
                    f"concurrent_lock_busy({lock}): inspect active workers before removing a stale lock"
                ) from None
            wait(LOCK_RETRY_SECONDS)
    try:
        previous = read_timestamp(stamp_path)
        now = time.time()
        if previous > now + 60:
            raise WaitFailure(f"ncbi_rate_clock_skew({previous}, {now})")
        wait(max(0.0, previous + gap - now))
        reserved_at = time.time()
        # System time may have jumped backwards during a wait; fail closed.
        if reserved_at + 1e-6 < previous + gap:
            raise WaitFailure("clock moved backwards during NCBI reservation")
        write_timestamp(stamp_path, reserved_at)
        return reserved_at
    finally:
        # Do NOT delete a lock owned by a different process. This process
        # only enters the finally block after it successfully creates it.
        lock.rmdir()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    delay = sub.add_parser("wait", help="sleep without spinning")
    delay.add_argument("seconds")
    reservation = sub.add_parser("reserve", help="reserve shared NCBI request slot")
    reservation.add_argument("cache_root", type=Path)
    reservation.add_argument("gap")
    args = parser.parse_args(argv)
    try:
        if args.action == "wait":
            wait(bounded_seconds(args.seconds, 0, MAX_WAIT))
            print("SLEPT")
        else:
            gap = bounded_seconds(args.gap, MIN_GAP, MAX_GAP)
            reserve(args.cache_root, gap)
            print("RESERVED")
        return 0
    except (WaitFailure, OSError, OverflowError) as exc:
        print(f"NCBI host wait failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
