#!/usr/bin/env python3
"""Offline tests for guideline_agent.sh and its step in run_agent.sh.

The scripts and the Prolog stages are the real ones; a stub deepclause stands
in for the agents, so no API key or network is needed. SWI-Prolog is required.
"""
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

PROGRAM = """type Text
type Word
type Name
Word <: Text
Name <: Text
Name <: Word
if regex "[a-z]+" decide Word
guideline "the name of a person" decide Name
"""

# Answers every request with the first allowed type, as the guideline agent
# would, and logs each call. STUB_FAIL names the .dml to exit 1 on.
STUB = """#!/usr/bin/env python3
import glob, json, os, sys
root = os.environ["STUB_ROOT"]
dml = sys.argv[2]
with open(os.path.join(root, "calls.jsonl"), "a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\\n")
if dml == "dataset_builder.dml":
    os.makedirs("dataset/runs/r1", exist_ok=True)
    with open("dataset/runs/r1/manifest.json", "w") as f:
        json.dump({"selected_pmc_ids": ["PMC1"]}, f)
    print("Run manifest: /workspace/dataset/runs/r1/manifest.json")
if dml == "type_guidelines.dml":
    args = sys.argv[1:]
    only = next((a[len("papers="):] for a in args if a.startswith("papers=")), None)
    wanted = only.split(",") if only else None
    os.makedirs("dataset/cache", exist_ok=True)
    for name in sorted(glob.glob("dataset/papers/*/guideline_requests.json")):
        request = json.load(open(name))
        if wanted is not None and request["paper"] not in wanted:
            continue
        if os.environ.get("STUB_ANSWER", "1") != "1":
            continue
        with open("dataset/cache/guideline_answers.jsonl", "a") as cache:
            for batch in request["batches"]:
                for item in batch["items"]:
                    cache.write(json.dumps({
                        "program_sha256": request["program_sha256"],
                        "text": item["text"], "rule_type": item["rule_type"],
                        "caption": batch["caption"], "answer": item["allowed"][0],
                        "batch_id": batch["batch_id"]}) + "\\n")
sys.exit(1 if os.environ.get("STUB_FAIL") == dml else 0)
"""


TEXTS = {"PMC1": "alice", "PMC2": "bob"}


def table(pmc):
    return {"table_uid": f"{pmc}/t0", "pmc_id": pmc, "table_index": 0,
            "context": {"caption": "c"},
            "cells": [{"cell_id": 0, "row": 0, "column": 0, "kind": "source",
                       "text": TEXTS[pmc]}],
            "raster": [[0]]}


