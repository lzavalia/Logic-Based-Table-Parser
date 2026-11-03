#!/usr/bin/env python3
"""Phase 0 of the type-abstraction experiment: do cell types depend on regions?

Reads, for every paper of a dataset, papers/PMC<id>/tables.jsonl and the
types.jsonl written next to it by table_type_abstraction.pl, and a gold file
that names the correct candidate of each labeled table:

  {"pmc_id":"PMC123", "table_index":0, "gold_candidate":"PMC123/t0/h1_v1",
   "confidence":"high"}

gold_candidate is null when no candidate is correct; such tables count toward
coverage only. --min-confidence high drops rows whose confidence is "low".

The gold candidate's labels give each cell a region (hmd, vmd, data,
separator). Measured, at the family level (Numeric, Text, ...) or the fine
type level (--level type):

  coverage       share of non-empty cells no rule typed
  dependence     mutual information I(type; region) over all labeled cells,
                 pooled and as a mean over tables, each against a permutation
                 baseline that shuffles regions within each table
  data regions   how many gold data regions are mostly Numeric, mostly Text
                 or mixed (typed cells only)
  purity         for each data column (row), the share of its typed cells
                 that have the line's most common type; empty, missing and
                 untyped cells are ignored. Compared between the gold
                 boundary and every other boundary (Hmd, Vmd) the same table
                 admits geometrically, up to 4 HMD rows and 3 VMD columns
  contrast       share of data columns whose header cell (lowest HMD cell of
                 the column) has a different type from the column's most
                 common type; the same for data rows and their VMD cell

Nothing here is semantic ground truth unless the gold file is: the labels
used for the first run were provisional, made by a model, not by people.
"""
import argparse
import json
import math
import random
import sys
from collections import Counter, defaultdict
from pathlib import Path

IGNORED_IN_PURITY = {"empty", "untyped", "Missing"}


def read_jsonl(path):
    with Path(path).open(encoding="utf-8") as src:
        return [json.loads(line) for line in src if line.strip()]


def load_dataset(dataset, types_name="types.jsonl"):
    """Return {(pmc_id, table_index): (table record, type record)}."""
    tables = {}
    for tables_file in sorted(Path(dataset, "papers").glob("PMC*/tables.jsonl")):
        types_file = tables_file.with_name(types_name)
        if not types_file.exists():
            raise ValueError(f"no {types_name} next to {tables_file}")
        records, types = read_jsonl(tables_file), read_jsonl(types_file)
        if [r["table_uid"] for r in records] != [t["table_uid"] for t in types]:
            raise ValueError(f"{types_file} does not match {tables_file}")
        for record, typed in zip(records, types):
            tables[(record["pmc_id"], record["table_index"])] = (record, typed)
    return tables


def cell_types(typed, level):
    key = "family" if level == "family" else "type"
    return {c["cell_id"]: c[key] for c in typed["cells"]}


def cell_families(typed):
    return {c["cell_id"]: c["family"] for c in typed["cells"]}


def coverage(typed_records):
    cells = untyped = 0
    for typed in typed_records:
        cells += typed["counts"]["cells"] - typed["counts"]["empty"]
        untyped += typed["counts"]["untyped"]
    return {"non_empty_cells": cells, "untyped_cells": untyped,
            "untyped_rate": ratio(untyped, cells)}


# --- dependence --------------------------------------------------------------

def mutual_information(pairs):
    """I(X; Y) in bits for a list of (x, y) pairs, and H(Y)."""
    n = len(pairs)
    if n == 0:
        return 0.0, 0.0
    joint = Counter(pairs)
    xs = Counter(x for x, _ in pairs)
    ys = Counter(y for _, y in pairs)
    mi = sum(c / n * math.log2(c * n / (xs[x] * ys[y]))
             for (x, y), c in joint.items())
    hy = -sum(c / n * math.log2(c / n) for c in ys.values())
    return mi, hy


def table_pairs(record, typed, candidate, level):
    """(type, region) for every cell the candidate labels."""
    types = cell_types(typed, level)
    return [(types[label["cell_id"]], label["region"])
            for label in candidate["labels"]]


