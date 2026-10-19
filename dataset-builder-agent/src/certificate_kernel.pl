% Trusted checker for geometric labelability certificates.
%
% A certificate claims that a table, split at a boundary (Hmd, Vmd), can be
% labelled geometrically. Hmd and Vmd are counts, as in parse_constraints.pl:
%   rows 0 .. Hmd-1                        horizontal metadata (HMD)
%   rows Hmd .., columns 0 .. Vmd-1        vertical metadata (VMD)
%   rows Hmd .., columns Vmd ..            data
%
% The HMD graph has a node for every cell in the HMD rows over the data
% columns, and an edge A -> B when, in some data column, A is directly above
% B and A \== B (the top-to-bottom reading). Because every cell is a
% rectangle the graph is acyclic; its roots are the cells in row 0 and its
% sinks the cells in row Hmd-1. The path of a data column is the column's
% HMD cell ids, top to bottom, without consecutive repeats; it is always a
% root-to-sink path of the graph.
%
% The table is column-labelable when the data columns and the root-to-sink
% paths of the HMD graph correspond one to one: no two columns share a path
% and the graph has no path that no column follows. Row-labelable is the
% same on the VMD (the left-to-right reading of the data rows). A table is
% labelable when it is column-labelable OR row-labelable, and the
% certificate's claim/1 says which of the two it proves.
%
% Independently of the claim, no cell may cross the line between the HMD
% and the rows below it, nor, below the HMD, the line between the VMD and
% the data. The structural constraints 0 and 1 already forbid this, but the
% kernel checks it again so that a certificate does not depend on them.
%
% A certificate is a list of ground facts:
%   certificate_version(1).
%   table_uid(Uid).                  optional, informational
%   raster(Rows).                    list of rows of cell ids
%   boundary(Hmd, Vmd).
%   claim(columns) or claim(rows).
%   column_path(J, Path).            one per data column, for claim(columns)
%   row_path(I, Path).               one per data row, for claim(rows)
%
% This file is the whole trusted base: it depends only on SWI-Prolog's
% standard libraries, and checks everything the certificate states rather
% than trusting the generator (table_certify.pl).

