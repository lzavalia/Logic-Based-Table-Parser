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

% --- version 2: tables split into subtables --------------------------------

% Tables from table_layouts_regression_tests.pl.
layout_raster(data_title, [[0,1,1],[2,3,4],[5,6,6],[7,8,9]]).
layout_raster(separator_rows,
              [[0,0,0],[1,2,3],[4,5,6],[7,7,7],[8,9,10],[11,11,11]]).
layout_raster(central_hmd,
              [[ 0, 1, 1, 2, 2],[ 3, 4, 5, 6, 7],[ 8, 9,10,11,12],
               [13,14,14,15,15],[16,17,18,19,20],[21,22,23,24,25]]).
layout_raster(central_vmd, [[0,1,2,3,4],[5,6,7,8,9],[10,11,7,12,13]]).
layout_raster(mixed_cuts,
              [[ 0, 1, 2, 3, 4],[ 5, 6, 7, 8, 9],[10,11, 7,12,13],
               [14,15,15,16,16],[17,18,19,20,21],[22,23,24,25,26]]).
% Every data row of the second marginal reading is a separator.
layout_raster(all_separators, [[0,1,1],[0,2,3],[4,5,5],[4,5,5]]).

% layout_certified(+Raster, +Layout, -Facts)
layout_certified(Raster, Layout, Facts) :-
   layout_subtables(Raster, Layout, Separators, Subtables),
   certify_layout(Raster, Separators, Subtables, none, certificate(Facts)).

% The layout of Raster whose labels, one string per row as in
% table_layouts_regression_tests.pl, are Rows.
labelled_layout(Raster, Rows, Layout) :-
   table_layouts(Raster, Layouts),
   member(Layout, Layouts),
   layout_labels(Raster, Layout, Labels),
   maplist([Row, String]>>( maplist(label_char, Row, Chars),
                            string_chars(String, Chars) ),
           Labels, Rows), !.

label_char(hmd, h).
label_char(vmd, v).
label_char(data, d).
label_char(separator, s).

% certificate_labels(+Facts, -Labels): the role the certificate gives each
% slot, in the shape of its raster.
certificate_labels(Facts, Labels) :-
   memberchk(raster(Raster), Facts),
   findall(Row,
           ( nth0(R, Raster, RasterRow),
             findall(Label,
                     ( nth0(C, RasterRow, _),
                       certificate_slot_label(Facts, R, C, Label) ),
                     Row) ),
           Labels).

certificate_slot_label(Facts, R, C, separator) :-
   member(separator(R, Cols), Facts), memberchk(C, Cols), !.
certificate_slot_label(Facts, R, C, Label) :-
   member(subtable(K, Rows, Cols), Facts),
   nth0(I, Rows, R), nth0(J, Cols, C), !,
   memberchk(boundary(K, Hmd, Vmd), Facts),
   (  I < Hmd -> Label = hmd
   ;  J < Vmd -> Label = vmd
   ;  Label = data
   ).

% The certificate labels the table as layout_labels/3 does, except that a
% separator of a data region also sets aside the VMD slots beside it.
labels_agree([], []).
labels_agree([Row|Rows], [CRow|CRows]) :-
   maplist(label_agrees, Row, CRow),
   labels_agree(Rows, CRows).

label_agrees(Label, Label) :- !.
label_agrees(vmd, separator).

% The generator's verdict on a hand-made split of Raster: the kernel rejects
% the whole for Reason, although every subtable is labelable.
rejected_layout(Raster, Separators, Subtables, Reason) :-
   certify_layout(Raster, Separators, Subtables, none, rejected(Reason)).

:- begin_tests(layout_certificates).

% --- the generator ---------------------------------------------------------

test(every_layout_of_the_hand_built_tables_is_certified) :-
   forall(( layout_raster(_, Raster),
            table_layouts(Raster, Layouts),
            member(Layout, Layouts) ),
          ( layout_certified(Raster, Layout, Facts),
            certificate_labels(Facts, CertLabels),
            layout_labels(Raster, Layout, Labels),
            labels_agree(Labels, CertLabels) )).

