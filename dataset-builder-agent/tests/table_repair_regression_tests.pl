% Merging empty cells so that a refused boundary becomes a candidate
% (table_repair.pl, consulted in dataset_pipeline), on hand-made rasters.
% From dataset-builder-agent/tests/:
%   swipl -q -s table_repair_regression_tests.pl -g run_tests -t halt
:- use_module('../src/dataset_pipeline').
:- use_module(library(plunit)).
:- use_module(library(lists)).

% record(+Raster, +Texts, -Record): one source cell per id; Texts gives
% Id-Text, and a missing id has empty text.
record(Raster, Texts, json{table_uid:"PMC1/t0", raster:Raster, cells:Cells}) :-
   append(Raster, Slots),
   list_to_set(Slots, Ids),
   findall(json{cell_id:Id, text:Text, kind:"source"},
           ( member(Id, Ids), ( memberchk(Id-Text, Texts) -> true ; Text = "" ) ),
           Cells).

repair(Raster, Texts, H, V, Repair) :-
   record(Raster, Texts, Record),
   repair_boundary(Record, H, V, Repair).

merge_ids(Repair, Pairs) :-
   findall(E-A-D, ( member(M, Repair.merges), E = M.cell_id, A = M.into,
                    D = M.direction ), Pairs).

:- begin_tests(table_repair).

test(blank_cells_join_a_label_whose_children_repeat) :-
   % Each year is written once, with a blank below it, over the same two
   % treatments.
   Raster = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [9, 10, 11], [12, 13, 14]],
   repair(Raster,
          [0-"Year", 1-"Treatment", 2-"Yield", 3-"2014", 4-"N0", 5-"1",
           7-"N1", 8-"2", 9-"2015", 10-"N0", 11-"3", 13-"N1", 14-"4"],
          1, 2, R),
   R.status == "repaired",
   merge_ids(R, [6-3-"up", 12-9-"up"]),
   R.merges = [M|_], M.rows == [2, 2], M.columns == [0, 0],
   R.refused == [],
   R.matched == json{kind:"boundary", hmd:1, vmd:2},
   R.remaining == null,
   sub_string(R.summary, _, _, _, "2 empty cells (2 into the label above, e.g. into \"2014\" and \"2015\")"),
   repaired_raster(Raster, R.merges, Repaired),
   Repaired == [[0, 1, 2], [3, 4, 5], [3, 7, 8], [9, 10, 11], [9, 13, 14]].

test(a_label_whose_children_do_not_repeat_is_left_alone) :-
   % The two years head different treatments: the blank below 2014 may
   % repeat it or mean that the row has no year.
   repair([[0, 1, 2], [3, 4, 5], [6, 7, 8], [9, 10, 11], [12, 13, 14]],
          [0-"Year", 1-"Treatment", 2-"Yield", 3-"2014", 4-"N0", 5-"1",
           7-"N1", 8-"2", 9-"2015", 10-"P0", 11-"3", 13-"P1", 14-"4"],
          1, 2, R),
   R.status == "refused",
   R.merges == [],
   R.refused = [F1, F2],
   F1.into == 3, F1.cells == [6], F1.reason == "children_not_repeated",
   F2.into == 9, F2.cells == [12],
   sub_string(R.summary, _, _, _, "the cells beside \"2014\" do not repeat").

test(blank_cells_under_a_section_row_are_not_merged) :-
   % Row 1 is a section row, set aside; the parent column below it is blank.
   % There is no label to join, and blanks never join one another.
   repair([[0, 1, 2], [3, 3, 3], [4, 5, 6], [7, 8, 9]],
          [0-"Variety", 1-"Fertilizer", 2-"Yield", 3-"Effect of fertilizer",
           5-"NPK", 6-"1", 8-"PK", 9-"2"],
          1, 2, R),
   R.status == "not_applicable",
   R.merges == [].