def dependence(labeled, level, permutations, rng):
    """Pooled and per-table MI with a within-table permutation baseline."""
    per_table = [table_pairs(r, t, c, level) for r, t, c in labeled]
    pooled = [p for pairs in per_table for p in pairs]
    observed, h_region = mutual_information(pooled)
    macro_observed = mean([mutual_information(p)[0] for p in per_table])
    pooled_null, macro_null = [], []
    for _ in range(permutations):
        shuffled = []
        for pairs in per_table:
            regions = [y for _, y in pairs]
            rng.shuffle(regions)
            shuffled.append([(x, y) for (x, _), y in zip(pairs, regions)])
        pooled_null.append(mutual_information([p for s in shuffled for p in s])[0])
        macro_null.append(mean([mutual_information(s)[0] for s in shuffled]))
    joint = Counter(pooled)
    by_region = defaultdict(Counter)
    for (x, y), c in joint.items():
        by_region[y][x] = c
    return {
        "labeled_cells": len(pooled),
        "pooled_mi_bits": round(observed, 4),
        "pooled_mi_normalized": ratio(observed, h_region),
        "pooled_null_mean_bits": round(mean(pooled_null), 4) if pooled_null else None,
        "pooled_null_max_bits": round(max(pooled_null), 4) if pooled_null else None,
        "pooled_p_value": p_value(observed, pooled_null),
        "macro_mi_bits": round(macro_observed, 4),
        "macro_null_mean_bits": round(mean(macro_null), 4) if macro_null else None,
        "macro_p_value": p_value(macro_observed, macro_null),
        "type_given_region": {
            region: {t: ratio(c, sum(counts.values()))
                     for t, c in counts.most_common()}
            for region, counts in sorted(by_region.items())},
    }


def p_value(observed, null):
    if not null:
        return None
    return round((1 + sum(v >= observed for v in null)) / (1 + len(null)), 6)


# --- purity and contrast -----------------------------------------------------

def boundary_regions(record, hmd, vmd):
    """Region of each cell for a plain (hmd, vmd) boundary, labeled by the
    cell's top-left slot, as tables.jsonl does; None if the boundary cuts a
    merged cell."""
    raster = record["raster"]
    first, cut = {}, False
    for r, row in enumerate(raster):
        for c, cid in enumerate(row):
            region = "hmd" if r < hmd else "vmd" if c < vmd else "data"
            if cid not in first:
                first[cid] = region
            elif first[cid] != region:
                cut = True
    return None if cut else first


def candidate_regions(candidate):
    return {label["cell_id"]: label["region"] for label in candidate["labels"]}


def lines(record, regions, axis):
    """Cell ids of the data region along each column (axis 0) or row
    (axis 1), each cell once per line, with the metadata cell heading it."""
    raster = record["raster"]
    grid = raster if axis == 1 else [list(col) for col in zip(*raster)]
    head_region = "vmd" if axis == 1 else "hmd"
    result = []
    for line in grid:
        data, head, seen = [], None, set()
        for cid in line:
            region = regions.get(cid)
            if region == head_region:
                head = cid
            elif region == "data" and cid not in seen:
                seen.add(cid)
                data.append(cid)
        if data:
            result.append((head, data))
    return result


def purity(record, typed, regions, level):
    """Mean over data columns and rows of the most common type's share."""
    types = cell_types(typed, level)
    scores = []
    for axis in (0, 1):
        axis_scores = []
        for _, data in lines(record, regions, axis):
            counted = Counter(types[c] for c in data
                              if cell_families(typed)[c] not in IGNORED_IN_PURITY)
            if counted:
                axis_scores.append(counted.most_common(1)[0][1] / sum(counted.values()))
        scores.append(mean(axis_scores) if axis_scores else None)
    return {"column": scores[0], "row": scores[1]}


def contrast(record, typed, regions, level):
    """Share of data columns (rows) whose heading cell's type differs from
    the line's most common type; lines without a typed heading are skipped."""
    types = cell_types(typed, level)
    families = cell_families(typed)
    out = {}
    for axis, name in ((0, "column"), (1, "row")):
        differs = total = 0
        for head, data in lines(record, regions, axis):
            counted = Counter(types[c] for c in data
                              if families[c] not in IGNORED_IN_PURITY)
            if head is None or families[head] in IGNORED_IN_PURITY or not counted:
                continue
            total += 1
            differs += types[head] != counted.most_common(1)[0][0]
        out[name] = (differs, total)
    return out


