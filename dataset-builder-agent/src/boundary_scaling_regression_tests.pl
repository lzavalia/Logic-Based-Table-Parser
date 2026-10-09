% F11: differential tests against the unchanged public seven-constraint oracle.
% swipl -q -s boundary_scaling_regression_tests.pl -g run_tests -t halt
:- use_module(library(random)).
:- use_module(library(lists)).
:- consult(parse_constraints).
:- use_module(dataset_pipeline).

:- begin_tests(boundary_scaling).

reference_boundaries(Raster, Boundaries) :-
   ( valid_raster_shape(Raster, Rows, Cols) ->
       MaxH is Rows - 2, MaxV is Cols - 2,
       findall(json{hmd:H,vmd:V},
               ( between(0, MaxH, H), between(0, MaxV, V),
                 omni_validate(Raster, H, V) ), Boundaries)
   ; Boundaries = [] ).

same_as_reference(Raster) :-
   reference_boundaries(Raster, Reference),
   valid_boundaries(Raster, Fast),
   assertion(Fast == Reference),
   forall(member(json{hmd:H,vmd:V}, Fast),
          assertion(omni_validate(Raster, H, V, none))).

binary_cell(0).
binary_cell(1).

flat_rows([], _, []).
flat_rows(Flat, Cols, [Row|Rows]) :-
   length(Row, Cols),
   append(Row, Rest, Flat),
   flat_rows(Rest, Cols, Rows).

binary_raster(R, C, Raster) :-
   Size is R * C,
   length(Flat, Size),
   maplist(binary_cell, Flat),
   flat_rows(Flat, C, Raster).

random_raster(Rows, Cols, MaxId, Raster) :-
   findall(Row,
           ( between(1, Rows, _),
             findall(Id, (between(1, Cols, _),
                          random_between(0, MaxId, Id)), Row) ),
           Raster).

% Exhaustively cover all equality configurations of modest size (including
% those not geometrically realizable), not just convenient all-distinct rows.
test(exhaustive_2x2) :-
   forall(binary_raster(2,2,Raster), same_as_reference(Raster)).
test(exhaustive_2x3) :-
   forall(binary_raster(2,3,Raster), same_as_reference(Raster)).
test(exhaustive_3x2) :-
   forall(binary_raster(3,2,Raster), same_as_reference(Raster)).
test(exhaustive_3x3) :-
   forall(binary_raster(3,3,Raster), same_as_reference(Raster)).
test(exhaustive_3x4) :-
   forall(binary_raster(3,4,Raster), same_as_reference(Raster)).

test(randomized_rectangular_rasters) :-
   set_random(seed(20261009)),
   forall(between(1, 400, _),
          ( random_between(2, 14, R),
            random_between(2, 14, C),
            random_between(1, 4, M),
            random_raster(R, C, M, Raster),
            same_as_reference(Raster) )).

test(realistic_merged_cells_and_ambiguous_boundaries) :-
   maplist(same_as_reference,
           [ [[0,1],[2,3]],
             [[0,1,2],[3,4,5],[6,7,8]],
             [[0,1,2],[3,4,5],[3,6,7]],
             [[0,0,1,1],[2,3,4,5],[2,6,7,8]],
             [[0,0,0],[1,1,1],[2,2,2]],
             [[0,1,1],[2,3,4]],
             [[0,1],[2,3],[2,4]] ]).

test(malformed_or_degenerate_returns_no_candidates) :-
   maplist(same_as_reference,
           [[], [[]], [[],[]], [[0]], [[0,1]],
            [[0],[1]], [[0,1],[2]], [[0,1],[2,3,4]]]).

test(stable_order_for_many_candidates) :-
   Raster = [[0,1,2,3],[4,5,6,7],[4,8,9,10],[4,11,12,13]],
   same_as_reference(Raster).

% Streaming is an output/memory optimization only.  Match the old in-memory
% renderer byte-for-byte for both ambiguous and abstaining tables.
legacy_vs_streamed(Html) :-
   dataset_pipeline:parse_html(Html, Dom),
   dataset_pipeline:extract_tables(Dom, [Table]),
   dataset_pipeline:rasterize_table(Table, Raster),
   dataset_pipeline:valid_boundaries(Raster, Bs),
   dataset_pipeline:table_source_context(Table, [], none, Context),
   dataset_pipeline:table_annotations(Table, Bs, Annotations),
   with_output_to(string(Legacy),
                  dataset_pipeline:save_annotated_candidates(
                      current_output, Context, Bs, Annotations)),
   with_output_to(string(Streamed),
                  dataset_pipeline:save_candidates_stream(
                      current_output, Context, Table, Raster, Bs)),
   assertion(Streamed == Legacy).

test(streaming_preserves_merged_ambiguous_html) :-
   legacy_vs_streamed(
     '<table><tr><td>A</td><td>B</td><td>C</td></tr><tr><td rowspan="2">R</td><td>1</td><td>2</td></tr><tr><td>3</td><td>4</td></tr></table>').

test(streaming_preserves_abstained_html) :-
   legacy_vs_streamed('<table><tr><td>only one cell</td></tr></table>').

test(streaming_preserves_unmerged_html) :-
   legacy_vs_streamed('<table><tr><th>H</th><th>V</th></tr><tr><th>K</th><td>D</td></tr></table>').

% A dense all-distinct 50x50 raster has 2401 valid (H,V) pairs and 2500
% distinct cells. Materializing all 6,002,500 per-candidate labels would
% overwhelm the F10 JSONL schema. Reject that before opening output files.
unique_raster(Rows, Cols, Raster) :-
   LastRow is Rows - 1, LastCol is Cols - 1,
   findall(Row, (between(0, LastRow, R),
                 findall(Id, (between(0, LastCol, C),
                              Id is R*Cols+C), Row)), Raster).

test(output_budget_allows_small_tables) :-
   unique_raster(8, 8, Raster),
   valid_boundaries(Raster, Candidates),
   length(Candidates, 49),
   dataset_pipeline:ensure_candidate_output_budget(Raster, Candidates).

test(output_budget_rejects_combinatorial_label_volume,
     [throws(error(table_output_limit_exceeded(candidate_labels, 500000, 6002500), _))]) :-
   unique_raster(50, 50, Raster),
   valid_boundaries(Raster, Candidates),
   length(Candidates, 2401),
   dataset_pipeline:ensure_candidate_output_budget(Raster, Candidates).

test(output_budget_allows_zero_candidate_abstention) :-
   dataset_pipeline:ensure_candidate_output_budget([[0]], []).

:- end_tests(boundary_scaling).
