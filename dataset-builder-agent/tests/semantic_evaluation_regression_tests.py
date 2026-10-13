"""Exercise the offline evaluator with synthetic, explicitly NOT human gold."""
import json
import tempfile
import unittest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from evaluate_structural_candidates import evaluate, records_from_jsonl


class EvaluationTests(unittest.TestCase):
    def test_counts_denomination_and_no_headers(self):
        predictions = {
            ("PMC1", 0): {"status": "unique", "candidates": [{"hmd": 0, "vmd": 0}]},
            ("PMC1", 1): {"status": "ambiguous", "candidates": [{"hmd": 0, "vmd": 0}, {"hmd": 1, "vmd": 0}]},
            ("PMC1", 2): {"status": "abstained", "candidates": []},
            ("PMC1", 3): {"status": "unique", "candidates": [{"hmd": 0, "vmd": 0}]},
        }
        gold = {("PMC1", 0): {"hmd": 0, "vmd": 0},
                ("PMC1", 1): {"hmd": 1, "vmd": 0},
                ("PMC1", 2): None, ("PMC1", 3): None}
        result = evaluate(predictions, gold)
        c, m = result['counts'], result['metrics']
        self.assertEqual(c['gold_in_candidate_set'], 2)
        self.assertEqual(c['no_header_false_candidates'], 1)
        self.assertEqual(m['candidate_recall_on_header_tables'], 1.0)
        self.assertEqual(m['unique_prediction_precision'], 0.5)
        self.assertEqual(m['unique_prediction_coverage'], 0.5)
        self.assertEqual(m['no_header_false_candidate_rate'], 0.5)

    def test_does_not_invent_gold_results(self):
        with self.assertRaises(ValueError):
            evaluate({}, {})
        with self.assertRaises(ValueError):
            evaluate({}, {('PMC7', 0): None})

    def test_duplicate_id_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            file = Path(tmp) / 'data.jsonl'
            row = {'pmc_id': 'PMC1', 'table_index': 0}
            file.write_text(json.dumps(row) + '\n' + json.dumps(row) + '\n')
            with self.assertRaises(ValueError):
                records_from_jsonl([file])


if __name__ == '__main__':
    unittest.main()
