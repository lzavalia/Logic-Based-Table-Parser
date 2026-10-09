"""Host-side, fully offline F14 regression tests.

Run: python3 -m unittest -v ncbi_wait_regression_tests
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import ncbi_wait

SCRIPT = Path(__file__).with_name("ncbi_wait.py")


def invoke(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True, text=True, check=False, timeout=10,
    )


class HostTimedWaitTests(unittest.TestCase):
    def test_zero_wait(self):
        result = invoke("wait", "0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "SLEPT")

    def test_wait_is_not_cpu_busy_loop(self):
        begin_wall = time.monotonic()
        begin_cpu = time.process_time()
        ncbi_wait.wait(0.3)
        wall = time.monotonic() - begin_wall
        cpu = time.process_time() - begin_cpu
        self.assertGreaterEqual(wall, 0.27)
        self.assertLess(cpu, 0.1, f"expected OS sleep, consumed {cpu:.3f}s CPU")

    def test_wait_command_uses_actual_host_timer(self):
        begin = time.monotonic()
        result = invoke("wait", "0.15")
        elapsed = time.monotonic() - begin
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "SLEPT")
        self.assertGreaterEqual(elapsed, 0.14)

    def test_invalid_wait_duration_fails_closed(self):
        for value in ("-1", "inf", "nan", "301", "xyz", "0;touch /tmp/ignored"):
            with self.subTest(value=value):
                result = invoke("wait", value)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("SLEPT", result.stdout)

    def test_invalid_gap_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            for value in ("0.2", "61", "nan", "-5", "inf", "bad"):
                with self.subTest(value=value):
                    result = invoke("reserve", temp, value)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse((Path(temp) / ".ncbi-last-request").exists())

    def test_sequential_reservations_observe_gap(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            first = ncbi_wait.reserve(root, 0.35)
            second = ncbi_wait.reserve(root, 0.35)
            self.assertGreaterEqual(second - first, 0.345)
            self.assertFalse((root / ".ncbi-request.lock").exists())
            self.assertAlmostEqual(float((root / ".ncbi-last-request").read_text()), second, places=3)

    def test_independent_workers_coordinate_reservations(self):
        with tempfile.TemporaryDirectory() as temp:
            def reserve_one(_: int) -> tuple[subprocess.CompletedProcess[str], float]:
                result = invoke("reserve", temp, "0.35")
                return result, time.monotonic()

            with ThreadPoolExecutor(max_workers=3) as executor:
                completions = list(executor.map(reserve_one, range(3)))
            for completed, _ in completions:
                self.assertEqual(completed.returncode, 0, completed.stderr)
                self.assertEqual(completed.stdout.strip(), "RESERVED")
            finished = sorted(at for _, at in completions)
            for a, b in zip(finished, finished[1:]):
                self.assertGreaterEqual(b - a, 0.31)
            self.assertFalse((Path(temp) / ".ncbi-request.lock").exists())

    def test_broken_timestamp_preserves_state_and_releases_lock(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            state = root / ".ncbi-last-request"
            state.write_text("not a number", encoding="utf-8")
            result = invoke("reserve", temp, "0.35")
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(state.read_text(), "not a number")
            self.assertFalse((root / ".ncbi-request.lock").exists())

    def test_clock_skew_fails_closed_and_releases_lock(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / ".ncbi-last-request").write_text("99999999999")
            result = invoke("reserve", temp, "0.35")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("clock_skew", result.stderr)
            self.assertFalse((root / ".ncbi-request.lock").exists())

    def test_existing_lock_not_stolen(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            lock = root / ".ncbi-request.lock"
            lock.mkdir()
            with patch.object(ncbi_wait, "LOCK_ATTEMPTS", 1), patch.object(
                ncbi_wait, "LOCK_RETRY_SECONDS", 0.001
            ):
                with self.assertRaises(ncbi_wait.WaitFailure):
                    ncbi_wait.reserve(root, 0.35)
            self.assertTrue(lock.is_dir())

    def test_reservation_sleep_uses_os_wait_without_spin(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            previous = ncbi_wait.reserve(root, 0.35)
            start_cpu = time.process_time()
            start_wall = time.monotonic()
            next_time = ncbi_wait.reserve(root, 0.35)
            delta_wall = time.monotonic() - start_wall
            delta_cpu = time.process_time() - start_cpu
            self.assertGreaterEqual(next_time - previous, 0.345)
            self.assertGreaterEqual(delta_wall, 0.3)
            self.assertLess(delta_cpu, 0.1)


if __name__ == "__main__":
    unittest.main()
