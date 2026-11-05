#!/usr/bin/env python3
"""Draw the table sample of an ablation run.

  python3 make_sample.py OUT.jsonl [--complex N] [--simple N] [--seed S]
                         [--max-slots K]
  python3 make_sample.py OUT.jsonl --extend SAMPLE.jsonl
                         --quota multi_level=3,subtables=1,separator_rows=1
                         [--seed S] [--max-slots K]
  python3 make_sample.py OUT.jsonl --batch N --gold-out GOLD.jsonl
                         --exclude SAMPLE.jsonl[,SAMPLE.jsonl...] [--seed S]
                         [--max-slots K]

Half the sample comes from the complex-table dataset, the other half from the
first (mostly simple) dataset of the type-abstraction experiment:

  complex  the human-reviewed complex dev sample (gold_complex_dev.reviewed.jsonl),
           stratified by complexity class: subtables, separator rows,
           multi-level, in that order of priority for the remainder. The test
           sample (gold_complex_test.reviewed.jsonl) is not touched, so it
           stays clean for a later full run.
  simple   the first dataset's test split (gold_test.provisional.jsonl). Its
           labels are provisional and follow the opposite VMD convention, so
           each sampled table is relabelled in smoke_gold.jsonl before it is
           scored (see README.md).

Only tables with a gold candidate are drawn, at most one table per paper (so
that per-table runs never overwrite one another's paper files), and at most
--max-slots raster slots, to bound the cost. Each line gives table_uid,
pmc_id, table_index, set, complexity, slots, source (the dataset the paper is
copied from, relative to experiments/type_abstraction/) and the gold label it
starts from.

With --extend, OUT is SAMPLE followed by further complex tables, so many of
each class as --quota says, from papers not yet in SAMPLE. No reviewed dev
table has a gold answer with several subtables, so a "subtables" table is
one where the parser offers a split, not one that needs it.

With --batch, OUT is N further tables for growing the study batch by batch,
and GOLD their labels. Only human-reviewed labels are drawn: the complex dev
and test samples together (the ablation tunes nothing, so the split does not
matter), round-robin over the complexity classes. A table in any --exclude
sample is never drawn again, so no table is paid for twice. Tables of one
paper may land in different batches, but each batch has at most one table
per paper, since every run rebuilds its dataset.
"""
import argparse
import json
import random
from pathlib import Path

TA = Path(__file__).resolve().parent.parent / "type_abstraction"
SOURCES = {"complex": "data/complex/ds", "simple": "data/ds"}
CLASSES = ["subtables", "separator_rows", "multi_level"]


def read_jsonl(path):
    return [json.loads(line) for line in Path(path).read_text().splitlines() if line.strip()]


def table_record(source, pmc_id, index):
    path = TA / source / "papers" / pmc_id / "tables.jsonl"
    return next(r for r in read_jsonl(path) if r["table_index"] == index)


def pool(set_name, gold_file, classes, golds=None):
    rows = []
    for g in read_jsonl(TA / gold_file):
        if golds is not None:
            golds[g["table_uid"]] = g
        if not g["gold_candidate"]:
            continue
        record = table_record(SOURCES[set_name], g["pmc_id"], g["table_index"])
        rows.append({
            "table_uid": g["table_uid"], "pmc_id": g["pmc_id"],
            "table_index": g["table_index"], "set": set_name,
            "complexity": classes.get(g["table_uid"], "simple"),
            "slots": record["rows"] * record["columns"],
            "source": SOURCES[set_name],
            "gold_candidate": g["gold_candidate"],
            "gold_file": gold_file, "gold_labeler": g.get("labeler"),
        })
    return rows


def draw_quota(candidates, quota, rng, used_papers, max_slots):
    candidates = [c for c in candidates if c["slots"] <= max_slots]
    rng.shuffle(candidates)
    picked = []
    for stratum, n in quota:
        mine = [c for c in candidates
                if c["complexity"] == stratum and c["pmc_id"] not in used_papers]
        if len(mine) < n:
            raise SystemExit(f"only {len(mine)} {stratum} tables can be drawn, not {n}")
        for c in mine[:n]:
            picked.append(c)
            used_papers.add(c["pmc_id"])
    return picked


