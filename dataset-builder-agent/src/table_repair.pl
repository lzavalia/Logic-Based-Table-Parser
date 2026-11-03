% Repair of a table so that a boundary the parser refused becomes a candidate.
%
% Consulted in the dataset_pipeline module after boundary_explainer.pl, whose
% witnesses it acts on; dataset_pipeline exports repair_boundary/4.
%
% Two repairs, both merging empty cells into a label (see
% boundary_explainer.pl for the rules):
%   - Missing hierarchy evidence (rules 2 and 3): a parent label written
%     once, with empty cells below it (or beside it) where the source should
%     have had a rowspan (or a colspan). The empty cells are merged into the
%     label, which gives the parser the spanning cell it looks for.
%   - Group rows cut by the row-header line (rule 0): a label that starts in
%     column 0 and already spans past the row-header columns, followed only
%     by empty cells. The empty cells are merged into it, so the label
%     covers the row, which the parser then sets aside as a section row
%     over the rows below it, as it does for a source row of one cell.
% Rows and columns never change, so the boundary means the same on the
% repaired table.
%
% Soundness comes first: a merge is made only when the table leaves no other
% reading of the empty cells, and a table that cannot be repaired that way is
% left alone. The geometry alone never decides it. An empty cell below a
% label may repeat that label (a ditto mark) or mean that the row has no
% value there; an empty header cell right of a label may continue it or be
% the top of the label below it. So the repair assumes two things only:
%   - a label heads the rows below it (the columns right of it), not those
%     above it, and
%   - each row-header column (header row) is one level of the hierarchy.
% and asks for evidence of everything else:
%   - Repeated children. The labels of a column form blocks: each label with
%     the empty cells merged into it. The children of a block are the
%     distinct cells beside it in the next column, in order, compared by
%     text. A merge is made only into a block whose children are exactly
%     those of another labelled block of two or more rows: the same
%     treatments under every year, the same SE and SP rows under every study.
%     A table with a label heading rows that are not its children, or with
%     labels in the middle of their blocks, does not repeat that way.
%   - A label on top. If any run of rows in the column (from the header, or
%     from a row set aside, down to the next row set aside) starts with an
%     empty cell, nothing in the column is merged: its labels may sit in the
%     middle or at the bottom of their blocks, and three or more such blocks
%     can repeat by coincidence.
% Empty cells are only ever merged into a label, never into one another.
%
% Group rows, for each cell that breaks rule 0 (it spans the line right of
% the row-header columns, below the header): the cell must be a label one
% row high that starts in column 0, and every other cell of its row empty
% and one row high; then those cells join it. The evidence is the source's
% own: its author already stretched the label beyond the row-header columns,
% which no row label with data beside it needs, and left nothing else in the
% row. A label followed by any text (a p-value, say) is left alone: making
% the row a section row would drop that text from the data, and shrinking
% the label to the row-header columns would lose the rows it groups.
%
% Merges, for each row-header column J that breaks rule 3, left to right:
% going down column J below the header, an empty cell one column wide may
% join the label one column wide directly above it. A row set aside (covered
% by a single cell) ends the block. No merge is made where column J-1 splits
% the two cells: that would merge what the parent column splits (rule 5).
% Column J-1 is the repaired one, so a parent column is always repaired
% first. The children are those in column J+1.
%
% For each header row I that breaks rule 2, top to bottom, the same is done
% along row I right of the row-header columns: an empty cell may join the
% label to its left with the same rows, except where the header row above
% splits the two cells (rule 4). The children are those in the next header
% row.
%
% After the merges the parser runs again (table_candidates/2). The repair
% holds when the boundary is then a candidate the review can match: a plain
% boundary, or a layout of one subtable read as the model reads it (as in
% table_review:candidate_boundaries/2). Merging can make a column or row
% that broke the rule satisfy it and expose another rule, so the merges are
% repeated, at most max_repair_rounds/1 times, while they still change the
% table.
%
%   repair_boundary(+Record, +Hmd, +Vmd, -Repair)
%       Record is a tables.jsonl record. Repair is a JSON dict:
%         repair_version  "empty-merge-v3"
%         boundary        {hmd, vmd}, as given
%         status          "repaired"; "not_repaired" (merges were made but
%                         the boundary is still refused); "refused" (empty
%                         cells could join labels, but without the evidence
%                         above); "not_applicable" (no empty cell beside a
%                         label); or "already_offered"
%         merges          [{cell_id, into, direction, rows, columns}], in
%                         order: the cell merged, the label it joins, "up" or
%                         "left" (in a header row or a group row), and the
%                         merged cell's rows and columns as [first, last]
%         refused         [{line, index, into, cells, reason, message}]: the
%                         merges not made, by column ("column", index J) or
%                         header row ("row", index I); into is the label, or
%                         null when the whole line is refused; reason is
%                         "children_not_repeated" or "block_without_label_on_top"
%         matched         the candidate on the repaired table, {kind, hmd,
%                         vmd} with kind "boundary" or "layout", or null
%         remaining       when not repaired after merges, explain_boundary/5
%                         on the table as merged; otherwise null
%         summary         one or two sentences
%   repaired_raster(+Raster, +Merges, -Repaired)
%       Raster with every merge applied, from the merges of a Repair.
%   repaired_record(+Record, +Repair, -Repaired)
%       The tables.jsonl record of the table as repaired: the merged raster,
%       the cells without those merged away, and the parser's candidates on
%       the merged raster, built as the build builds them
%       (table_machine_records.pl) for the table uid "<uid>/repaired", so
%       their ids read "<uid>/repaired/h2_v1" and their certificates
%       "certificateN_repaired_h2_v1.pl". Its table_uid is "<uid>/repaired";
%       source_table_uid and source_raster keep the record's own, and repair
%       is Repair.
%   reviewed_record(+Record, +Review, -Effective)
%       The record the review's selected candidate belongs to: Record, or,
%       for a review decided by the repair, repaired_record/3. The repair is
%       recomputed from Record and the review's llm_boundary; unless it is
%       "repaired" with exactly the merges the review records, this throws
%       repair_mismatch, so a stale or edited review never makes a table
%       valid.

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(assoc)).
:- use_module(library(pairs)).
:- use_module(library(ordsets)).

