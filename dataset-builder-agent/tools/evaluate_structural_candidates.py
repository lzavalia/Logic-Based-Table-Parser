#!/usr/bin/env python3
"""Offline evaluation of structural candidates against independently labeled gold.

Gold JSONL row: {"pmc_id":"PMC123", "table_index":0,
                 "gold_boundary":{"hmd":0,"vmd":0}}
Use null for gold_boundary if human annotation says there is no HMD+VMD
segmentation; this does NOT train or infer semantic labels.
"""
import argparse
import json
import sys
from pathlib import Path


def records_from_jsonl(paths):
    result = {}
    for path in paths:
        with Path(path).open(encoding="utf-8") as src:
            for line_no, line in enumerate(src, start=1):
                if not line.strip():
                    continue
                obj = json.loads(line)
                key = (obj["pmc_id"], obj["table_index"])
                if key in result:
                    raise ValueError(f"duplicate table identity {key} at {path}:{line_no}")
                result[key] = obj
    return result


def evaluate(records, gold):
    """Return denominated metrics; never call hypothesis membership 'accuracy'."""
    if not gold:
        raise ValueError("empty gold set")
    missing = set(gold) - set(records)
    if missing:
        raise ValueError(f"missing predictions for {sorted(missing)!r}")
    c = dict(labeled_tables=0, gold_header_tables=0, gold_no_header_tables=0,
             predicted_unique=0, predicted_ambiguous=0, predicted_abstained=0,
             correctly_unique=0, gold_in_candidate_set=0,
             no_header_false_candidates=0, no_header_abstentions=0,
             quarantined=0)
    for key, gt in gold.items():
        obj = records[key]
        candidates = obj.get("candidates", [])
        if not isinstance(candidates, list):
            raise ValueError(f"invalid candidate list for {key}")
        status = obj.get("status")
        if status == "quarantined":
            c["quarantined"] += 1
        elif not candidates:
            c["predicted_abstained"] += 1
        elif len(candidates) == 1:
            c["predicted_unique"] += 1
        else:
            c["predicted_ambiguous"] += 1
        if gt is None:
            c["gold_no_header_tables"] += 1
            if candidates:
                c["no_header_false_candidates"] += 1
            else:
                c["no_header_abstentions"] += 1
        else:
            c["gold_header_tables"] += 1
            matches = sum(isinstance(p, dict) and
                          p.get("hmd") == gt["hmd"] and p.get("vmd") == gt["vmd"]
                          for p in candidates)
            if matches:
                c["gold_in_candidate_set"] += 1
            if len(candidates) == 1 and matches:
                c["correctly_unique"] += 1
        c["labeled_tables"] += 1
    def ratio(num, den):
        return None if den == 0 else round(num / den, 6)
    metrics = dict(
        candidate_recall_on_header_tables=ratio(c["gold_in_candidate_set"], c["gold_header_tables"]),
        unique_prediction_precision=ratio(c["correctly_unique"], c["predicted_unique"]),
        unique_prediction_coverage=ratio(c["predicted_unique"], c["labeled_tables"]),
        unique_exact_match_on_all_tables=ratio(c["correctly_unique"], c["labeled_tables"]),
        no_header_false_candidate_rate=ratio(c["no_header_false_candidates"], c["gold_no_header_tables"]),
        abstention_rate=ratio(c["predicted_abstained"], c["labeled_tables"]),
        ambiguous_rate=ratio(c["predicted_ambiguous"], c["labeled_tables"]),
    )
    return {"counts": c, "metrics": metrics,
            "disclaimer": "Only comparison with independent human gold evaluates semantic correctness; candidates are structural hypotheses."}


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--predictions", nargs="+", required=True, type=Path,
                   help="One or more tables.jsonl files")
    p.add_argument("--gold", required=True, type=Path, help="Human-labeled JSONL")
    p.add_argument("--output", type=Path, help="Optional JSON result file")
    args = p.parse_args(argv)
    gold = records_from_jsonl([args.gold])
    cleaned = {}
    for key, row in gold.items():
        gt = row["gold_boundary"]
        if gt is not None and not (isinstance(gt, dict) and
                                    set(gt) == {"hmd", "vmd"} and
                                    all(type(gt[k]) is int and gt[k] >= 0
                                        for k in ("hmd", "vmd"))):
            p.error(f"invalid gold_boundary for {key}")
        cleaned[key] = gt
    out = evaluate(records_from_jsonl(args.predictions), cleaned)
    encoded = json.dumps(out, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_text(encoded, encoding="utf-8")
    sys.stdout.write(encoded)


if __name__ == "__main__":
    main()
