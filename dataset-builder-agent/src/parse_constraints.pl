% Prolog port of ConstraintValidators.scala, with HMD and VMD as counts.
%
% Raster is the flattened raster: a list of rows, each row a list of cell ids.
% Cells belonging to the same (merged) cell share the same id.
% The class-scoped values num_rows / num_cols become the plain variables
% NumRows / NumCols, computed by raster_dimensions/3.
%
% A boundary (Hmd, Vmd) gives the NUMBER of horizontal-metadata rows and the
% number of vertical-metadata columns:
%   rows 0 .. Hmd-1                        horizontal metadata (HMD)
%   rows Hmd .., columns 0 .. Vmd-1        vertical metadata (VMD)
%   rows Hmd .., columns Vmd ..            data
% Hmd = 0 means the table has no HMD rows, Vmd = 0 that it has no VMD columns.
% Constraints 7 and 8 forbid a table that is entirely data (0, 0) or whose
% data region is empty (Hmd = NumRows or Vmd = NumCols). Constraint 9 biases
% towards HMD: Hmd = 0 is considered only for a plain grid, a table without
% any merged cell, which therefore admits (0, 1), (1, 0) and (1, 1).
%
% Constraints 0 to 6 are those of ConstraintValidators.scala, which used the
% index of the last HMD row and of the last VMD column. For Hmd >= 1 and
% Vmd >= 1 each one tests exactly the cells the original tested at
% (Hmd-1, Vmd-1). A rule that compares a region with one that is empty has
% nothing to compare and holds. This is a structural contract, not evidence
% that those cells are semantically headers.
%
% valid_boundaries/2 finds metadata on the margins of the table only.
% table_layouts/2 builds on it to also find metadata in the middle of the
% table (see "central metadata" below).

:- use_module(library(assoc)).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(pairs)).

% --- helpers ---------------------------------------------------------------

raster_dimensions(Raster, NumRows, NumCols) :-
   length(Raster, NumRows),
   (  Raster = [FirstRow|_]
   -> length(FirstRow, NumCols)
   ;  NumCols = 0
   ).

% cell(+Raster, +I, +J, -Value): Value = flattened_raster(I)(J)
cell(Raster, I, J, Value) :-
   nth0(I, Raster, Row),
   nth0(J, Row, Value).

% until(+Low, +High, -X): X ranges over Scala's (Low until High)
until(Low, High, X) :-
   First is Low, Last is High - 1,
   between(First, Last, X).

% A raster must be rectangular with at least one cell. Checking every row
% prevents constraints from silently succeeding on a ragged raster.
% One-row and one-column tables are allowed; constraints 7 and 8 decide
% which of their boundaries make sense.
valid_raster_shape(Raster, NumRows, NumCols) :-
   is_list(Raster),
   Raster = [FirstRow|_],
   is_list(FirstRow),
   length(Raster, NumRows),
   length(FirstRow, NumCols),
   NumRows >= 1,
   NumCols >= 1,
   forall(member(Row, Raster), (is_list(Row), length(Row, NumCols))).

% Counts can range over the whole table; constraints 7 and 8 then reject the
% two degenerate ends.
valid_boundary_domain(Raster, Hmd, Vmd) :-
   integer(Hmd),
   integer(Vmd),
   valid_raster_shape(Raster, NumRows, NumCols),
   Hmd >= 0, Hmd =< NumRows,
   Vmd >= 0, Vmd =< NumCols.

% --- constraint 0 ----------------------------------------------------------

% No merged cell crosses the line between the last VMD column and the first
% data column, in the rows below the HMD.
vertical_no_merged_cell_bisections(Raster, Hmd, Vmd) :-
   raster_dimensions(Raster, NumRows, _),
   V0 is Vmd - 1,
   \+ ( Vmd > 0,
        until(Hmd, NumRows, I),
        cell(Raster, I, V0, A),
        cell(Raster, I, Vmd, B),
        A == B ).

% --- constraint 1 ----------------------------------------------------------