repair_version("empty-merge-v3").
max_repair_rounds(10).

repair_boundary(Record, Hmd, Vmd, Repair) :-
   repair_version(Version),
   repair_rounds(Record, Hmd, Vmd, 0, [], [], Final, Merges, Refused0, Matched),
   list_to_set(Refused0, Refused),
   maplist(merge_json, Merges, MergeJson),
   (  Matched \== none, Merges == []
   -> Status = "already_offered", Remaining = null
   ;  Matched \== none
   -> Status = "repaired", Remaining = null
   ;  Merges \== []
   -> Status = "not_repaired",
      repaired_candidates(Final, Candidates),
      explain_boundary(Final, Candidates, Hmd, Vmd, Remaining)
   ;  Refused \== []
   -> Status = "refused", Remaining = null
   ;  Status = "not_applicable", Remaining = null ),
   matched_json(Matched, MatchedJson),
   repair_summary(Status, Record, Merges, Refused, Hmd, Vmd, Remaining, Summary),
   Repair = json{repair_version:Version, boundary:json{hmd:Hmd, vmd:Vmd},
                 status:Status, merges:MergeJson, refused:Refused,
                 matched:MatchedJson, remaining:Remaining, summary:Summary}.

% repair_rounds(+Record, +H, +V, +Round, +Merges0, +Refused0,
%               -Final, -Merges, -Refused, -Matched)
repair_rounds(Record, H, V, Round, Merges0, Refused0, Final, Merges, Refused, Matched) :-
   (  reviewable_match(Record.raster, H, V, Match)
   -> Final = Record, Merges = Merges0, Refused = Refused0, Matched = Match
   ;  max_repair_rounds(Max), Round >= Max
   -> Final = Record, Merges = Merges0, Refused = Refused0, Matched = none
   ;  round_merges(Record, H, V, Record1, New, NewRefused),
      append(Refused0, NewRefused, Refused1),
      (  New \== []
      -> append(Merges0, New, Merges1),
         Round1 is Round + 1,
         repair_rounds(Record1, H, V, Round1, Merges1, Refused1,
                       Final, Merges, Refused, Matched)
      ;  Final = Record, Merges = Merges0, Refused = Refused1, Matched = none ) ).

