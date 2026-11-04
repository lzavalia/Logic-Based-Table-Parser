#!/usr/bin/env python3
"""Score an ablation run: accuracy and tokens per arm.

  python3 score_ablation.py COLLECTED.jsonl DATASET_DIR RUN_DIR
                            [--input-price USD_PER_MTOK --output-price USD_PER_MTOK]

COLLECTED is the output of src/ablation_collect.pl, DATASET_DIR the dataset
the arms ran on, RUN_DIR the run directory of run_ablation.sh, which holds
<arm>/<table>/review_token_usage.json for every call. Writes
RUN_DIR/scores.json and RUN_DIR/summary.md and prints the summary.

Each table ends in one outcome per arm:

  correct          accepted, and the segmentation equals the gold one
  wrong_accepted   accepted with another segmentation: a silent error
  invalid_output   accepted, but the export could not build it (llm-only)
  rejected         the arm refused to give a parse (unparseable)
  not_reviewed     not sent, or no usable answer

cell_accuracy is the share of the table's cells (each merged cell once) given
the gold label: hmd, vmd, data, separator. Over "answered" tables it is
measured on the accepted segmentation; "end to end" counts a table without
one as 0. llm_correct says whether the model's own answer was right, also
where the arm refused it. There are no significance tests: the smoke sample
is far too small for them.
"""
import argparse
import json
from collections import defaultdict
from pathlib import Path

ARM_ORDER = ["llm-only", "constraints", "full"]


def read_jsonl(path):
    return [json.loads(line) for line in Path(path).read_text().splitlines() if line.strip()]


def table_record(dataset, uid):
    pmc = uid.split("/")[0]
    for r in read_jsonl(Path(dataset, "papers", pmc, "tables.jsonl")):
        if r["table_uid"] == uid:
            return r
    raise KeyError(uid)


def slot_label(seg, row, col):
    if seg is None:
        return None
    if row in seg["separator_rows"]:
        return "separator"
    for sub in seg["subtables"]:
        if not (sub["first_row"] <= row <= sub["last_row"]
                and sub["first_column"] <= col <= sub["last_column"]):
            continue
        rows = [r for r in range(sub["first_row"], sub["last_row"] + 1)
                if r not in seg["separator_rows"]]
        if rows.index(row) < sub["column_header_rows"]:
            return "hmd"
        if col - sub["first_column"] < sub["row_header_columns"]:
            return "vmd"
        return "data"
    return "uncovered"


def cell_accuracy(record, seg, gold):
    if seg is None or gold is None:
        return None
    cells = [c for c in record["cells"] if c.get("kind") != "synthetic_gap"]
    same = sum(slot_label(seg, c["row"], c["column"]) == slot_label(gold, c["row"], c["column"])
               for c in cells)
    return same / len(cells) if cells else None


def outcome(line):
    status = line["final_status"]
    if status == "valid":
        if line["export_error"]:
            return "invalid_output"
        return "correct" if line["accepted_correct"] else "wrong_accepted"
    if status == "unparseable":
        return "rejected"
    return "not_reviewed"


def usage(run_dir, arm, uid):
    path = Path(run_dir, arm, uid.replace("/", "_"), "review_token_usage.json")
    totals = {"calls": 0, "inputTokens": 0, "outputTokens": 0}
    if not path.exists():
        return None
    for model_usage in json.loads(path.read_text()).values():
        for key in totals:
            totals[key] += model_usage.get(key, 0) or 0
    return totals


