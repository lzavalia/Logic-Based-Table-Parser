% Why a boundary is not among the parser's candidates.
%
% Consulted in the dataset_pipeline module after parse_constraints.pl, whose
% rules it explains; dataset_pipeline exports the two predicates below.
%
% When the review's model gives its own boundary (H column-header rows, V
% row-header columns) and no candidate has those counts, the table is
% unparseable (table_review.pl). This file says why, from the geometry
% alone: no LLM, and nothing is changed.
%
% The parser sets aside the rows covered by a single cell before it checks a
% boundary (table_layouts/2 of parse_constraints.pl), so the explainer does
% the same. H counts rows from the top of the whole table, as the review
% prompt defines it; of those, the rows that are kept give the number of HMD
% rows the parser checks. Every rule that boundary breaks is then reported
% with its witnesses: the cells, rows or columns that break it. Rows and
% columns are always those of the whole table, numbered from 0.
%
% Each broken rule falls in one category:
%
%   rules  category                            the boundary ...
%   7, 8   no_headers_or_no_data               has no headers, or leaves no data
%   9      header_row_required                 has no header row, in a table with
%                                              merged cells
%   0, 1   boundary_cuts_merged_cell           runs through a merged cell
%   2, 3   missing_hierarchy_evidence          has an upper header row (left
%                                              row-header column) with no spanning
%                                              cell that the next one splits
%   4, 5   inverted_hierarchy                  has a header row (row-header column)
%                                              merging what the one before splits
%   6      spanning_cell_in_last_header_row    has a cell spanning columns in its
%                                              last header row
%
% A boundary that breaks no rule and is still not a candidate is
% not_offered: it ends on a row the parser sets aside, or every row below its
% header is set aside. The category of the explanation is that of the first
% broken rule, in the order omni_validate/4 checks them (7, 8, 9, 0 ... 6).
%
%   explain_boundary(+Record, +Candidates, +Hmd, +Vmd, -Explanation)
%       Record is a tables.jsonl record (raster and cells); Candidates are the
%       boundaries the review can match, b{candidate_id, hmd, vmd}
%       (table_review:candidate_boundaries/2). Explanation is a JSON dict:
%         explainer_version   "boundary-explainer-v1"
%         boundary            {hmd, vmd}, as given
%         category            see above, or "offered" when the boundary is a
%                             candidate, "out_of_range" when it does not fit
%                             the table
%         categories          the categories of every broken rule, in order
%         summary             the explanation in sentences
%         violations          [{rule, category, message, cells, rows,
%                             columns, count}]; rule is null for not_offered;
%                             cells (at most 5, count gives them all) are
%                             {cell_id, text, rows, columns, empty}, with
%                             rows and columns as [first, last]
%         set_aside_rows      the rows covered by a single cell
%         parser_reading      {hmd, vmd}: the boundary the parser checks, its
%                             hmd counted in the rows it keeps
%         nearest_candidates  up to 3 candidates, closest counts first
%   boundary_violations(+Raster, +Hmd, +Vmd, -Violations)
%       Violations is v(Rule, Witness) for every rule the boundary breaks, in
%       the order above; [] exactly when omni_validate(Raster, Hmd, Vmd).
%       The boundary must be in the domain (valid_boundary_domain/3).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(assoc)).
:- use_module(library(pairs)).

explainer_version("boundary-explainer-v1").

% Witness cells listed in a message, and in a violation's cells.
max_message_cells(3).
max_listed_cells(5).
max_text_chars(30).

% --- witnesses ---------------------------------------------------------------

boundary_violations(Raster, Hmd, Vmd, Violations) :-
   findall(v(N, Witness),
           ( constraint(N, _), rule_witness(N, Raster, Hmd, Vmd, Witness) ),
           Violations).

% rule_witness(+Rule, +Raster, +Hmd, +Vmd, -Witness) succeeds exactly when
% the rule of that number in parse_constraints.pl fails, and gives what
% breaks it. The loops are those of the rules, with the same bounds.
rule_witness(7, _, 0, 0, none).
rule_witness(8, Raster, Hmd, Vmd, no_data(AllRows, AllCols)) :-
   raster_dimensions(Raster, NumRows, NumCols),
   ( Hmd >= NumRows -> AllRows = true ; AllRows = false ),
   ( Vmd >= NumCols -> AllCols = true ; AllCols = false ),
   ( AllRows == true ; AllCols == true ), !.
