% Regression tests for geometric labelability certificates: the trusted
% checker (certificate_kernel.pl) and the generator (table_certify.pl).
%
% From dataset-builder-agent/tests/:
%   swipl -q -s certificate_regression_tests.pl -g run_tests -t halt
%
% No network, LLM, article downloads, or DeepClause installation required.

:- use_module(library(random)).
:- use_module(library(assoc)).
:- use_module(library(process)).
:- consult('../src/parse_constraints').
:- consult('../src/table_certify').

% Accepted certificate facts for Raster at (Hmd, Vmd).
certified(Raster, Hmd, Vmd, Facts) :-
   certify(Raster, Hmd, Vmd, certificate(Facts)).

% The kernel's reason for rejecting Facts.
rejected_for(Facts, Reason) :-
   check_certificate(Facts, rejected(Reason)).

replace_fact(Old, New, Facts, Changed) :-
   selectchk(Old, Facts, New, Changed).

% random_tiling(+Rows, +Cols, +MaxSpan, -Raster): a raster of rectangular
% cells, numbered in row-major order like the rasterizer's.
random_tiling(Rows, Cols, MaxSpan, Raster) :-
   empty_assoc(Grid0),
   tile(0, 0, Rows, Cols, MaxSpan, 0, Grid0, Grid),
   LastRow is Rows - 1, LastCol is Cols - 1,
   findall(Row,
           ( between(0, LastRow, I),
             findall(Id, ( between(0, LastCol, J), get_assoc(I-J, Grid, Id) ), Row) ),
           Raster).

tile(I, _, Rows, _, _, _, Grid, Grid) :- I >= Rows, !.
tile(I, J, Rows, Cols, Max, Id, Grid0, Grid) :-
   J >= Cols, !,
   I1 is I + 1,
   tile(I1, 0, Rows, Cols, Max, Id, Grid0, Grid).
tile(I, J, Rows, Cols, Max, Id, Grid0, Grid) :-
   get_assoc(I-J, Grid0, _), !,
   J1 is J + 1,
   tile(I, J1, Rows, Cols, Max, Id, Grid0, Grid).
tile(I, J, Rows, Cols, Max, Id, Grid0, Grid) :-
   random_between(1, Max, Width0),
   random_between(1, Max, Height0),
   free_width(Grid0, I, J, Cols, Width0, 0, Width),
   Height is min(Height0, Rows - I),
   LastI is I + Height - 1, LastJ is J + Width - 1,
   findall(P-Q, ( between(I, LastI, P), between(J, LastJ, Q) ), Slots),
   foldl([Slot, G0, G]>>put_assoc(Slot, G0, Id, G), Slots, Grid0, Grid1),
   Id1 is Id + 1, J1 is J + Width,
   tile(I, J1, Rows, Cols, Max, Id1, Grid1, Grid).

free_width(Grid, I, J, Cols, Max, Width0, Width) :-
   (  Width0 < Max, J < Cols, \+ get_assoc(I-J, Grid, _)
   -> Width1 is Width0 + 1, J1 is J + 1,
      free_width(Grid, I, J1, Cols, Max, Width1, Width)
   ;  Width = Width0
   ).

% The one known way a candidate of valid_boundaries/2 is not certifiable:
% constraint 1 checks the HMD line only from column Vmd-1 rightwards, so a
% VMD cell further left may cross it. The kernel forbids that everywhere.
stub_crosses_hmd_line(Vmd, not_labelable(Reasons)) :-
   memberchk(columns-cell_crosses_hmd_line(_, column(J)), Reasons),
   J < Vmd - 1.

run_certificate_file(File, Status) :-
   current_prolog_flag(executable, Swipl),
   absolute_file_name('../src', Src, [file_type(directory)]),
   atom_concat('certificate_kernel=', Src, Alias),
   process_create(Swipl, ['-q', '-p', Alias, File],
                  [stdout(null), stderr(null), process(Pid)]),
   process_wait(Pid, exit(Status)).

with_certificate_file(Facts, Goal) :-
   tmp_file_stream(text, File, Stream),
   close(Stream),
   setup_call_cleanup(true,
                      ( write_certificate(File, Facts), call(Goal, File) ),
                      delete_file(File)).

