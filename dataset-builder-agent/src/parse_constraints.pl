% Prolog port of ConstraintValidators.scala.
%
% Raster is the flattened raster: a list of rows, each row a list of cell ids.
% Cells belonging to the same (merged) cell share the same id.
% The class-scoped values num_rows / num_cols become the plain variables
% NumRows / NumCols, computed by raster_dimensions/3.
%
% Each constraint predicate succeeds when its Scala validate(...) returns true.
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
% Fails outside the raster. A boundary of -1 (no metadata on that axis, used
% for central metadata) therefore makes the checks that touch it hold
% vacuously.
cell(Raster, I, J, Value) :-
   I >= 0, J >= 0,
   nth0(I, Raster, Row),
   nth0(J, Row, Value).

% until(+Low, +High, -X): X ranges over Scala's (Low until High)
until(Low, High, X) :-
   First is Low, Last is High - 1,
   between(First, Last, X).

% --- constraint 0 ----------------------------------------------------------

vertical_no_merged_cell_bisections(Raster, HmdBoundary, VmdBoundary) :-
   raster_dimensions(Raster, NumRows, _),
   V1 is VmdBoundary + 1,
   \+ ( until(HmdBoundary + 1, NumRows, I),
        cell(Raster, I, VmdBoundary, A),
        cell(Raster, I, V1, B),
        A == B ).

% --- constraint 1 ----------------------------------------------------------

horizontal_no_merged_cell_bisections(Raster, HmdBoundary, VmdBoundary) :-
   raster_dimensions(Raster, _, NumCols),
   H1 is HmdBoundary + 1,
   \+ ( until(VmdBoundary, NumCols, J),  % asymmetry is intentional
        cell(Raster, HmdBoundary, J, A),
        cell(Raster, H1, J, B),
        A == B ).

% --- constraint 2 ----------------------------------------------------------

horizontal_split_existence(Raster, HmdBoundary, VmdBoundary) :-
   raster_dimensions(Raster, _, NumCols),
   forall(
      until(0, HmdBoundary, I),
      (  I1 is I + 1,
         once(( until(VmdBoundary + 1, NumCols - 1, J),
                J1 is J + 1,
                cell(Raster, I, J, A),  cell(Raster, I, J1, B),  A == B,
                cell(Raster, I1, J, C), cell(Raster, I1, J1, D), C \== D ))
      )
   ).

% --- constraint 3 ----------------------------------------------------------

vertical_split_existence(Raster, HmdBoundary, VmdBoundary) :-
   raster_dimensions(Raster, NumRows, _),
   forall(
      until(0, VmdBoundary, J),
      (  J1 is J + 1,
         once(( until(HmdBoundary + 1, NumRows - 1, I),
                I1 is I + 1,
                cell(Raster, I, J, A),  cell(Raster, I1, J, B),  A == B,
                cell(Raster, I, J1, C), cell(Raster, I1, J1, D), C \== D ))
      )
   ).

% --- constraint 4 ----------------------------------------------------------

horizontal_no_inverted_hierarchies(Raster, HmdBoundary, VmdBoundary) :-
   raster_dimensions(Raster, _, NumCols),
   \+ ( until(0, HmdBoundary, I),
        until(VmdBoundary + 1, NumCols - 1, J),
        I1 is I + 1, J1 is J + 1,
        cell(Raster, I, J, A),  cell(Raster, I, J1, B),  A \== B,
        cell(Raster, I1, J, C), cell(Raster, I1, J1, D), C == D ).

% --- constraint 5 ----------------------------------------------------------

vertical_no_inverted_hierarchies(Raster, HmdBoundary, VmdBoundary) :-
   raster_dimensions(Raster, NumRows, _),
   \+ ( until(0, VmdBoundary, J),
        until(HmdBoundary, NumRows - 1, I),
        I1 is I + 1, J1 is J + 1,
        cell(Raster, I, J, A),  cell(Raster, I1, J, B),  A \== B,
        cell(Raster, I, J1, C), cell(Raster, I1, J1, D), C == D ).

% --- constraint 6 ----------------------------------------------------------

horizontal_key_value_property(Raster, HmdBoundary, VmdBoundary) :-
   raster_dimensions(Raster, _, NumCols),
   \+ ( until(VmdBoundary, NumCols - 1, J),
        J1 is J + 1,
        cell(Raster, HmdBoundary, J, A),
        cell(Raster, HmdBoundary, J1, B),
        A == B ).

% --- omni validator --------------------------------------------------------