% No merged cell crosses the line between the last HMD row and the first row
% below it, from the last VMD column rightwards.
horizontal_no_merged_cell_bisections(Raster, Hmd, Vmd) :-
   raster_dimensions(Raster, _, NumCols),
   H0 is Hmd - 1,
   \+ ( Hmd > 0,
        until(max(0, Vmd - 1), NumCols, J),  % asymmetry is intentional
        cell(Raster, H0, J, A),
        cell(Raster, Hmd, J, B),
        A == B ).

% --- constraint 2 ----------------------------------------------------------

% Every HMD row except the last has, right of the VMD, a merged cell that is
% split in the row below it.
horizontal_split_existence(Raster, Hmd, Vmd) :-
   raster_dimensions(Raster, _, NumCols),
   forall(
      until(0, Hmd - 1, I),
      (  I1 is I + 1,
         once(( until(Vmd, NumCols - 1, J),
                J1 is J + 1,
                cell(Raster, I, J, A),  cell(Raster, I, J1, B),  A == B,
                cell(Raster, I1, J, C), cell(Raster, I1, J1, D), C \== D ))
      )
   ).

% --- constraint 3 ----------------------------------------------------------

% Every VMD column except the last has, below the HMD, a merged cell that is
% split in the column to its right.
vertical_split_existence(Raster, Hmd, Vmd) :-
   raster_dimensions(Raster, NumRows, _),
   forall(
      until(0, Vmd - 1, J),
      (  J1 is J + 1,
         once(( until(Hmd, NumRows - 1, I),
                I1 is I + 1,
                cell(Raster, I, J, A),  cell(Raster, I1, J, B),  A == B,
                cell(Raster, I, J1, C), cell(Raster, I1, J1, D), C \== D ))
      )
   ).

% --- constraint 4 ----------------------------------------------------------

% In the HMD, right of the VMD, a row never merges what the row above splits.
horizontal_no_inverted_hierarchies(Raster, Hmd, Vmd) :-
   raster_dimensions(Raster, _, NumCols),
   \+ ( until(0, Hmd - 1, I),
        until(Vmd, NumCols - 1, J),
        I1 is I + 1, J1 is J + 1,
        cell(Raster, I, J, A),  cell(Raster, I, J1, B),  A \== B,
        cell(Raster, I1, J, C), cell(Raster, I1, J1, D), C == D ).

% --- constraint 5 ----------------------------------------------------------

% In the VMD, from the last HMD row down, a column never merges what the
% column to its left splits.
vertical_no_inverted_hierarchies(Raster, Hmd, Vmd) :-
   raster_dimensions(Raster, NumRows, _),
   \+ ( until(0, Vmd - 1, J),
        until(max(0, Hmd - 1), NumRows - 1, I),
        I1 is I + 1, J1 is J + 1,
        cell(Raster, I, J, A),  cell(Raster, I1, J, B),  A \== B,
        cell(Raster, I, J1, C), cell(Raster, I1, J1, D), C == D ).

% --- constraint 6 ----------------------------------------------------------

% The last HMD row is a row of keys: from the last VMD column rightwards, it
% has no horizontally merged cells.
horizontal_key_value_property(Raster, Hmd, Vmd) :-
   raster_dimensions(Raster, _, NumCols),
   H0 is Hmd - 1,
   \+ ( Hmd > 0,
        until(max(0, Vmd - 1), NumCols - 1, J),
        J1 is J + 1,
        cell(Raster, H0, J, A),
        cell(Raster, H0, J1, B),
        A == B ).

% --- constraint 7 ----------------------------------------------------------

% A table is never entirely data: it has HMD rows, VMD columns, or both.
not_entirely_data(_Raster, Hmd, Vmd) :-
   ( Hmd > 0 ; Vmd > 0 ), !.

% --- constraint 8 ----------------------------------------------------------

% A table is never entirely metadata: some cell is below the HMD and right
% of the VMD.
not_entirely_metadata(Raster, Hmd, Vmd) :-
   raster_dimensions(Raster, NumRows, NumCols),
   Hmd < NumRows,
   Vmd < NumCols.

