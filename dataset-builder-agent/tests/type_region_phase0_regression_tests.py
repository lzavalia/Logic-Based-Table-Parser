"""Exercise the Phase 0 type/region analysis on a synthetic table."""
import contextlib
import io
import json
import random
import tempfile
import unittest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from type_region_phase0 import (boundary_regions, contrast, dependence, lines,
                                main, mutual_information, purity)

# A 3x3 table: a header row of Text, a row-header column of Text, Numeric
# data, and one Missing data cell.
RASTER = [[0, 1, 2], [3, 4, 5], [6, 7, 8]]
FAMILIES = ["empty", "Text", "Text", "Text", "Numeric", "Numeric",
            "Text", "Numeric", "Missing"]


def record():
    return {"pmc_id": "PMC1", "table_index": 0, "table_uid": "PMC1/t0",
            "raster": RASTER,
            "cells": [{"cell_id": i} for i in range(9)],
            "candidates": [candidate(1, 1), candidate(1, 0)]}


def candidate(hmd, vmd):
    regions = boundary_regions({"raster": RASTER}, hmd, vmd)
    return {"candidate_id": f"PMC1/t0/h{hmd}_v{vmd}", "kind": "boundary",
            "hmd": hmd, "vmd": vmd,
            "labels": [{"cell_id": i, "region": regions[i]} for i in range(9)]}


def typed():
    cells = [{"cell_id": i, "type": f, "family": f} for i, f in enumerate(FAMILIES)]
    return {"table_uid": "PMC1/t0", "cells": cells,
            "counts": {"cells": 9, "empty": 1, "untyped": 0, "typed": 8}}


class Phase0Tests(unittest.TestCase):
    def test_mutual_information(self):
        mi, h = mutual_information([("a", "x"), ("b", "y")] * 4)
        self.assertAlmostEqual(mi, 1.0)
        self.assertAlmostEqual(h, 1.0)
        mi, _ = mutual_information([("a", "x"), ("a", "y")])
        self.assertAlmostEqual(mi, 0.0)

    def test_boundary_regions_reject_cut_merged_cells(self):
        merged = {"raster": [[0, 0], [1, 2]]}
        self.assertIsNone(boundary_regions(merged, 0, 1))
        self.assertEqual(boundary_regions(merged, 1, 0), {0: "hmd", 1: "data", 2: "data"})

    def test_lines_purity_and_contrast(self):
        regions = boundary_regions(record(), 1, 1)
        self.assertEqual(lines(record(), regions, 0), [(1, [4, 7]), (2, [5, 8])])
        self.assertEqual(lines(record(), regions, 1), [(3, [4, 5]), (6, [7, 8])])
        self.assertEqual(purity(record(), typed(), regions, "family"),
                         {"column": 1.0, "row": 1.0})
        self.assertEqual(contrast(record(), typed(), regions, "family"),
                         {"column": (2, 2), "row": (2, 2)})
        # Without the VMD column the Text row headers join the data rows.
        no_vmd = boundary_regions(record(), 1, 0)
        # Row 1 is Text, Numeric, Numeric (2/3); row 2 Text, Numeric and an
        # ignored Missing cell (1/2).
        scores = purity(record(), typed(), no_vmd, "family")
        self.assertEqual(scores["column"], 1.0)
        self.assertAlmostEqual(scores["row"], 7 / 12)

    def test_dependence_against_permutations(self):
        labeled = [(record(), typed(), candidate(1, 1))]
        result = dependence(labeled, "family", 20, random.Random(0))
        self.assertEqual(result["labeled_cells"], 9)
        self.assertGreater(result["pooled_mi_bits"], result["pooled_null_mean_bits"])
        self.assertEqual(result["type_given_region"]["data"],
                         {"Numeric": 0.75, "Missing": 0.25})

    def test_main_end_to_end(self):
        with tempfile.TemporaryDirectory() as tmp:
            paper = Path(tmp, "papers", "PMC1")
            paper.mkdir(parents=True)
            (paper / "tables.jsonl").write_text(json.dumps(record()) + "\n")
            (paper / "types.jsonl").write_text(json.dumps(typed()) + "\n")
            gold = Path(tmp, "gold.jsonl")
            gold.write_text(json.dumps({"pmc_id": "PMC1", "table_index": 0,
                                        "gold_candidate": "PMC1/t0/h1_v1",
                                        "confidence": "high"}) + "\n")
            out = Path(tmp, "out.json")
            with contextlib.redirect_stdout(io.StringIO()):
                main(["--dataset", tmp, "--gold", str(gold), "--permutations", "5",
                      "--output", str(out)])
            result = json.loads(out.read_text())
        self.assertEqual(result["tables"], 1)
        self.assertEqual(result["coverage"]["untyped_rate"], 0.0)
        self.assertEqual(result["gold_data_regions"], {"mostly_numeric": 1})
        # h2_v1 is just as pure: purity alone saturates, as on real tables.
        self.assertEqual(result["purity"]["row"]["gold_tied_purest_share"], 1.0)


if __name__ == "__main__":
    unittest.main()
