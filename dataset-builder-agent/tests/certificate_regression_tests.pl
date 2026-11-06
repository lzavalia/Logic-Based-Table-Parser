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

% Runs the certificate with nothing but swipl, from the temporary directory,
% so that no kernel can be found but the one the certificate carries.
run_certificate_file(File, Status) :-
   run_certificate_file(File, Status, _).

run_certificate_file(File, Status, Output) :-
   current_prolog_flag(executable, Swipl),
   tmp_file(dir, Scratch), make_directory(Scratch),
   process_create(Swipl, ['-q', File],
                  [cwd(Scratch), stdout(pipe(Out)), stderr(null), process(Pid)]),
   read_string(Out, _, Output), close(Out),
   process_wait(Pid, exit(Status)),
   delete_directory(Scratch).

% Writes Facts as they are, with no kernel added or replaced.
with_raw_certificate_file(Facts, Goal) :-
   tmp_file_stream(text, File, Stream),
   setup_call_cleanup(true,
                      ( write_certificate_stream(Stream, Facts), close(Stream),
                        call(Goal, File) ),
                      delete_file(File)).

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

% Constraint 1 rejects this boundary too, so the two agree on it.
test(stub_cell_crossing_the_hmd_line_is_rejected) :-
   Raster = [[0,1,2],[0,3,4],[5,6,7],[5,8,9]],
   omni_validate(Raster, 1, 2, some(1)),
   certify(Raster, 1, 2, not_labelable(Reasons)),
   memberchk(columns-cell_crosses_hmd_line(0, column(0)), Reasons).

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

% --- the embedded kernel -----------------------------------------------------

test(written_certificate_carries_the_kernel_source) :-
   certified([[0,1],[2,3]], 1, 1, Facts),
   with_certificate_file(Facts, [File]>>(
      read_certificate_file(File, Read),
      memberchk(checking_kernel(Sha, Source), Read),
      read_file_to_string('../src/certificate_kernel.pl', Kernel, [encoding(utf8)]),
      Source == Kernel,
      text_sha256(Kernel, Sha),
      run_certificate_file(File, 0, Output),
      once(sub_string(Output, _, _, _, Sha)),
      once(sub_string(Output, _, _, _, "certificate accepted")) )).

test(one_embedded_kernel_however_often_written) :-
   certified([[0,1],[2,3]], 1, 1, Facts),
   certificate_with_kernel(Facts, Once),
   certificate_with_kernel(Once, Twice),
   Once == Twice,
   with_raw_certificate_file(Once, [File]>>check_certificate_file(File, accepted)).

test(embedded_kernel_must_match_its_hash) :-
   certified([[0,1],[2,3]], 1, 1, Facts),
   certificate_with_kernel(Facts, WithKernel),
   memberchk(checking_kernel(Sha, Source), WithKernel),
   string_concat(Source, "% edited\n", Edited),
   replace_fact(checking_kernel(Sha, Source), checking_kernel(Sha, Edited),
                WithKernel, Bad),
   rejected_for(Bad, embedded_kernel_hash_mismatch(Sha, _)),
   with_raw_certificate_file(Bad, [File]>>run_certificate_file(File, 1)).

% An embedded kernel that accepts anything, with its own hash, fools the
% certificate run as a program, but not a check as data with a kernel one
% trusts; the run prints a hash that is not the trusted kernel's.
test(a_lax_embedded_kernel_does_not_fool_a_trusted_one) :-
   certified([[0,0],[1,2],[3,4]], 2, 0, Facts),
   replace_fact(column_path(1, [0,2]), column_path(1, [0]), Facts, Bad0),
   Lax = ":- module(certificate_kernel, [check_loaded_certificate/0]).\n\c
          check_loaded_certificate :- format(\"certificate accepted~n\").\n",
   text_sha256(Lax, LaxSha),
   append(Bad0, [checking_kernel(LaxSha, Lax)], Bad),
   with_raw_certificate_file(Bad, [File]>>(
      run_certificate_file(File, 0, Output),
      once(sub_string(Output, _, _, _, LaxSha)),
      check_certificate_file(File, rejected(paths_do_not_match_raster)) )).

test(certificate_without_a_kernel_still_checks_as_data) :-
   certified([[0,1],[2,3]], 1, 1, Facts),
   \+ memberchk(checking_kernel(_, _), Facts),
   check_certificate(Facts, accepted).

test(reading_a_certificate_never_runs_its_directives) :-
   tmp_file_stream(text, File, Stream),
   format(Stream, ":- throw(directive_was_run).~n", []),
   certified([[0,1],[2,3]], 1, 1, Facts),
   forall(member(Fact, Facts), portray_clause(Stream, Fact)),
   close(Stream),
   call_cleanup(check_certificate_file(File, accepted), delete_file(File)).

% --- agreement with the structural constraints -----------------------------

% Every candidate of valid_boundaries/2 is certifiable.
test(structural_candidates_are_certifiable) :-
   set_random(seed(11)),
   forall(( between(1, 3000, _),
            random_between(1, 7, Rows), random_between(1, 7, Cols),
            random_between(1, 3, MaxSpan),
            random_tiling(Rows, Cols, MaxSpan, Raster),
            valid_boundaries(Raster, Boundaries),
            member(json{hmd:Hmd, vmd:Vmd}, Boundaries) ),
          certify(Raster, Hmd, Vmd, certificate(_))).

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
            layout_labels(Raster, Layout, CertLabels) )).

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
   labelled_layout(Raster, ["hhh","hhh","sss","vdd"], Layout),
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