:- begin_tests(geometric_certificates).

% --- the generator picks the claim that holds ------------------------------

test(single_header_row_is_column_labelable) :-
   certified([[0,1],[2,3]], 1, 1, Facts),
   memberchk(claim(columns), Facts),
   memberchk(column_path(1, [1]), Facts).

test(two_level_hierarchy_is_column_labelable) :-
   certified([[0,0],[1,2],[3,4]], 2, 0, Facts),
   memberchk(claim(columns), Facts),
   memberchk(column_path(0, [0,1]), Facts),
   memberchk(column_path(1, [0,2]), Facts).

test(rowspanned_header_cell_appears_once_in_its_path) :-
   certified([[0,1],[0,2],[3,4]], 2, 0, Facts),
   memberchk(column_path(0, [0]), Facts),
   memberchk(column_path(1, [1,2]), Facts).

test(without_hmd_rows_are_labelled_by_the_vmd) :-
   certified([[0,1],[2,3]], 0, 1, Facts),
   memberchk(claim(rows), Facts),
   memberchk(row_path(0, [0]), Facts),
   memberchk(row_path(1, [2]), Facts).

test(vmd_hierarchy_is_row_labelable) :-
   % Column 0 groups rows 0-1, column 1 splits them.
   certified([[0,1,2],[0,3,4],[5,6,7]], 0, 2, Facts),
   memberchk(claim(rows), Facts),
   memberchk(row_path(0, [0,1]), Facts),
   memberchk(row_path(1, [0,3]), Facts),
   memberchk(row_path(2, [5,6]), Facts).

% --- the strong reading ----------------------------------------------------

test(inverted_hierarchy_has_paths_no_column_follows) :-
   % Both columns pass through the merged cell 2, so the graph has four
   % paths for two columns, although the columns' paths differ.
   certify([[0,1],[2,2],[3,4],[5,6]], 3, 0,
           not_labelable([columns-graph_has_paths_without_line(4, 2),
                          rows-no_header_on_claimed_axis])).

test(columns_sharing_a_header_cell_are_not_labelable) :-
   certify([[0,0],[1,2]], 1, 0,
           not_labelable([columns-lines_share_a_path, _])).

test(no_header_on_either_axis_is_not_labelable) :-
   certify([[0,1],[2,3]], 0, 0, not_labelable(Reasons)),
   memberchk(columns-no_header_on_claimed_axis, Reasons).

% --- the boundary lines ----------------------------------------------------

test(cell_crossing_the_hmd_line_is_rejected) :-
   certify([[0,1],[0,2]], 1, 0, not_labelable(Reasons)),
   memberchk(columns-cell_crosses_hmd_line(0, column(0)), Reasons).

test(cell_crossing_the_vmd_line_is_rejected) :-
   certify([[0,1],[2,2]], 1, 1, not_labelable(Reasons)),
   memberchk(rows-cell_crosses_vmd_line(2, row(1)), Reasons).

test(vmd_line_inside_the_hmd_may_be_crossed) :-
   % A title spanning the whole first row is part of the HMD.
   certified([[0,0],[1,2],[3,4]], 2, 1, _).

test(stub_cell_crossing_the_hmd_line_is_rejected) :-
   Raster = [[0,1,2],[0,3,4],[0,5,4]],
   valid_boundaries(Raster, Boundaries),
   memberchk(json{hmd:1, vmd:2}, Boundaries),
   certify(Raster, 1, 2, Result),
   stub_crosses_hmd_line(2, Result).

% --- the kernel rejects malformed or tampered certificates -----------------

test(non_rectangular_cell_is_rejected) :-
   certify([[0,1],[1,0]], 1, 0, not_labelable(Reasons)),
   memberchk(columns-cell_not_rectangular(_), Reasons).

test(ragged_raster_is_rejected) :-
   rejected_for([certificate_version(1), raster([[0,1],[2]]), boundary(1,0),
                 claim(columns), column_path(0,[0]), column_path(1,[1])],
                raster_not_rectangular).

test(boundary_without_data_is_rejected) :-
   rejected_for([certificate_version(1), raster([[0,1],[2,3]]), boundary(2,0),
                 claim(columns), column_path(0,[0,2]), column_path(1,[1,3])],
                boundary_out_of_range(2, 0)).

