#!/usr/bin/env python3
"""Phase 1 of the type-abstraction experiment: choose a candidate by types.

The experiment's scorer and evaluation against gold labels. It is not part of
the pipeline, which scores with src/table_type_scorer.pl (the same bit cost and
purity, without the experiment's other options).

Reads papers/PMC<id>/tables.jsonl and types.jsonl (table_type_abstraction.pl)
of a dataset, scores every candidate of every table with two or more, and
selects the one whose regions describe the type grid most cheaply. With
--gold, the selections are compared with the gold candidates; with --html, a
page shows each table colored by the selected candidate.

Score (description length, in bits; lower is better). For every subtable of
the candidate (a plain boundary is one subtable):
  data      each data column and each data row has its own type
            distribution; a line costs n * H(types of its cells). The data
            cost is the mean of the column view and the row view.
  hmd, vmd  with --header-model region (the default), all HMD cells of
            the subtable share one distribution, and so do all its VMD
            cells; with --header-model line (the first, pre-registered
            version), each HMD row and each VMD column has its own. The line
            model cannot see a numeric data column moved into the VMD, since
            that column is uniform on its own.
Cells whose family is empty, Missing or untyped are left out, as are
separator rows. Every cell of a line is counted once, however many slots it
spans.

Putting too little in the metadata leaves header cells among the data, which
mixes types along a data line; putting too much moves data into a header row
or column, which mixes types there. A table whose cells all have one type
costs 0 under every candidate.

With --model-cost, each distribution used (a line or header region with at
least one typed cell) also costs 0.5 * log2(N) bits, N the table's typed
cells, as in BIC; without it, splitting a table into more subtables can only
lower the cost, so spurious subtable candidates win.

With --data-families F... (or --data-types T... for fine types such as the
guideline type EntityName), cells whose family is in F (Identifier: study
citations, trial and variant ids) are treated as data by role: they are left
out of the data rows' type distributions, since a row's key says nothing
about the types of its content, and each one a candidate places in the VMD
costs 0.5 * log2(N) bits.

Selection: the candidate with the lowest cost. When two or more share it
(within 1e-9 bits), the scorer abstains. The margin is the cost of the
runner-up minus the best cost, divided by the number of typed cells.

Baselines, reported alongside:
  random    expected accuracy of a uniformly random candidate
  prior11   the candidate with one VMD column and the fewest HMD rows (at
            least one), else the one closest to (1, 1)
  purity    highest mean of column and row purity (type_region_phase0.py);
            abstains on ties

Gold rows as in type_region_phase0.py; gold_candidate null means no candidate
is correct, so any selection there is wrong.
"""
import argparse
import html
import json
import math
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from type_region_phase0 import load_dataset, read_jsonl  # noqa: E402

IGNORED = {"empty", "untyped", "Missing"}
TIE = 1e-9


# --- geometry ----------------------------------------------------------------

def subtables(record, candidate):
    """(rows, columns, hmd, vmd) of each subtable of the candidate."""
    if candidate.get("kind") == "layout":
        return [(s["rows"], s["columns"], s["hmd"], s["vmd"])
                for s in candidate["subtables"]]
    raster = record["raster"]
    return [(list(range(len(raster))), list(range(len(raster[0]))),
             candidate["hmd"], candidate["vmd"])]


def subtable_lines(record, regions, rows, columns, hmd, vmd):
    """Cell ids, each once per line, of the data columns, data rows, HMD rows
    and VMD columns of one subtable, by the candidate's region labels."""
    raster = record["raster"]

    def line(slots, region):
        seen, out = set(), []
        for r, c in slots:
            cid = raster[r][c]
            if regions.get(cid) == region and cid not in seen:
                seen.add(cid)
                out.append(cid)
        return out

    head_rows, body_rows = rows[:hmd], rows[hmd:]
    head_cols, body_cols = columns[:vmd], columns[vmd:]
    data_cols = [line([(r, c) for r in body_rows], "data") for c in body_cols]
    data_rows = [line([(r, c) for c in body_cols], "data") for r in body_rows]
    hmd_rows = [line([(r, c) for c in columns], "hmd") for r in head_rows]
    vmd_cols = [line([(r, c) for r in body_rows], "vmd") for c in head_cols]
    return data_cols, data_rows, hmd_rows, vmd_cols


# --- scores ------------------------------------------------------------------

def line_cost(cells, types, families):
    counted = Counter(types[c] for c in cells if families[c] not in IGNORED)
    n = sum(counted.values())
    if n == 0:
        return 0.0
    return -sum(k * math.log2(k / n) for k in counted.values())