% --- constraint 9 ----------------------------------------------------------

% A table without HMD rows must be a plain grid: no two raster slots belong to
% the same cell. Any merged cell is taken as evidence of a header hierarchy,
% so such tables are read with at least one HMD row. Vmd = 0 is not limited.
no_hmd_only_for_plain_grids(Raster, Hmd, _Vmd) :-
   (  Hmd > 0
   -> true
   ;  plain_grid(Raster)
   ).

% plain_grid(+Raster): every slot holds a different cell id. Padding slots for
% short rows get their own ids, so a ragged table without spans is plain.
plain_grid(Raster) :-
   append(Raster, Slots),
   length(Slots, NumSlots),
   sort(Slots, Ids),
   length(Ids, NumSlots).

% --- omni validator --------------------------------------------------------

% Constraints 7, 8 and 9 are listed first so that a degenerate boundary, or a
% boundary without HMD in a table with merged cells, is reported as such, not
% as whichever structural rule it also happens to break.
constraint(7, not_entirely_data).
constraint(8, not_entirely_metadata).
constraint(9, no_hmd_only_for_plain_grids).
constraint(0, vertical_no_merged_cell_bisections).
constraint(1, horizontal_no_merged_cell_bisections).
constraint(2, horizontal_split_existence).
constraint(3, vertical_split_existence).
constraint(4, horizontal_no_inverted_hierarchies).
constraint(5, vertical_no_inverted_hierarchies).
constraint(6, horizontal_key_value_property).

% omni_validate(+Raster, +Hmd, +Vmd, -Offending)
% Always succeeds.  Offending = none if the boundary is in the domain and
% every constraint holds; some(invalid_boundary) if the raster is
% degenerate/ragged or the counts are outside 0..NumRows and 0..NumCols;
% some(7) or some(8) for a table that would be entirely data or entirely
% metadata; some(9) for a boundary without HMD rows in a table that has a
% merged cell; otherwise some(N) where N is the first violated structural
% constraint (getOffendingConstraint).
omni_validate(Raster, Hmd, Vmd, Offending) :-
   (  \+ valid_boundary_domain(Raster, Hmd, Vmd)
   -> Offending = some(invalid_boundary)
   ;  constraint(N, Validator),
      \+ call(Validator, Raster, Hmd, Vmd)
   -> Offending = some(N)
   ;  Offending = none
   ).

% omni_validate(+Raster, +Hmd, +Vmd): succeeds iff the boundary is in the
% domain and all ten constraints hold.
omni_validate(Raster, Hmd, Vmd) :-
   omni_validate(Raster, Hmd, Vmd, none).

% --- boundary search -------------------------------------------------------

% valid_boundaries(+Raster, -Boundaries): exact same candidates and ordering
% (Hmd ascending, then Vmd ascending) as the exhaustive reference, but
% precompute adjacency witnesses once and query the condensed predicates for
% each pair. Public constraints and omni_validate/3-4 remain the reference
% for diagnostics.
:- consult(fast_boundaries).

valid_boundaries(Raster, Boundaries) :-
   ( valid_raster_shape(Raster, Rows, Cols)
   -> fast_valid_boundaries(Raster, Rows, Cols, Boundaries)
   ;  Boundaries = [] ).

% --- central metadata ------------------------------------------------------