test(altered_path_is_rejected) :-
   certified([[0,0],[1,2],[3,4]], 2, 0, Facts),
   replace_fact(column_path(1, [0,2]), column_path(1, [0,1]), Facts, Bad),
   rejected_for(Bad, paths_do_not_match_raster).

test(missing_path_is_rejected) :-
   certified([[0,0],[1,2],[3,4]], 2, 0, Facts),
   selectchk(column_path(1, _), Facts, Bad),
   rejected_for(Bad, paths_do_not_match_raster).

test(repeated_path_fact_is_rejected) :-
   certified([[0,0],[1,2],[3,4]], 2, 0, Facts),
   append(Facts, [column_path(1, [0,2])], Bad),
   rejected_for(Bad, paths_do_not_match_raster).

test(path_for_a_stub_column_is_rejected) :-
   certified([[0,1],[2,3]], 1, 1, Facts),
   append(Facts, [column_path(0, [0])], Bad),
   rejected_for(Bad, paths_do_not_match_raster).

test(switched_claim_is_rejected) :-
   certified([[0,1],[2,3]], 0, 1, Facts),
   replace_fact(claim(rows), claim(columns), Facts, Bad),
   rejected_for(Bad, path_of_other_axis(row_path)).

test(edited_raster_is_rejected) :-
   certified([[0,0],[1,2],[3,4]], 2, 0, Facts),
   replace_fact(raster(_), raster([[0,0],[1,1],[3,4]]), Facts, Bad),
   rejected_for(Bad, paths_do_not_match_raster).

test(unknown_and_duplicate_facts_are_rejected) :-
   certified([[0,1],[2,3]], 1, 1, Facts),
   rejected_for([trusted(yes)|Facts], unknown_fact(trusted(yes))),
   rejected_for([boundary(1,1)|Facts], expected_one_fact(boundary/2)),
   rejected_for([claim(_)|Facts], nonground_fact(claim(_))).

% --- certificates as programs ----------------------------------------------

test(written_certificate_reads_back_as_data) :-
   certify([[0,0],[1,2],[3,4]], 2, 0, "PMC1/t0", certificate(Facts)),
   with_certificate_file(Facts,
      [File]>>check_certificate_file(File, accepted)).

test(written_certificate_checks_itself_when_run) :-
   certified([[0,0],[1,2],[3,4]], 2, 0, Facts),
   with_certificate_file(Facts,
      [File]>>run_certificate_file(File, 0)).

test(tampered_certificate_fails_when_run) :-
   certified([[0,0],[1,2],[3,4]], 2, 0, Facts),
   replace_fact(column_path(1, [0,2]), column_path(1, [0]), Facts, Bad),
   with_certificate_file(Bad,
      [File]>>run_certificate_file(File, 1)).

test(reading_a_certificate_never_runs_its_directives) :-
   tmp_file_stream(text, File, Stream),
   format(Stream, ":- throw(directive_was_run).~n", []),
   certified([[0,1],[2,3]], 1, 1, Facts),
   forall(member(Fact, Facts), portray_clause(Stream, Fact)),
   close(Stream),
   call_cleanup(check_certificate_file(File, accepted), delete_file(File)).

% --- agreement with the structural constraints -----------------------------

% Every candidate of valid_boundaries/2 is certifiable, except when a VMD
% cell left of column Vmd-1 crosses the HMD line (see stub_crosses_hmd_line).
test(structural_candidates_are_certifiable) :-
   set_random(seed(11)),
   forall(( between(1, 3000, _),
            random_between(1, 7, Rows), random_between(1, 7, Cols),
            random_between(1, 3, MaxSpan),
            random_tiling(Rows, Cols, MaxSpan, Raster),
            valid_boundaries(Raster, Boundaries),
            member(json{hmd:Hmd, vmd:Vmd}, Boundaries) ),
          ( certify(Raster, Hmd, Vmd, Result),
            (  Result = certificate(_)
            -> true
            ;  stub_crosses_hmd_line(Vmd, Result)
            ) )).

:- end_tests(geometric_certificates).
