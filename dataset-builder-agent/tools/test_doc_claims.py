#!/usr/bin/env python3
"""Keep documentation from overstating what structural constraints prove (audit F02)."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ("README.md", "summary.md")
# Phrases the audit identified as overclaims: constraint satisfaction does not
# establish semantic header labels (e.g. an unmerged grid always admits (0,0)).
BANNED = (
    "declines rather than guesses",
    "labels do not drift",
    "cells are labelled as",
    "cells are labeled as",
)


class DocClaims(unittest.TestCase):
    def test_no_overclaiming_phrases(self):
        for name in DOCS:
            text = (ROOT / name).read_text(encoding="utf-8").lower()
            for phrase in BANNED:
                self.assertNotIn(phrase, text, f"{name} contains overclaim: {phrase!r}")

    def test_unverified_disclaimer_present(self):
        markers = ("unverified", "not verified", "not established")
        for name in DOCS:
            text = (ROOT / name).read_text(encoding="utf-8").lower()
            self.assertTrue(any(m in text for m in markers),
                            f"{name} must state that candidates are unverified")


if __name__ == "__main__":
    unittest.main()