% Metadata may also sit in the middle of a table: a header band that restarts
% the columns part way down, or a header column that restarts the rows part
% way across. The marginal constraints never look inside the data region, so
% the only geometric sign of such metadata is a merged cell there.
%
% table_layouts/2 proposes every reading of the table the geometry supports:
%
%   1. Rows covered by a single cell (titles, footers, separators) are set
%      aside; they take no part in parsing.
%   2. valid_boundaries/2 gives the marginal readings of what is left.
%   3. A merged cell in the data region suggests a cut: a horizontal cut above
%      a cell spanning several columns, a vertical cut left of a cell spanning
%      several rows. The piece that starts at the cut has the merged cell on
%      its margin, so the same constraints can parse it; its own data region
%      is then searched in the same way.
%   4. A cut is kept only if the pieces still satisfy the constraints once
%      they are fused back with the metadata around them. Pieces are checked
%      without constraint 9 (see piece_validate/3).
%   5. Every cut is optional. Not cutting reads the merged cell as data, so
%      the marginal reading of step 2 is always among the layouts.
%
% Rows and columns are always lists of indices into the original raster, so
% a piece of the table need not be contiguous and nothing has to be
% translated back.
%
% A layout is a term layout(SeparatorRows, block(HmdRows, VmdCols, Region)):
%
%   block(HmdRows, VmdCols, Region)
%       Metadata and the data region it governs. The top-level block may
%       lack one kind of metadata (HmdRows = [] or VmdCols = []). The piece
%       after a horizontal cut is a block with VmdCols = [], and the piece
%       right of a vertical cut is a block with HmdRows = [].
%   region(Rows, Cols, SeparatorRows, Split)
%       A data region. SeparatorRows are the rows set aside inside it (see
%       region_separator_row/3); Rows are the others. Split is one of
%         none                  the region is all data
%         hsplit(Before, Block) Before is the region above the cut
%         vsplit(Left, Block)   Left is the region left of the cut

% At most this many layouts with central metadata are reported for a table,
% and four times as many are looked for under each marginal reading. The
% marginal layouts are always reported on top of them.
max_central_layouts(16).

% table_layouts(+Raster, -Layouts)
% Layouts with the most cuts come first and the marginal ones last. Layouts
% is [] if no marginal reading is valid, i.e. the table cannot be parsed.
table_layouts(Raster, Layouts) :-
   raster_dimensions(Raster, NumRows, NumCols),
   indices(NumRows, AllRows),
   indices(NumCols, Cols),
   partition(single_cell_row(Raster, Cols), AllRows, Separators, Rows),
   view(Raster, Rows, Cols, Stripped),
   valid_boundaries(Stripped, Boundaries),
   findall(
      layout(Separators, Block),
      ( member(Boundary, Boundaries),
        marginal_block(Raster, Rows, Cols, Boundary, Block) ),
      Marginal
   ),
   max_central_layouts(Max),
   Limit is 4 * Max,  % headroom for layouts that label the table identically
   findall(
      Found,
      ( member(Boundary, Boundaries),
        once(findnsols(
           Limit,
           layout(Separators, Block),
           central_block(Raster, Rows, Cols, Boundary, Block),
           Found
        )) ),
      FoundLists
   ),
   append(FoundLists, Found),
   distinct_layouts(Raster, Found, Distinct),
   map_list_to_pairs(layout_uncut, Distinct, Keyed),
   keysort(Keyed, Ordered),
   pairs_values(Ordered, Sorted),
   take(Max, Sorted, Central),
   append(Central, Marginal, Layouts).

% Sort key that puts the layouts with the most cuts first.
layout_uncut(Layout, Key) :-
   layout_cuts(Layout, Cuts),
   Key is -Cuts.

marginal_block(Raster, Rows, Cols, Boundary, block(HmdRows, VmdCols, Region)) :-
   boundary_split(Rows, Cols, Boundary, HmdRows, VmdCols, DataRows, DataCols),
   partition(region_separator_row(Raster, DataCols), DataRows, Separators, Rest),
   Region = region(Rest, DataCols, Separators, none).

central_block(Raster, Rows, Cols, Boundary, block(HmdRows, VmdCols, Region)) :-
   boundary_split(Rows, Cols, Boundary, HmdRows, VmdCols, DataRows, DataCols),
   region(Raster, ctx(HmdRows, VmdCols), DataRows, DataCols, [h, v], Region),
   Region = region(_, _, _, Split),
   Split \== none.

boundary_split(Rows, Cols, json{hmd: Hmd, vmd: Vmd}, HmdRows, VmdCols, DataRows, DataCols) :-
   split_at(Hmd, Rows, HmdRows, DataRows),
   split_at(Vmd, Cols, VmdCols, DataCols).

