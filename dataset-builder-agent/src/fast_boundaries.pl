% F11 indexed boundary search.  The seven public predicates in
% parse_constraints.pl remain the reference specification and are used by
% omni_validate/3-4.  This evaluator compiles their exact adjacency tests
% once per rectangular raster, so no candidate requires nth0/3 or a scan.
%
% For a raster with R rows and C columns, preparation costs O(R*C +
% (R+C)*log(R+C)) with O(R+C) summary space.  Candidate evaluation costs
% O(log(R+C)) using ordered assocs, plus the cost of emitted candidates.
%
% An equality check is term *identity* (==), matching the reference rules.
% Summary indices and raster coordinates are zero based.

:- use_module(library(assoc)).

% fast_valid_boundaries(+Raster,+Rows,+Cols,-Boundaries)
% Caller has already established valid_raster_shape/3.
fast_valid_boundaries(Raster, Rows, Cols, Boundaries) :-
   fast_boundary_features(Raster, Rows, Cols, Features),
   LastH is Rows - 2,
   LastV is Cols - 2,
   findall(json{hmd:H, vmd:V},
           ( between(0, LastH, H),
             fast_candidate_v_range(Features, H, LastV, FirstV, EndV),
             between(FirstV, EndV, V),
             fast_column_checks(Features, H, V) ),
           Boundaries).

% features(KeyMax, CrossingRowMax, SplitRowPrefixMin,
%          InversionRowPrefixMax, SameColumnMaxRow,
%          SplitColumnPrefixMin, InversionColumnPrefixMax)
fast_boundary_features(Raster, Rows, Cols,
                       features(Keys, Crossing, RSplit, RInvert,
                                CSame, CSplit, CInvert)) :-
   empty_assoc(E),
   scan_fast_rows(Raster, 0, fast_state(E,E,E,E,E,E,E),
                  fast_state(Keys,Crossing,RawRSplit,RawRInvert,
                             CSame,RawCSplit,RawCInvert)),
   LastH is Rows - 2,
   LastV is Cols - 2,
   prefix_extrema(LastH, RawRSplit, RawRInvert, Cols,
                  RSplit, RInvert),
   prefix_extrema(LastV, RawCSplit, RawCInvert, Rows,
                  CSplit, CInvert).

scan_fast_rows([], _, State, State).
scan_fast_rows([Row|Rest], I,
               fast_state(K0,B0,S0,N0,C0,W0,V0), State) :-
   row_adjacencies(Row, I, 0, C0, C1, -1, KeyMax),
   put_assoc(I, K0, KeyMax, K1),
   ( Rest = [Next|_] ->
       row_pair_adjacencies(Row, Next, I, 0, -1, -1, -1,
                            W0, W1, V0, V1,
                            CrossingMax, SplitMax, InvertMax),
       put_assoc(I, B0, CrossingMax, B1),
       put_assoc(I, S0, SplitMax, S1),
       put_assoc(I, N0, InvertMax, N1)
   ;   B1=B0, S1=S0, N1=N0, W1=W0, V1=V0 ),
   I1 is I + 1,
   scan_fast_rows(Rest, I1,
                  fast_state(K1,B1,S1,N1,C1,W1,V1), State).

% Highest horizontal same-cell adjacency J in each row.  For each J,
% record the highest row with that adjacency (constraint 0).
row_adjacencies([A,B|Rest], I, J, C0, C, K0, K) :- !,
   ( A == B -> put_assoc(J, C0, I, C1), K1 = J
   ; C1 = C0, K1 = K0 ),
   J1 is J + 1,
   row_adjacencies([B|Rest], I, J1, C1, C, K1, K).
row_adjacencies([_], _, _, C, C, K, K).

