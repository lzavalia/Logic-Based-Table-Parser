% Regression tests for the public table-boundary API.
%
% A boundary (Hmd, Vmd) gives the number of HMD rows and of VMD columns;
% either may be 0, but not both (constraint 7), and some data must remain
% (constraint 8). Hmd = 0 is only for plain grids without merged cells
% (constraint 9).
%
% From dataset-builder-agent/tests/:
%   swipl -q -s boundary_regression_tests.pl -g run_tests -t halt
%
% No network, LLM, article downloads, or DeepClause installation required.

:- use_module(library(random)).
:- use_module(legacy_index_constraints).
:- consult('../src/parse_constraints').

% Every admissible pair, by the exhaustive reference (omni_validate/3).
reference_pairs(Raster, Pairs) :-
   (  valid_raster_shape(Raster, Rows, Cols)
   -> findall(H-V, ( between(0, Rows, H), between(0, Cols, V),
                     omni_validate(Raster, H, V) ), Pairs)
   ;  Pairs = [] ).

random_raster(Rows, Cols, MaxId, Raster) :-
   length(Raster, Rows),
   maplist(random_row(Cols, MaxId), Raster).
random_row(Cols, MaxId, Row) :-
   length(Row, Cols),
   maplist(random_between(0, MaxId), Row).

:- begin_tests(table_boundary_regressions).

% --- tables with HMD and VMD (unchanged rules, counted from 1) -------------

test(ordinary_two_by_two_has_both_kinds_and_each_alone) :-
    valid_boundaries([[0,1],[2,3]],
                     [json{hmd:0,vmd:1}, json{hmd:1,vmd:0}, json{hmd:1,vmd:1}]),
    omni_validate([[0,1],[2,3]], 1, 1),
    omni_validate([[0,1],[2,3]], 1, 1, none).

test(ordinary_three_by_three_retains_valid_partition) :-
    valid_boundaries([[0,1,2],[3,4,5],[6,7,8]], Boundaries),
    member(json{hmd:1,vmd:1}, Boundaries).

test(original_structural_constraints_still_report_offending_number) :-
    % Row 0 merges columns 0 and 1, so it is not a row of keys (rule 6).
    omni_validate([[0,0],[1,2]], 1, 1, some(6)),
    \+ omni_validate([[0,0],[1,2]], 1, 1).

% For every table with HMD and VMD, the count-form rules accept exactly the
% boundaries the original (last-index) rules accepted, shifted by one.
test(counts_agree_with_the_original_rules_when_both_regions_exist) :-
    set_random(seed(7)),
    forall(between(1, 3000, _),
           ( random_between(2, 6, Rows), random_between(2, 6, Cols),
             random_between(1, 4, MaxId),
             random_raster(Rows, Cols, MaxId, Raster),
             legacy_valid_boundaries(Raster, Old),
             findall(H1-V1, ( member(H-V, Old), H1 is H + 1, V1 is V + 1 ), Shifted),
             reference_pairs(Raster, New),
             findall(H-V, ( member(H-V, New), H >= 1, V >= 1 ), Both),
             assertion(Both == Shifted) )).

% --- HMD only and VMD only -------------------------------------------------

test(header_rows_without_row_headers) :-
    % A two-level header (cell 0 spans two columns, split in the row below)
    % over plain data: two HMD rows and no VMD column is the only fit. Row 0
    % alone cannot be the last header row, since it has a merge (rule 6).
    Raster = [[0,0,1],[2,3,4],[5,6,7]],
    valid_boundaries(Raster, [json{hmd:2,vmd:0}]),
    omni_validate(Raster, 1, 0, some(6)).

test(plain_grid_admits_exactly_three_parses) :-
    valid_boundaries([[0,1,2],[3,4,5],[6,7,8]],
                     [json{hmd:0,vmd:1}, json{hmd:1,vmd:0}, json{hmd:1,vmd:1}]).

test(no_hmd_rows_only_for_plain_grids) :-
    % A row-header cell spanning two rows is a merged cell, so the table is
    % read with HMD rows even though VMD alone would satisfy rules 0 to 8.
    Raster = [[0,1,2],[0,3,4],[5,6,7]],
    valid_boundaries(Raster, Boundaries),
    \+ member(json{hmd:0,vmd:_}, Boundaries),
    omni_validate(Raster, 0, 1, some(9)),
    % A one-row table with a merged cell has no admissible boundary at all.
    valid_boundaries([[0,0,1]], []),
    omni_validate([[0,0,1]], 0, 1, some(9)).

test(no_vmd_columns_are_not_limited_to_plain_grids) :-
    Raster = [[0,0,1],[2,3,4],[5,6,7]],
    valid_boundaries(Raster, [json{hmd:2,vmd:0}]).