def purity_comparison(labeled, level):
    """Gold boundary against every other admissible plain boundary, on
    column purity and on row purity."""
    out = {}
    for axis in ("column", "row"):
        gold_scores, other_scores, gold_best, ties, compared = [], [], 0, 0, 0
        for record, typed, candidate in labeled:
            gold_regions = candidate_regions(candidate)
            gold = purity(record, typed, gold_regions, level)[axis]
            if gold is None:
                continue
            others = [purity(record, typed, regions, level)[axis]
                      for regions in other_boundaries(record, gold_regions)]
            others = [o for o in others if o is not None]
            if not others:
                continue
            compared += 1
            gold_scores.append(gold)
            other_scores.append(mean(others))
            best = max(others)
            gold_best += gold > best
            ties += gold == best
        out[axis] = {
            "tables": compared,
            "gold_mean_purity": rounded(mean(gold_scores)),
            "other_boundaries_mean_purity": rounded(mean(other_scores)),
            "gold_strictly_purest_share": ratio(gold_best, compared),
            "gold_tied_purest_share": ratio(ties, compared),
        }
    return out


def other_boundaries(record, gold_regions):
    """Regions of every plain boundary, up to 4 HMD rows and 3 VMD columns,
    that does not cut a merged cell and differs from the gold labeling."""
    rows, cols = len(record["raster"]), len(record["raster"][0])
    for h in range(0, min(rows - 1, 4) + 1):
        for v in range(0, min(cols - 1, 3) + 1):
            if (h, v) == (0, 0):
                continue
            regions = boundary_regions(record, h, v)
            if regions is not None and regions != gold_regions:
                yield regions


def data_families(labeled):
    """How many gold data regions are mostly Numeric, mostly Text, or
    neither, counting typed cells only."""
    kinds = Counter()
    for record, typed, candidate in labeled:
        families = cell_families(typed)
        counted = Counter(families[l["cell_id"]] for l in candidate["labels"]
                          if l["region"] == "data"
                          and families[l["cell_id"]] not in IGNORED_IN_PURITY)
        total = sum(counted.values())
        if counted["Numeric"] > total / 2:
            kinds["mostly_numeric"] += 1
        elif counted["Text"] > total / 2:
            kinds["mostly_text"] += 1
        else:
            kinds["mixed"] += 1
    return dict(kinds)


def contrast_summary(labeled, level):
    sums = {"column": [0, 0], "row": [0, 0]}
    for record, typed, candidate in labeled:
        for name, (differs, total) in contrast(record, typed, candidate_regions(candidate), level).items():
            sums[name][0] += differs
            sums[name][1] += total
    return {f"{name}_heading_differs_share": ratio(d, t)
            for name, (d, t) in sums.items()} | {
            f"{name}_lines": t for name, (_, t) in sums.items()}


# --- helpers -----------------------------------------------------------------

def mean(values):
    values = [v for v in values if v is not None]
    return sum(values) / len(values) if values else None


def ratio(num, den):
    return None if not den else round(num / den, 4)


def rounded(value):
    return None if value is None else round(value, 4)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--dataset", required=True, type=Path)
    p.add_argument("--gold", required=True, type=Path)
    p.add_argument("--level", choices=["family", "type"], default="family")
    p.add_argument("--types-file", default="types.jsonl",
                   help="type records next to each tables.jsonl, e.g. guided_types.jsonl")
    p.add_argument("--min-confidence", choices=["low", "high"], default="low")
    p.add_argument("--permutations", type=int, default=1000)
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--output", type=Path)
    args = p.parse_args(argv)

    tables = load_dataset(args.dataset, args.types_file)
    gold = read_jsonl(args.gold)
    labeled, abstained, typed_records = [], 0, []
    for row in gold:
        key = (row["pmc_id"], row["table_index"])
        if key not in tables:
            p.error(f"no table {key} in {args.dataset}")
        record, typed = tables[key]
        if args.min_confidence == "high" and row.get("confidence") == "low":
            continue
        typed_records.append(typed)
        if row["gold_candidate"] is None:
            abstained += 1
            continue
        matches = [c for c in record["candidates"]
                   if c["candidate_id"] == row["gold_candidate"]]
        if len(matches) != 1:
            p.error(f"gold candidate {row['gold_candidate']} not found")
        labeled.append((record, typed, matches[0]))

    rng = random.Random(args.seed)
    result = {
        "level": args.level,
        "min_confidence": args.min_confidence,
        "tables": len(typed_records),
        "tables_without_correct_candidate": abstained,
        "coverage": coverage(typed_records),
        "dependence": dependence(labeled, args.level, args.permutations, rng),
        "gold_data_regions": data_families(labeled),
        "purity": purity_comparison(labeled, args.level),
        "contrast": contrast_summary(labeled, args.level),
    }
    encoded = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_text(encoded, encoding="utf-8")
    sys.stdout.write(encoded)


if __name__ == "__main__":
    main()
