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

% valid_boundaries(+Raster, -Boundaries): every (HmdBoundary, VmdBoundary)
% pair inside the raster for which omni_validate/3 holds, i.e. all seven
% constraints are satisfied. Each pair is a dict json{hmd: Hmd, vmd: Vmd}.
valid_boundaries(Raster, Boundaries) :-
   raster_dimensions(Raster, NumRows, NumCols),
   findall(
      json{hmd: Hmd, vmd: Vmd},
      ( until(0, NumRows, Hmd),
        until(0, NumCols, Vmd),
        omni_validate(Raster, Hmd, Vmd) ),
      Boundaries
   ).