% round_merges(+Record, +H, +V, -Record1, -Merges, -Refused): one round of
% merges for the columns breaking rule 3, the rows breaking rule 2 and the
% group rows breaking rule 0, each applied before the next is looked at.
round_merges(Record, H, V, Record1, Merges, Refused) :-
   Raster = Record.raster,
   raster_dimensions(Raster, NumRows, NumCols),
   indices(NumRows, AllRows),
   indices(NumCols, AllCols),
   partition(single_cell_row(Raster, AllCols), AllRows, _, Kept),
   findall(R, ( member(R, Kept), R < H ), HmdRows),
   length(HmdRows, KeptHmd),
   view(Raster, Kept, AllCols, Stripped),
   boundary_violations(Stripped, KeptHmd, V, Violations),
   ( memberchk(v(3, columns(Cols)), Violations) -> true ; Cols = [] ),
   ( memberchk(v(2, rows(KeptRows)), Violations) -> true ; KeptRows = [] ),
   ( memberchk(v(0, cells(Cut)), Violations) -> true ; Cut = [] ),
   maplist(kept_row(Kept), KeptRows, Rows),
   foldl(column_step(Kept, H), Cols, s(Record, [], []), S0),
   foldl(row_step(Kept, H, V, NumCols), Rows, S0, S1),
   foldl(group_row_step(H), Cut, S1, s(Record1, Merges1, Refused)),
   reverse(Merges1, Merges).

column_step(Kept, H, J, s(Record0, Acc0, Ref0), s(Record, Acc, Ref)) :-
   column_merges(Record0, Kept, H, J, Merges, Refused),
   apply_merges(Record0, Merges, Record),
   reverse(Merges, Reversed),
   append(Reversed, Acc0, Acc),
   append(Ref0, Refused, Ref).

row_step(Kept, H, V, NumCols, I, s(Record0, Acc0, Ref0), s(Record, Acc, Ref)) :-
   row_merges(Record0, Kept, H, V, NumCols, I, Merges, Refused),
   apply_merges(Record0, Merges, Record),
   reverse(Merges, Reversed),
   append(Reversed, Acc0, Acc),
   append(Ref0, Refused, Ref).

group_row_step(H, Id, s(Record0, Acc0, Ref), s(Record, Acc, Ref)) :-
   group_row_merges(Record0, H, Id, Merges),
   apply_merges(Record0, Merges, Record),
   reverse(Merges, Reversed),
   append(Reversed, Acc0, Acc).

% --- group rows ----------------------------------------------------------------

% group_row_merges(+Record, +H, +Id, -Merges): the empty cells of the row of
% label Id, which spans the row-header line, as merge(E, Id, left, Rows,
% Cols), when they are all the row holds besides the label; otherwise [].
% Id may have grown earlier in the round.
group_row_merges(Record, H, Id, Merges) :-
   cell_facts(Record, Facts),
   (  get_assoc(Id, Facts, fact(_, false, R-R, 0-_)),
      R >= H,
      nth0(R, Record.raster, Row),
      list_to_set(Row, Ids),
      selectchk(Id, Ids, Others),
      Others \== [],
      forall(member(E, Others), get_assoc(E, Facts, fact(_, true, R-R, _)))
   -> findall(merge(E, Id, "left", R-R, C0-C1),
              ( member(E, Others), get_assoc(E, Facts, fact(_, _, _, C0-C1)) ),
              Merges)
   ;  Merges = [] ).

