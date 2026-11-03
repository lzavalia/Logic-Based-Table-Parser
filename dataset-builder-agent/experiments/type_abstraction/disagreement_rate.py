#!/usr/bin/env python3
"""Disagreement rate of the LLM review with and without the table repair.

A table sent to the model disagrees with the parser when the model's boundary
is not a parser candidate. With the repair (src/table_repair.pl) some of those
tables become valid, decided_by "repair". The repair runs after the model has
answered and the prompt does not depend on it, so the rate without the repair
is exact, from the same answers: a table decided by the repair counts as a
disagreement.

The baseline is a fixed list of papers (results/disagreement_baseline_papers.txt),
so that reviewing more papers later does not change it. --freeze writes that
list from the papers that have a review.jsonl.

    python3 disagreement_rate.py --freeze      # once: fix the baseline
    python3 disagreement_rate.py               # the counts, by split
"""
import argparse
import json
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATASET = HERE / "data" / "complex" / "ds"
BASELINE = HERE / "results" / "disagreement_baseline_papers.txt"
OUTPUT = HERE / "results" / "disagreement_rate_baseline.json"
SPLIT = HERE / "complex_split.json"
GOLD = [HERE / "gold_complex_dev.reviewed.jsonl", HERE / "gold_complex_test.reviewed.jsonl"]


def read_jsonl(path):
    with open(path, encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def reviews(dataset, papers):
    out = []
    for paper in papers:
        path = dataset / "papers" / paper / "review.jsonl"
        if not path.exists():
            raise SystemExit(f"{paper} is in the baseline but has no review.jsonl")
        out.extend(read_jsonl(path))
    return out


def check_provenance(records):
    """All reviews must come from one prompt, model, scorer and repair."""
    keys = Counter((r["prompt_version"], r["model"], r["scorer"]) for r in records)
    repairs = {(r.get("repair") or {}).get("repair_version") for r in records} - {None}
    if len(keys) != 1 or len(repairs) > 1:
        raise SystemExit(f"mixed reviews: {dict(keys)}, repair versions {sorted(repairs)}")
    (prompt, model, scorer), = keys
    return {"prompt_version": prompt, "model": model, "scorer": scorer,
            "repair_version": repairs.pop() if repairs else None}


def counts(records):
    asked = [r for r in records if r["decided_by"] in ("llm", "repair")]
    repaired = [r for r in asked if r["decided_by"] == "repair"]
    still = [r for r in asked if r["final_status"] == "unparseable"]
    n = len(asked)

    def rate(k):
        return round(100 * k / n, 1) if n else None

    return {
        "tables": len(records),
        "asked": n,
        "disagree_without_repair": len(repaired) + len(still),
        "rate_without_repair": rate(len(repaired) + len(still)),
        "disagree_with_repair": len(still),
        "rate_with_repair": rate(len(still)),
        "repaired": len(repaired),
        # Why the boundary is refused (first broken rule), before the repair.
        "category_without_repair": dict(Counter(
            (r.get("disagreement") or {}).get("category", "unknown")
            for r in repaired + still).most_common()),
        "category_with_repair": dict(Counter(
            (r.get("disagreement") or {}).get("category", "unknown")
            for r in still).most_common()),
        "repair_status_of_remaining": dict(Counter(
            (r.get("repair") or {}).get("status", "none") for r in still).most_common()),
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dataset", type=Path, default=DATASET)
    ap.add_argument("--baseline", type=Path, default=BASELINE)
    ap.add_argument("--output", type=Path, default=OUTPUT)
    ap.add_argument("--freeze", action="store_true",
                    help="write the baseline list from the papers with a review.jsonl")
    args = ap.parse_args()

    if args.freeze:
        if args.baseline.exists():
            raise SystemExit(f"{args.baseline} exists; the baseline is already fixed")
        papers = sorted(p.parent.name for p in (args.dataset / "papers").glob("*/review.jsonl"))
        args.baseline.write_text("\n".join(papers) + "\n", encoding="utf-8")
        print(f"baseline: {len(papers)} papers written to {args.baseline}")

    papers = [p for p in args.baseline.read_text(encoding="utf-8").split() if p]
    records = reviews(args.dataset, papers)
    provenance = check_provenance(records)
    split = json.loads(SPLIT.read_text(encoding="utf-8"))
    gold = {r["table_uid"] for path in GOLD for r in read_jsonl(path)}

    result = {"baseline_papers": len(papers), **provenance,
              "all": counts(records)}
    for name in ("dev", "test"):
        result[name] = counts([r for r in records if split.get(r["pmc_id"]) == name])
    result["gold_tables"] = counts([r for r in records if r["table_uid"] in gold])
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")

    print(f"{len(papers)} papers; {provenance}")
    print(f"{'':12}{'asked':>7}{'without repair':>18}{'with repair':>16}{'repaired':>10}")
    for name in ("all", "dev", "test", "gold_tables"):
        c = result[name]
        print(f"{name:12}{c['asked']:>7}"
              f"{c['disagree_without_repair']:>9} ({c['rate_without_repair']:>4}%)"
              f"{c['disagree_with_repair']:>8} ({c['rate_with_repair']:>4}%)"
              f"{c['repaired']:>10}")
    print(f"written to {args.output}")


if __name__ == "__main__":
    main()