rule_witness(9, Raster, 0, _, cells(Ids)) :-
   \+ plain_grid(Raster),
   append(Raster, Slots),
   msort(Slots, Sorted),
   clumped_ids(Sorted, Clumps),
   findall(Id, ( member(Id-N, Clumps), N > 1 ), Ids).
rule_witness(0, Raster, Hmd, Vmd, cells(Ids)) :-
   Vmd > 0,
   raster_dimensions(Raster, NumRows, _),
   V0 is Vmd - 1,
   findall(A, ( until(Hmd, NumRows, I),
                cell(Raster, I, V0, A), cell(Raster, I, Vmd, B), A == B ),
           Ids0),
   nonempty_set(Ids0, Ids).
rule_witness(1, Raster, Hmd, _, cells(Ids)) :-
   Hmd > 0,
   raster_dimensions(Raster, _, NumCols),
   H0 is Hmd - 1,
   findall(A, ( until(0, NumCols, J),
                cell(Raster, H0, J, A), cell(Raster, Hmd, J, B), A == B ),
           Ids0),
   nonempty_set(Ids0, Ids).
rule_witness(2, Raster, Hmd, Vmd, rows(Rows)) :-
   raster_dimensions(Raster, _, NumCols),
   findall(I, ( until(0, Hmd - 1, I),
                \+ horizontal_split_at(Raster, I, Vmd, NumCols) ),
           Rows),
   Rows \== [].
rule_witness(3, Raster, Hmd, Vmd, columns(Cols)) :-
   raster_dimensions(Raster, NumRows, _),
   findall(J, ( until(0, Vmd - 1, J),
                \+ vertical_split_at(Raster, J, Hmd, NumRows) ),
           Cols),
   Cols \== [].
rule_witness(4, Raster, Hmd, Vmd, cells(Ids)) :-
   raster_dimensions(Raster, _, NumCols),
   findall(C, ( until(0, Hmd - 1, I), until(Vmd, NumCols - 1, J),
                I1 is I + 1, J1 is J + 1,
                cell(Raster, I, J, A),  cell(Raster, I, J1, B),  A \== B,
                cell(Raster, I1, J, C), cell(Raster, I1, J1, D), C == D ),
           Ids0),
   nonempty_set(Ids0, Ids).
rule_witness(5, Raster, Hmd, Vmd, cells(Ids)) :-
   raster_dimensions(Raster, NumRows, _),
   findall(C, ( until(0, Vmd - 1, J), until(max(0, Hmd - 1), NumRows - 1, I),
                I1 is I + 1, J1 is J + 1,
                cell(Raster, I, J, A),  cell(Raster, I1, J, B),  A \== B,
                cell(Raster, I, J1, C), cell(Raster, I1, J1, D), C == D ),
           Ids0),
   nonempty_set(Ids0, Ids).
rule_witness(6, Raster, Hmd, Vmd, cells(Ids)) :-
   Hmd > 0,
   raster_dimensions(Raster, _, NumCols),
   H0 is Hmd - 1,
   findall(A, ( until(max(0, Vmd - 1), NumCols - 1, J), J1 is J + 1,
                cell(Raster, H0, J, A), cell(Raster, H0, J1, B), A == B ),
           Ids0),
   nonempty_set(Ids0, Ids).

% The witness of rule 2 for row I: a cell right of the VMD that spans two
% columns and is split in the row below.
horizontal_split_at(Raster, I, Vmd, NumCols) :-
   I1 is I + 1,
   until(Vmd, NumCols - 1, J),
   J1 is J + 1,
   cell(Raster, I, J, A),  cell(Raster, I, J1, B),  A == B,
   cell(Raster, I1, J, C), cell(Raster, I1, J1, D), C \== D, !.

% The witness of rule 3 for column J: a cell below the HMD that spans two
% rows and is split in the column to its right.
vertical_split_at(Raster, J, Hmd, NumRows) :-
   J1 is J + 1,
   until(Hmd, NumRows - 1, I),
   I1 is I + 1,
   cell(Raster, I, J, A),  cell(Raster, I1, J, B),  A == B,
   cell(Raster, I, J1, C), cell(Raster, I1, J1, D), C \== D, !.

nonempty_set(List, Set) :-
   List \== [],
   sort(List, Set).