test(labels_in_the_middle_of_their_blocks_are_left_alone) :-
   % Centred labels: the children repeat when read from each label down
   % (b, c, a under P1 and P2), but the column starts with a blank.
   repair([[0, 1, 2], [3, 4, 5], [6, 7, 8], [9, 10, 11],
           [12, 13, 14], [15, 16, 17], [18, 19, 20],
           [21, 22, 23], [24, 25, 26], [27, 28, 29]],
          [0-"Group", 1-"Item", 2-"Value",
           4-"a", 5-"1", 6-"P1", 7-"b", 8-"2", 10-"c", 11-"3",
           13-"a", 14-"4", 15-"P2", 16-"b", 17-"5", 19-"c", 20-"6",
           22-"a", 23-"7", 24-"P3", 25-"b", 26-"8", 28-"c", 29-"9"],
          1, 2, R),
   R.status == "refused",
   R.merges == [],
   R.refused = [F], F.reason == "block_without_label_on_top", F.into == null.

test(no_merge_across_a_split_in_the_parent_column) :-
   % Column 1 is blank beside a parent column 0 that splits every row, so
   % merging it would break rule 5; column 0 itself has nothing to merge.
   repair([[0, 1, 2, 3], [4, 5, 6, 7], [8, 9, 10, 11], [12, 13, 14, 15]],
          [0-"Year", 1-"Variety", 2-"Trt", 3-"Y", 4-"2014", 6-"a", 7-"1",
           8-"2015", 10-"b", 11-"2", 12-"2016", 14-"c", 15-"3"],
          1, 3, R),
   R.status == "not_applicable",
   R.merges == [].

test(blank_header_cells_join_a_label_whose_children_repeat) :-
   % "2019" and "2020" each head the same two columns.
   repair([[0, 1, 2, 3, 4], [5, 6, 7, 8, 9], [10, 11, 12, 13, 14]],
          [0-"Site", 1-"2019", 3-"2020", 5-"Name", 6-"a", 7-"b", 8-"a", 9-"b",
           10-"x", 11-"1", 12-"2", 13-"3", 14-"4"],
          2, 1, R),
   R.status == "repaired",
   merge_ids(R, [2-1-"left", 4-3-"left"]),
   R.matched == json{kind:"boundary", hmd:2, vmd:1}.

test(a_header_label_over_unrelated_columns_is_left_alone) :-
   % The pattern of PMC9661877/t0: the blanks right of "Corresponding risk"
   % are the tops of the labels below them, not part of it.
   repair([[0, 1, 2, 3, 4], [5, 6, 7, 8, 9], [10, 11, 12, 13, 14]],
          [0-"Outcome", 1-"Assumed risk", 2-"Corresponding risk",
           5-"Name", 6-"Standard care", 7-"Skin care", 8-"Relative effect",
           9-"Participants", 10-"x", 11-"1", 12-"2", 13-"3", 14-"4"],
          2, 1, R),
   R.status == "refused",
   R.merges == [],
   R.refused = [F], F.line == "row", F.into == 2, F.cells == [3, 4],
   F.reason == "children_not_repeated".

test(a_header_row_starting_with_a_blank_is_left_alone) :-
   % With no row-header column the first header cell is blank, as in
   % PMC9661877/t0.
   repair([[0, 1, 2, 3], [4, 5, 6, 7], [8, 9, 10, 11]],
          [1-"2019", 4-"Name", 5-"a", 6-"b", 7-"c", 8-"x", 9-"1", 10-"2",
           11-"3"],
          2, 0, R),
   R.status == "refused",
   R.refused = [F], F.reason == "block_without_label_on_top",
   sub_string(F.message, 0, _, _, "Header row 0").

test(no_header_merge_across_a_split_in_the_row_above) :-
   % Row 0 splits columns 1 and 2, so the blank of row 1 may not join "x".
   repair([[0, 1, 2], [3, 4, 5], [6, 7, 8], [9, 10, 11]],
          [0-"Name", 1-"A", 2-"B", 4-"x", 6-"y", 7-"p", 8-"q", 9-"z",
           10-"1", 11-"2"],
          3, 1, R),
   \+ ( member(M, R.merges), M.cell_id == 5 ).