test(single_row_can_have_row_headers_only) :-
    % A plain row. A second VMD column would need a vertical merge to its
    % left (rule 3).
    valid_boundaries([[0,1,2]], [json{hmd:0,vmd:1}]),
    omni_validate([[0,1,2]], 0, 2, some(3)).

test(single_column_can_have_a_header_row_only) :-
    % A second HMD row would need a horizontal merge above it (rule 2).
    valid_boundaries([[0],[1],[2]], [json{hmd:1,vmd:0}]),
    omni_validate([[0],[1],[2]], 2, 0, some(2)).

test(multi_row_header_without_row_headers_needs_its_hierarchy) :-
    % Two header rows: the first must merge what the second splits (rule 2).
    valid_boundaries([[0,0],[1,2],[3,4]], B1),
    member(json{hmd:2,vmd:0}, B1),
    valid_boundaries([[0,1],[2,3],[4,5]], B2),
    \+ member(json{hmd:2,vmd:0}, B2),
    omni_validate([[0,1],[2,3],[4,5]], 2, 0, some(2)).

% --- constraints 7 and 8 ---------------------------------------------------

test(no_table_is_entirely_data) :-
    Raster = [[0,1],[2,3]],
    \+ omni_validate(Raster, 0, 0),
    omni_validate(Raster, 0, 0, some(7)),
    valid_boundaries(Raster, Boundaries),
    \+ member(json{hmd:0,vmd:0}, Boundaries).

test(no_table_is_entirely_metadata) :-
    Raster = [[0,1],[2,3]],
    omni_validate(Raster, 0, 2, some(8)),
    omni_validate([[0],[1]], 2, 0, some(8)),
    \+ omni_validate(Raster, 2, 0),
    valid_boundaries(Raster, Boundaries),
    forall(member(json{hmd:H,vmd:V}, Boundaries), (H < 2, V < 2)).

test(single_cell_has_no_partition) :-
    % (0,0) is all data, (1,0) and (0,1) are all metadata.
    valid_boundaries([[0]], []),
    omni_validate([[0]], 0, 0, some(7)),
    omni_validate([[0]], 1, 0, some(8)).

test(merged_header_does_not_allow_all_rows_as_hmd) :-
    Raster = [[0,1,1],[2,3,4]],
    valid_boundaries(Raster, Boundaries),
    \+ member(json{hmd:2,vmd:_}, Boundaries),
    \+ omni_validate(Raster, 2, 1).

test(merged_side_does_not_allow_all_columns_as_vmd) :-
    Raster = [[0,1],[2,3],[2,4]],
    valid_boundaries(Raster, Boundaries),
    \+ member(json{hmd:_,vmd:2}, Boundaries),
    \+ omni_validate(Raster, 1, 2).

% --- malformed input -------------------------------------------------------

test(empty_raster_has_no_partition) :-
    valid_boundaries([], []).

test(empty_rows_have_no_partition) :-
    valid_boundaries([[],[]], []).

% Both public validator arities must enforce the same strict domain.
test(negative_counts_are_rejected) :-
    Raster = [[0,1],[2,3]],
    \+ omni_validate(Raster, -1, 1),
    \+ omni_validate(Raster, 1, -1),
    omni_validate(Raster, -1, -1, some(invalid_boundary)).

test(counts_beyond_the_table_are_rejected) :-
    Raster = [[0,1],[2,3]],
    \+ omni_validate(Raster, 3, 0),
    omni_validate(Raster, 2, 3, some(invalid_boundary)),
    omni_validate(Raster, 3, 1, some(invalid_boundary)).

test(non_integer_counts_are_rejected) :-
    Raster = [[0,1],[2,3]],
    \+ omni_validate(Raster, 1.0, 1),
    \+ omni_validate(Raster, foo, 1),
    omni_validate(Raster, foo, 1, some(invalid_boundary)).

test(ragged_rasters_are_rejected) :-
    Raster = [[0,1],[2]],
    valid_boundaries(Raster, []),
    \+ omni_validate(Raster, 1, 1),
    omni_validate(Raster, 1, 1, some(invalid_boundary)).

test(all_reported_candidates_satisfy_every_constraint) :-
    Raster = [[0,1,2],[3,4,5],[6,7,8]],
    valid_boundaries(Raster, Boundaries),
    forall(member(json{hmd:Hmd,vmd:Vmd}, Boundaries),
           ( Hmd >= 0, Hmd < 3,
             Vmd >= 0, Vmd < 3,
             Hmd + Vmd > 0,
             omni_validate(Raster, Hmd, Vmd, none) )).

:- end_tests(table_boundary_regressions).