def description_length(record, typed, candidate, level, header_model="region",
                       model_cost=False, data_families=()):
    types, families = type_maps(typed, level)
    fine = {c["cell_id"]: c["type"] for c in typed["cells"]}
    def data_role(c):
        return families[c] in data_families or fine[c] in data_families
    regions = {l["cell_id"]: l["region"] for l in candidate["labels"]}
    # BIC-style charge for each distribution the candidate uses: half a
    # log2 of the number of typed cells in the table. Data lines count half,
    # like their cost, since each data cell is in a column and a row.
    unit = 0.5 * math.log2(max(typed_cells(typed), 2))
    per_distribution = unit if model_cost else 0.0
    total = 0.0
    for rows, columns, hmd, vmd in subtables(record, candidate):
        data_cols, data_rows, hmd_rows, vmd_cols = subtable_lines(
            record, regions, rows, columns, hmd, vmd)
        if data_families:
            # Cells of a data role (identifiers) name their row: they say
            # nothing about the types along it, and they cost one unit each
            # when the candidate puts them in the VMD.
            data_rows = [[c for c in line if not data_role(c)] for line in data_rows]
            total += unit * len({c for line in vmd_cols for c in line if data_role(c)})
        def cost(lines):
            used = [l for l in lines if any(families[c] not in IGNORED for c in l)]
            return (sum(line_cost(l, types, families) for l in used)
                    + per_distribution * len(used))
        total += (cost(data_cols) + cost(data_rows)) / 2
        if header_model == "region":
            # A cell spanning several header lines is counted once.
            hmd_rows = [list(dict.fromkeys(c for line in hmd_rows for c in line))]
            vmd_cols = [list(dict.fromkeys(c for line in vmd_cols for c in line))]
        total += cost(hmd_rows) + cost(vmd_cols)
    return total


def purity_score(record, typed, candidate, level):
    """Mean of column and row purity of the data lines (higher is better)."""
    types, families = type_maps(typed, level)
    regions = {l["cell_id"]: l["region"] for l in candidate["labels"]}
    views = [[], []]
    for rows, columns, hmd, vmd in subtables(record, candidate):
        data_cols, data_rows, _, _ = subtable_lines(record, regions, rows, columns, hmd, vmd)
        for view, lines in zip(views, (data_cols, data_rows)):
            for cells in lines:
                counted = Counter(types[c] for c in cells if families[c] not in IGNORED)
                if counted:
                    view.append(counted.most_common(1)[0][1] / sum(counted.values()))
    means = [sum(v) / len(v) for v in views if v]
    return sum(means) / len(means) if means else 0.0


def type_maps(typed, level):
    key = "family" if level == "family" else "type"
    return ({c["cell_id"]: c[key] for c in typed["cells"]},
            {c["cell_id"]: c["family"] for c in typed["cells"]})


def typed_cells(typed):
    return sum(c["family"] not in IGNORED for c in typed["cells"])


# --- selection ---------------------------------------------------------------

def select(scored, lower_is_better=True):
    """(selected candidate id or None, margin) from [(id, score)]."""
    ordered = sorted(scored, key=lambda p: p[1] if lower_is_better else -p[1])
    best, runner = ordered[0], ordered[1]
    gap = abs(runner[1] - best[1])
    return (None if gap <= TIE else best[0]), gap


def prior11(candidates):
    def key(c):
        h, v = c["hmd"], c["vmd"]
        return (v != 1, h < 1, h, abs(h - 1) + abs(v - 1), c["candidate_id"])
    return min(candidates, key=key)["candidate_id"]


def score_table(record, typed, level, header_model="region", model_cost=False,
                data_families=()):
    candidates = record["candidates"]
    costs = [(c["candidate_id"], description_length(record, typed, c, level, header_model,
                                                    model_cost, data_families))
             for c in candidates]
    purities = [(c["candidate_id"], purity_score(record, typed, c, level))
                for c in candidates]
    selected, gap = select(costs)
    purity_selected, _ = select(purities, lower_is_better=False)
    n = typed_cells(typed)
    return {
        "table_uid": record["table_uid"],
        "costs": dict(costs),
        "purities": {k: round(v, 4) for k, v in purities},
        "selected": selected,
        "margin": gap / n if n else 0.0,
        "purity_selected": purity_selected,
        "prior11_selected": prior11(candidates),
    }


# --- evaluation --------------------------------------------------------------