test(other_rules_are_not_repaired) :-
   % A group row cuts the row-header line (rule 0): nothing to merge.
   repair([[0, 1, 2], [3, 3, 4], [5, 6, 7]],
          [0-"Variable", 1-"Total", 2-"P", 3-"Gender", 4-"0.2", 5-"F",
           6-"1", 7-"2"],
          1, 1, R),
   R.status == "not_applicable",
   R.matched == null.

test(merges_that_leave_another_broken_rule_are_reported) :-
   % The blanks join "A" and "B", but the group row still cuts the line
   % (rule 0).
   repair([[0, 1, 2, 3], [4, 5, 6, 7], [8, 9, 10, 11], [12, 13, 14, 15],
           [16, 17, 18, 19], [20, 20, 20, 21]],
          [0-"G", 1-"S", 2-"Y", 3-"Z", 4-"A", 5-"s1", 6-"1", 7-"2", 9-"s2",
           10-"3", 11-"4", 12-"B", 13-"s1", 14-"5", 15-"6", 17-"s2", 18-"7",
           19-"8", 20-"Group", 21-"9"],
          1, 2, R),
   R.status == "not_repaired",
   merge_ids(R, [8-4-"up", 16-12-"up"]),
   R.remaining.category == "boundary_cuts_merged_cell",
   sub_string(R.summary, _, _, _, "Even after merging 2 empty cells").

test(a_group_row_followed_by_blanks_becomes_a_section_row) :-
   % "Gender" already spans columns 0-1, past the row-header column, and
   % the rest of its row is blank: it heads Male and Female.
   Raster = [[0, 1, 2, 3], [4, 4, 5, 6], [7, 8, 9, 10], [11, 12, 13, 14]],
   repair(Raster,
          [0-"Variable", 1-"A", 2-"B", 3-"P", 4-"Gender", 7-"Male", 8-"1",
           9-"2", 10-"0.1", 11-"Female", 12-"3", 13-"4", 14-"0.2"],
          1, 1, R),
   R.status == "repaired",
   merge_ids(R, [5-4-"left", 6-4-"left"]),
   R.matched.kind == "layout",
   repaired_raster(Raster, R.merges, Repaired),
   nth0(1, Repaired, [4, 4, 4, 4]).

test(a_group_row_with_a_value_is_left_alone) :-
   % The p-value of "Gender" would be lost in a section row.
   repair([[0, 1, 2, 3], [4, 4, 5, 6], [7, 8, 9, 10], [11, 12, 13, 14]],
          [0-"Variable", 1-"A", 2-"B", 3-"P", 4-"Gender", 6-"0.03",
           7-"Male", 8-"1", 9-"2", 10-"0.1", 11-"Female", 12-"3", 13-"4",
           14-"0.2"],
          1, 1, R),
   R.status == "not_applicable", R.merges == [].

test(a_spanning_cell_not_starting_the_row_is_left_alone) :-
   % "Both" spans columns 1-2 in the body and starts at column 1, so it is
   % not a group row label; the boundary V = 2 cuts it.
   repair([[0, 1, 2, 3], [4, 5, 5, 6], [7, 8, 9, 10]],
          [0-"Group", 1-"A", 2-"B", 3-"C", 4-"x", 5-"Both", 7-"y", 8-"z",
           9-"1", 10-"2"],
          1, 2, R),
   R.merges == [].

test(blanks_spanning_other_rows_do_not_join_a_group_row) :-
   % The blank right of "Gender" also covers row 2, so merging it would not
   % make row 1 a single cell.
   repair([[0, 1, 2, 3], [4, 4, 5, 6], [7, 8, 5, 9], [10, 11, 12, 13]],
          [0-"Variable", 1-"A", 2-"B", 3-"P", 4-"Gender", 7-"Male", 8-"1",
           9-"0.1", 10-"Female", 11-"3", 12-"4", 13-"0.2"],
          1, 1, R),
   \+ ( member(M, R.merges), M.into == 4 ).

test(an_offered_boundary_needs_no_repair) :-
   repair([[0, 1], [2, 3]], [0-"a", 1-"b", 2-"c", 3-"d"], 1, 1, R),
   R.status == "already_offered", R.merges == [],
   R.matched == json{kind:"boundary", hmd:1, vmd:1}.

:- end_tests(table_repair).
