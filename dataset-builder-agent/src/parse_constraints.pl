% Prolog port of ConstraintValidators.scala.
%
% Raster is the flattened raster: a list of rows, each row a list of cell ids.
% Cells belonging to the same (merged) cell share the same id.
% The class-scoped values num_rows / num_cols become the plain variables
% NumRows / NumCols, computed by raster_dimensions/3.
%
% Each constraint predicate succeeds when its Scala validate(...) returns true.

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

% A boundary denotes the *last* HMD row and the *last* VMD column.
% All three regions (HMD, VMD and data) must contain at least one cell.
% In particular, the data region starts at (HmdBoundary+1,VmdBoundary+1),
% which must be an actual raster slot.  This is a structural contract, not
% evidence that those cells are semantically headers.
%
% Treat malformed/degenerate rasters as having no admissible boundaries.
% Checking every row also prevents constraints from silently succeeding when
% a purportedly rectangular raster is ragged.
valid_raster_shape(Raster, NumRows, NumCols) :-
   is_list(Raster),
   Raster = [FirstRow|_],
   is_list(FirstRow),
   length(Raster, NumRows),
   length(FirstRow, NumCols),
   NumRows >= 2,
   NumCols >= 2,
   forall(member(Row, Raster), (is_list(Row), length(Row, NumCols))).

valid_boundary_domain(Raster, HmdBoundary, VmdBoundary) :-
   integer(HmdBoundary),
   integer(VmdBoundary),
   valid_raster_shape(Raster, NumRows, NumCols),
   HmdBoundary >= 0,
   VmdBoundary >= 0,
   HmdBoundary < NumRows - 1,
   VmdBoundary < NumCols - 1.

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
% Always succeeds.  Offending = none if the boundary is in the valid domain
% and every constraint holds; some(invalid_boundary) if the raster is
% degenerate/ragged or coordinates are invalid; otherwise some(N) where N is
% the first violated structural constraint (getOffendingConstraint).
omni_validate(Raster, HmdBoundary, VmdBoundary, Offending) :-
   (  \+ valid_boundary_domain(Raster, HmdBoundary, VmdBoundary)
   -> Offending = some(invalid_boundary)
   ;  constraint(N, Validator),
      \+ call(Validator, Raster, HmdBoundary, VmdBoundary)
   -> Offending = some(N)
   ;  Offending = none
   ).

% omni_validate(+Raster, +Hmd, +Vmd): succeeds iff the boundary is in the
% domain and all seven constraints hold.
omni_validate(Raster, HmdBoundary, VmdBoundary) :-
   omni_validate(Raster, HmdBoundary, VmdBoundary, none).

% --- boundary search -------------------------------------------------------

% valid_boundaries(+Raster, -Boundaries): every (HmdBoundary, VmdBoundary)
% pair with nonempty HMD, VMD and data regions for which all seven
% constraints hold.  An undersized or malformed raster produces [].
% Each pair is a dict json{hmd: Hmd, vmd: Vmd}.
valid_boundaries(Raster, Boundaries) :-
   findall(
      json{hmd: Hmd, vmd: Vmd},
      ( valid_raster_shape(Raster, NumRows, NumCols),
        MaxHmd is NumRows - 2,
        MaxVmd is NumCols - 2,
        between(0, MaxHmd, Hmd),
        between(0, MaxVmd, Vmd),
        omni_validate(Raster, Hmd, Vmd) ),
      Boundaries
   ).