def evaluate(results, gold, n_candidates):
    """Accuracy, coverage and a risk-coverage curve for each method."""
    keys = [k for k in results if k in gold]
    out = {"tables": len(keys),
           "gold_has_candidate": sum(gold[k] is not None for k in keys)}
    for method in ("selected", "purity_selected", "prior11_selected"):
        decided = [k for k in keys if results[k][method] is not None]
        right = [k for k in decided if results[k][method] == gold[k]]
        out[method.replace("_selected", "") if method != "selected" else "description_length"] = {
            "decided": len(decided),
            "correct": len(right),
            "coverage": ratio(len(decided), len(keys)),
            "accuracy_when_decided": ratio(len(right), len(decided)),
            "accuracy_over_all": ratio(len(right), len(keys)),
        }
    out["random"] = {"expected_accuracy_over_all": ratio(
        sum(1 / n_candidates[k] for k in keys if gold[k] is not None), len(keys))}
    # Risk-coverage: decide only the tables with the largest margins.
    ordered = sorted((k for k in keys if results[k]["selected"] is not None),
                     key=lambda k: -results[k]["margin"])
    curve, right = [], 0
    for i, k in enumerate(ordered, start=1):
        right += results[k]["selected"] == gold[k]
        curve.append({"decided": i, "coverage": ratio(i, len(keys)),
                      "accuracy": ratio(right, i),
                      "margin_at_least": round(results[k]["margin"], 4)})
    out["risk_coverage"] = curve
    return out


def ratio(a, b):
    return None if not b else round(a / b, 4)


# --- page --------------------------------------------------------------------

COLORS = {"hmd": "#b7e4b0", "vmd": "#b3cdf2", "data": "#e6e6e6",
          "separator": "#e8dca0"}


def table_html(record, typed, candidate, level):
    raster = record["raster"]
    texts = {c["cell_id"]: c.get("text") or "" for c in record["cells"]}
    types, _ = type_maps(typed, level)
    regions = ({l["cell_id"]: l["region"] for l in candidate["labels"]}
               if candidate else {})
    extent = {}
    for r, row in enumerate(raster):
        for c, cid in enumerate(row):
            r0, c0, r1, c1 = extent.get(cid, (r, c, r, c))
            extent[cid] = (min(r0, r), min(c0, c), max(r1, r), max(c1, c))
    out = ["<table class='t'>"]
    for r, row in enumerate(raster):
        out.append("<tr>")
        for c, cid in enumerate(row):
            r0, c0, r1, c1 = extent[cid]
            if (r, c) != (r0, c0):
                continue
            color = COLORS.get(regions.get(cid), "#fff")
            text = html.escape(texts[cid][:80] + ("…" if len(texts[cid]) > 80 else ""))
            out.append(f"<td rowspan='{r1 - r0 + 1}' colspan='{c1 - c0 + 1}' "
                       f"style='background:{color}'>{text}"
                       f"<span class='ty'>{html.escape(str(types[cid]))}</span></td>")
        out.append("</tr>")
    out.append("</table>")
    return "".join(out)


