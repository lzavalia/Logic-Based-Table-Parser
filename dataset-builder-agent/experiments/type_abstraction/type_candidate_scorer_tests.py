"""Exercise the Phase 1 description-length scorer on synthetic tables."""
import math
import unittest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from type_candidate_scorer import description_length, prior11, score_table, select
from type_region_phase0 import boundary_regions

# A header row of Text over a row-header column of Text and Numeric data.
RASTER = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [9, 10, 11]]
FAMILIES = ["Text", "Text", "Text",
            "Text", "Numeric", "Numeric",
            "Text", "Numeric", "Numeric",
            "Text", "Numeric", "Numeric"]


def candidate(hmd, vmd):
    regions = boundary_regions({"raster": RASTER}, hmd, vmd)
    return {"candidate_id": f"PMC1/t0/h{hmd}_v{vmd}", "kind": "boundary",
            "hmd": hmd, "vmd": vmd,
            "labels": [{"cell_id": i, "region": r} for i, r in regions.items()]}


def typed(families):
    return {"cells": [{"cell_id": i, "type": f, "family": f}
                      for i, f in enumerate(families)]}


def record(*shapes):
    return {"table_uid": "PMC1/t0", "raster": RASTER,
            "candidates": [candidate(h, v) for h, v in shapes]}


class ScorerTests(unittest.TestCase):
    def test_true_boundary_is_cheapest(self):
        rec, ty = record(), typed(FAMILIES)
        costs = {(h, v): description_length(rec, ty, candidate(h, v), "family")
                 for h, v in [(1, 1), (0, 1), (1, 0), (2, 1), (1, 2)]}
        self.assertEqual(costs[(1, 1)], 0.0)
        # Too little metadata mixes Text into data lines; too much puts
        # Numeric cells into a header row or column.
        for shape in [(0, 1), (1, 0), (2, 1), (1, 2)]:
            self.assertGreater(costs[shape], 0.0, shape)

    def test_line_header_model_misses_numeric_vmd_column(self):
        # The first, pre-registered version: each VMD column alone is
        # uniform, so moving a numeric data column into the VMD costs nothing.
        cost = description_length(record(), typed(FAMILIES), candidate(1, 2),
                                  "family", header_model="line")
        self.assertEqual(cost, 0.0)

    def test_spanning_header_cell_counted_once(self):
        raster = [[0, 0], [1, 2], [3, 4]]
        rec = {"raster": raster}
        cand = {"kind": "boundary", "hmd": 2, "vmd": 0,
                "labels": [{"cell_id": i, "region": r} for i, r in
                           boundary_regions(rec, 2, 0).items()]}
        ty = typed(["Text", "Text", "Numeric", "Numeric", "Numeric"])
        # HMD holds cells 0, 1, 2 once each: Text, Text, Numeric.
        expected = -(2 * math.log2(2 / 3) + math.log2(1 / 3))
        self.assertAlmostEqual(description_length(rec, ty, cand, "family"), expected)

    def test_model_cost_penalises_spurious_subtables(self):
        # Splitting the table into two side-by-side subtables, each with its
        # own VMD column, is free without a model cost (every line is still
        # uniform) but uses more distributions, so it costs more with one.
        rec, ty = record(), typed(FAMILIES)
        regions = boundary_regions({"raster": RASTER}, 1, 1)
        regions[2] = "hmd"
        split = {"candidate_id": "PMC1/t0/layout0", "kind": "layout", "hmd": 1, "vmd": 1,
                 "separators": [],
                 "subtables": [{"rows": [0, 1, 2, 3], "columns": [0, 1], "hmd": 1, "vmd": 1},
                               {"rows": [0, 1, 2, 3], "columns": [2], "hmd": 1, "vmd": 0}],
                 "labels": [{"cell_id": i, "region": r} for i, r in regions.items()]}
        plain = candidate(1, 1)
        self.assertEqual(description_length(rec, ty, split, "family"), 0.0)
        self.assertEqual(description_length(rec, ty, plain, "family"), 0.0)
        self.assertGreater(description_length(rec, ty, split, "family", model_cost=True),
                           description_length(rec, ty, plain, "family", model_cost=True))

    def test_identifier_column_is_data_by_role(self):
        # Column 0 holds study citations. Without the role the scorer takes
        # it as a VMD (the Identifier column is uniform and the data rows
        # are then purely Numeric); with the role, h1_v0 is cheaper.
        families = ["Text", "Text", "Text",
                    "Identifier", "Numeric", "Numeric",
                    "Identifier", "Numeric", "Numeric",
                    "Identifier", "Numeric", "Numeric"]
        rec, ty = record(), typed(families)
        def cost(h, v, roles):
            return description_length(rec, ty, candidate(h, v), "family",
                                      model_cost=True, data_families=roles)
        self.assertLess(cost(1, 1, ()), cost(1, 0, ()))
        self.assertLess(cost(1, 0, {"Identifier"}), cost(1, 1, {"Identifier"}))

    def test_one_type_tables_abstain(self):
        rec = record((1, 1), (1, 0), (0, 1))
        result = score_table(rec, typed(["Text"] * 12), "family")
        self.assertIsNone(result["selected"])
        self.assertEqual(set(result["costs"].values()), {0.0})

    def test_ignored_families_do_not_count(self):
        families = list(FAMILIES)
        families[5] = "Missing"
        families[8] = "untyped"
        self.assertEqual(description_length(record(), typed(families),
                                             candidate(1, 1), "family"), 0.0)

    def test_select_and_prior(self):
        self.assertEqual(select([("a", 3.0), ("b", 1.0)]), ("b", 2.0))
        self.assertEqual(select([("a", 1.0), ("b", 1.0)])[0], None)
        cands = [candidate(1, 0), candidate(2, 1), candidate(1, 1)]
        self.assertEqual(prior11(cands), "PMC1/t0/h1_v1")


if __name__ == "__main__":
    unittest.main()
