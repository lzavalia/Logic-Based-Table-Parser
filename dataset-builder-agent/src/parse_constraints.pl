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
