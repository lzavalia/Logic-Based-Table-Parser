#!/usr/bin/env python3
"""Pool several ablation runs into one report, without calling a model again.

  python3 pool_ablation.py OUT_DIR RUN_DIR [RUN_DIR...]
                           [--input-price USD_PER_MTOK --output-price USD_PER_MTOK]

Each RUN_DIR is a scored run of run_ablation.sh (its scores.json is read).
The study grows batch by batch, each batch a run of its own, so the pooled
numbers are the scored lines of every run put together. Stops if two runs
scored the same table on the same arm, or if the runs used different models.
Writes OUT_DIR/scores.json, OUT_DIR/summary.md and OUT_DIR/runs.json.
"""
import argparse
import json
from pathlib import Path

from score_ablation import report


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir")
    ap.add_argument("run_dirs", nargs="+")
    ap.add_argument("--input-price", type=float, help="USD per million input tokens")
    ap.add_argument("--output-price", type=float, help="USD per million output tokens")
    args = ap.parse_args()

    tables, seen, runs = [], {}, []
    for run_dir in args.run_dirs:
        manifest = json.loads(Path(run_dir, "manifest.json").read_text())
        for line in json.loads(Path(run_dir, "scores.json").read_text())["tables"]:
            key = (line["arm"], line["table_uid"])
            if key in seen:
                raise SystemExit(f"error: {key[1]} ({key[0]}) is in both {seen[key]} and {run_dir}")
            seen[key] = run_dir
            line["run"] = Path(run_dir).name
            tables.append(line)
        runs.append({"run": Path(run_dir).name, "model": manifest["model"],
                     "git_commit": manifest["git_commit"], "git_dirty": manifest["git_dirty"],
                     "tables": len({l["table_uid"] for l in tables if l["run"] == Path(run_dir).name})})
    models = {r["model"] for r in runs}
    if len(models) > 1:
        raise SystemExit(f"error: the runs used different models: {', '.join(sorted(models))}")

    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    (out / "runs.json").write_text(json.dumps(runs, indent=1))
    report(tables, out, args.input_price, args.output_price)


if __name__ == "__main__":
    main()