constraint(0, vertical_no_merged_cell_bisections).
constraint(1, horizontal_no_merged_cell_bisections).
constraint(2, horizontal_split_existence).
constraint(3, vertical_split_existence).
constraint(4, horizontal_no_inverted_hierarchies).
constraint(5, vertical_no_inverted_hierarchies).
constraint(6, horizontal_key_value_property).

% omni_validate(+Raster, +Hmd, +Vmd, -Offending)
% Always succeeds. Offending = none if every constraint holds, otherwise
% some(N) where N is the first violated constraint (getOffendingConstraint).
omni_validate(Raster, HmdBoundary, VmdBoundary, Offending) :-
   (  constraint(N, Validator),
      \+ call(Validator, Raster, HmdBoundary, VmdBoundary)
   -> Offending = some(N)
   ;  Offending = none
   ).

% omni_validate(+Raster, +Hmd, +Vmd): succeeds iff all constraints hold.
omni_validate(Raster, HmdBoundary, VmdBoundary) :-
   omni_validate(Raster, HmdBoundary, VmdBoundary, none).

% --- boundary search -------------------------------------------------------

% valid_boundaries(+Raster, -Boundaries): every reading of the margins of
% Raster that satisfies all seven constraints. Each one is a dict
% json{hmd: Hmd, vmd: Vmd} of layer counts: the first Hmd rows are horizontal
% metadata and the first Vmd columns are vertical metadata. A count of 0
% means the table has no metadata of that kind.
%
% The constraints above work on boundaries instead: the index of the last
% metadata row or column, i.e. the count minus one, so -1 for no metadata.
%
% With no metadata on an axis the constraints of that axis hold vacuously,
% so two more rules apply:
%   - 0 is offered on an axis only if no merged cell lies along that margin
%     (see min_layers/2). Such a margin is one layer of metadata or none,
%     and the geometry cannot tell which.
%   - 0/0 is never reported: it holds for every table and labels nothing.
valid_boundaries(Raster, Boundaries) :-
   raster_dimensions(Raster, NumRows, NumCols),
   min_layers(Raster, MinHmd),
   transpose_raster(Raster, Transposed),
   min_layers(Transposed, MinVmd),
   findall(
      json{hmd: Hmd, vmd: Vmd},
      ( between(MinHmd, NumRows, Hmd),
        between(MinVmd, NumCols, Vmd),
        Hmd + Vmd > 0,
        HmdBoundary is Hmd - 1,
        VmdBoundary is Vmd - 1,
        omni_validate(Raster, HmdBoundary, VmdBoundary) ),
      Boundaries
   ).

% min_layers(+Raster, -Min): the fewest HMD layers Raster may have. Min is 1
% if a cell of the first row is merged, across columns or down into the
% second row, and 0 otherwise.
min_layers(Raster, Min) :-
   (  merged_first_row(Raster)
   -> Min = 1
   ;  Min = 0
   ).

merged_first_row([Row|_]) :-
   append(_, [A, B|_], Row),
   A == B,
   !.
merged_first_row([Row, Next|_]) :-
   nth0(J, Row, A),
   nth0(J, Next, B),
   A == B,
   !.

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
%      they are fused back with the metadata around them.
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

transpose_raster([], []).
transpose_raster([[]|_], []) :- !.
transpose_raster(Rows, [Col|Cols]) :-
   maplist(head_tail, Rows, Col, Tails),
   transpose_raster(Tails, Cols).

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
   transpose_raster(Sub, Transposed),
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
   until(0, NumRows - 1, Hmd),
   omni_validate(Piece, Hmd, -1),
   split_at(Hmd + 1, Rows, HmdRows, DataRows).

% central_vmd(+Raster, +Rows, +Cols, -VmdCols, -DataCols)
% The same for a piece whose first columns are VMD, with no HMD.
central_vmd(Raster, Rows, Cols, VmdCols, DataCols) :-
   view(Raster, Rows, Cols, Piece),
   length(Cols, NumCols),
   until(0, NumCols - 1, Vmd),
   omni_validate(Piece, -1, Vmd),
   split_at(Vmd + 1, Cols, VmdCols, DataCols).

% block_valid(+Raster, +HmdRows, +VmdCols, +DataRows, +DataCols)
% The fusion check: the table made of a data region and the metadata around
% it satisfies every constraint.
block_valid(Raster, HmdRows, VmdCols, DataRows, DataCols) :-
   append(HmdRows, DataRows, Rows),
   append(VmdCols, DataCols, Cols),
   view(Raster, Rows, Cols, Block),
   length(HmdRows, NumHmd),
   length(VmdCols, NumVmd),
   Hmd is NumHmd - 1,
   Vmd is NumVmd - 1,
   omni_validate(Block, Hmd, Vmd).

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
