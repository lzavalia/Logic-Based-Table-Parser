# Type abstraction experiment

Do the types of a table's cells (from a type DSL program) line up with its
metadata/data regions closely enough to choose between the parser's candidate
boundaries without a model call? This folder holds the inputs and results of
Phase 0, which asks only whether types and regions are dependent at all.

## Files

| File | What it is |
|---|---|
| `papers.json` | The 60 PMC ids used, with the search phrase that found each: the 20 papers of `first_test.zip` plus 8 from each of five other fields. 49 of them have tables. |
| `split.json` | Dev/test split by paper (SHA-1 of the PMC id mod 10 < 4 is dev): 15 dev, 34 test papers. |
| `gold_test.provisional.jsonl` | For each of the 98 test tables with two or more candidates, the correct candidate, or null when none is correct, with a confidence and a note. **Labelled by Claude (claude-opus-5-5) reading the cell text, not by people.** Replace it with human labels before drawing conclusions. |
| `data/` | Not in git. `xml/`: the 60 JATS XML files as fetched; `ds/papers/PMC<id>/`: the 49 papers with tables after the pipeline and typing (`input_tableN.html`, `candidatesN.html`, `tables.jsonl`, `types.jsonl`, `metadata.json`). Rebuild it with the steps below. |
| `disagreement_targets.provisional.jsonl` | For the 37 human-reviewed complex tables (22 test, 15 dev) whose gold has no correct candidate, the boundary (H, V) the gold note describes, counted as the review prompt counts it, or null when it is not one boundary (6 tables). **Written by Claude from the gold notes, not reviewed.** |
| `results/disagreement_explanations.provisional.jsonl` | Why each of those boundaries is not a candidate (`src/boundary_explainer.pl`), and the repair (`src/table_repair.pl`); see [Why the gold boundary is not a candidate](#why-the-gold-boundary-is-not-a-candidate). |
| `results/phase0_<level>_<confidence>.json` | Output of `tools/type_region_phase0.py` at the family or fine type level, on all labelled tables (`low`) or the high-confidence ones only (`high`). |

The type program is `type_dsl_examples/sci.tdsl`. Its rules were written
from the cells of the dev split only and frozen before Phase 0 was run.

## Reproduce

From `dataset-builder-agent/src/`, with SWI-Prolog and Python 3:

```bash
X=../experiments/type_abstraction
python3 $X/fetch_papers.py /tmp/ta/xml
swipl -q -g "use_module(dataset_pipeline),
  directory_files('/tmp/ta/xml', Fs),
  forall((member(F, Fs), file_name_extension(B, xml, F), sub_atom(B, 3, _, 0, Id)),
         (atom_concat('/tmp/ta/xml/', F, P),
          catch(process_paper(Id, P, '/tmp/ta/ds', [on_table_error(quarantine)], _), _, true)))" -t halt
swipl -q -g "use_module(table_type_abstraction),
  type_dataset('../type_dsl_examples/sci.tdsl', '/tmp/ta/ds')" -t halt
python3 ../tools/type_region_phase0.py --dataset /tmp/ta/ds \
  --gold $X/gold_test.provisional.jsonl --level family
```

Eleven of the papers have no tables in their full text and are skipped by
`process_paper`.

## Phase 0 results (test split, provisional labels)

- **Coverage.** 7.9% of non-empty test cells match no rule (2.1% on dev).
- **Dependence.** I(type family; region) = 0.184 bits, 18.6% of the region
  entropy; the largest of 1000 within-table permutations was 0.004 bits
  (p < 0.001). With fine types: 0.240 bits (24.3%). Within a table the mean is
  0.48 bits against 0.06 for permutations. Data cells are 57% Numeric and 31%
  Text; HMD cells 78% Text, VMD cells 81% Text.
- **Where types cannot help.** 32 of the 88 gold data regions are mostly Text.
- **Purity saturates.** The gold boundary's data columns are 99.3% pure at the
  family level, but other boundaries are 97.4% pure as well. Gold is strictly
  the purest in only 10% of tables and tied in 83%; row purity behaves the same
  (9% strictly purest, 65% tied). Adding a text row-header column to the data
  adds another perfectly pure column, and removing a numeric column leaves the
  rest pure, so purity alone cannot pick a boundary.
- **Contrast.** At the family level, the heading cell differs in type from its
  data column in 60% of columns and from its data row in 56% of rows; at the
  fine type level, in 83% and 74%.

Restricting to high-confidence labels changes none of these by more than a
few points.

## Phase 1: choosing a candidate by types (test split, provisional labels)

The pipeline scores with `src/table_type_scorer.pl`. `type_candidate_scorer.py`
and `type_candidate_scorer_tests.py` here are the experiment's own version, kept
for its options and its evaluation against gold; run them from this folder.
On all 860 ambiguous tables of the complex dataset, the Prolog scorer with its
fixed configuration (`--level family --model-cost --data-families Identifier`
here) selects the same candidate as this one under both scores.

`type_candidate_scorer.py` scores every candidate of the 98 ambiguous
test tables by description length (see its docstring) and selects the
cheapest; ties abstain. Everything was fixed before the first run, except the
header model: the pre-registered `line` model scores each HMD row and VMD
column alone and so cannot see a numeric column moved into the VMD (found by
a synthetic regression test after the first run). The `region` model, now the
default, scores all HMD cells of a subtable together, and all VMD cells. On
these tables the two differ in one selection.

| Level, header model | Decided | Correct when decided | Correct over all 98 |
|---|---|---|---|
| family, line (pre-registered) | 72 | 80.6% | 59.2% |
| family, region | 72 | 81.9% | 60.2% |
| type, line (pre-registered) | 90 | 80.0% | 73.5% |
| type, region | 90 | 80.0% | 73.5% |
| prior11 baseline (always decides) | 98 | 78.6% | 78.6% |
| purity baseline, type level | 91 | 67.0% | 62.2% |
| random candidate (expected) | 98 | | 33.8% |

Ten of the 98 tables have no correct candidate, so at most 89.8% is possible
over all; 10 of the 18 wrong selections at the type level are on those
tables, where prior11 is wrong as well.

Ranking decisions by margin (bits per typed cell between the best and the
runner-up), type level: the top 22 are 95.5% correct, the top 45 93.3%, the
top 68 88.2%. Most remaining errors are all-text tables decided by small
margins between Text subtypes (Word, Phrase, LabelWithUnit).

`results/phase1_<level>_<header model>.html` shows every table colored by the
selected candidate, each cell with its type, and the cost of every candidate.

## Complex-table dataset

Collected because the first dataset holds few complex tables (no test table
whose gold answer has subtables).

- `search_papers.py` ran ten queries chosen to reach stacked subgroups,
  section rows and multi-level headers (baseline characteristics by subgroup,
  multivariable models, Cox regression, subgroup analyses, split-plot field
  trials, soil depth profiles, perovskite forward/reverse scans, cathode
  comparisons, summary-of-findings tables, diagnostic accuracy by subgroup),
  30 new papers each: `complex_papers.json` maps each id to its query.
- 248 of the 300 papers have tables: 1,091 tables, 860 with two or more
  candidates.
- `complex_tables.jsonl` lists the 462 tables whose candidate set is complex,
  by the most complex candidate offered: `subtables` (a layout with two or
  more subtables, 69), `separator_rows` (a layout with rows set aside, 166) or
  `multi_level` (a candidate with two or more HMD rows or VMD columns, 227).
  The class describes the candidates, not the correct answer.
- `complex_split.json`: dev/test by paper, same hash rule as `split.json`
  (109 dev, 139 test papers; 201 dev, 261 test complex tables).
- Types from the frozen `sci.tdsl`: 10.4% of non-empty cells in complex tables
  are untyped (7.9% in the first test split).
- Downloads and the built dataset are in `data/complex/` (not in git). To
  rebuild: `python3 fetch_papers.py data/complex/xml complex_papers.json`,
  then the reproduce steps above with `data/complex` in place of `/tmp/ta`.

### Labels for the complex test sample

- `complex_test_sample.jsonl`: a stratified sample of 150 complex test tables
  (seed 20261026): all 35 `subtables` tables, 58 `multi_level`, 57
  `separator_rows`, from 74 papers.
- `gold_complex_test.provisional.jsonl`: Claude's labels for the sample, from
  the cell text only (types not shown). 94 high confidence, 32 low, 24 with no
  correct candidate. By class: `subtables` 9 / 11 / 15, `multi_level`
  45 / 9 / 4, `separator_rows` 40 / 12 / 5 (high / low / none). Most `none`
  labels are tables that need a VMD column that no candidate offers, or two
  side-by-side blocks with their own VMD that no candidate splits.
- `complex_review.html` (built by `build_review_page.py`) shows each sampled
  table coloured by the chosen candidate, with Claude's pick preselected, for
  a human to confirm or correct; choices stay in the browser and are exported
  as `gold_complex_test.reviewed.jsonl`, where reviewed rows carry
  `"labeler": "human review"`. Cell types are not shown on the page.

### Results on the complex test sample (human-reviewed gold)

`gold_complex_test.reviewed.jsonl` is the provisional file after a human
review of all 150 tables: 38 picks changed, 31 of them moving a column that
names each row's entity (Study, Trial, Author) from VMD to data. 128 tables
have a correct candidate.

Phase 0 (`results/complex_phase0_<level>.json`): I(type family; region) =
0.171 bits (16.6% of region entropy; permutation max 0.008), fine types 0.210.
11.7% of non-empty cells untyped. 44 of 128 gold data regions are mostly Text.

Phase 1, correct selections out of 150 (`results/complex_phase1_*.json`):

| Scorer | subtables (35) | separator rows (57) | multi-level (58) | all (150) |
|---|---|---|---|---|
| description length, family (as pre-registered) | 1 | 30 | 36 | 67 |
| description length, type (as pre-registered) | 2 | 33 | 37 | 72 |
| + model cost, family (post-hoc) | 11 | 37 | 48 | **96** |
| + model cost, type (post-hoc) | 9 | 39 | 50 | 98 |
| prior11 baseline | 3 | 37 | 30 | 70 |
| random candidate (expected) | 3.0 | 21.2 | 26.2 | 50.3 |
| tables with a correct candidate | 21 | 52 | 55 | 128 |

The pre-registered scorer failed on the `subtables` class: 20 of its 21
correct answers do not split the table, but giving each subtable its own
distributions can only lower the cost, so spurious splits won or tied (12
abstentions). `--model-cost` charges 0.5·log2(N) bits per distribution used
(BIC-style, no tuned parameter). It was added after seeing these results and
is evaluated on the same tables, so its numbers are optimistic until checked
on labelled dev tables. Against prior11, family level with model cost is
right on 37 tables where prior11 is wrong and wrong on 11 where it is right
(McNemar exact p = 0.0002; bootstrap 95% CI of the accuracy difference
+8.7 to +26.0 points). On the first test split (provisional labels) the model
cost changes little: 57/98 against 59/98 without it.

Ranked by margin, the family-level scorer with model cost is 92% correct on
its 25 most confident tables and 88% on its top 50.

### Labels for the complex dev sample

- `complex_dev_sample.jsonl`: 80 complex dev tables (seed 20261027): all 34
  `subtables`, 23 `multi_level`, 23 `separator_rows`, from 51 papers.
- `gold_complex_dev.provisional.jsonl`: Claude's labels, following the
  convention from the test review (entity-naming columns are data), applied
  also to material names, brain areas and outcome names in
  summary-of-findings tables; those calls are marked low confidence where
  unsure. 41 high, 24 low, 15 none.
- `complex_dev_review.html`: review page; exports
  `gold_complex_dev.reviewed.jsonl`. Dev labels are for choosing among the
  schema/contrast scorer variants; the test sample is scored once afterwards.

### Schema and contrast scorers: selection on dev

`gold_complex_dev.reviewed.jsonl`: the user reviewed all 80 dev labels and
changed none. Four scores (`--score`, see `tools/type_schema.py` and the
scorer's help) × three type levels, all with `--model-cost`, were run on the
80 dev tables only (`results/dev/`). Correct out of 80 (65 have a correct
candidate; prior11 gets 28):

| score | family | type | mixed |
|---|---|---|---|
| dl (current) | 43 | 37 | 40 |
| contrast | 44 | 43 | 46 |
| blocks | 44 | 45 | **49** |
| schema | 37 | 39 | 41 |

Chosen before touching the test sample: `--score blocks --level mixed
--model-cost`. The column-schema score alone does worst, as expected from
its blind spot for a VMD column taken as data.

Test run (once, `results/complex_phase1_blocks_mixed.json`): 97/150
(subtables 13/35, separator rows 37/57, multi-level 47/58), deciding 147.
The earlier post-hoc `dl family --model-cost` got 96/150 deciding 138: the
two are right on different tables (9 vs 8; McNemar p = 1), so the dev gain
(49 vs 43) did not carry over. Against prior11 (70/150) the chosen scorer is
right on 44 tables where prior11 is wrong and wrong on 17 where it is right
(McNemar exact p = 0.0007). Since the chosen scorer includes the model cost,
this is the first clean (not post-hoc) test of it.

The schema/contrast scorers (`tools/type_schema.py`, `--score`, `--level
mixed`) were removed afterwards at the user's request; the result files in
`results/dev/` and `results/complex_phase1_blocks_mixed.*` are kept as the
record of that experiment.

### Identifier types (idea B.1)

`sci.tdsl` gained a fifth family, `Identifier` (`Citation`: author–year and
author–reference citations such as `Sawada et al. (2019) [ 16 ]`, `Bernard
[ 35 ]`, `Shargie 2006 ETH`; `TrialID`: NCT/ISRCTN/ChiCTR; `VariantID`:
rs numbers), written from dev cells only and placed before the text rules.
The scorer's `--data-families Identifier` treats them as data by role: they
are left out of the data rows' distributions and cost one model-cost unit
each when a candidate puts them in the VMD. Both datasets were re-typed.

Dev (80 tables, `results/dev/id_*.json`), all with `--model-cost`:

| level | before (no Identifier) | types only | types + role |
|---|---|---|---|
| family | 43 | 40 | **48** |
| type | 37 | 36 | 43 |

Chosen before the test run: `--level family --model-cost --data-families
Identifier`.

## Guideline step (model typing of text cells)

`src/type_guidelines.pl`, `src/guideline_answers.pl` and
`src/type_guidelines.dml` bring the DSL's `guideline` statements online. A
cell goes to the model only when no rule types it, or when its rule type has
guideline-decided subtypes (in `sci.tdsl`: Word, Phrase, LabelWithUnit may
become VariableLabel, CategoryLevel, EntityName, StatisticLabel or
Description); every other rule type, Citation included, is final. Answers
are checked against each cell's allowed types and cached by (program hash,
text, rule type), so re-running costs nothing and editing the program
invalidates them. Offline tests: `tests/type_guidelines_regression_tests.pl`.

Size: the whole complex dataset needs 712 batches and 23,640 cell texts; the
125 papers with reviewed labels (`labelled_papers.txt`) need 436 batches and
15,191 texts. The prompts alone are about 1.0M and 0.66M input tokens, but a
run costs more: DeepClause adds about 1,900 tokens per call, and a model that
calls `set_result` and `finish` in separate turns sends each prompt twice.
Measured on all 712 batches with a fake model (at 4 characters per token):
about 5.1M input tokens in two turns, about 2.4M in one; for the 125 papers,
about 3.4M and 1.6M.

To run on the labelled papers (needs a configured model, as for the
review), from `dataset-builder-agent/` with the complex dataset linked or
copied to `src/dataset`:

```bash
./guideline_agent.sh --papers "$(cat experiments/type_abstraction/labelled_papers.txt)"
```

then score with `--types-file guided_types.jsonl` (and e.g. `--data-types
EntityName`).

## Guideline pilot of `sci_text.tdsl` (dev split, provisional labels)

One run, 2026-10-30: `claude-sonnet-4-6`, temperature 0, captions off, on the
20 dev papers in `results/guideline_pilot/papers.txt`, from an isolated copy.
All 1,773 cell texts were answered in 55 batches and 110 calls (two turns per
batch), 468,198 input and 37,459 output tokens.

Against 299 stratified cells labelled before the run from their table context
(`check_labels.prelabel.jsonl`, by Claude, not yet reviewed), the model agrees
on 83.9% of types and 87.3% of groups. Two papers hold 145 of the cells; without
them, 81.2% and 86.4%. `disagreements_for_review.jsonl` lists the 48
disagreements. Captions on has not been run.

## Why the gold boundary is not a candidate

2026-11-02. 37 of the 230 human-reviewed complex tables (dev and test) have
no correct candidate. For each, `disagreement_targets.provisional.jsonl`
gives the boundary the gold note describes (provisional, by Claude, following
the labelling convention that row-identifier columns are data). Six are not
one boundary: five tables of two side-by-side blocks (PMC5754143) and one
where each entry spans two rows (PMC13161761/t2). The other 31 were explained
by `src/boundary_explainer.pl`, by the first parse rule each breaks:

| Category (first broken rule) | Test | Dev | All |
|---|---|---|---|
| `boundary_cuts_merged_cell` (rule 0) | 8 | 8 | 16 |
| `missing_hierarchy_evidence` (rule 2 or 3) | 5 | 7 | 12 |
| `header_row_required` (rule 9) | 2 | 0 | 2 |
| `no_headers_or_no_data` (rule 7) | 1 | 0 | 1 |
| excluded (not one boundary) | 6 | 0 | 6 |

- **Rule 0, 16 tables.** Every one is a group-label row ("Gender, n (%)",
  "Race/ethnicity") whose cell spans the label column and some data columns
  but not the whole width, so the row is not set aside and a row-header
  column cuts through it. What follows the label differs: in 9 tables it is
  text, such as the group's p-value; in 6 it is only empty cells
  (PMC6204586/t0, PMC8359171/t5, PMC11846376/t0, PMC12357927/t4,
  PMC7780720/t1, PMC9822893/t5), so with them merged into the label the row
  would span the whole width and be set aside; PMC12416123/t0 has rows of
  both kinds.
- **Rules 2 and 3, 12 tables.** In 10 the parent column (or upper header row)
  is written once per group with blank cells below or beside it, so it has no
  spanning cell; the explanation lists those empty cells. The other two:
  PMC9075525/t1, where two row-header columns span exactly the same rows, so
  the left one is never split by the right; and PMC12945645/t2, whose group
  row sits below the row it groups (it also breaks rules 4 and 6).
- **Rule 9, 2 tables** (PMC11731873/t1, t2): no header row, but some rows
  span two columns.
- **Rule 7, 1 table** (PMC8072689/t0): a plot grid with no headers at all.

**Repair of blank cells** (`src/table_repair.pl`, rule `empty-merge-v3`).
Merging empty cells into their parent labels makes the
gold boundary a candidate for 5 of the 12 rule 2/3 tables (test 2 of 5, dev
3 of 7): PMC3046964/t1, PMC3344821/t2, PMC13029392/t1 and both PMC5325311
tables. A merge is only made where the same sequence of children repeats
under another label, which rules out the other readings of the blanks.

The first version (`empty-merge-v1`) merged wherever the grid allowed and
repaired 10. One of those, PMC9661877/t0, was wrong: it stretched
"Corresponding risk" over four columns it does not head, since the blanks
right of it are the tops of the labels below. That table's second header row
has no spanning cell at all, so no sound repair exists. The strict rule
refuses it, along with:

- PMC8987291/t2: each cancer type heads different studies, so nothing
  repeats. Reading the types as groups is almost certainly right, but the
  table does not prove it.
- The three PMC10221898 tables, whose blanks have no label above them (they
  follow section rows); v1 merged them into blank group cells, which v2 no
  longer makes.
- Inside the repaired tables, the merges into "Two way ANOVA", "ANOVA" and
  the "Tillage" header repeated in the body of PMC3344821/t2: 7 cells, left
  alone; the tables are repaired without them.

**Group rows** (v3, rule 0). Merging the blank tail of a group row into its
label, which already spans past the row-header column, makes the row a
section row and the gold boundary a candidate for 5 of the 16 rule 0 tables
(test 2 of 8, dev 3 of 8): PMC6204586/t0, PMC8359171/t5, PMC11846376/t0,
PMC12357927/t4 and PMC7780720/t1. Each merged label was checked by hand: it
heads the rows below it ("Model 1-4" under "Tumor size (cm)", the infection
sites under "Source of infection n (%)"). Of the other 11, nine
have group rows followed by a value, nearly always a p-value, which the
repair leaves alone (a section row would drop the value; shrinking the label
would lose its rows); one of them, PMC12416123/t0, has its blank-tailed group
rows merged but stays refused. PMC8482729/t1's cut cell is a sub-header row.
PMC9822893/t5 has its group rows merged but stays refused, since its year row
sits below the header row it groups (rules 2, 4 and 6).

With both repairs, 10 of the 37 gold boundaries become candidates (test 4 of
22, dev 6 of 15). If the review always gave the gold boundary, the share of
the 230 tables it disagrees with would fall from 37 (16.1%) to 27 (11.7%):
test 22 to 18 of 150, dev 15 to 9 of 80.

PMC9075525/t1 and PMC12945645/t2 have no blank cells to merge. Of the other
19 tables, PMC11731873/t1 has its "Publication bias" blanks merged (two
blocks with the same tests under them) but rule 9 still refuses the boundary;
PMC11731873/t2 is refused.

In the pipeline, a review whose boundary the repair makes a candidate is now
`valid` with `decided_by: "repair"` (see the main README). These counts are
the offline ones, against the gold boundaries, not against review answers.

Reproduce, from `dataset-builder-agent/src/`:

```bash
swipl explain_disagreements.pl --dataset=../experiments/type_abstraction/data/complex/ds \
    --targets=../experiments/type_abstraction/disagreement_targets.provisional.jsonl \
    --output=../experiments/type_abstraction/results/disagreement_explanations.provisional.jsonl
```