% --- views -----------------------------------------------------------------

% view(+Raster, +Rows, +Cols, -Sub): Sub is the raster made of the slots of
% Raster at the given row and column indices, in the given order.
view(Raster, Rows, Cols, Sub) :-
   maplist(view_row(Raster, Cols), Rows, Sub).

view_row(Raster, Cols, R, SubRow) :-
   nth0(R, Raster, Row),
   maplist(row_slot(Row), Cols, SubRow).

row_slot(Row, C, Value) :-
   nth0(C, Row, Value).

indices(N, Indices) :-
   findall(I, until(0, N, I), Indices).

% split_at(+N, +List, -Front, -Back): Front is the first N elements of List.
split_at(N, List, Front, Back) :-
   Length is N,
   length(Front, Length),
   append(Front, Back, List).

% take(+N, +List, -Front): Front is the first N elements of List, or all of
% List if it is shorter.
take(N, List, Front) :-
   (  split_at(N, List, Front0, _)
   -> Front = Front0
   ;  Front = List
   ).

view_transpose([], []).
view_transpose([[]|_], []) :- !.
view_transpose(Rows, [Col|Cols]) :-
   maplist(head_tail, Rows, Col, Tails),
   view_transpose(Tails, Cols).

head_tail([Head|Tail], Head, Tail).

% --- separators ------------------------------------------------------------

% single_cell_row(+Raster, +Cols, +R): one cell covers row R across all of
% Cols. A single column never counts: every row of it would qualify.
single_cell_row(Raster, Cols, R) :-
   Cols = [_, _|_],
   view_row(Raster, Cols, R, [Id|Ids]),
   maplist(==(Id), Ids).

% region_separator_row(+Raster, +Cols, +R): row R of a data region with
% columns Cols is set aside as a separator.
%
% This is the policy for a title that spans the data columns only, leaving
% the VMD columns to other cells. Such a row is treated like a row covered by
% a single cell. To let these titles compete as central HMD instead (a
% horizontal cut above them, with the fallback of reading them as data),
% make this predicate fail.
region_separator_row(Raster, Cols, R) :-
   single_cell_row(Raster, Cols, R).

% --- cuts ------------------------------------------------------------------

% region(+Raster, +Ctx, +Rows, +Cols, +Cuts, -Region)
% Region is a reading of the data region Rows x Cols; on backtracking, every
% reading. Ctx = ctx(HmdRows, VmdCols) is the metadata governing the region.
% Cuts lists the kinds of cut (h, v) the region itself may start with.
region(Raster, Ctx, Rows0, Cols, Cuts, region(Rows, Cols, Separators, Split)) :-
   partition(region_separator_row(Raster, Cols), Rows0, Separators, Rows),
   region_split(Raster, Ctx, Rows, Cols, Cuts, Split).

% The fusion checks of a cut depend only on the two pieces and on Ctx, not on
% how the pieces are read further down, so they are made before descending.
%
% The region above a horizontal cut may not start with a horizontal cut
% itself (nor the region left of a vertical cut with a vertical one): the
% same labelling is already found by making that cut first.
region_split(Raster, ctx(HmdRows, VmdCols), Rows, Cols, Cuts,
             hsplit(Before, block(CentralRows, [], After))) :-
   memberchk(h, Cuts),
   view(Raster, Rows, Cols, Sub),
   cut_line(Sub, R),
   split_at(R, Rows, RowsBefore, RowsAfter),
   central_hmd(Raster, RowsAfter, Cols, CentralRows, DataRows),
   block_valid(Raster, CentralRows, VmdCols, DataRows, Cols),
   block_valid(Raster, HmdRows, VmdCols, RowsBefore, Cols),
   region(Raster, ctx(HmdRows, VmdCols), RowsBefore, Cols, [v], Before),
   region(Raster, ctx(CentralRows, VmdCols), DataRows, Cols, [h, v], After).