% Every layout of table_layouts/2 is certifiable, and the certificate labels
% the table as layout_labels/3 does.
test(layouts_are_certifiable) :-
   set_random(seed(7)),
   forall(( between(1, 3000, _),
            random_between(2, 8, Rows), random_between(2, 7, Cols),
            random_between(1, 3, MaxSpan),
            random_tiling(Rows, Cols, MaxSpan, Raster),
            table_layouts(Raster, Layouts),
            member(Layout, Layouts) ),
          ( layout_subtables(Raster, Layout, Separators, Subtables),
            certify_layout(Raster, Separators, Subtables, none,
                           certificate(Facts)),
            certificate_labels(Facts, CertLabels),
            layout_labels(Raster, Layout, CertLabels) )).

:- end_tests(layout_certificates).

% --- typing ------------------------------------------------------------------

% A table typed by a small program:
%   [[0, 1, 2],     "Arm"  "Dose"  "Note x"
%    [3, 4, 5]]     "Placebo"  " 12 "  "3-4%"
% Rules: Integer and Numeric both match " 12 " (Integer is more specific);
% Word matches the one-word texts. Label lies below Word, so the Word cells
% are routed to the guidelines with [Label]; "Note x" matches no rule but
% has a letter, so it is routed with every guideline type; "3-4%" matches
% none and has no letter, so it stays untyped by the rules.
typing_program([
   typing_version(1),
   type_program("t.tdsl", "0000"),
   type_rule(0, "t.tdsl:1", regex("[0-9]+"), 'Integer'),
   type_rule(1, "t.tdsl:2", regex("[0-9]+(?:\\.[0-9]+)?"), 'Numeric'),
   type_rule(2, "t.tdsl:3", and(regex("\\p{L}+"), not(equals("none"))), 'Word'),
   type_subtype('Integer', 'Numeric'),
   type_subtype('Label', 'Word'),
   guideline(0, "a label", 'Label'),
   guideline(1, "an arm", 'Arm')
]).

typing_cells([
   cell_text(0, "Arm"),     cell_type(0, 'Label', guideline("B/1")),
   cell_text(1, "Dose"),    cell_type(1, 'Word', guideline_none("B/1")),
   cell_text(2, "Note  x"), cell_type(2, 'Arm', guideline("B/2")),
   cell_text(3, "Placebo"), cell_type(3, 'Word', guideline_pending),
   cell_text(4, " 12 "),    cell_type(4, 'Integer', rules),
   cell_text(5, "3-4%"),    cell_type(5, untyped, rules)
]).

typed_certificate(Facts) :-
   certified([[0,1,2],[3,4,5]], 1, 1, Geometric),
   typing_program(Program),
   typing_cells(Cells),
   append([Geometric, Program, Cells], Facts).

replace_typing(Old, New, Bad) :-
   typed_certificate(Facts),
   replace_fact(Old, New, Facts, Bad).

:- begin_tests(typing_certificates).

test(typing_section_is_accepted) :-
   typed_certificate(Facts),
   check_certificate(Facts, accepted).

test(rule_type_must_be_the_replayed_one) :-
   replace_typing(cell_type(4, 'Integer', rules), cell_type(4, 'Numeric', rules), Bad),
   rejected_for(Bad, rule_type_mismatch(4, 'Numeric', 'Integer')).

test(changed_text_changes_the_rule_type) :-
   replace_typing(cell_text(4, " 12 "), cell_text(4, "12.5"), Bad),
   rejected_for(Bad, rule_type_mismatch(4, 'Integer', 'Numeric')).

test(changed_rule_changes_the_rule_type) :-
   replace_typing(type_rule(0, "t.tdsl:1", regex("[0-9]+"), 'Integer'),
                  type_rule(0, "t.tdsl:1", regex("[0-9]"), 'Integer'), Bad),
   rejected_for(Bad, rule_type_mismatch(4, 'Integer', 'Numeric')).

test(routed_cell_cannot_be_typed_by_rules) :-
   replace_typing(cell_type(3, 'Word', guideline_pending), cell_type(3, 'Word', rules), Bad),
   rejected_for(Bad, routed_cell_typed_by_rules(3, 'Word', ['Label'])).