:- module(certificate_kernel,
          [ check_certificate/1,          % +Facts
            check_certificate/2,          % +Facts, -Verdict
            check_certificate_file/2,     % +File, -Verdict
            read_certificate_file/2,      % +File, -Facts
            check_loaded_certificate/0,
            axis_paths/4,                 % +Raster, +Hmd, +Vmd, -Paths
            transpose_raster/2            % +Raster, -Transposed
          ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(pairs)).
:- use_module(library(assoc)).

certificate_fact(certificate_version, 1).
certificate_fact(table_uid, 1).
certificate_fact(raster, 1).
certificate_fact(boundary, 2).
certificate_fact(claim, 1).
certificate_fact(column_path, 2).
certificate_fact(row_path, 2).

% --- entry points ----------------------------------------------------------

% check_certificate(+Facts): Facts is an accepted certificate.
check_certificate(Facts) :-
   check_certificate(Facts, accepted).

% check_certificate(+Facts, -Verdict): Verdict is accepted, or
% rejected(Reason) for the first check that fails.
check_certificate(Facts, Verdict) :-
   catch(( check_steps(Facts), Verdict = accepted ),
         certificate_rejected(Reason),
         Verdict = rejected(Reason)).

% check_certificate_file(+File, -Verdict): reads File as data. Directives
% are skipped, never run, so an untrusted certificate cannot execute code.
check_certificate_file(File, Verdict) :-
   read_certificate_file(File, Facts),
   check_certificate(Facts, Verdict).

% read_certificate_file(+File, -Facts): the clauses of File, without its
% directives, which are skipped and never run.
read_certificate_file(File, Facts) :-
   setup_call_cleanup(
      open(File, read, Stream, [encoding(utf8)]),
      read_certificate_terms(Stream, Facts),
      close(Stream)).

read_certificate_terms(Stream, Facts) :-
   read_term(Stream, Term, [double_quotes(string)]),
   (  Term == end_of_file
   -> Facts = []
   ;  Term = (:- _)
   -> read_certificate_terms(Stream, Facts)
   ;  Facts = [Term|More],
      read_certificate_terms(Stream, More)
   ).

% check_loaded_certificate: checks the certificate facts loaded into module
% user. A generated certificate calls it as its main goal, so running the
% certificate file exits with status 0 if it is accepted and 1 if not.
check_loaded_certificate :-
   findall(Fact,
           ( certificate_fact(Name, Arity),
             current_predicate(user:Name/Arity),
             functor(Fact, Name, Arity),
             clause(user:Fact, true) ),
           Facts),
   check_certificate(Facts, Verdict),
   (  Verdict == accepted
   -> format("certificate accepted~n")
   ;  format(user_error, "certificate rejected: ~q~n", [Verdict]),
      fail
   ).

% --- checks, in order ------------------------------------------------------

check_steps(Facts) :-
   require(is_list(Facts), not_a_fact_list),
   forall(member(Fact, Facts), known_fact(Fact)),
   one_fact(certificate_version(Version), Facts),
   require(Version == 1, unsupported_version(Version)),
   optional_fact(table_uid(_), Facts),
   one_fact(raster(Raster), Facts),
   one_fact(boundary(Hmd, Vmd), Facts),
   one_fact(claim(Claim), Facts),
   require(rectangular_raster(Raster, Rows, Cols), raster_not_rectangular),
   rectangular_cells(Raster),
   require(( integer(Hmd), integer(Vmd),
             between(0, Rows, Hmd), Hmd < Rows,
             between(0, Cols, Vmd), Vmd < Cols ),
           boundary_out_of_range(Hmd, Vmd)),
   closed_boundary(Raster, Hmd, Vmd),
   claim_axis(Claim, Facts, Raster, Hmd, Vmd, AxisRaster, AxisHmd, AxisVmd, Claimed),
   axis_labelable(AxisRaster, AxisHmd, AxisVmd, Claimed).

require(Goal, Reason) :-
   (  call(Goal)
   -> true
   ;  throw(certificate_rejected(Reason))
   ).

known_fact(Fact) :-
   require(( callable(Fact), functor(Fact, Name, Arity),
             certificate_fact(Name, Arity) ),
           unknown_fact(Fact)),
   require(ground(Fact), nonground_fact(Fact)).

one_fact(Template, Facts) :-
   functor(Template, Name, Arity),
   facts_named(Name, Arity, Facts, Found),
   require(Found = [Template], expected_one_fact(Name/Arity)).

optional_fact(Template, Facts) :-
   functor(Template, Name, Arity),
   facts_named(Name, Arity, Facts, Found),
   require(( Found = [] ; Found = [_] ), expected_at_most_one_fact(Name/Arity)).

facts_named(Name, Arity, Facts, Found) :-
   functor(General, Name, Arity),
   include(subsumes_term(General), Facts, Found).

% --- raster shape ----------------------------------------------------------

rectangular_raster(Raster, Rows, Cols) :-
   is_list(Raster),
   Raster = [First|_],
   is_list(First),
   length(Raster, Rows),
   length(First, Cols),
   Cols >= 1,
   forall(member(Row, Raster), ( is_list(Row), length(Row, Cols) )).

% Every cell id covers a full rectangle of slots: its slot count equals the
% area of its bounding box. This makes both graphs acyclic.
rectangular_cells(Raster) :-
   findall(Id-(I-J), ( nth0(I, Raster, Row), nth0(J, Row, Id) ), Slots),
   keysort(Slots, Sorted),
   group_pairs_by_key(Sorted, Cells),
   forall(member(Id-Coords, Cells),
          require(filled_box(Coords), cell_not_rectangular(Id))).

filled_box(Coords) :-
   pairs_keys_values(Coords, Is, Js),
   min_list(Is, I0), max_list(Is, I1),
   min_list(Js, J0), max_list(Js, J1),
   length(Coords, Count),
   Count =:= (I1 - I0 + 1) * (J1 - J0 + 1).

% --- boundary lines --------------------------------------------------------

% No cell is both in the last HMD row and in the row below it, in any
% column; below the HMD, no cell is both in the last VMD column and in the
% first data column.
closed_boundary(Raster, Hmd, Vmd) :-
   (  Hmd > 0
   -> Above is Hmd - 1,
      nth0(Above, Raster, UpperRow),
      nth0(Hmd, Raster, LowerRow),
      (  nth0(J, UpperRow, Id), nth0(J, LowerRow, Same), Id == Same
      -> throw(certificate_rejected(cell_crosses_hmd_line(Id, column(J))))
      ;  true
      )
   ;  true
   ),
   (  Vmd > 0
   -> Left is Vmd - 1,
      (  nth0(I, Raster, Row), I >= Hmd,
         nth0(Left, Row, Id2), nth0(Vmd, Row, Same2), Id2 == Same2
      -> throw(certificate_rejected(cell_crosses_vmd_line(Id2, row(I))))
      ;  true
      )
   ;  true
   ).

% --- claims ----------------------------------------------------------------

% Rows of the original are columns of the transposed raster, with the roles
% of Hmd and Vmd exchanged, so both claims are checked by axis_labelable/4.
claim_axis(columns, Facts, Raster, Hmd, Vmd, Raster, Hmd, Vmd, Claimed) :- !,
   facts_named(row_path, 2, Facts, Other),
   require(Other == [], path_of_other_axis(row_path)),
   findall(J-Path, member(column_path(J, Path), Facts), Claimed).
claim_axis(rows, Facts, Raster, Hmd, Vmd, Transposed, Vmd, Hmd, Claimed) :- !,
   facts_named(column_path, 2, Facts, Other),
   require(Other == [], path_of_other_axis(column_path)),
   transpose_raster(Raster, Transposed),
   findall(I-Path, member(row_path(I, Path), Facts), Claimed).
claim_axis(Claim, _, _, _, _, _, _, _, _) :-
   throw(certificate_rejected(unknown_claim(Claim))).

% axis_labelable(+Raster, +Hmd, +Vmd, +Claimed): the header is rows
% 0 .. Hmd-1, the keyed lines are the columns Vmd .. Cols-1.
axis_labelable(Raster, Hmd, Vmd, Claimed) :-
   require(Hmd >= 1, no_header_on_claimed_axis),
   axis_paths(Raster, Hmd, Vmd, Paths),
   msort(Claimed, SortedClaimed),
   require(SortedClaimed == Paths, paths_do_not_match_raster),
   pairs_values(Paths, PathList),
   sort(PathList, Distinct),
   length(PathList, NumLines),
   length(Distinct, NumDistinct),
   require(NumDistinct =:= NumLines, lines_share_a_path),
   header_path_count(Raster, Hmd, Vmd, NumPaths),
   require(NumPaths =:= NumLines, graph_has_paths_without_line(NumPaths, NumLines)).

% axis_paths(+Raster, +Hmd, +Vmd, -Paths): Paths is J-Path for every
% column J >= Vmd, in order, where Path is the column's ids in rows
% 0 .. Hmd-1 without consecutive repeats.
axis_paths(Raster, Hmd, Vmd, Paths) :-
   length(Header, Hmd),
   append(Header, _, Raster),
   Raster = [First|_],
   length(First, Cols),
   Last is Cols - 1,
   findall(J-Path,
           ( between(Vmd, Last, J),
             findall(Id, ( member(Row, Header), nth0(J, Row, Id) ), Column),
             collapse(Column, Path) ),
           Paths).

collapse([], []).
collapse([X|Xs], [X|Ys]) :-
   skip_same(X, Xs, Rest),
   collapse(Rest, Ys).

skip_same(X, [Y|Ys], Rest) :-
   Y == X, !,
   skip_same(X, Ys, Rest).
skip_same(_, Rest, Rest).

% --- the header graph ------------------------------------------------------

% header_path_count(+Raster, +Hmd, +Vmd, -Count): the number of root-to-sink
% paths of the header graph over columns Vmd .., counted by dynamic
% programming over the (acyclic) graph, not by enumerating paths.
header_path_count(Raster, Hmd, Vmd, Count) :-
   length(Header, Hmd),
   append(Header, _, Raster),
   Header = [Top|_],
   findall(A-B,
           ( append(_, [Upper, Lower|_], Header),
             nth0(J, Upper, A), J >= Vmd,
             nth0(J, Lower, B), A \== B ),
           Edges0),
   sort(Edges0, Edges),
   group_pairs_by_key(Edges, Successors),
   list_to_assoc(Successors, Graph),
   findall(Root, ( nth0(J, Top, Root), J >= Vmd ), Roots0),
   sort(Roots0, Roots),
   empty_assoc(Memo0),
   foldl(add_path_count(Graph), Roots, 0-Memo0, Count-_).

add_path_count(Graph, Node, Sum0-Memo0, Sum-Memo) :-
   path_count(Graph, Node, Memo0, Memo, Count),
   Sum is Sum0 + Count.

% A node without successors is a sink, a cell in row Hmd-1.
path_count(Graph, Node, Memo0, Memo, Count) :-
   (  get_assoc(Node, Memo0, Count)
   -> Memo = Memo0
   ;  get_assoc(Node, Graph, Next)
   -> foldl(add_path_count(Graph), Next, 0-Memo0, Count-Memo1),
      put_assoc(Node, Memo1, Count, Memo)
   ;  Count = 1,
      put_assoc(Node, Memo0, Count, Memo)
   ).

% --- helpers ---------------------------------------------------------------

transpose_raster([], []).
transpose_raster([Row|Rows], Columns) :-
   transpose_rows(Row, [Row|Rows], Columns).

transpose_rows([], _, []).
transpose_rows([_|More], Rows, [Column|Columns]) :-
   maplist(split_head, Rows, Column, Rests),
   transpose_rows(More, Rests, Columns).

split_head([Head|Tail], Head, Tail).