clumped_ids([], []).
clumped_ids([Id|Ids], [Id-N|Clumps]) :-
   same_id_run(Ids, Id, 1, N, Rest),
   clumped_ids(Rest, Clumps).

same_id_run([Next|Ids], Id, N0, N, Rest) :-
   Next == Id, !,
   N1 is N0 + 1,
   same_id_run(Ids, Id, N1, N, Rest).
same_id_run(Rest, _, N, N, Rest).

% --- explanation -------------------------------------------------------------

explain_boundary(Record, Candidates, Hmd, Vmd, Explanation) :-
   Raster = Record.raster,
   raster_dimensions(Raster, NumRows, NumCols),
   explainer_version(Version),
   nearest_candidates(Candidates, Hmd, Vmd, Nearest),
   Base = json{explainer_version:Version, boundary:json{hmd:Hmd, vmd:Vmd},
               nearest_candidates:Nearest},
   (  \+ ( integer(Hmd), integer(Vmd),
           between(0, NumRows, Hmd), between(0, NumCols, Vmd) )
   -> format(string(Summary),
             "H = ~w, V = ~w does not fit a table of ~d rows and ~d columns.",
             [Hmd, Vmd, NumRows, NumCols]),
      put_dict(json{category:"out_of_range", categories:["out_of_range"],
                    summary:Summary, violations:[], set_aside_rows:[],
                    parser_reading:null},
               Base, Explanation)
   ;  explain_in_range(Record, Candidates, Hmd, Vmd, Base, Explanation) ).

explain_in_range(Record, Candidates, Hmd, Vmd, Base, Explanation) :-
   Raster = Record.raster,
   raster_dimensions(Raster, NumRows, NumCols),
   indices(NumRows, AllRows),
   indices(NumCols, AllCols),
   partition(single_cell_row(Raster, AllCols), AllRows, SetAside, Kept),
   findall(R, ( member(R, Kept), R < Hmd ), HmdRows),
   length(HmdRows, KeptHmd),
   view(Raster, Kept, AllCols, Stripped),
   cell_facts(Record, Facts),
   Ctx = ctx(Kept, HmdRows, KeptHmd, Vmd, Facts, Stripped),
   (  member(C, Candidates), C.hmd =:= Hmd, C.vmd =:= Vmd
   -> Category = "offered", Violations = [],
      format(string(Summary), "H = ~d, V = ~d is candidate ~w.",
             [Hmd, Vmd, C.candidate_id])
   ;  boundary_violations(Stripped, KeptHmd, Vmd, Found),
      maplist(violation_json(Ctx), Found, RuleViolations),
      not_offered(Raster, Ctx, Hmd, Found, Candidates, Unmatched),
      append(RuleViolations, Unmatched, Violations),
      Violations = [First|_],
      Category = First.category,
      maplist(get_dict(message), Violations, Messages),
      set_aside_note(SetAside, Hmd, KeptHmd, Note),
      atomics_to_string(Messages, " ", Body),
      format(string(Summary),
             "H = ~d, V = ~d is not a parser candidate. ~s~s",
             [Hmd, Vmd, Note, Body]) ),
   findall(Cat, ( member(V, Violations), Cat = V.category ), Cats0),
   ( Cats0 == [] -> Cats = [Category] ; list_to_set(Cats0, Cats) ),
   put_dict(json{category:Category, categories:Cats, summary:Summary,
                 violations:Violations, set_aside_rows:SetAside,
                 parser_reading:json{hmd:KeptHmd, vmd:Vmd}},
            Base, Explanation).

