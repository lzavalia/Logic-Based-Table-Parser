# Ablation study

What do the geometric parse constraints, and the type inference with the
table repair, add to an LLM that segments tables on its own? Three arms, each
a code path selected with `review_agent.sh --arm`:

| Arm | `--arm` | Who decides | Parse constraints | Type scorer | Repair | Agent |
|---|---|---|---|---|---|---|
| A | `llm-only` | The LLM segments the table; its answer is the result | – | – | – | `src/ablation_review.dml` |
| B | `constraints` | The LLM segments the table blind; valid only if it equals a parser candidate, else `unparseable` | ✓ | – | – | `src/ablation_review.dml` |
| C | `full` (default) | The guideline step refines the rule types, the type scorer proposes a candidate, the LLM reviews it, the repair runs on disagreements | ✓ | ✓ | ✓ | `src/review_dataset.dml` |

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
- **C now includes the guideline step.** Since 2026-11-05 `review_agent.sh
  --arm full` runs the guideline step (the LLM refines the cells the rules
  route to the program's guidelines) before type inference, and its tokens
  (`guideline_token_usage.json`) count towards C's. The 188-table results
  below were run before that: C's type scorer saw the rule types only. The
  guideline step types the whole paper of a sampled table, so in a run with
  `--tables` C also pays for the paper's other tables.

Outputs per paper: `review.<arm>.jsonl` and `final_tables.<arm>.json` for A
and B, `review.jsonl` and `final_tables.json` for C. `tables.jsonl` is never
changed.

**Certificates.** C's certificates (in the paper's directory) carry the
typing of every cell: which types the rules decide, replayed by the kernel,
and which a model chose following the guidelines (see the main README).
`run_ablation.sh` copies each call's certificate, `types.jsonl` and
`guided_types.jsonl` into its results directory.
B writes the geometric certificate of every valid table
whose matched candidate is labelable to `certificates.constraints/` in the
paper's directory (`certificateN_hH_vV.pl` or `certificateN_layoutK.pl`),
kept apart from C's certificates, which C's review replaces in the paper's
directory itself. Like C's, each certificate carries its checking kernel and
checks itself with `swipl <certificate>`; B's carry no typing, since B uses
no types. A has no parser candidate and so no certificate. `run_ablation.sh`
copies B's into each call's results directory. For reviews published before
B wrote certificates, write them without the model:

```bash
cd src && swipl certify_reviews.pl --dataset=ablation/<name>/dataset --arm=constraints
```

## Files

| File | |
|---|---|
| `make_sample.py` | Draws a sample: half complex (human-reviewed **dev** labels, stratified by class), half from the first dataset's test split; one table per paper, at most 400 slots |
| `batch<NN>_sample.jsonl`, `batch<NN>_gold.jsonl` | The later batches (02–16, and 17a–17f for the last one) and their human-reviewed gold labels, drawn with `make_sample.py --batch` |
| `smoke_sample.jsonl` | The 15-table smoke sample: 10 drawn with seed 20261103, 5 complex added with `--extend smoke_sample.jsonl --quota multi_level=3,subtables=1,separator_rows=1 --seed 20261104` |
| `smoke_gold.jsonl` | Its gold labels (see below) |
| `<PMC>_t<N>_input.html`, `<PMC>_t<N>_candidates.html` | Each sample table as published, and coloured once per parser candidate |
| `data/<source>/papers/<PMC>/` | The smoke sample's papers (`tables.jsonl`, `metadata.json`), copied from `../type_abstraction/data/`, which is downloaded rather than kept in the repository |
| `prepare_dataset.py` | Copies the sample's papers (`tables.jsonl`, `metadata.json`) into a fresh dataset under `src/`, where DeepClause can see it; each paper comes from `data/` here if present, otherwise from `../type_abstraction/` |
| `run_ablation.sh` | Runs every arm on every table, one DeepClause run per table and arm, then collects and scores |
| `../../src/certify_reviews.pl` | Writes B's certificates again from published reviews, without the model |
| `../../src/ablation_collect.pl` | Turns each arm's verdict into a segmentation comparable with the gold (rebuilding repaired tables) |
| `score_ablation.py` | Outcomes, cell accuracy and tokens per arm |
| `run_batch.sh` | Draws one batch of tables no earlier sample holds, copies its papers into `data/`, checks every gold label resolves, then runs `run_ablation.sh` on it |
| `run_remaining.sh` | Runs every table still left as one last batch, in rounds of one table per paper |
| `pool_ablation.py` | Pools several scored runs into one report without calling a model; refuses a table scored twice |

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

