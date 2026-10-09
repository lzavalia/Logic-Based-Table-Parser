% Regression tests for the public table-boundary API.
%
% From dataset-builder-agent/src/:
%   swipl -q -s boundary_regression_tests.pl -g run_tests -t halt
%
% No network, LLM, article downloads, or DeepClause installation required.

:- begin_tests(table_boundary_regressions).
:- consult(parse_constraints).

% Positive baselines: rejecting degenerate partitions must not suppress
% legitimate boundary candidates or change the seven original constraints.
test(ordinary_two_by_two_has_valid_partition) :-
    valid_boundaries([[0,1],[2,3]], [json{hmd:0,vmd:0}]),
    omni_validate([[0,1],[2,3]], 0, 0),
    omni_validate([[0,1],[2,3]], 0, 0, none).

test(ordinary_three_by_three_retains_valid_partition) :-
    valid_boundaries([[0,1,2],[3,4,5],[6,7,8]], Boundaries),
    member(json{hmd:0,vmd:0}, Boundaries).

test(original_structural_constraints_still_report_offending_number) :-
    omni_validate([[0,0],[1,2]], 0, 0, some(6)),
    \+ omni_validate([[0,0],[1,2]], 0, 0).

% Previously, all seven constraints succeeded vacuously on these inputs.
test(single_cell_has_no_partition) :-
    valid_boundaries([[0]], []).

test(single_row_has_no_data_rows) :-
    valid_boundaries([[0,1,2]], []).

test(single_column_has_no_data_columns) :-
    valid_boundaries([[0],[1],[2]], []).

test(empty_raster_has_no_partition) :-
    valid_boundaries([], []).

test(empty_rows_have_no_partition) :-
    valid_boundaries([[],[]], []).

test(merged_header_does_not_allow_all_rows_as_hmd) :-
    Raster = [[0,1,1],[2,3,4]],
    valid_boundaries(Raster, Boundaries),
    \+ member(json{hmd:1,vmd:0}, Boundaries),
    omni_validate(Raster, 1, 0, some(invalid_boundary)).

test(merged_side_does_not_allow_all_columns_as_vmd) :-
    Raster = [[0,1],[2,3],[2,4]],
    valid_boundaries(Raster, Boundaries),
    \+ member(json{hmd:0,vmd:1}, Boundaries),
    omni_validate(Raster, 0, 1, some(invalid_boundary)).

% Both public validator arities must enforce the same strict domain.
test(negative_coordinates_are_rejected) :-
    Raster = [[0,1],[2,3]],
    \+ omni_validate(Raster, -1, 0),
    \+ omni_validate(Raster, 0, -1),
    omni_validate(Raster, -1, -1, some(invalid_boundary)).

test(too_large_coordinates_are_rejected) :-
    Raster = [[0,1],[2,3]],
    \+ omni_validate(Raster, 1, 0),
    \+ omni_validate(Raster, 0, 1),
    \+ omni_validate(Raster, 2, 3),
    omni_validate(Raster, 2, 3, some(invalid_boundary)).

test(non_integer_coordinates_are_rejected) :-
    Raster = [[0,1],[2,3]],
    \+ omni_validate(Raster, 0.0, 0),
    \+ omni_validate(Raster, foo, 0),
    omni_validate(Raster, foo, 0, some(invalid_boundary)).

test(ragged_rasters_are_rejected) :-
    Raster = [[0,1],[2]],
    valid_boundaries(Raster, []),
    \+ omni_validate(Raster, 0, 0),
    omni_validate(Raster, 0, 0, some(invalid_boundary)).

test(all_reported_candidates_have_nonempty_regions) :-
    Raster = [[0,1,2],[3,4,5],[6,7,8]],
    valid_boundaries(Raster, Boundaries),
    forall(member(json{hmd:Hmd,vmd:Vmd}, Boundaries),
           ( Hmd >= 0, Hmd < 2,
             Vmd >= 0, Vmd < 2,
             omni_validate(Raster, Hmd, Vmd, none) )).

:- end_tests(table_boundary_regressions).