test(central_hmd_is_two_subtables) :-
   layout_raster(central_hmd, Raster),
   labelled_layout(Raster, ["hhhhh","hhhhh","vdddd","hhhhh","hhhhh","vdddd"], Layout),
   layout_certified(Raster, Layout, Facts),
   memberchk(certificate_version(2), Facts),
   memberchk(subtable(0, [0,1,2], [0,1,2,3,4]), Facts),
   memberchk(boundary(0, 2, 1), Facts),
   memberchk(subtable(1, [3,4,5], [0,1,2,3,4]), Facts),
   memberchk(boundary(1, 2, 1), Facts),
   \+ memberchk(subtable(2, _, _), Facts).

test(vertical_cut_shares_the_hmd) :-
   layout_raster(central_vmd, Raster),
   labelled_layout(Raster, ["hhhhh","vdvdd","vdvdd"], Layout),
   layout_certified(Raster, Layout, Facts),
   memberchk(subtable(0, [0,1,2], [0,1]), Facts),
   memberchk(boundary(0, 1, 1), Facts),
   memberchk(subtable(1, [0,1,2], [2,3,4]), Facts),
   memberchk(boundary(1, 1, 1), Facts).

test(separator_sets_aside_the_vmd_cell_beside_it) :-
   layout_raster(data_title, Raster),
   labelled_layout(Raster, ["hhh","hhh","vss","vdd"], Layout),
   layout_certified(Raster, Layout, Facts),
   memberchk(separator(2, [0,1,2]), Facts),
   memberchk(subtable(0, [0,1,3], [0,1,2]), Facts).

test(region_of_separators_only_has_no_layout) :-
   layout_raster(all_separators, Raster),
   table_layouts(Raster, Layouts),
   forall(member(Layout, Layouts),
          ( layout_labels(Raster, Layout, Labels),
            \+ memberchk([vmd, separator, separator], Labels) )).

test(unlabelable_subtable_is_reported_by_key) :-
   Raster = [[0,0,1],[2,3,4],[5,6,7]],
   certify_layout(Raster, [],
                  [subtable([0,1,2], [0,1], 1, 0), subtable([0,1,2], [2], 1, 0)],
                  none, not_labelable([0-Reasons])),
   memberchk(columns-lines_share_a_path, Reasons).

% --- the partition ---------------------------------------------------------

test(data_in_two_subtables_is_rejected) :-
   layout_raster(central_hmd, Raster),
   rejected_layout(Raster, [],
                   [subtable([0,1,2], [0,1,2,3,4], 2, 0),
                    subtable([0,1,2,3,4,5], [0,1,2,3,4], 2, 0)],
                   data_slot_shared(2-0)).

test(slot_with_two_roles_is_rejected) :-
   layout_raster(central_hmd, Raster),
   rejected_layout(Raster, [],
                   [subtable([0,1,2], [0,1,2,3,4], 2, 0),
                    subtable([2,3,4,5], [0,1,2,3,4], 1, 0)],
                   slot_roles_disagree(2-0)).

test(uncovered_slot_is_rejected) :-
   layout_raster(central_hmd, Raster),
   rejected_layout(Raster, [], [subtable([0,1,2], [0,1,2,3,4], 2, 0)],
                   slot_not_covered(3-0)).

test(data_cell_in_two_subtables_is_rejected) :-
   layout_raster(central_vmd, Raster),
   rejected_layout(Raster, [],
                   [subtable([0,1], [0,1,2,3,4], 1, 1),
                    subtable([0,2], [0,1,2,3,4], 1, 1)],
                   data_cell_split(7)).

test(cell_both_data_and_metadata_is_rejected) :-
   layout_raster(central_vmd, Raster),
   rejected_layout(Raster, [],
                   [subtable([0,1], [0,1,2,3,4], 1, 1),
                    subtable([0,2], [0,1], 1, 1),
                    subtable([0,2], [2,3,4], 1, 1)],
                   cell_roles_disagree(7)).

test(separator_over_a_subtable_is_rejected) :-
   rejected_layout([[0,1],[2,3]], [separator(0, [0,1])],
                   [subtable([0,1], [0,1], 1, 1)],
                   separator_overlaps_subtable(0-0)).

% --- the kernel rejects malformed or tampered certificates -----------------