region_split(Raster, ctx(HmdRows, VmdCols), Rows, Cols, Cuts,
             vsplit(Left, block([], CentralCols, Right))) :-
   memberchk(v, Cuts),
   view(Raster, Rows, Cols, Sub),
   view_transpose(Sub, Transposed),
   cut_line(Transposed, C),
   split_at(C, Cols, ColsLeft, ColsRight),
   central_vmd(Raster, Rows, ColsRight, CentralCols, DataCols),
   block_valid(Raster, HmdRows, CentralCols, Rows, DataCols),
   block_valid(Raster, HmdRows, VmdCols, Rows, ColsLeft),
   region(Raster, ctx(HmdRows, VmdCols), Rows, ColsLeft, [h], Left),
   region(Raster, ctx(HmdRows, CentralCols), Rows, DataCols, [h, v], Right).
region_split(_, _, _, _, _, none).

% cut_line(+Sub, -R): Sub can be cut above its row R. No cell straddles the
% line, and row R holds a cell spanning several columns, which therefore
% starts at R. R > 0, so both pieces are non-empty.
cut_line(Sub, R) :-
   nth0(R, Sub, Row),
   R > 0,
   R0 is R - 1,
   nth0(R0, Sub, Above),
   maplist(\==, Above, Row),
   once(( append(_, [A, B|_], Row), A == B )).

% central_hmd(+Raster, +Rows, +Cols, -HmdRows, -DataRows)
% The piece Rows x Cols, taken alone, parses with its first rows as HMD and
% no VMD, leaving at least one row of data.
central_hmd(Raster, Rows, Cols, HmdRows, DataRows) :-
   view(Raster, Rows, Cols, Piece),
   length(Rows, NumRows),
   until(1, NumRows, Hmd),
   piece_validate(Piece, Hmd, 0),
   split_at(Hmd, Rows, HmdRows, DataRows).

% central_vmd(+Raster, +Rows, +Cols, -VmdCols, -DataCols)
% The same for a piece whose first columns are VMD, with no HMD.
central_vmd(Raster, Rows, Cols, VmdCols, DataCols) :-
   view(Raster, Rows, Cols, Piece),
   length(Cols, NumCols),
   until(1, NumCols, Vmd),
   piece_validate(Piece, 0, Vmd),
   split_at(Vmd, Cols, VmdCols, DataCols).

% block_valid(+Raster, +HmdRows, +VmdCols, +DataRows, +DataCols)
% The fusion check: the table made of a data region and the metadata around
% it satisfies every constraint but 9.
block_valid(Raster, HmdRows, VmdCols, DataRows, DataCols) :-
   append(HmdRows, DataRows, Rows),
   append(VmdCols, DataCols, Cols),
   view(Raster, Rows, Cols, Block),
   length(HmdRows, Hmd),
   length(VmdCols, Vmd),
   piece_validate(Block, Hmd, Vmd).

% piece_validate(+Piece, +Hmd, +Vmd): omni_validate/3 without constraint 9.
% Constraint 9 reads any merged cell of a table without HMD as evidence of a
% header hierarchy. The piece right of a vertical cut has no HMD by
% construction, and the merged cell that suggested the cut is its VMD, so
% the evidence is already accounted for. With constraint 9, no vertical cut
% could ever be made. The top-level reading (valid_boundaries/2) still
% applies it to the whole table.
piece_validate(Piece, Hmd, Vmd) :-
   valid_boundary_domain(Piece, Hmd, Vmd),
   forall(( constraint(N, Validator), N =\= 9 ),
          call(Validator, Piece, Hmd, Vmd)).

% --- labels ----------------------------------------------------------------