% --- columns -----------------------------------------------------------------

% column_merges(+Record, +Kept, +H, +J, -Merges, -Refused): the merges of
% column J that have the evidence, as merge(E, A, up, Rows, Cols), and the
% refusals of the others.
column_merges(Record, Kept, H, J, Merges, Refused) :-
   Raster = Record.raster,
   raster_dimensions(Raster, NumRows, _),
   cell_facts(Record, Facts),
   Last is NumRows - 1,
   (  H =< Last -> numlist(H, Last, Rows) ; Rows = [] ),
   column_walk(Rows, Raster, Facts, Kept, J, none, Tentative),
   (  Tentative == []
   -> Merges = [], Refused = []
   ;  \+ column_runs_start_with_labels(Rows, Raster, Facts, Kept, H, J)
   -> Merges = [],
      line_refusal("column", J, Facts, Tentative, Refused)
   ;  repaired_raster(Raster, Tentative, Raster1),
      J1 is J + 1,
      findall(Id-Child, ( member(R, Rows), memberchk(R, Kept),
                          cell(Raster1, R, J, Id), cell(Raster1, R, J1, Child) ),
              Pairs),
      confirmed(Pairs, Facts, Confirmed),
      split_merges("column", J, Facts, Tentative, Confirmed, Merges, Refused) ).

% column_walk(+Rows, +Raster, +Facts, +Kept, +J, +Anchor, -Merges): each
% cell is looked at in its top row. The anchor is anchor(A, Bottom), the
% label one column wide that an empty cell starting at row Bottom + 1 may
% join, or none.
column_walk([], _, _, _, _, _, []).
column_walk([R|Rows], Raster, Facts, Kept, J, Anchor0, Merges) :-
   cell(Raster, R, J, Id),
   get_assoc(Id, Facts, fact(_, Empty, R0-R1, C0-C1)),
   (  \+ memberchk(R, Kept)
   -> Anchor = none, Merges = Rest
   ;  R0 < R
   -> Anchor = Anchor0, Merges = Rest
   ;  C0-C1 \== J-J
   -> Anchor = none, Merges = Rest
   ;  Empty == true
   -> (  Anchor0 = anchor(A, Bottom), Bottom + 1 =:= R,
         parent_column_joins(Raster, J, Bottom, R)
      -> Merges = [merge(Id, A, "up", R0-R1, C0-C1)|Rest],
         Anchor = anchor(A, R1)
      ;  Anchor = none, Merges = Rest )
   ;  Anchor = anchor(Id, R1), Merges = Rest ),
   column_walk(Rows, Raster, Facts, Kept, J, Anchor, Rest).

% The cells of column J-1 in rows Above and Below are one cell, so merging
% across the line between them in column J merges nothing it splits.
parent_column_joins(_, 0, _, _) :- !.
parent_column_joins(Raster, J, Above, Below) :-
   J0 is J - 1,
   cell(Raster, Above, J0, A),
   cell(Raster, Below, J0, B),
   A == B.

% Every run of kept rows in column J, from row H or from a row set aside,
% starts with a label that starts in that row.
column_runs_start_with_labels(Rows, Raster, Facts, Kept, H, J) :-
   forall(( member(R, Rows), memberchk(R, Kept),
            ( R =:= H ; R0 is R - 1, \+ memberchk(R0, Kept) ) ),
          ( cell(Raster, R, J, Id),
            get_assoc(Id, Facts, fact(_, false, Top-_, _)),
            Top =:= R )).

% --- header rows ---------------------------------------------------------------