test(model_may_only_choose_an_allowed_type) :-
   replace_typing(cell_type(0, 'Label', guideline("B/1")), cell_type(0, 'Arm', guideline("B/1")), Bad),
   rejected_for(Bad, guideline_type_not_allowed(0, 'Arm', ['Label'])).

test(a_cell_not_routed_has_no_model_answer) :-
   replace_typing(cell_type(5, untyped, rules), cell_type(5, 'Arm', guideline("B/3")), Bad),
   rejected_for(Bad, cell_not_routed(5)).

test(kept_answer_keeps_the_rule_type) :-
   replace_typing(cell_type(1, 'Word', guideline_none("B/1")),
                  cell_type(1, 'Label', guideline_none("B/1")), Bad),
   rejected_for(Bad, rule_type_mismatch(1, 'Label', 'Word')).

test(every_cell_has_one_type_and_one_text) :-
   typed_certificate(Facts),
   selectchk(cell_type(5, untyped, rules), Facts, NoType),
   rejected_for(NoType, expected_one_cell_type(5)),
   selectchk(cell_text(5, "3-4%"), Facts, NoText),
   rejected_for(NoText, expected_one_cell_text(5)),
   rejected_for([synthetic_cell(5)|Facts], expected_one_cell_text(5)),
   rejected_for([cell_type(9, untyped, rules)|Facts],
                typing_fact_for_unknown_cell(cell_type(9, untyped, rules))).

test(synthetic_cells_are_empty) :-
   replace_typing(cell_text(5, "3-4%"), synthetic_cell(5), Bad0),
   rejected_for(Bad0, rule_type_mismatch(5, untyped, empty)),
   replace_fact(cell_type(5, untyped, rules), cell_type(5, empty, rules), Bad0, Good),
   check_certificate(Good, accepted).

test(typing_facts_need_the_typing_version) :-
   typed_certificate(Facts),
   selectchk(typing_version(1), Facts, Bad),
   rejected_for(Bad, expected_one_fact(typing_version/1)),
   replace_fact(typing_version(1), typing_version(2), Facts, Later),
   rejected_for(Later, unsupported_typing_version(2)).

test(rules_and_guidelines_are_numbered_and_well_formed) :-
   replace_typing(type_rule(1, "t.tdsl:2", regex("[0-9]+(?:\\.[0-9]+)?"), 'Numeric'),
                  type_rule(3, "t.tdsl:2", regex("[0-9]+(?:\\.[0-9]+)?"), 'Numeric'), Gap),
   rejected_for(Gap, type_rules_not_numbered),
   replace_typing(type_rule(1, "t.tdsl:2", regex("[0-9]+(?:\\.[0-9]+)?"), 'Numeric'),
                  type_rule(1, "t.tdsl:2", regex("[0-9"), 'Numeric'), BadRegex),
   rejected_for(BadRegex, rule_regex_invalid(1)),
   replace_typing(guideline(1, "an arm", 'Arm'), guideline(1, an_arm, 'Arm'), BadGuideline),
   rejected_for(BadGuideline, guideline_malformed(1)),
   replace_typing(cell_type(1, 'Word', guideline_none("B/1")),
                  cell_type(1, 'Word', guessed), Unknown),
   rejected_for(Unknown, unknown_derivation(1, guessed)).

test(typing_report_counts_rules_and_models) :-
   typed_certificate(Facts),
   typing_report(Facts, [Total, Rules, Chosen, Kept]),
   sub_string(Total, _, _, _, "6 cell(s)"), !,
   sub_string(Rules, _, _, _, "1 typed by deterministic rules"), !,
   sub_string(Rules, _, _, _, "1 empty or untyped"), !,
   sub_string(Chosen, _, _, _, "2 typed by a model"), !,
   sub_string(Kept, _, _, _, "1 kept at the rule type by a model, 1 routed"), !,
   typing_explanation(Facts, Lines),
   length(Lines, 6),
   nth0(2, Lines, Line2),
   sub_string(Line2, _, _, _, "chosen by a model (guideline batch B/2)"), !,
   nth0(4, Lines, Line4),
   sub_string(Line4, _, _, _, "deterministic: rule t.tdsl:1"), !,
   certified([[0,1],[2,3]], 1, 1, Plain),
   typing_report(Plain, []).

test(typed_certificate_checks_itself_and_explains_when_run) :-
   typed_certificate(Facts),
   with_certificate_file(Facts, [File]>>(
      run_certificate_file(File, 0, Output),
      once(sub_string(Output, _, _, _, "2 typed by a model")) )),
   replace_fact(cell_type(4, 'Integer', rules), cell_type(4, 'Numeric', rules), Facts, Bad),
   with_certificate_file(Bad, [File]>>run_certificate_file(File, 1)).

:- end_tests(typing_certificates).