@unittest.skipUnless(shutil.which("swipl"), "SWI-Prolog is not installed")
class GuidelineAgentTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.agent = self.root / "agent"
        (self.agent / "src").mkdir(parents=True)
        (self.agent / "type_dsl_examples").mkdir()
        (self.agent / "type_dsl_examples/sci.tdsl").write_text(PROGRAM)
        for script in ("run_agent.sh", "guideline_agent.sh", "review_agent.sh"):
            shutil.copy(ROOT / script, self.agent)
        for source in (ROOT / "src").glob("*.pl"):
            shutil.copy(source, self.agent / "src")
        self.papers = self.agent / "src/dataset/papers"
        for pmc in ("PMC1", "PMC2"):
            (self.papers / pmc).mkdir(parents=True)
            (self.papers / pmc / "tables.jsonl").write_text(json.dumps(table(pmc)) + "\n")
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        stub = bin_dir / "deepclause"
        stub.write_text(STUB)
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC)
        self.env = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}",
                    "STUB_ROOT": str(self.root)}
        self.env.pop("LOG_DIR", None)
        self.env.pop("SWIPL", None)

    def run_script(self, script, *args, **env):
        return subprocess.run([str(self.agent / script), *args], text=True,
                              capture_output=True, env={**self.env, **env})

    def calls(self):
        log = self.root / "calls.jsonl"
        if not log.exists():
            return []
        return [json.loads(l) for l in log.read_text().splitlines()]

    def steps(self):
        return [call[1] for call in self.calls()]

    def guided(self, pmc):
        return json.loads((self.papers / pmc / "guided_types.jsonl").read_text())

    def test_all_stages_run_in_order(self):
        result = self.run_script("guideline_agent.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.guided("PMC1")["cells"][0]["type"], "Name")
        self.assertEqual(self.guided("PMC2")["cells"][0]["source"], "guideline")
        self.assertIn("2 paper(s): 2 routed cell(s), 2 typed by guidelines", result.stdout)
        log = (self.agent / "src/guideline_log.txt").read_text()
        self.assertIn("batch(es)", log)
        self.assertIn("typed by guidelines", log)
        self.assertEqual(self.steps(), ["type_guidelines.dml"])
        self.assertIn("--temperature", self.calls()[0])

    def test_papers_limits_every_stage(self):
        result = self.run_script("guideline_agent.sh", "--papers", "PMC2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("papers=PMC2", self.calls()[0])
        self.assertTrue((self.papers / "PMC2/guided_types.jsonl").exists())
        self.assertFalse((self.papers / "PMC1/types.jsonl").exists())

    def test_rerun_sends_only_what_is_unanswered(self):
        self.run_script("guideline_agent.sh")
        request = self.papers / "PMC1/guideline_requests.json"
        self.assertTrue(request.exists())
        result = self.run_script("guideline_agent.sh")
        self.assertIn("0 batch(es), 0 cell text(s) to send", result.stdout)
        self.assertFalse(request.exists())

    def test_model_failure_still_applies_and_is_reported(self):
        result = self.run_script("guideline_agent.sh", STUB_FAIL="type_guidelines.dml",
                                 STUB_ANSWER="0")
        self.assertEqual(result.returncode, 1)
        self.assertIn("2 pending", result.stdout)
        self.assertEqual(self.guided("PMC1")["cells"][0]["type"], "Word")

    def test_bad_program_stops_before_the_model(self):
        result = self.run_script("guideline_agent.sh", "--program", "/no/such.tdsl")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.calls(), [])

    def test_unknown_run_stops_before_the_model(self):
        result = self.run_script("guideline_agent.sh", "--run", "nope")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.calls(), [])

    def test_run_agent_runs_the_steps_on_the_build_papers(self):
        result = self.run_script("run_agent.sh", "topic")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.steps(), ["dataset_builder.dml", "type_guidelines.dml",
                                        "review_dataset.dml"])
        self.assertIn("papers=PMC1", self.calls()[1])
        self.assertTrue((self.papers / "PMC1/guided_types.jsonl").exists())
        self.assertFalse((self.papers / "PMC2/types.jsonl").exists())

    def test_run_agent_no_guidelines(self):
        result = self.run_script("run_agent.sh", "topic", "--no-guidelines")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.steps(), ["dataset_builder.dml", "review_dataset.dml"])

    def test_run_agent_no_review(self):
        result = self.run_script("run_agent.sh", "topic", "--no-review")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.steps(), ["dataset_builder.dml", "type_guidelines.dml"])

    def test_run_agent_build_only(self):
        result = self.run_script("run_agent.sh", "topic", "--no-review", "--no-guidelines")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.steps(), ["dataset_builder.dml"])

    def test_guideline_failure_does_not_stop_the_review(self):
        result = self.run_script("run_agent.sh", "topic", STUB_FAIL="type_guidelines.dml")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.steps()[-1], "review_dataset.dml")

    def test_review_starts_from_type_inference(self):
        result = self.run_script("run_agent.sh", "topic", "--scorer", "purity")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.steps()[-1], "review_dataset.dml")
        inference = (self.papers / "PMC1/type_inference.jsonl").read_text(encoding="utf-8")
        self.assertEqual(json.loads(inference.splitlines()[0])["scorer"], "purity")

    def test_type_inference_defaults_to_bit_cost(self):
        self.run_script("run_agent.sh", "topic")
        inference = (self.papers / "PMC1/type_inference.jsonl").read_text(encoding="utf-8")
        self.assertEqual(json.loads(inference.splitlines()[0])["scorer"], "bit-cost")

    def test_unknown_scorer_stops_before_the_review(self):
        result = self.run_script("run_agent.sh", "topic", "--scorer=nonsense")
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("review_dataset.dml", self.steps())

    def test_failed_build_runs_no_later_step(self):
        result = self.run_script("run_agent.sh", "topic", STUB_FAIL="dataset_builder.dml")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.steps(), ["dataset_builder.dml"])

    def test_options_reach_every_step(self):
        self.run_script("run_agent.sh", "topic", "--model", "m:x")
        for call in self.calls():
            self.assertIn("m:x", call)


if __name__ == "__main__":
    unittest.main()