% row_merges(+Record, +Kept, +H, +V, +NumCols, +I, -Merges, -Refused): the
% same along header row I, from column V rightwards, for cells that lie in
% the header; the children are in the next kept row.
row_merges(Record, Kept, H, V, NumCols, I, Merges, Refused) :-
   Raster = Record.raster,
   cell_facts(Record, Facts),
   Last is NumCols - 1,
   (  V =< Last -> numlist(V, Last, Cols) ; Cols = [] ),
   ( previous_kept(Kept, I, Above) -> true ; Above = none ),
   row_walk(Cols, Raster, Facts, H, I, Above, none, Tentative),
   (  Tentative == []
   -> Merges = [], Refused = []
   ;  \+ row_starts_with_label(Raster, Facts, I, V)
   -> Merges = [],
      line_refusal("row", I, Facts, Tentative, Refused)
   ;  next_kept(Kept, I, Below)
   -> repaired_raster(Raster, Tentative, Raster1),
      findall(Id-Child, ( member(C, Cols),
                          cell(Raster1, I, C, Id), cell(Raster1, Below, C, Child) ),
              Pairs),
      confirmed(Pairs, Facts, Confirmed),
      split_merges("row", I, Facts, Tentative, Confirmed, Merges, Refused)
   ;  Merges = [],
      line_refusal("row", I, Facts, Tentative, Refused) ).

row_walk([], _, _, _, _, _, _, []).
row_walk([C|Cols], Raster, Facts, H, I, Above, Anchor0, Merges) :-
   cell(Raster, I, C, Id),
   get_assoc(Id, Facts, fact(_, Empty, R0-R1, C0-C1)),
   (  C0 < C
   -> Anchor = Anchor0, Merges = Rest
   ;  R1 >= H
   -> Anchor = none, Merges = Rest
   ;  Empty == true
   -> (  Anchor0 = anchor(A, Right, R0-R1), Right + 1 =:= C,
         header_above_joins(Raster, Above, Right, C)
      -> Merges = [merge(Id, A, "left", R0-R1, C0-C1)|Rest],
         Anchor = anchor(A, C1, R0-R1)
      ;  Anchor = none, Merges = Rest )
   ;  Anchor = anchor(Id, C1, R0-R1), Merges = Rest ),
   row_walk(Cols, Raster, Facts, H, I, Above, Anchor, Rest).

header_above_joins(_, none, _, _) :- !.
header_above_joins(Raster, Above, Left, Right) :-
   cell(Raster, Above, Left, A),
   cell(Raster, Above, Right, B),
   A == B.

% Header row I starts, at column V, with a label that starts there.
row_starts_with_label(Raster, Facts, I, V) :-
   cell(Raster, I, V, Id),
   get_assoc(Id, Facts, fact(_, false, _, Left-_)),
   Left =:= V.

previous_kept(Kept, I, Above) :-
   append(Before, [I|_], Kept),
   last(Before, Above).

next_kept(Kept, I, Below) :-
   append(_, [I, Below|_], Kept), !.

% --- evidence ------------------------------------------------------------------

% confirmed(+Pairs, +Facts, -Confirmed): Pairs gives, slot by slot along the
% line, the cell of the line and the cell beside it in the next line. A
% block is a cell of the line; its children are the distinct cells beside
% it, in order, compared by lower-case text. Confirmed are the labelled
% blocks of two or more slots whose children are those of another such
% block.
confirmed(Pairs, Facts, Confirmed) :-
   line_blocks(Pairs, Blocks),
   findall(Id-Sig,
           ( member(block(Id, Size, Children), Blocks),
             Size >= 2, \+ empty_cell(Facts, Id),
             maplist(child_text(Facts), Children, Sig) ),
           Labelled),
   findall(Id, ( select(Id-Sig, Labelled, Others), memberchk(_-Sig, Others) ),
           Confirmed).

% line_blocks(+Pairs, -Blocks): block(Id, Slots, Children) for each run of
% slots of one cell.
line_blocks([], []).
line_blocks([Id-Child|Pairs], [block(Id, Size, Children)|Blocks]) :-
   same_cell_run(Pairs, Id, Rest, Run),
   length([Child|Run], Size),
   distinct_runs([Child|Run], Children),
   line_blocks(Rest, Blocks).

same_cell_run([Id1-Child|Pairs], Id, Rest, [Child|Run]) :-
   Id1 == Id, !,
   same_cell_run(Pairs, Id, Rest, Run).