% not_offered(+Raster, +Ctx, +Hmd, +Violations, +Candidates, -Unmatched):
% why a boundary that breaks no rule is still not a candidate.
not_offered(_, _, _, [_|_], _, []) :- !.
not_offered(Raster, ctx(Kept, HmdRows, KeptHmd, Vmd, _, _), Hmd, [], Candidates,
            [json{rule:null, category:"not_offered", message:Message,
                  cells:[], rows:Rows, columns:[], count:0}]) :-
   ( HmdRows == [] -> ParserHmd = 0 ; last(HmdRows, Last), ParserHmd is Last + 1 ),
   (  ParserHmd =\= Hmd
   -> numlist(ParserHmd, Hmd, Rows0), exclude(==(Hmd), Rows0, Rows),
      rows_phrase(Rows, RowsText),
      (  member(C, Candidates), C.hmd =:= ParserHmd, C.vmd =:= Vmd
      -> format(string(Offered), ", which is candidate ~w", [C.candidate_id])
      ;  Offered = "" ),
      format(string(Message),
             "The header ends on ~s, which the parser sets aside because a single cell covers it; it reads the boundary as H = ~d, V = ~d~s.",
             [RowsText, ParserHmd, Vmd, Offered])
   ;  length(Prefix, KeptHmd), append(Prefix, DataRows, Kept),
      raster_dimensions(Raster, _, NumCols),
      numlist(Vmd, NumCols, Cols0), exclude(==(NumCols), Cols0, DataCols),
      include(region_separator_row(Raster, DataCols), DataRows, Rows),
      (  Rows == DataRows
      -> Message = "Every row below the header is covered by a single cell across the data columns, so the parser sets them all aside and no data is left."
      ;  Message = "The boundary breaks no rule, but the parser does not offer it." ) ).

set_aside_note(SetAside, Hmd, KeptHmd, Note) :-
   include(>(Hmd), SetAside, Inside),
   (  Inside == []
   -> Note = ""
   ;  rows_phrase(Inside, RowsText),
      format(string(Note),
             "The parser sets aside ~s (covered by a single cell), so it checks ~d header row(s). ",
             [RowsText, KeptHmd]) ).

% violation_json(+Ctx, +Violation, -Json)
violation_json(Ctx, v(N, Witness), json{rule:N, category:Category, message:Message,
                                        cells:Cells, rows:Rows, columns:Cols,
                                        count:Count}) :-
   rule_category(N, Category),
   witness_parts(N, Witness, Ctx, Ids, Rows, Cols),
   Ctx = ctx(_, _, _, _, Facts, _),
   length(Ids, Count),
   max_listed_cells(MaxListed),
   take_at_most(MaxListed, Ids, Listed),
   maplist(cell_json(Facts), Listed, Cells),
   rule_message(N, Witness, Ctx, Ids, Rows, Cols, Message).

rule_category(7, "no_headers_or_no_data").
rule_category(8, "no_headers_or_no_data").
rule_category(9, "header_row_required").
rule_category(0, "boundary_cuts_merged_cell").
rule_category(1, "boundary_cuts_merged_cell").
rule_category(2, "missing_hierarchy_evidence").
rule_category(3, "missing_hierarchy_evidence").
rule_category(4, "inverted_hierarchy").
rule_category(5, "inverted_hierarchy").
rule_category(6, "spanning_cell_in_last_header_row").

% witness_parts(+Rule, +Witness, +Ctx, -CellIds, -Rows, -Cols): rows of the
% kept raster become rows of the table. For rules 2 and 3 the cells are the
% empty ones in the rows (columns) that lack evidence, inside the HMD (VMD).
witness_parts(_, none, _, [], [], []).
witness_parts(_, no_data(_, _), _, [], [], []).
witness_parts(_, cells(Ids), _, Ids, [], []).
witness_parts(2, rows(KeptRows), Ctx, Ids, Rows, []) :-
   Ctx = ctx(Kept, _, _, Vmd, Facts, Stripped),
   maplist(kept_row(Kept), KeptRows, Rows),
   findall(Id, ( member(I, KeptRows), nth0(I, Stripped, Row),
                 nth0(J, Row, Id), J >= Vmd, empty_cell(Facts, Id) ),
           Ids0),
   list_to_set(Ids0, Ids).
witness_parts(3, columns(Cols), Ctx, Ids, [], Cols) :-
   Ctx = ctx(_, _, KeptHmd, _, Facts, Stripped),
   findall(Id, ( member(J, Cols), nth0(I, Stripped, Row), I >= KeptHmd,
                 nth0(J, Row, Id), empty_cell(Facts, Id) ),
           Ids0),
   list_to_set(Ids0, Ids).

kept_row(Kept, I, Row) :- nth0(I, Kept, Row).

last_header_row(ctx(_, HmdRows, _, _, _, _), Row) :- last(HmdRows, Row).

rule_message(7, _, _, _, _, _,
   "With no header rows and no row-header columns the table would be all data, which the parser never proposes (rule 7).").
rule_message(8, no_data(AllRows, AllCols), _, _, _, _, Message) :-
   (  AllRows == true, AllCols == true
   -> What = "every row the parser keeps would be a header row and every column a row-header column"
   ;  AllRows == true
   -> What = "every row the parser keeps would be a header row"
   ;  What = "every column would be a row-header column" ),
   format(string(Message), "This leaves no data: ~s (rule 8).", [What]).
