"""Offline contract tests for the portable CI regression harness.

No SWI-Prolog installation is required: mock executables exercise error
handling, discovery, working-directory independence, and failure propagation.
"""

import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "src" / "run_regression_tests.sh"
SRC = ROOT / "src"


class RegressionRunnerTests(unittest.TestCase):
    def invoke(self, *args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        values = os.environ.copy()
        if env:
            values.update(env)
        # Calling from outside the repo exercises working-directory independence.
        return subprocess.run(
            ["sh", str(SCRIPT), *args],
            cwd=tempfile.gettempdir(),
            env=values,
            capture_output=True,
            text=True,
            timeout=90,
            check=False,
        )

    def fake_swipl(self, directory: Path, exit_on: str | None = None) -> Path:
        executable = directory / "swipl-mock"
        executable.write_text(
            "#!/bin/sh\n"
            "for arg do\n"
            "  if [ \"$arg\" = '-s' ]; then next_is_suite=1; continue; fi\n"
            "  if [ \"${next_is_suite:-0}\" = 1 ]; then\n"
            "    printf '%s\\n' \"$arg\" >> \"$MOCK_LOG\"\n"
            f"    if [ \"$arg\" = '{exit_on or ''}' ]; then exit 25; fi\n"
            "    break\n"
            "  fi\n"
            "done\n"
            "exit 0\n",
            encoding="utf-8",
        )
        executable.chmod(0o755)
        return executable

    def test_list_discovers_all_suites(self) -> None:
        result = self.invoke("--list")
        self.assertEqual(result.returncode, 0, result.stderr)
        prolog = sorted(p.name for p in SRC.glob("*_regression_tests.pl"))
        python = sorted(p.name for p in SRC.glob("*_regression_tests.py"))
        self.assertGreater(len(prolog), 10)
        self.assertTrue(python)
        for suite in prolog + python:
            self.assertIn(suite, result.stdout)
        self.assertIn(f"Prolog suites ({len(prolog)})", result.stdout)
        self.assertIn(f"Python suites ({len(python)})", result.stdout)

    def test_bad_arguments_fail(self) -> None:
        for args in [("--unknown",), ("--all", "--list")]:
            with self.subTest(args=args):
                result = self.invoke(*args)
                self.assertEqual(result.returncode, 2)

    def test_missing_prolog_fails_without_silent_skip(self) -> None:
        result = self.invoke("--prolog-only", env={"SWIPL": "nonexistent-swipl-f16"})
        self.assertEqual(result.returncode, 127)
        self.assertIn("SWI-Prolog executable not found", result.stderr)

    def test_missing_python_fails_without_silent_skip(self) -> None:
        result = self.invoke("--python-only", env={"PYTHON": "nonexistent-python-f16"})
        self.assertEqual(result.returncode, 127)
        self.assertIn("Python executable not found", result.stderr)

    def test_each_prolog_suite_runs_in_separate_process(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            log = directory / "log"
            result = self.invoke("--prolog-only", env={
                "SWIPL": str(self.fake_swipl(directory)),
                "MOCK_LOG": str(log),
            })
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(log.read_text().splitlines(), sorted(
                p.name for p in SRC.glob("*_regression_tests.pl")
            ))

    def test_prolog_suite_failure_stops_runner(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            log = directory / "log"
            # The first test suite exits nonzero; no subsequent suites run.
            first = sorted(p.name for p in SRC.glob("*_regression_tests.pl"))[0]
            result = self.invoke("--all", env={
                "SWIPL": str(self.fake_swipl(directory, exit_on=first)),
                "MOCK_LOG": str(log),
                "PYTHON": "nonexistent-python-f16",
            })
            self.assertEqual(result.returncode, 25)
            self.assertEqual(log.read_text().splitlines(), [first])
            self.assertNotIn("All selected regression suites passed", result.stdout)

    def test_python_suite_failure_propagates(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            executable = Path(tmp) / "python-mock"
            executable.write_text("#!/bin/sh\nexit 29\n", encoding="utf-8")
            executable.chmod(0o755)
            result = self.invoke("--python-only", env={"PYTHON": str(executable)})
            self.assertEqual(result.returncode, 29)
            self.assertNotIn("All selected regression suites passed", result.stdout)

    def test_python_only_executes_real_host_tests(self) -> None:
        result = self.invoke("--python-only", env={
            "SWIPL": "nonexistent-swipl-f16", "PYTHON": sys.executable
        })
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("All selected regression suites passed", result.stdout)
        count = re.search(r"Ran (\d+) tests", result.stderr)
        self.assertIsNotNone(count, result.stderr)
        self.assertGreater(int(count.group(1)), 0)


if __name__ == "__main__":
    unittest.main()