same_cell_run(Rest, _, Rest, []).

distinct_runs([], []).
distinct_runs([X|Xs], [X|Ys]) :-
   drop_same(Xs, X, Rest),
   distinct_runs(Rest, Ys).

drop_same([Y|Ys], X, Rest) :- Y == X, !, drop_same(Ys, X, Rest).
drop_same(Rest, _, Rest).

child_text(Facts, Id, Text) :-
   get_assoc(Id, Facts, fact(Text0, _, _, _)),
   string_lower(Text0, Text).

% A named predicate, not a lambda: in DeepClause's engine (SWI-Prolog 9.3)
% a compiled lambda such as [M]>>memberchk(M, Confirmed) gets a fresh copy of
% Confirmed, so every merge passed and the evidence was ignored.
into_confirmed(Confirmed, merge(_, A, _, _, _)) :-
   memberchk(A, Confirmed).

% split_merges(+Line, +Index, +Facts, +Tentative, +Confirmed, -Merges,
% -Refused): the merges into confirmed labels, and one refusal for each
% other label.
split_merges(Line, Index, Facts, Tentative, Confirmed, Merges, Refused) :-
   partition(into_confirmed(Confirmed), Tentative, Merges, Others),
   findall(A, member(merge(_, A, _, _, _), Others), As0),
   list_to_set(As0, As),
   findall(json{line:Line, index:Index, into:A, cells:Es,
                reason:"children_not_repeated", message:Message},
           ( member(A, As),
             findall(E, member(merge(E, A, _, _, _), Others), Es),
             label_phrase(Facts, A, Label),
             line_phrase(Line, Index, Where),
             format(string(Message),
                    "In ~s the cells beside ~s do not repeat under another label, so the empty cells below it are left as they are.",
                    [Where, Label]) ),
           Refused).

line_refusal(Line, Index, _Facts, Tentative, [json{line:Line, index:Index, into:null,
                                                   cells:Es, reason:Reason,
                                                   message:Message}]) :-
   Reason = "block_without_label_on_top",
   findall(E, member(merge(E, _, _, _, _), Tentative), Es),
   line_phrase(Line, Index, Where),
   (  Line == "column"
   -> What = "a run of rows that starts with an empty cell, so its labels may not head the rows below them"
   ;  What = "no label in its first cell, or no header row below it" ),
   capitalized(Where, Where1),
   format(string(Message), "~s has ~s; nothing in it is merged.", [Where1, What]).

capitalized(Text, Capitalized) :-
   sub_string(Text, 0, 1, _, First),
   sub_string(Text, 1, _, 0, Rest),
   string_upper(First, Upper),
   string_concat(Upper, Rest, Capitalized).

line_phrase("column", J, Text) :- format(string(Text), "column ~d", [J]).
line_phrase("row", I, Text) :- format(string(Text), "header row ~d", [I]).

% --- applying merges -------------------------------------------------------------

apply_merges(Record, [], Record) :- !.
apply_merges(Record, Merges, Repaired) :-
   repaired_raster(Record.raster, Merges, Raster),
   put_dict(raster, Record, Raster, Repaired).

repaired_raster(Raster, Merges, Repaired) :-
   findall(E-A, member(merge(E, A, _, _, _), Merges), Pairs0),
   findall(E-A, ( member(M, Merges), is_dict(M), E = M.cell_id, A = M.into ), Pairs1),
   append(Pairs0, Pairs1, Pairs),
   list_to_assoc(Pairs, Into),
   maplist(maplist(merged_id(Into)), Raster, Repaired).

% A label can join a cell that grew in an earlier round.
merged_id(Into, Id0, Id) :-
   (  get_assoc(Id0, Into, Id1) -> merged_id(Into, Id1, Id) ; Id = Id0 ).

% --- the repaired record ---------------------------------------------------------