rule_message(9, _, ctx(_, _, _, _, Facts, _), Ids, _, _, Message) :-
   cells_phrase(Facts, Ids, Cells),
   format(string(Message),
          "With no header row the table may have no merged cell, but it has ~s; the parser reads a merged cell as a sign of a header row (rule 9).",
          [Cells]).
rule_message(0, _, ctx(_, _, _, Vmd, Facts, _), Ids, _, _, Message) :-
   cells_phrase(Facts, Ids, Cells),
   format(string(Message),
          "The line between the row-header columns and the data, left of column ~d, runs through ~s (rule 0).",
          [Vmd, Cells]).
rule_message(1, _, Ctx, Ids, _, _, Message) :-
   Ctx = ctx(_, _, _, _, Facts, _),
   last_header_row(Ctx, Last),
   cells_phrase(Facts, Ids, Cells),
   format(string(Message),
          "The line below the last header row, row ~d, runs through ~s (rule 1).",
          [Last, Cells]).
rule_message(2, _, ctx(_, _, _, _, Facts, _), Ids, Rows, _, Message) :-
   rows_phrase(Rows, RowsText),
   (  Rows = [_] -> Pronoun = "it heads the header row" ; Pronoun = "they head the header rows" ),
   empty_note(Facts, Ids, Note),
   format(string(Message),
          "In header ~s no cell right of the row headers spans columns that the next header row splits, so nothing shows that ~s below (rule 2).~s",
          [RowsText, Pronoun, Note]).
rule_message(3, _, ctx(_, _, _, _, Facts, _), Ids, _, Cols, Message) :-
   columns_phrase(Cols, ColsText),
   (  Cols = [_] -> Pronoun = "it groups the column" ; Pronoun = "they group the columns" ),
   empty_note(Facts, Ids, Note),
   format(string(Message),
          "In row-header ~s no cell below the header spans rows that the next column splits, so nothing shows that ~s to the right (rule 3).~s",
          [ColsText, Pronoun, Note]).
rule_message(4, _, ctx(_, _, _, _, Facts, _), Ids, _, _, Message) :-
   cells_phrase(Facts, Ids, Cells),
   span_verb(Ids, Verb),
   format(string(Message),
          "In the header, ~s ~s cells that the row above keeps apart (rule 4).",
          [Cells, Verb]).
rule_message(5, _, ctx(_, _, _, _, Facts, _), Ids, _, _, Message) :-
   cells_phrase(Facts, Ids, Cells),
   span_verb(Ids, Verb),
   format(string(Message),
          "In the row headers, ~s ~s cells that the column to its left keeps apart (rule 5).",
          [Cells, Verb]).
rule_message(6, _, Ctx, Ids, _, _, Message) :-
   Ctx = ctx(_, _, _, _, Facts, _),
   last_header_row(Ctx, Last),
   cells_phrase(Facts, Ids, Cells),
   span_verb(Ids, Verb),
   format(string(Message),
          "Row ~d is the last header row, so each of its cells must label a single column, but ~s ~s several (rule 6).",
          [Last, Cells, Verb]).

span_verb([_], "spans") :- !.
span_verb(_, "span").

empty_note(_, [], "") :- !.
empty_note(_, Ids, Note) :-
   length(Ids, N),
   (  N =:= 1
   -> Note = " One of the cells there is empty."
   ;  format(string(Note), " ~d of the cells there are empty.", [N]) ).

% --- cells -------------------------------------------------------------------

% cell_facts(+Record, -Facts): cell id -> fact(Text, Empty, Rows, Cols), with
% the cell's rows and columns as First-Last in the whole raster. A cell is
% empty, as in table_type_abstraction.pl, when it is a synthetic gap or its
% text is only white space.
cell_facts(Record, Facts) :-
   Raster = Record.raster,
   findall(Id-(R-C), ( nth0(R, Raster, Row), nth0(C, Row, Id) ), Slots),
   keysort(Slots, Sorted),
   group_pairs_by_key(Sorted, Grouped),
   findall(Id-fact(Text, Empty, R0-R1, C0-C1),
           ( member(Id-Positions, Grouped),
             pairs_keys_values(Positions, Rs, Cs),
             min_list(Rs, R0), max_list(Rs, R1),
             min_list(Cs, C0), max_list(Cs, C1),
             record_cell(Record, Id, Text, Empty) ),
           Pairs),
   list_to_assoc(Pairs, Facts).