def pct(n, d):
    return f"{n}/{d}" if d else "–"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("collected")
    ap.add_argument("dataset")
    ap.add_argument("run_dir")
    ap.add_argument("--input-price", type=float, help="USD per million input tokens")
    ap.add_argument("--output-price", type=float, help="USD per million output tokens")
    args = ap.parse_args()

    lines = read_jsonl(args.collected)
    if not lines:
        raise SystemExit(f"error: {args.collected} has no lines")
    tables = []
    by_arm = defaultdict(list)
    for line in lines:
        record = table_record(args.dataset, line["table_uid"])
        line["outcome"] = outcome(line)
        line["cell_accuracy"] = cell_accuracy(record, line["accepted_segmentation"],
                                              line["gold_segmentation"])
        line["llm_cell_accuracy"] = cell_accuracy(record, line["llm_segmentation"],
                                                  line["gold_segmentation"])
        line["usage"] = usage(args.run_dir, line["arm"], line["table_uid"])
        by_arm[line["arm"]].append(line)
        tables.append(line)

    arms = [a for a in ARM_ORDER if a in by_arm] + [a for a in by_arm if a not in ARM_ORDER]
    summary = {}
    for arm in arms:
        rows = by_arm[arm]
        s = {"tables": len(rows)}
        for o in ["correct", "wrong_accepted", "invalid_output", "rejected", "not_reviewed"]:
            s[o] = sum(r["outcome"] == o for r in rows)
        for group in ["complex", "simple"]:
            g = [r for r in rows if r["set"] == group]
            s[f"correct_{group}"] = sum(r["outcome"] == "correct" for r in g)
            s[f"tables_{group}"] = len(g)
        s["llm_correct"] = sum(r["llm_correct"] is True for r in rows)
        answered = [r["cell_accuracy"] for r in rows if r["cell_accuracy"] is not None]
        s["cell_accuracy_answered"] = sum(answered) / len(answered) if answered else None
        s["cell_accuracy_end_to_end"] = sum(r["cell_accuracy"] or 0 for r in rows) / len(rows)
        used = [r["usage"] for r in rows if r["usage"]]
        s["usage_files"] = len(used)
        for key in ["calls", "inputTokens", "outputTokens"]:
            s[key] = sum(u[key] for u in used)
        if args.input_price is not None and args.output_price is not None:
            s["cost_usd"] = (s["inputTokens"] * args.input_price
                             + s["outputTokens"] * args.output_price) / 1e6
        summary[arm] = s

    out = Path(args.run_dir)
    (out / "scores.json").write_text(json.dumps({"summary": summary, "tables": tables}, indent=1))

    md = ["| | " + " | ".join(arms) + " |", "|---|" + "---|" * len(arms)]

    def row(label, f):
        md.append(f"| {label} | " + " | ".join(f(summary[a]) for a in arms) + " |")

    row("correct (all)", lambda s: pct(s["correct"], s["tables"]))
    row("correct (complex)", lambda s: pct(s["correct_complex"], s["tables_complex"]))
    row("correct (simple)", lambda s: pct(s["correct_simple"], s["tables_simple"]))
    row("wrong but accepted", lambda s: str(s["wrong_accepted"]))
    row("invalid output", lambda s: str(s["invalid_output"]))
    row("rejected (unparseable)", lambda s: str(s["rejected"]))
    row("not reviewed", lambda s: str(s["not_reviewed"]))
    row("model's own answer correct", lambda s: pct(s["llm_correct"], s["tables"]))
    row("cell accuracy, answered", lambda s: "–" if s["cell_accuracy_answered"] is None
        else f"{s['cell_accuracy_answered']:.3f}")
    row("cell accuracy, end to end", lambda s: f"{s['cell_accuracy_end_to_end']:.3f}")
    row("model calls", lambda s: str(s["calls"]))
    row("input tokens", lambda s: f"{s['inputTokens']:,}")
    row("output tokens", lambda s: f"{s['outputTokens']:,}")
    row("input tokens per table", lambda s: f"{s['inputTokens'] / s['tables']:,.0f}")
    if args.input_price is not None and args.output_price is not None:
        row("cost (USD)", lambda s: f"{s['cost_usd']:.3f}")

    md += ["", "| table | set | " + " | ".join(arms) + " |", "|---|---|" + "---|" * len(arms)]
    uids = list(dict.fromkeys(r["table_uid"] for r in tables))
    for uid in uids:
        cells = []
        for arm in arms:
            r = next((x for x in by_arm[arm] if x["table_uid"] == uid), None)
            if r is None:
                cells.append("–")
                continue
            acc = "" if r["cell_accuracy"] is None else f" ({r['cell_accuracy']:.2f})"
            tok = "" if not r["usage"] else f", {r['usage']['inputTokens']:,} in"
            cells.append(f"{r['outcome']}{acc}{tok}")
        first = next(r for r in tables if r["table_uid"] == uid)
        md.append(f"| {uid} | {first['set']}/{first['complexity']} | " + " | ".join(cells) + " |")
    text = "\n".join(md) + "\n"
    (out / "summary.md").write_text(text)
    print(text)


if __name__ == "__main__":
    main()