repaired_record(Record, Repair, Repaired) :-
   repaired_raster(Record.raster, Repair.merges, Raster),
   machine_first_slots(Raster, FirstSlots),
   pairs_keys(FirstSlots, Ids),
   list_to_ord_set(Ids, Kept),
   include(kept_cell(Kept), Record.cells, Cells),
   format(string(Uid), "~s/repaired", [Record.table_uid]),
   table_candidates(Raster, Boundaries),
   maplist(machine_candidate(Uid, Record.table_index, Raster, FirstSlots),
           Boundaries, Candidates0),
   maplist(repaired_certificate_name, Candidates0, Candidates),
   put_dict(json{table_uid:Uid, source_table_uid:Record.table_uid,
                 raster:Raster, source_raster:Record.raster, cells:Cells,
                 candidates:Candidates, repair:Repair},
            Record, Repaired).

kept_cell(Kept, Cell) :-
   get_dict(cell_id, Cell, Id),
   ord_memberchk(Id, Kept).

% "certificate3_h2_v1.pl" becomes "certificate3_repaired_h2_v1.pl", so the
% certificate of a repaired table is never taken for one of the table itself.
repaired_certificate_name(Candidate0, Candidate) :-
   Certificate0 = Candidate0.geometric_certificate,
   (  Certificate0.status == "certified"
   -> File0 = Certificate0.file,
      once(sub_string(File0, Before, _, _, "_")),
      sub_string(File0, 0, Before, _, Head),
      sub_string(File0, Before, _, 0, Tail),
      string_concat(Head, "_repaired", Head1),
      string_concat(Head1, Tail, File),
      put_dict(file, Certificate0, File, Certificate),
      put_dict(geometric_certificate, Candidate0, Certificate, Candidate)
   ;  Candidate = Candidate0 ).

reviewed_record(Record, Review, Effective) :-
   (  get_dict(decided_by, Review, "repair")
   -> checked_repair(Record, Review, Repair),
      repaired_record(Record, Repair, Effective)
   ;  Effective = Record ).

checked_repair(Record, Review, Repair) :-
   (  get_dict(llm_boundary, Review, Boundary), is_dict(Boundary),
      get_dict(hmd, Boundary, H), integer(H),
      get_dict(vmd, Boundary, V), integer(V),
      get_dict(repair, Review, Recorded), is_dict(Recorded),
      get_dict(merges, Recorded, RecordedMerges), is_list(RecordedMerges),
      repair_boundary(Record, H, V, Repair),
      Repair.status == "repaired",
      maplist(merge_term, Repair.merges, Terms),
      maplist(merge_term, RecordedMerges, Terms)
   -> true
   ;  throw(error(repair_mismatch(Record.table_uid),
                  context(reviewed_record/3,
                          'The review\'s repair is not the one tables.jsonl gives'))) ).

% A merge as a plain term, so that one read back from JSON compares equal
% whatever the dict tag or text type.
merge_term(Merge, m(E, A, D, Rows, Columns)) :-
   is_dict(Merge),
   get_dict(cell_id, Merge, E), integer(E),
   get_dict(into, Merge, A), integer(A),
   get_dict(direction, Merge, D0), text_to_string(D0, D),
   get_dict(rows, Merge, Rows), get_dict(columns, Merge, Columns).

% reviewable_match(+Raster, +H, +V, -Match): the parser's candidate with
% the counts the review compares, as table_review:reviewable_counts/3 reads
% them.
reviewable_match(Raster, H, V, Match) :-
   table_candidates(Raster, Candidates),
   member(Candidate, Candidates),
   reviewable_reading(Raster, Candidate, Match),
   Match = match(_, H1, V1), H1 =:= H, V1 =:= V, !.

reviewable_reading(_, json{hmd:H, vmd:V}, match(boundary, H, V)) :- !.
reviewable_reading(Raster, layout(_, Layout), match(layout, H, V)) :-
   layout_subtables(Raster, Layout, _, [subtable(Rows, _, Hmd, V)]),
   (  Hmd =:= 0 -> H = 0 ; Last is Hmd - 1, nth0(Last, Rows, Row), H is Row + 1 ).

