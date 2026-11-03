% Why a boundary is not a candidate (boundary_explainer.pl, consulted in
% dataset_pipeline), on small hand-made rasters and on random ones.
% From dataset-builder-agent/tests/:
%   swipl -q -s boundary_explainer_regression_tests.pl -g run_tests -t halt
:- use_module('../src/dataset_pipeline').
:- use_module(library(plunit)).
:- use_module(library(lists)).
:- use_module(library(apply)).

% record(+Raster, +Texts, -Record): a tables.jsonl record with one source
% cell per id; Texts gives Id-Text, and a missing id has empty text.
record(Raster, Texts, json{table_uid:"PMC1/t0", raster:Raster, cells:Cells}) :-
   append(Raster, Slots),
   list_to_set(Slots, Ids),
   findall(json{cell_id:Id, text:Text, kind:"source"},
           ( member(Id, Ids), ( memberchk(Id-Text, Texts) -> true ; Text = "" ) ),
           Cells).

explain(Raster, Texts, Candidates, H, V, E) :-
   record(Raster, Texts, Record),
   explain_boundary(Record, Candidates, H, V, E).

% random_raster(+Rows, +Cols, -Raster): rectangular merged cells placed
% row by row at the first free slot.
random_raster(Rows, Cols, Raster) :-
   length(Raster, Rows),
   maplist([Row]>>length(Row, Cols), Raster),
   fill(Raster, Rows, Cols, 0, 0).

fill(_, Rows, _, Rows, _) :- !.
fill(Raster, Rows, Cols, R, Id) :-
   nth0(R, Raster, Row),
   (  nth0(C, Row, Slot), var(Slot)
   -> free_width(Row, C, Cols, MaxW),
      random_between(1, MaxW, W),
      MaxH is Rows - R,
      random_between(1, MaxH, H0),
      fitting_height(Raster, R, C, W, H0, H),
      R1 is R + H - 1, C1 is C + W - 1,
      findall(I-J, ( between(R, R1, I), between(C, C1, J) ), Slots),
      bind_slots(Slots, Raster, Id),
      Next is Id + 1,
      fill(Raster, Rows, Cols, R, Next)
   ;  R2 is R + 1,
      fill(Raster, Rows, Cols, R2, Id) ).

% Bind every slot of Slots to Id (forall/2 would undo the bindings).
bind_slots([], _, _).
bind_slots([I-J|Slots], Raster, Id) :-
   nth0(I, Raster, Row),
   nth0(J, Row, Id),
   bind_slots(Slots, Raster, Id).

free_width(Row, C, Cols, W) :-
   (  C + 1 < Cols, C1 is C + 1, nth0(C1, Row, S), var(S)
   -> free_width(Row, C1, Cols, W0), W is W0 + 1
   ;  W = 1 ).

% The tallest height up to H0 whose rectangle is still free.
fitting_height(Raster, R, C, W, H0, H) :-
   (  H0 =:= 1
   -> H = 1
   ;  R1 is R + H0 - 1, C1 is C + W - 1,
      forall(( between(R, R1, I), between(C, C1, J) ),
             ( nth0(I, Raster, RowI), nth0(J, RowI, S), var(S) ))
   -> H = H0
   ;  H1 is H0 - 1,
      fitting_height(Raster, R, C, W, H1, H) ).

:- begin_tests(boundary_explainer).

test(violations_agree_with_omni_validate) :-
   set_random(seed(20261102)),
   forall(between(1, 400, _),
          ( random_between(1, 5, Rows), random_between(1, 5, Cols),
            random_raster(Rows, Cols, Raster),
            forall(( between(0, Rows, H), between(0, Cols, V) ),
                   agrees(Raster, H, V)) )).

agrees(Raster, H, V) :-
   boundary_violations(Raster, H, V, Violations),
   dataset_pipeline:omni_validate(Raster, H, V, Offending),
   (  Violations == []
   -> Offending == none
   ;  Violations = [v(N, _)|_], Offending == some(N) ),
   !.
agrees(Raster, H, V) :-
   format(user_error, "disagreement on ~q at ~d, ~d~n", [Raster, H, V]),
   fail.

