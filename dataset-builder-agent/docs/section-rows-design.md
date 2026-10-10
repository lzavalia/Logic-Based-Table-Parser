# Design: section-row support

**Status:** proposal. Nothing in the repo has been changed for this.
**Evidence base:** the 20-paper run in `first_test.zip` (49 tables), plus a Python reference model written for this design.
**Reference model and property test (both run, both pass):** `tools/section_rows_model.py`, `tools/section_rows_property_test.py`.
**Not yet done:** any Prolog implementation. The Prolog sketches below are untested.

---

## 1. Problem

In the real run, 7 of 49 tables (14%) abstained with `no_boundary_satisfies_constraints`. They fall into four distinct patterns, and only one of them is about section rows:

| Table | Shape | Why it abstains | Pattern |
|---|---|---|---|
| PMC12386235 t2 | 24×3 | rows 1, 6, 10 are one cell spanning all 3 columns | **section rows** |
| PMC7293797 t2 | 10×3 | rows 1, 7 span all columns ("Full model …") | **section rows** |
| PMC7293797 t3 | 19×3 | rows 1, 12 span all columns | **section rows** |
| PMC5831205 t1 | 36×5 | rows 2, 29 span all columns, **and** a stacked flat header | section rows + stacked header |
| PMC5831205 t0 | 27×5 | two flat header rows with rowspanned corner cells, no spans | stacked flat header |
| PMC12581614 t3 | 8×5 | header cell spans 2 columns in the last header row | constraint 6 (header colspan) |
| PMC12386235 t1 | 10×1 | one column | out of shape (needs ≥2 columns) |

**Why section rows break the model.** A full-width cell in a data row crosses the VMD|data boundary for *every* candidate `(H, V)`, so constraint 0 (`vertical_no_merged_cell_bisections`) fails everywhere. No boundary can satisfy it.

**Prototype result.** Handling section rows recovers **3 of the 7** (all three are `(0, 0)`), taking abstention from 7/49 (14.3%) to 4/49 (8.2%). The 42 tables that already succeed are untouched. The other 4 need different mechanisms (§9).

---

## 2. Definition (v1)

A **full-width row** is a raster row with at least 2 slots in which every slot holds the same cell id.

A **section row** is a full-width row that has a non-full-width row somewhere above it **and** somewhere below it.

Deliberately **not** section rows in v1:

- **Leading** full-width rows. These are title or spanning header rows, and constraints 2 and 4 already model them as header hierarchy.
- **Trailing** full-width rows. These are notes or footers, and they still abstain. None occurred in the sample.
- **Non-merged** rows whose only filled cell is the first one (§9).

A full-width cell with `rowspan > 1` makes several consecutive full-width rows with the same id. All of them are section rows, and they are removed together.

---

## 3. Design principles

1. **The seven constraints do not change.** `parse_constraints.pl`, `fast_boundaries.pl` and the differential check stay as they are. Section handling is a layer in front of them.
2. **Never alter an existing result.** If `valid_boundaries/2` already finds candidates, the output is identical to today. Reduction only runs when the direct search finds nothing, so it can only turn an abstention into candidates.
3. **Reduction preserves geometry.** A section row cannot be crossed by another cell's span, since every slot in it belongs to one cell. Removing it therefore creates no new merge and splits none. Rows above and below become adjacent with different cell ids.
4. **Fail closed.** Any removed row at or above a candidate's header boundary rejects that candidate.
5. **Be honest about the result.** Recovered candidates are structural hypotheses like all the others, and most are weak-evidence `(0, 0)` grids (§8).

**Why direct-first is principled, not just safe.** If a candidate `(H, V)` is valid on the raw raster, any full-width row below `H` would break constraint 0. So a direct candidate can only have full-width rows at or above `H`, which is exactly the "title row inside the header" case. Direct candidates and section rows cannot conflict.

---

## 4. Algorithm

Input: raster `R` (list of rows of cell ids).

1. `Direct = valid_boundaries(R)`. If non-empty, return it unchanged, with `section_rows: []` on each candidate.
2. `Sections = section_rows(R)`. If empty, return no candidates (abstain).
3. `Reduced` = `R` without the rows in `Sections`. `Keep` = the original index of each kept row.
4. `Found = valid_boundaries(Reduced)` using the unchanged indexed checker.
5. For each `(H', V)` in `Found`, set `H = Keep[H']`. **Reject** the candidate if any section row index is `≤ H` (a section row inside the header region). Otherwise emit `{hmd: H, vmd: V, section_rows: Sections}`.
6. Candidate order is the order of `Found`. Empty result means abstain.

Notes:

- A reduced raster with fewer than 2 rows is handled by the existing shape check (no candidates).
- The cost is one extra `valid_boundaries` call on abstained tables only.
- `Sections` is the same list for every candidate of a table, since it is a property of the table.