repaired_candidates(Record, Candidates) :-
   table_candidates(Record.raster, All),
   findall(b{candidate_id:Id, hmd:H, vmd:V},
           ( nth0(K, All, C), reviewable_reading(Record.raster, C, match(Kind, H, V)),
             format(string(Id), "repaired/~w~d", [Kind, K]) ),
           Candidates).

merge_json(merge(E, A, Direction, R0-R1, C0-C1),
           json{cell_id:E, into:A, direction:Direction,
                rows:[R0, R1], columns:[C0, C1]}).

matched_json(none, null).
matched_json(match(Kind, H, V), json{kind:Name, hmd:H, vmd:V}) :-
   atom_string(Kind, Name).

% --- summary -------------------------------------------------------------------

repair_summary("already_offered", _, _, _, H, V, _, Summary) :-
   format(string(Summary), "H = ~d, V = ~d is already a candidate.", [H, V]).
repair_summary("not_applicable", _, _, _, H, V, _, Summary) :-
   format(string(Summary),
          "No empty cell beside a label can give H = ~d, V = ~d the spanning cells it lacks.",
          [H, V]).
repair_summary("refused", _, _, Refused, H, V, _, Summary) :-
   refusals_phrase(Refused, Why),
   format(string(Summary),
          "No merge has the evidence a sound repair of H = ~d, V = ~d needs. ~s",
          [H, V, Why]).
repair_summary("repaired", Record, Merges, Refused, H, V, _, Summary) :-
   merges_phrase(Record, Merges, Text),
   refused_note(Refused, Note),
   format(string(Summary), "Merging ~s makes H = ~d, V = ~d a candidate.~s",
          [Text, H, V, Note]).
repair_summary("not_repaired", Record, Merges, Refused, _, _, Remaining, Summary) :-
   merges_phrase(Record, Merges, Text),
   refused_note(Refused, Note),
   format(string(Summary), "Even after merging ~s: ~s~s",
          [Text, Remaining.summary, Note]).

refusals_phrase(Refused, Text) :-
   findall(M, ( member(R, Refused), M = R.message ), Messages),
   atomics_to_string(Messages, " ", Text).

refused_note([], "") :- !.
refused_note(Refused, Note) :-
   findall(N, ( member(R, Refused), get_dict(cells, R, Cells), length(Cells, N) ), Ns),
   sum_list(Ns, Total),
   (  Total =:= 1
   -> Note = " One other empty cell was left alone for lack of evidence."
   ;  format(string(Note), " ~d other empty cells were left alone for lack of evidence.",
             [Total]) ).

% merges_phrase(+Record, +Merges, -Text): "3 empty cells into the label
% above (e.g. "2013" and "2014")".
merges_phrase(Record, Merges, Text) :-
   cell_facts(Record, Facts),
   length(Merges, N),
   ( N =:= 1 -> Noun = "empty cell" ; Noun = "empty cells" ),
   findall(D, member(merge(_, _, D, _, _), Merges), Ds),
   msort(Ds, Sorted), clumped(Sorted, Counts),
   maplist(direction_phrase, Counts, Parts),
   and_list(Parts, How),
   findall(A, member(merge(_, A, _, _, _), Merges), As0),
   list_to_set(As0, As),
   take_at_most(3, As, Shown),
   maplist(label_phrase(Facts), Shown, Labels0),
   list_to_set(Labels0, Labels),
   and_list(Labels, LabelText),
   format(string(Text), "~d ~s (~s, e.g. into ~s)", [N, Noun, How, LabelText]).

direction_phrase("up"-K, Text) :- format(string(Text), "~d into the label above", [K]).
direction_phrase("left"-K, Text) :- format(string(Text), "~d into the label to the left", [K]).

label_phrase(Facts, Id, Text) :-
   get_assoc(Id, Facts, fact(CellText, _, _, _)),
   max_text_chars(Max),
   shorten_text(CellText, Max, Short),
   format(string(Text), "\"~s\"", [Short]).