% layout_labels(+Raster, +Layout, -Labels)
% Labels has the shape of Raster, each slot holding hmd, vmd, data or
% separator. As with the marginal boundaries, HMD rows are HMD across the
% VMD columns too: the top-level ones across the whole table, central ones
% across the VMD columns governing their region.
layout_labels(Raster, layout(Separators, block(HmdRows, VmdCols, Region)), Labels) :-
   raster_dimensions(Raster, NumRows, NumCols),
   indices(NumRows, AllRows),
   indices(NumCols, AllCols),
   empty_assoc(Slots0),
   paint(Separators, AllCols, separator, Slots0, Slots1),
   paint(HmdRows, AllCols, hmd, Slots1, Slots2),
   region_rows(Region, BodyRows),
   paint(BodyRows, VmdCols, vmd, Slots2, Slots3),
   paint_region(Region, VmdCols, Slots3, Slots),
   maplist(label_row(Slots, AllCols), AllRows, Labels).

label_row(Slots, Cols, R, Labels) :-
   maplist(slot_label(Slots, R), Cols, Labels).

slot_label(Slots, R, C, Label) :-
   get_assoc(R-C, Slots, Label).

region_rows(region(Rows, _, Separators, _), AllRows) :-
   append(Rows, Separators, AllRows).

paint_region(region(Rows, Cols, Separators, Split), VmdCols, Slots0, Slots) :-
   paint(Separators, Cols, separator, Slots0, Slots1),
   paint_split(Split, Rows, Cols, VmdCols, Slots1, Slots).

paint_split(none, Rows, Cols, _, Slots0, Slots) :-
   paint(Rows, Cols, data, Slots0, Slots).
paint_split(hsplit(Before, block(CentralRows, [], After)), _, Cols, VmdCols, Slots0, Slots) :-
   paint_region(Before, VmdCols, Slots0, Slots1),
   append(VmdCols, Cols, Wide),
   paint(CentralRows, Wide, hmd, Slots1, Slots2),
   paint_region(After, VmdCols, Slots2, Slots).
paint_split(vsplit(Left, block([], CentralCols, Right)), _, _, VmdCols, Slots0, Slots) :-
   paint_region(Left, VmdCols, Slots0, Slots1),
   region_rows(Right, RightRows),
   paint(RightRows, CentralCols, vmd, Slots1, Slots2),
   paint_region(Right, CentralCols, Slots2, Slots).

% paint(+Rows, +Cols, +Label, +Slots0, -Slots): Slots is an assoc from
% Row-Col to label; a later label replaces an earlier one.
paint(Rows, Cols, Label, Slots0, Slots) :-
   foldl(paint_row(Cols, Label), Rows, Slots0, Slots).

paint_row(Cols, Label, R, Slots0, Slots) :-
   foldl(paint_slot(Label, R), Cols, Slots0, Slots).

paint_slot(Label, R, C, Slots0, Slots) :-
   put_assoc(R-C, Slots0, Label, Slots).

% distinct_layouts(+Raster, +Layouts, -Distinct): drops every layout that
% labels the table exactly as an earlier one does.
distinct_layouts(Raster, Layouts, Distinct) :-
   distinct_layouts(Layouts, Raster, [], Distinct).

distinct_layouts([], _, _, []).
distinct_layouts([Layout|Layouts], Raster, Seen, Distinct) :-
   layout_labels(Raster, Layout, Labels),
   (  memberchk(Labels, Seen)
   -> Distinct = Distinct1
   ;  Distinct = [Layout|Distinct1]
   ),
   distinct_layouts(Layouts, Raster, [Labels|Seen], Distinct1).

% layout_cuts(+Layout, -Cuts): the number of cuts in Layout.
layout_cuts(layout(_, block(_, _, Region)), Cuts) :-
   region_cuts(Region, Cuts).

region_cuts(region(_, _, _, Split), Cuts) :-
   split_cuts(Split, Cuts).

split_cuts(none, 0).
split_cuts(hsplit(Before, block(_, _, After)), Cuts) :-
   region_cuts(Before, N1),
   region_cuts(After, N2),
   Cuts is N1 + N2 + 1.
split_cuts(vsplit(Left, block(_, _, Right)), Cuts) :-
   region_cuts(Left, N1),
   region_cuts(Right, N2),
   Cuts is N1 + N2 + 1.