test(spanning_cell_in_last_header_row) :-
   explain([[0, 1, 1, 2], [3, 4, 5, 6], [7, 8, 9, 10]],
           [0-"Study", 1-"Selection", 2-"Total", 3-"A", 7-"B"],
           [b{candidate_id:"PMC1/t0/h2_v0", hmd:2, vmd:0}], 1, 1, E),
   E.category == "spanning_cell_in_last_header_row",
   E.violations = [V],
   V.rule == 6, V.count =:= 1,
   V.cells == [json{cell_id:1, text:"Selection", rows:[0, 0], columns:[1, 2],
                    empty:false}],
   sub_string(E.summary, _, _, _,
              "cell 1 \"Selection\" (row 0, columns 1-2) spans several (rule 6)"),
   E.nearest_candidates == [json{candidate_id:"PMC1/t0/h2_v0", hmd:2, vmd:0}].

test(blank_parent_column_lacks_hierarchy_evidence) :-
   % Year is written once per group, with blanks below it.
   explain([[0, 1, 2], [3, 4, 5], [6, 7, 8], [9, 10, 11]],
           [0-"Year", 1-"Treatment", 2-"Yield", 3-"2014", 4-"N0", 5-"1",
            7-"N1", 8-"2", 9-"2015", 10-"N0", 11-"3"],
           [], 1, 2, E),
   E.category == "missing_hierarchy_evidence",
   E.violations = [V],
   V.rule == 3, V.columns == [0],
   V.cells == [json{cell_id:6, text:"", rows:[2, 2], columns:[0, 0], empty:true}],
   sub_string(E.summary, _, _, _, "One of the cells there is empty.").

test(group_row_cuts_the_row_header_line) :-
   explain([[0, 1, 2], [3, 3, 4], [5, 6, 7]],
           [0-"Variable", 1-"Total", 2-"P", 3-"Gender, n (%)", 4-"0.2"],
           [], 1, 1, E),
   E.category == "boundary_cuts_merged_cell",
   E.violations = [V],
   V.rule == 0,
   V.cells = [C], C.cell_id == 3, C.columns == [0, 1],
   sub_string(E.summary, _, _, _, "left of column 1, runs through cell 3").

test(no_headers_in_a_table_with_merged_cells) :-
   explain([[0, 0], [1, 2]], [0-"Title", 1-"a", 2-"b"], [], 0, 0, E),
   E.category == "no_headers_or_no_data",
   E.categories == ["no_headers_or_no_data"],
   % Row 0 is set aside, so what is left is a plain grid: no rule 9.
   E.set_aside_rows == [0].

test(rule_9_names_the_merged_cells) :-
   explain([[0, 1], [2, 2], [3, 4]], [2-"Group"], [], 0, 1, E),
   % Row 1 is set aside; the rest is plain, so (0, 1) is not refused by rule 9.
   E.category \== "header_row_required",
   explain([[0, 1], [2, 3], [2, 4]], [2-"Group"], [], 0, 1, E2),
   E2.category == "header_row_required",
   E2.violations = [V|_], V.rule == 9,
   V.cells = [C], C.cell_id == 2, C.rows == [1, 2].

test(header_ending_on_a_set_aside_row_is_not_offered) :-
   % Row 1, covered by one cell, sits between the header and the data.
   explain([[0, 1], [2, 2], [3, 4]], [0-"A", 1-"B", 2-"Title"],
           [b{candidate_id:"PMC1/t0/layout1", hmd:1, vmd:0}], 2, 0, E),
   E.category == "not_offered",
   E.violations = [V],
   V.rule == null, V.rows == [1],
   E.parser_reading == json{hmd:1, vmd:0},
   sub_string(E.summary, _, _, _, "which is candidate PMC1/t0/layout1").

test(rows_are_those_of_the_whole_table) :-
   % Row 0 is a title, set aside; rows 1 and 2 are the header.
   explain([[0, 0, 0], [1, 2, 3], [4, 5, 6], [7, 8, 9]],
           [0-"Title", 1-"x", 2-"y", 4-"a", 5-"b", 6-"c"], [], 3, 1, E),
   E.violations = [V|_],
   V.rule == 2, V.rows == [1],
   V.cells = [C], C.cell_id == 3, C.empty == true,
   E.parser_reading == json{hmd:2, vmd:1},
   sub_string(E.summary, _, _, _, "sets aside row 0").

test(a_candidate_is_offered) :-
   explain([[0, 1], [2, 3]], [], [b{candidate_id:"PMC1/t0/h1_v1", hmd:1, vmd:1}],
           1, 1, E),
   E.category == "offered", E.violations == [].

test(boundary_outside_the_table) :-
   explain([[0, 1], [2, 3]], [], [], 5, 0, E),
   E.category == "out_of_range", E.parser_reading == null.

:- end_tests(boundary_explainer).