## Growing the study batch by batch

After the smoke run, the study was grown to every table with a human-reviewed
gold label: the complex dev and test samples together (the ablation tunes
nothing, so the split does not matter), at most 400 slots, 188 tables in all.
Each batch is a run of its own, and no table was ever sent twice.

```bash
experiments/ablation/run_batch.sh 18 20261121          # 10 new tables, asks before the paid calls
experiments/ablation/run_remaining.sh 18 20261121      # every table left, as one last batch
python3 experiments/ablation/pool_ablation.py experiments/ablation/results/pooled-final \
    experiments/ablation/results/smoke-* experiments/ablation/results/batch*-*
```

- **Drawing.** `make_sample.py --batch N --exclude <every earlier sample>`
  draws round-robin over the classes (subtables, separator rows,
  multi-level). It writes the batch's gold labels from the reviewed files.
- **One table per paper per run.** `review_agent.sh --tables` marks a
  paper's other tables `not_selected` in its review file, and the collector
  reads that file. So two tables of one paper cannot share a run. They can
  sit in different batches, and `run_remaining.sh` splits the last batch
  into rounds (17a–17f) for that reason.
- **Check before paying.** `run_batch.sh` runs the collector on the fresh
  dataset first and stops unless every gold candidate resolves to a
  segmentation.
- **Seeds.** Batch 02 used 20261105, batch N (3–16) used 20261103 + N, and
  rounds 17a–17f used 20261120–20261125.

All batches ran at commit 3b76b98 with Claude Haiku 5.5. The smoke run ran on
the uncommitted ablation code that 3b76b98 later committed, with the same
prompt version (`table-segmentation-v1`).

## Results (188 tables)

`results/pooled-final/` pools the smoke run and every batch (batch 17's rounds
are also pooled alone in `results/batch17-pooled/`).

| | llm-only | constraints | full |
|---|---|---|---|
| correct (all) | 112/188 | 113/188 | **122/188** |
| correct (complex) | 110/183 | 111/183 | **120/183** |
| wrong but accepted | 75 | 50 | 47 |
| rejected (unparseable) | 0 | 25 | 19 |
| invalid output | 1 | 0 | 0 |
| cell accuracy, answered | 0.950 | 0.972 | 0.974 |
| cell accuracy, end to end | 0.950 | 0.843 | 0.875 |
| input / output tokens | 1,216,020 / 121,935 | 1,216,020 / 122,708 | 1,176,342 / 128,260 |

Paired, table by table (exact two-sided McNemar test on the disagreements):

| | first arm right only | second arm right only | p |
|---|---|---|---|
| full vs llm-only | 12 | 2 | 0.013 |
| full vs constraints | 12 | 3 | 0.035 |
| constraints vs llm-only | 6 | 5 | 1.0 |

Correct by class: subtables (36 tables) 14 / 15 / 19, separator rows (73)
46 / 48 / 49, multi-level (74) 50 / 48 / 52, simple (5, provisional labels)
2 / 2 / 2, for llm-only / constraints / full.

- The type scorer and the repair add correct answers; the constraints alone
  do not, but they turn about a third of the silent errors into refusals.
- 63 tables are wrong in every arm, usually with the same answer in all
  three. PMC9661877 alone accounts for 15 of them (0 of 15 right in any
  arm), then PMC5387038 and PMC5815492 (5 each). This points at the gold
  labels or the labelling convention, not at an arm. Their labels have not
  been rechecked, so absolute accuracy is understated for every arm.
- The one reviewed table whose gold answer has several subtables,
  PMC13467166/t2, failed in every arm (full refused it).

## Scoring

Each table ends in one outcome per arm: `correct` (accepted, segmentation
equals the gold), `wrong_accepted` (accepted, another segmentation: a silent
error), `invalid_output` (accepted, but not exportable), `rejected`
(`unparseable`) or `not_reviewed`. Also reported: cell accuracy (share of
cells with the gold label hmd/vmd/data/separator, over answered tables and
end to end), whether the model's own answer was right even where the arm
refused it, and model calls and tokens. The scorer runs no significance test;
the paired McNemar tests under Results were computed on the pooled 188 tables.

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