### Prolog sketch (untested)

```prolog
% src/table_sections.pl  (plain consulted file, like its siblings)

full_width_row([A,B|Rest]) :- maplist(==(A), [B|Rest]).

% Interior full-width rows: non-full-width rows exist above and below.
section_rows(Raster, Sections) :-
    findall(I, ( nth0(I, Raster, Row), \+ full_width_row(Row) ), Plain),
    Plain = [First|_], last(Plain, Last),
    findall(I, ( nth0(I, Raster, Row), full_width_row(Row),
                 I > First, I < Last ), Sections).

reduce_raster(Raster, Sections, Reduced, Keep) :-
    findall(I-Row, ( nth0(I, Raster, Row), \+ memberchk(I, Sections) ), Pairs),
    pairs_keys_values(Pairs, Keep, Reduced).

% candidate_boundaries(+Raster, -Candidates)
candidate_boundaries(Raster, Candidates) :-
    valid_boundaries(Raster, Direct),
    (   Direct \== []
    ->  findall(json{hmd:H, vmd:V, section_rows:[]},
                member(json{hmd:H, vmd:V}, Direct), Candidates)
    ;   section_rows(Raster, Sections), Sections \== []
    ->  reduce_raster(Raster, Sections, Reduced, Keep),
        valid_boundaries(Reduced, Found),
        findall(json{hmd:H, vmd:V, section_rows:Sections},
                ( member(json{hmd:Hr, vmd:V}, Found),
                  nth0(Hr, Keep, H),
                  \+ ( member(S, Sections), S =< H ) ),
                Candidates)
    ;   Candidates = []
    ).
```

---

## 5. Data contract changes

| Item | Change |
|---|---|
| `labels[].region` | new value `"section"` for every cell id located in a section row; existing values unchanged |
| candidate | new field `section_rows` (list of original row indices; `[]` for direct candidates) |
| table record | new field `section_rows_detected` (list; lets an abstained table say why it still failed, e.g. PMC5831205 t1) |
| `schema_version` | records become `"1.2"`; validation already accepts `"1.0"` and `"1.1"` and must also accept `"1.2"` (`dataset_pipeline.pl` ~lines 976 and 990) |
| `semantic_validation` | stays `"unverified"` |
| HTML | `region_color(section, khaki)`; candidate heading adds `data-section-rows="1,6,10"` when non-empty |
| candidate id | unchanged (`<table_uid>/h<H>_v<V>`) |

`section` is a **geometric** label: "a cell spanning every column inside the data region". It does not claim the row is semantically a group heading.

---

## 6. Integration points

All paths under `dataset-builder-agent/src/`. Today every caller uses `valid_boundaries/2` and passes `hmd`/`vmd` only.

| File and predicate | Change |
|---|---|
| new `table_sections.pl` | `full_width_row/1`, `section_rows/2`, `reduce_raster/4`, `candidate_boundaries/2` (§4) |
| `dataset_pipeline.pl` `save_table/5` (~line 1180) | call `candidate_boundaries/2` instead of `valid_boundaries/2`; keep `ensure_candidate_output_budget` |
| `dataset_pipeline.pl` JSONL consistency check (~line 1114) | recompute with the **same** `candidate_boundaries/2`, so the validator and the writer cannot diverge |
| `dataset_pipeline.pl` `render_boundary/3`, `save_annotated_candidate/4` | pass the candidate's sections to the annotator; extend the heading |
| `table_annotator.pl` `slot_region/5`, `annotate_table_element_raster/5` | add `Sections` argument (new `/6`, keep `/5` delegating with `[]`); `memberchk(R, Sections) -> section` before the existing `hmd`/`vmd`/`data` cases |
| `table_machine_records.pl` `machine_candidate/4`, `machine_cell_label/4` | same `Sections` argument; emit `section_rows` and `section_rows_detected` |
| `test_driver.pl` | call `candidate_boundaries/2` |
| `tools/evaluate_structural_candidates.py` | optional `gold_section_rows`; keep scoring `(hmd, vmd)` as it does today |
| README, `summary.md`, status file | describe the new region and the direct-first guarantee; no overclaiming (`tools/test_doc_claims.py` guards the wording) |

---

## 7. Verification plan

**Already done (Python reference model):**

- All 49 real rasters: the 42 existing results are identical, 3 abstentions recover to `(0, 0)`, 4 stay abstained.
- Property test: 15,177 random merged-cell tables with 1 to 3 full-width rows inserted. For every case, `candidates_with_sections(inserted)` equals the base candidates mapped to original row indices, minus any candidate whose header would include a section row (2,835 of those cases have a non-empty expected set).
- Edge assertions: trailing and leading full-width rows are never treated as sections.