record_cell(Record, Id, Text, Empty) :-
   (  member(Cell, Record.cells), Cell.cell_id == Id
   -> ( get_dict(text, Cell, T0), ( string(T0) ; atom(T0) ) -> true ; T0 = "" ),
      normalize_space(string(Text), T0),
      (  ( Text == "" ; get_dict(kind, Cell, "synthetic_gap") )
      -> Empty = true
      ;  Empty = false )
   ;  Text = "", Empty = true ).

empty_cell(Facts, Id) :-
   get_assoc(Id, Facts, fact(_, true, _, _)).

cell_json(Facts, Id, json{cell_id:Id, text:Short, rows:[R0, R1],
                          columns:[C0, C1], empty:Empty}) :-
   get_assoc(Id, Facts, fact(Text, Empty, R0-R1, C0-C1)),
   max_text_chars(Max),
   shorten_text(Text, Max, Short).

% cells_phrase(+Facts, +Ids, -Text): 'cell 12 "Gender (%)" (row 2, columns
% 0-2)', at most max_message_cells/1 of them, then "and N more".
cells_phrase(Facts, Ids, Text) :-
   max_message_cells(Max),
   take_at_most(Max, Ids, Shown),
   maplist(cell_phrase(Facts), Shown, Parts),
   length(Ids, N), More is N - Max,
   (  More > 0
   -> format(string(Tail), "~d more", [More]),
      append(Parts, [Tail], All)
   ;  All = Parts ),
   and_list(All, Text).

cell_phrase(Facts, Id, Text) :-
   get_assoc(Id, Facts, fact(CellText, Empty, Rows, Cols)),
   span_phrase("row", "rows", Rows, RowText),
   span_phrase("column", "columns", Cols, ColText),
   (  Empty == true
   -> format(string(Text), "empty cell ~w (~s, ~s)", [Id, RowText, ColText])
   ;  max_text_chars(Max),
      shorten_text(CellText, Max, Short),
      format(string(Text), "cell ~w \"~s\" (~s, ~s)", [Id, Short, RowText, ColText]) ).

span_phrase(One, _, A-A, Text) :- !, format(string(Text), "~s ~d", [One, A]).
span_phrase(_, Many, A-B, Text) :- format(string(Text), "~s ~d-~d", [Many, A, B]).

rows_phrase(Rows, Text) :- indices_phrase("row", "rows", Rows, Text).
columns_phrase(Cols, Text) :- indices_phrase("column", "columns", Cols, Text).

indices_phrase(One, _, [I], Text) :- !, format(string(Text), "~s ~d", [One, I]).
indices_phrase(_, Many, Is, Text) :-
   maplist([I, S]>>format(string(S), "~d", [I]), Is, Parts),
   and_list(Parts, List),
   format(string(Text), "~s ~s", [Many, List]).

and_list([One], One) :- !.
and_list(Parts, Text) :-
   append(Front, [Last], Parts), !,
   atomics_to_string(Front, ", ", Head),
   format(string(Text), "~s and ~s", [Head, Last]).

shorten_text(Text, Max, Short) :-
   string_length(Text, Length),
   (  Length =< Max
   -> Short = Text
   ;  sub_string(Text, 0, Max, _, Head),
      string_concat(Head, "...", Short) ).

take_at_most(N, List, Front) :-
   length(List, Length),
   (  Length =< N -> Front = List ; length(Front, N), append(Front, _, List) ).

% nearest_candidates(+Candidates, +Hmd, +Vmd, -Nearest): the three closest
% by |dH| + |dV|, then in candidate order.
nearest_candidates(Candidates, Hmd, Vmd, Nearest) :-
   (  integer(Hmd), integer(Vmd)
   -> findall(D-json{candidate_id:Id, hmd:H, vmd:V},
              ( member(C, Candidates),
                get_dict(candidate_id, C, Id), get_dict(hmd, C, H),
                get_dict(vmd, C, V),
                D is abs(H - Hmd) + abs(V - Vmd) ),
              Keyed),
      keysort(Keyed, Sorted),
      pairs_values(Sorted, All),
      take_at_most(3, All, Nearest)
   ;  Nearest = [] ).
