# Ablation study

What do the geometric parse constraints, and the type inference with the
table repair, add to an LLM that segments tables on its own? Three arms, each
a code path selected with `review_agent.sh --arm`:

| Arm | `--arm` | Who decides | Parse constraints | Type scorer | Repair | Agent |
|---|---|---|---|---|---|---|
| A | `llm-only` | The LLM segments the table; its answer is the result | – | – | – | `src/ablation_review.dml` |
| B | `constraints` | The LLM segments the table blind; valid only if it equals a parser candidate, else `unparseable` | ✓ | – | – | `src/ablation_review.dml` |
| C | `full` (default) | The type scorer proposes a candidate, the LLM reviews it, the repair runs on disagreements | ✓ | ✓ | ✓ | `src/review_dataset.dml` |

- **Same input.** All three show the table exactly as the full review does
  (`table_review:table_block/2`: cell texts, merges, `<th>` marks, label,
  caption, notes), at temperature 0, one fresh call per table.
- **A and B send the same prompt** (`ablation_review:segmentation_prompt/2`,
  version `table-segmentation-v1`) and make their own calls. The answer is
  the whole segmentation: separator rows, and subtables as row and column
  ranges, each with its column-header rows H and row-header columns V. That
  is exactly what a parser candidate describes (every layout in both
  datasets is contiguous rectangles plus full-width separator rows), so B
  compares an answer with the candidates as one term and can select any
  layout, including ones with several subtables. Neither prompt states the
  VMD labelling convention; neither does C's.
- **A uses no formal method.** It loads the review modules for the table
  rendering and the export, but calls no parse constraint, type or repair
  predicate. Its `final_tables.llm-only.json` is built from the model's
  segmentation by the same exporter (`table_export:candidate_structures/4`);
  an answer the exporter cannot build (no data left, headers that are no
  forest) is counted as *invalid output*.
- **C is today's pipeline, unchanged.** Its prompt is byte-identical to
  before (checked on all 2,756 candidates of both datasets).

Outputs per paper: `review.<arm>.jsonl` and `final_tables.<arm>.json` for A
and B, `review.jsonl` and `final_tables.json` for C. `tables.jsonl` is never
changed.

## Files

| File | |
|---|---|
| `make_sample.py` | Draws a sample: half complex (human-reviewed **dev** labels, stratified by class), half from the first dataset's test split; one table per paper, at most 400 slots |
| `smoke_sample.jsonl` | The 15-table smoke sample: 10 drawn with seed 20261103, 5 complex added with `--extend smoke_sample.jsonl --quota multi_level=3,subtables=1,separator_rows=1 --seed 20261104` |
| `smoke_gold.jsonl` | Its gold labels (see below) |
| `<PMC>_t<N>_input.html`, `<PMC>_t<N>_candidates.html` | Each sample table as published, and coloured once per parser candidate |
| `data/<source>/papers/<PMC>/` | The smoke sample's papers (`tables.jsonl`, `metadata.json`), copied from `../type_abstraction/data/`, which is downloaded rather than kept in the repository |
| `prepare_dataset.py` | Copies the sample's papers (`tables.jsonl`, `metadata.json`) into a fresh dataset under `src/`, where DeepClause can see it; each paper comes from `data/` here if present, otherwise from `../type_abstraction/` |
| `run_ablation.sh` | Runs every arm on every table, one DeepClause run per table and arm, then collects and scores |
| `../../src/ablation_collect.pl` | Turns each arm's verdict into a segmentation comparable with the gold (rebuilding repaired tables) |
| `score_ablation.py` | Outcomes, cell accuracy and tokens per arm |

## Running

From `dataset-builder-agent/`:

```bash
experiments/ablation/run_ablation.sh                      # all arms, Haiku 5.5, asks first
experiments/ablation/run_ablation.sh --arms llm-only      # one arm
experiments/ablation/run_ablation.sh --input-price X --output-price Y   # also report USD
```

It rebuilds `src/ablation/<name>/dataset/` (git-ignored), then for each arm
and table runs `review_agent.sh --arm <arm> --dataset ablation/<name>/dataset
--tables <uid> --force --model <model> --log-dir <dir>`. Everything goes to
`results/<name>-<UTC time>/`:

- `manifest.json`: model, arms, git commit (and whether the tree was dirty)
- `<arm>/<table>/`: the call's `review_token_usage.json`, `stdout.txt`,
  `exit_status`, and the paper's review and export as that call left them
- `collected.jsonl`, `scores.json`, `summary.md`: the results

One run per table is what makes tokens per table measurable: DeepClause's
usage file is per run and its trace has no token counts. A trivial call
costs about 1,250 input tokens of DeepClause overhead (measured with Haiku
5.5), which every arm pays once per table.

A single arm on a single table, by hand:

```bash
./review_agent.sh --arm llm-only --dataset ablation/smoke/dataset \
    --tables PMC1361785/t0 --force --model anthropic:claude-haiku-5-5
```

## Scoring

Each table ends in one outcome per arm: `correct` (accepted, segmentation
equals the gold), `wrong_accepted` (accepted, another segmentation: a silent
error), `invalid_output` (accepted, but not exportable), `rejected`
(`unparseable`) or `not_reviewed`. Also reported: cell accuracy (share of
cells with the gold label hmd/vmd/data/separator, over answered tables and
end to end), whether the model's own answer was right even where the arm
refused it, and model calls and tokens. Fifteen tables support no significance
test; the smoke run is for a feel of cost and accuracy, not a result.

## The smoke sample's labels

- Complex (10): human-reviewed dev labels (`gold_complex_dev.reviewed.jsonl`):
  3 subtables, 3 separator rows, 4 multi-level. No reviewed dev table has a
  gold answer with several subtables, so the subtables tables are ones where
  the parser offers a split that the gold answer does not take.
- Simple (5): **provisional**. The first dataset's labels follow the
  opposite VMD convention, so they were relabelled to the current one
  (a column naming each row's entity is data). Three changed:
  PMC12632427/t0 h1_v1 → h1_v0 (Sample: Control/Target; low confidence),
  PMC9656733/t1 h1_v1 → h1_v0 (perovskite names), PMC10199865/t2 h2_v1 →
  h2_v0 (Authors). They need a human check before any number is quoted.

## Offline check (no model)

On the first 10 tables of the sample, a probe agent run inside DeepClause, answering with the gold segmentation
for A and B and confirming every proposal for C, gave A 10/10, B 10/10 and
C 8/10. C's 8/10 is the type scorer alone on this sample (types without the
LLM): its two misses are the two relabelled tables where it prefers a VMD
column.