def page(tables, results, gold, summary, level):
    parts = [f"""<!doctype html><html><head><meta charset='utf-8'>
<meta name='viewport' content='width=device-width, initial-scale=1'>
<title>Type scorer selections</title><style>
body{{font:14px/1.4 system-ui,sans-serif;margin:16px;background:#fff;color:#222}}
h2{{font-size:15px;margin:28px 0 4px}} .cap{{color:#555;margin:0 0 6px}}
.t{{border-collapse:collapse;margin:6px 0;font-size:12px}}
.t td{{border:1px solid #999;padding:2px 5px;vertical-align:top;max-width:220px}}
.ty{{display:block;font-size:10px;color:#665;font-family:ui-monospace,monospace}}
.ok{{color:#176c2b;font-weight:600}} .bad{{color:#b3261e;font-weight:600}} .abs{{color:#8a6d00;font-weight:600}}
.costs{{border-collapse:collapse;font-size:12px}} .costs td,.costs th{{border:1px solid #ccc;padding:1px 6px;text-align:left}}
.wrap{{overflow-x:auto}} .legend span{{padding:1px 6px;margin-right:6px}}
</style></head><body>
<h1 style='font-size:18px'>Type scorer selections ({html.escape(level)} level)</h1>
<p class='legend'><span style='background:{COLORS["hmd"]}'>HMD</span><span style='background:{COLORS["vmd"]}'>VMD</span><span style='background:{COLORS["data"]}'>data</span><span style='background:{COLORS["separator"]}'>separator</span>
Each cell shows its text and, below, its type. Gold labels are provisional (labelled by a model, not by people).</p>
<pre>{html.escape(json.dumps({k: v for k, v in summary.items() if k != "risk_coverage"}, indent=1))}</pre>"""]
    for key, (record, typed) in tables.items():
        res = results[key]
        g = gold.get(key, "unlabeled")
        if res["selected"] is None:
            verdict = "<span class='abs'>abstained</span>"
        elif g == "unlabeled":
            verdict = "selected (no gold)"
        elif res["selected"] == g:
            verdict = "<span class='ok'>correct</span>"
        else:
            verdict = "<span class='bad'>wrong</span>"
        chosen = next((c for c in record["candidates"]
                       if c["candidate_id"] == res["selected"]), None)
        caption = (record.get("context") or {}).get("caption") or ""
        rows = "".join(
            f"<tr><td>{html.escape(cid.split('/')[-1])}"
            f"{' ← selected' if cid == res['selected'] else ''}"
            f"{' ← gold' if cid == g else ''}</td>"
            f"<td>{cost:.1f}</td><td>{res['purities'][cid]}</td></tr>"
            for cid, cost in sorted(res["costs"].items(), key=lambda p: p[1]))
        gold_text = "none correct" if g is None else g.split("/")[-1] if g != "unlabeled" else "—"
        parts.append(
            f"<h2>{html.escape(record['table_uid'])} — {verdict}</h2>"
            f"<p class='cap'>{html.escape(caption[:300])}</p>"
            f"<p>Selected: <b>{html.escape(res['selected'].split('/')[-1]) if res['selected'] else 'none'}</b>"
            f" · gold: <b>{html.escape(gold_text)}</b> · margin {res['margin']:.3f} bits/cell</p>"
            f"<table class='costs'><tr><th>candidate</th><th>cost (bits)</th><th>purity</th></tr>{rows}</table>"
            f"<div class='wrap'>{table_html(record, typed, chosen, level)}</div>")
    parts.append("</body></html>")
    return "".join(parts)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--dataset", required=True, type=Path)
    p.add_argument("--gold", type=Path)
    p.add_argument("--level", choices=["family", "type"], default="family")
    p.add_argument("--header-model", choices=["region", "line"], default="region")
    p.add_argument("--model-cost", action="store_true",
                   help="charge 0.5*log2(typed cells) bits per distribution (BIC-style; "
                        "added after the complex-table run, see the experiment README)")
    p.add_argument("--data-families", nargs="*", default=[],
                   help="type families whose cells are data by role (e.g. Identifier): "
                        "left out of the row view, and charged 0.5*log2(typed cells) bits "
                        "each when a candidate puts them in the VMD")
    p.add_argument("--data-types", nargs="*", default=[],
                   help="fine types treated the same way (e.g. EntityName from guidelines)")
    p.add_argument("--types-file", default="types.jsonl",
                   help="type records next to each tables.jsonl, e.g. guided_types.jsonl")
    p.add_argument("--papers", type=Path,
                   help="JSON object of paper names; only the papers whose value is --split are scored")
    p.add_argument("--split", default="test")
    p.add_argument("--only-gold", action="store_true",
                   help="score only the tables listed in --gold")
    p.add_argument("--output", type=Path, help="JSON with per-table scores and the evaluation")
    p.add_argument("--html", type=Path, help="page showing each selected table")
    args = p.parse_args(argv)

    tables = load_dataset(args.dataset, args.types_file)
    if args.papers:
        split = json.loads(args.papers.read_text())
        tables = {k: v for k, v in tables.items() if split.get(k[0]) == args.split}
    tables = {k: v for k, v in sorted(tables.items())
              if len(v[0]["candidates"]) >= 2}
    if args.only_gold:
        if not args.gold:
            p.error("--only-gold needs --gold")
        wanted = {(r["pmc_id"], r["table_index"]) for r in read_jsonl(args.gold)}
        tables = {k: v for k, v in tables.items() if k in wanted}
    results = {k: score_table(record, typed, args.level, args.header_model, args.model_cost,
                              frozenset(args.data_families) | frozenset(args.data_types))
               for k, (record, typed) in tables.items()}
    gold = {}
    if args.gold:
        gold = {(r["pmc_id"], r["table_index"]): r["gold_candidate"]
                for r in read_jsonl(args.gold)}
    summary = (evaluate(results, gold, {k: len(v[0]["candidates"]) for k, v in tables.items()})
               if gold else {"tables": len(results)})
    summary["level"] = args.level
    summary["header_model"] = args.header_model
    summary["model_cost"] = args.model_cost
    summary["data_families"] = args.data_families
    summary["data_types"] = args.data_types
    summary["types_file"] = args.types_file
    if args.output:
        args.output.write_text(json.dumps(
            {"summary": summary,
             "tables": [results[k] for k in results]}, indent=1) + "\n", encoding="utf-8")
    if args.html:
        args.html.write_text(page(tables, results, gold, summary, args.level), encoding="utf-8")
    sys.stdout.write(json.dumps({k: v for k, v in summary.items() if k != "risk_coverage"},
                                indent=2) + "\n")


if __name__ == "__main__":
    main()