test(tampered_subtable_path_is_rejected) :-
   layout_raster(central_hmd, Raster),
   labelled_layout(Raster, ["hhhhh","hhhhh","vdddd","hhhhh","hhhhh","vdddd"], Layout),
   layout_certified(Raster, Layout, Facts),
   member(column_path(1, 1, Path), Facts), !,
   replace_fact(column_path(1, 1, Path), column_path(1, 1, [99]), Facts, Bad),
   rejected_for(Bad, subtable_rejected(1, paths_do_not_match_raster)).

test(malformed_subtables_are_rejected) :-
   layout_raster(central_hmd, Raster),
   labelled_layout(Raster, ["hhhhh","hhhhh","vdddd","hhhhh","hhhhh","vdddd"], Layout),
   layout_certified(Raster, Layout, Facts),
   replace_fact(subtable(1, Rows, Cols), subtable(2, Rows, Cols), Facts, Gap),
   rejected_for(Gap, subtables_not_numbered([0,2])),
   selectchk(claim(1, _), Facts, NoClaim),
   rejected_for(NoClaim, expected_one_fact(claim/2, 1)),
   append(Facts, [boundary(5, 1, 1)], Stray),
   rejected_for(Stray, unknown_subtable(boundary(5, 1, 1))),
   replace_fact(subtable(1, _, _), subtable(1, [4,3,5], Cols), Facts, Unordered),
   rejected_for(Unordered, subtable_rows_invalid(1)),
   append(Facts, [separator(9, [0])], OutOfRange),
   rejected_for(OutOfRange, separator_invalid(9, [0])),
   append(Facts, [subtable(2, [0], [0])], NoBoundary),
   rejected_for(NoBoundary, expected_one_fact(boundary/3, 2)).

test(versions_do_not_mix) :-
   rejected_for([certificate_version(1), raster([[0,1],[2,3]]),
                 subtable(0, [0,1], [0,1]), boundary(1,1), claim(columns),
                 column_path(1,[1])],
                unknown_fact(subtable(0, [0,1], [0,1]))),
   rejected_for([certificate_version(2), raster([[0,1],[2,3]]),
                 boundary(1,1)],
                unknown_fact(boundary(1,1))).

% --- certificates as programs ----------------------------------------------

test(written_layout_certificate_checks_itself_when_run) :-
   layout_raster(mixed_cuts, Raster),
   table_layouts(Raster, [Layout|_]),
   layout_subtables(Raster, Layout, Separators, Subtables),
   certify_layout(Raster, Separators, Subtables, "PMC1/t0", certificate(Facts)),
   with_certificate_file(Facts, [File]>>check_certificate_file(File, accepted)),
   with_certificate_file(Facts, [File]>>run_certificate_file(File, 0)),
   member(column_path(K, J, Path), Facts), !,
   replace_fact(column_path(K, J, Path), column_path(K, J, []), Facts, Bad),
   with_certificate_file(Bad, [File]>>run_certificate_file(File, 1)).

% --- agreement with the layout search --------------------------------------

% Every layout of table_layouts/2 is certifiable, except when a VMD cell
% crosses the HMD line of a subtable (see stub_crosses_hmd_line), and the
% certificate labels the table as layout_labels/3 does.
test(layouts_are_certifiable) :-
   set_random(seed(7)),
   forall(( between(1, 3000, _),
            random_between(2, 8, Rows), random_between(2, 7, Cols),
            random_between(1, 3, MaxSpan),
            random_tiling(Rows, Cols, MaxSpan, Raster),
            table_layouts(Raster, Layouts),
            member(Layout, Layouts) ),
          ( layout_subtables(Raster, Layout, Separators, Subtables),
            certify_layout(Raster, Separators, Subtables, none, Result),
            (  Result = certificate(Facts)
            -> certificate_labels(Facts, CertLabels),
               layout_labels(Raster, Layout, Labels),
               labels_agree(Labels, CertLabels)
            ;  Result = not_labelable(Reasons),
               forall(member(K-Why, Reasons),
                      ( nth0(K, Subtables, subtable(_, _, _, Vmd)),
                        stub_crosses_hmd_line(Vmd, not_labelable(Why)) ))
            ) )).

:- end_tests(layout_certificates).