**To do in the repo:**

1. `src/section_rows_regression_tests.pl` with these cases:
   - Rasters from the 3 recovered tables (copy the real rasters: PMC12386235 t2, PMC7293797 t2 and t3).
   - A synthetic 4×3 with one interior section row gives `{hmd:0, vmd:0, section_rows:[2]}`.
   - A raster that already has direct candidates returns them unchanged with `section_rows:[]`.
   - A trailing note row still abstains.
   - A section row inside the header region rejects the candidate.
   - A multi-row full-width cell (`rowspan=2`) removes both rows.
   - Labels: section cells get `"section"`, and every cell id is labeled exactly once.
2. A Python differential tool, `tools/verify_section_rows.py` (adapt `tools/section_rows_model.py` and the property test), checking the Prolog output against the model on seeded random rasters, as `verify_fast_boundary_logic.py` does for the seven constraints.
3. Golden regression: store the 49-table candidate counts (42 unique, 3 recovered, 4 abstained) as a fixture test.
4. Output-schema tests for `"1.2"` records, plus acceptance of `"1.0"` and `"1.1"`.
5. A DeepClause re-run of the same 20 papers, expecting the abstention counts above.

**Acceptance criteria:**

- No candidate set that exists today changes (bit-for-bit, including order).
- The 3 recoveries reproduce; the other 4 abstentions persist with their `section_rows_detected`.
- Section rows never appear in a candidate's header range.
- The Prolog differential tool agrees with the Python model on every seeded case.

---

## 8. Limits, stated plainly

- **This is coverage, not accuracy.** Two of the three recovered tables reduce to fully unmerged grids and the third is mostly unmerged, so their `(0, 0)` is the weakest kind of evidence. Pair this with the planned `all_cells_unmerged` flag (G2b) so these hypotheses are marked.
- A full-width interior cell might be a spanning note or a repeated header block, not a group heading. The label `section` is a geometric hypothesis.
- No gold set exists. Whether a recovered `(0, 0)` is *correct* is unknown until human labels exist.
- Real section rows are more common than the geometric rule sees. See the next section.

---

## 9. Out of scope, with measurements

**Text-defined section rows (v2).** In 10 of the 42 already-successful tables there are 19 rows with only the first cell filled and the rest empty (for example "Clinical baseline diagnosis", "Symptoms at diagnosis", "Postmortem findings"). They are not merged, so they pass the constraints and are currently labeled `data` (with their first cell `vmd`). Detecting them needs cell text, which the structural layer deliberately does not use. If added, it must be a separate, clearly marked `section_text_heuristic` label that never changes boundaries.

**Stacked flat headers (PMC5831205 t0 and t1).** The header is two rows of single cells (name row, "N = 19" row) with rowspanned corner cells, and no spans. Constraint 2 rejects any multi-row header without hierarchical spans.

**Do not fix this by relaxing constraint 2.** Measured on the 48 tables with a valid shape: with constraint 2 disabled, **40 of 48 tables gain extra candidates**, commonly dozens each (`(1,0)`, `(2,0)`, … down to the last row). Constraint 2 is what prunes boundaries in otherwise unmerged tables. Stacked headers need a different, narrower rule, designed on its own (for example, header rows that are 1:1 stacked with no data-like repetition), with its own measurements.

**Header colspan in the last header row (PMC12581614 t3).** Only constraint 6 fails: the header cell "Unified staging" spans two columns. This is the key-value property itself, and a change here would redefine the model.

**One-column tables (PMC12386235 t1).** The shape check requires at least 2×2. These are lists, not tables with a header structure.

---

## 10. Work breakdown

| # | Step | Depends on |
|---|---|---|
| 1 | Add `table_sections.pl` and `candidate_boundaries/2` | none |
| 2 | Add `section_rows_regression_tests.pl` (§7.1) | 1 |
| 3 | Thread `Sections` through annotator, machine records, pipeline, test driver | 1 |
| 4 | Schema `"1.2"`, validators, HTML heading and color | 3 |
| 5 | `tools/verify_section_rows.py` differential tool and golden fixture | 1 |
| 6 | Docs, status file, evaluator field | 4 |
| 7 | Native Prolog run, then a DeepClause re-run of the 20 papers | all |

Step 7 is the real gate. None of the Prolog above has been executed.

---

## 11. Open questions

1. Should trailing full-width rows (notes inside `<tbody>`) be handled in v1? None occurred in 49 tables, so this proposal leaves them out. Say if your wider corpus has them.
2. Is `"section"` the right region name, or should it match your downstream vocabulary?
3. Do you want `section_rows_detected` on abstained tables, or only on tables with candidates?
