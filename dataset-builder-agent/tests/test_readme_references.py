#!/usr/bin/env python3
"""Fail if README.md names a src/, tests/ or tools/ file that does not exist (audit F16)."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
README = (ROOT / "README.md").read_text(encoding="utf-8")


class ReadmeReferences(unittest.TestCase):
    def test_every_named_file_in_readme_exists(self):
        named = set(re.findall(
            r"`((?:src|tests|tools)/[A-Za-z0-9_./-]+\.(?:pl|py|dml|sh))`", README))
        self.assertTrue(named, "README names no project files; pattern is stale")
        missing = sorted(n for n in named if not (ROOT / n).exists())
        self.assertEqual(missing, [], f"README references missing files: {missing}")

    def test_documented_driver_predicate_is_loadable_name(self):
        for name in re.findall(r"consult\((\w+)\)", README):
            self.assertTrue((ROOT / "src" / f"{name}.pl").exists(),
                            f"README consults {name}, but src/{name}.pl is absent")


if __name__ == "__main__":
    unittest.main()