% Examine every adjacent pair of rows and columns just once.  Each event
% either updates a row maximum or the last (highest) witness row for a
% column.  Missing witness indices have value -1.
row_pair_adjacencies([A,A1|As], [B,B1|Bs], I, J,
                      Eq0, Split0, Inv0, W0,W, V0,V, Eq,Split,Inv) :- !,
   ( A == B -> Eq1 = J ; Eq1 = Eq0 ),
   ( A == A1, B \== B1 -> Split1 = J ; Split1 = Split0 ),
   ( A \== A1, B == B1 -> Inv1 = J ; Inv1 = Inv0 ),
   ( A == B, A1 \== B1 -> put_assoc(J, W0, I, W1) ; W1 = W0 ),
   ( A \== B, A1 == B1 -> put_assoc(J, V0, I, V1) ; V1 = V0 ),
   J1 is J + 1,
   row_pair_adjacencies([A1|As], [B1|Bs], I, J1,
                        Eq1, Split1, Inv1, W1,W, V1,V,
                        Eq,Split,Inv).
row_pair_adjacencies([A], [B], _, J, Eq0, S, N,
                      W,W, V,V, Eq,S,N) :-
   ( A == B -> Eq = J ; Eq = Eq0 ).

% Index P summarizes all rows/columns strictly before P.
% For a split-existence condition, every preceding index must have a
% witness: the minimum of their maximum witness positions decides that.
% For an inversion-exclusion condition, the maximum is sufficient.
% P=0 is vacuously valid: its min sentinel is past the last usable
% coordinate and its max sentinel is -1.
prefix_extrema(Limit, RawSplit, RawInvert, Sentinel, Mins, Maxes) :-
   empty_assoc(E),
   put_assoc(0, E, Sentinel, M0),
   put_assoc(0, E, -1, X0),
   prefix_extrema_from(1, Limit, RawSplit, RawInvert,
                       Sentinel, -1, M0, X0, Mins, Maxes).

prefix_extrema_from(Index, Limit, _, _, _, _, Mins, Maxes, Mins, Maxes) :-
   Index > Limit, !.
prefix_extrema_from(Index, Limit, RawSplit, RawInvert,
                    PrevMin, PrevMax, M0, X0, Mins, Maxes) :-
   Prior is Index - 1,
   ( get_assoc(Prior, RawSplit, S) -> true ; S = -1 ),
   ( get_assoc(Prior, RawInvert, X) -> true ; X = -1 ),
   Min is min(PrevMin, S),
   Max is max(PrevMax, X),
   put_assoc(Index, M0, Min, M1),
   put_assoc(Index, X0, Max, X1),
   Next is Index + 1,
   prefix_extrema_from(Next, Limit, RawSplit, RawInvert,
                       Min, Max, M1, X1, Mins, Maxes).

% The first four row-dependent rules give an exact admissible range for V:
% C1: no vertical equality on H/H+1 at any column J >= V.
% C2: for every I<H a splitting witness exists at J>V.
% C4: no inverted horizontal pattern for I<H at J>V.
% C6: no horizontal equality on H at J>=V.
fast_candidate_v_range(features(Keys, Crossing, RSplit, RInvert,_,_,_),
                       H, LastV, FirstV, EndV) :-
   get_assoc(H, Keys, KeyMax),
   get_assoc(H, Crossing, CrossMax),
   get_assoc(H, RSplit, SplitMin),
   get_assoc(H, RInvert, InvMax),
   FirstV is max(0, max(KeyMax+1, max(CrossMax+1, InvMax))),
   EndV is min(LastV, SplitMin-1).

% C0: a horizontal merge across V/V+1 cannot occur below H.
% C3: every J<V needs a vertical splitting witness at I>H.
% C5: no inverted vertical pattern at I>=H for J<V.
fast_column_checks(features(_,_,_,_,CSame,CSplit,CInvert), H, V) :-
   ( get_assoc(V, CSame, LastSame) -> LastSame =< H ; true ),
   get_assoc(V, CSplit, WitnessMin),
   WitnessMin > H,
   get_assoc(V, CInvert, LastInversion),
   LastInversion < H.