def draw(candidates, n, rng, used_papers, max_slots, strata=None):
    candidates = [c for c in candidates if c["slots"] <= max_slots]
    rng.shuffle(candidates)
    picked = []
    order = strata or [None]
    # Round-robin over the strata, so each class is represented.
    while len(picked) < n:
        progress = False
        for stratum in order:
            if len(picked) == n:
                break
            for c in candidates:
                if (stratum is None or c["complexity"] == stratum) \
                        and c["pmc_id"] not in used_papers and c not in picked:
                    picked.append(c)
                    used_papers.add(c["pmc_id"])
                    progress = True
                    break
        if not progress:
            raise SystemExit(f"only {len(picked)} of {n} tables can be drawn")
    return picked


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--complex", type=int, default=5)
    ap.add_argument("--simple", type=int, default=5)
    ap.add_argument("--seed", type=int, default=20261103)
    ap.add_argument("--max-slots", type=int, default=400)
    ap.add_argument("--extend", help="an existing sample to add complex tables to")
    ap.add_argument("--quota", help="with --extend: class=N,... (classes: " + ", ".join(CLASSES) + ")")
    ap.add_argument("--batch", type=int, help="draw this many further human-labelled tables")
    ap.add_argument("--exclude", help="with --batch: comma-separated samples already run")
    ap.add_argument("--gold-out", help="with --batch: where to write the batch's gold labels")
    args = ap.parse_args()

    rng = random.Random(args.seed)
    classes = {r["table_uid"]: r["complexity"]
               for r in read_jsonl(TA / "complex_dev_sample.jsonl")}
    if args.batch:
        if not args.exclude or not args.gold_out:
            raise SystemExit("--batch needs --exclude and --gold-out")
        done = {row["table_uid"] for f in args.exclude.split(",") for row in read_jsonl(f)}
        classes.update((r["table_uid"], r["complexity"])
                       for r in read_jsonl(TA / "complex_test_sample.jsonl"))
        golds = {}
        candidates = [c for f in ("gold_complex_dev.reviewed.jsonl", "gold_complex_test.reviewed.jsonl")
                      for c in pool("complex", f, classes, golds) if c["table_uid"] not in done]
        n = min(args.batch, len({c["pmc_id"] for c in candidates if c["slots"] <= args.max_slots}))
        if n == 0:
            raise SystemExit("no human-labelled table is left to draw")
        sample = draw(candidates, n, rng, set(), args.max_slots, CLASSES)
        with open(args.out, "w") as out:
            for row in sample:
                out.write(json.dumps(row) + "\n")
        with open(args.gold_out, "w") as out:
            for row in sample:
                g = golds[row["table_uid"]]
                out.write(json.dumps({
                    "table_uid": row["table_uid"], "pmc_id": row["pmc_id"],
                    "table_index": row["table_index"], "gold_candidate": g["gold_candidate"],
                    "confidence": g.get("confidence"), "note": g.get("note", ""),
                    "labeler": g.get("labeler"), "source": row["gold_file"]}) + "\n")
        left = len([c for c in candidates if c["slots"] <= args.max_slots]) - len(sample)
        for row in sample:
            print(f"{row['complexity']:15} {row['slots']:4} slots  {row['table_uid']}  ({row['gold_file']})")
        print(f"{len(sample)} drawn, {left} human-labelled table(s) left")
        return
    if args.extend:
        if not args.quota:
            raise SystemExit("--extend needs --quota")
        quota = [(k, int(v)) for k, v in (part.split("=") for part in args.quota.split(","))]
        unknown = [k for k, _ in quota if k not in CLASSES]
        if unknown:
            raise SystemExit(f"unknown class(es): {', '.join(unknown)}")
        sample = read_jsonl(args.extend)
        used = {row["pmc_id"] for row in sample}
        added = draw_quota(pool("complex", "gold_complex_dev.reviewed.jsonl", classes),
                           quota, rng, used, args.max_slots)
        with open(args.out, "w") as out:
            for row in sample + added:
                out.write(json.dumps(row) + "\n")
        for row in added:
            print(f"added {row['set']:8} {row['complexity']:15} {row['slots']:4} slots  {row['table_uid']}")
        return
    used = set()
    sample = draw(pool("complex", "gold_complex_dev.reviewed.jsonl", classes),
                  args.complex, rng, used, args.max_slots, CLASSES)
    sample += draw(pool("simple", "gold_test.provisional.jsonl", {}),
                   args.simple, rng, used, args.max_slots)
    with open(args.out, "w") as out:
        for row in sample:
            out.write(json.dumps(row) + "\n")
    for row in sample:
        print(f"{row['set']:8} {row['complexity']:15} {row['slots']:4} slots  {row['table_uid']}")


if __name__ == "__main__":
    main()
