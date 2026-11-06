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
% Version 2 certifies a table made of several subtables, each one labelled
% on its own, as for a table with metadata in the middle (table_layouts/2 of
% parse_constraints.pl):
%   certificate_version(2).
%   table_uid(Uid).                  optional, informational
%   raster(Rows).
%   separator(Row, Cols).            zero or more: slots set aside
%   subtable(K, Rows, Cols).         K = 0, 1, ..: the subtable's rows and
%                                    columns, increasing indices into raster
%   boundary(K, Hmd, Vmd).           one per subtable, and
%   claim(K, Claim).                 the version 1 facts of the subtable,
%   column_path(K, J, Path).         keyed by K; J, I and the paths are
%   row_path(K, I, Path).            those of the subtable alone
%
% Subtable K is the raster made of the slots at Rows x Cols. It must pass
% every version 1 check at its boundary, and together the subtables and
% separators must partition the table:
%   - every slot is in a separator or in a subtable, never both;
%   - a slot in several subtables has the same role (HMD, VMD or data) in
%     each, and a data slot is in one subtable only;
%   - all slots of a cell have the same role, separator included;
%   - all slots of a data cell are in the same subtable.
% So a header cell may head several subtables, but data is never shared, no
% cell is split between data and metadata, and no slot is left unlabelled.
%
% Either version may also carry a typing section, which states the type of
% every cell of the raster and how it was reached: by the deterministic
% rules of a type DSL program, or by a model following the program's
% guidelines (type_dsl_engine.pl, table_type_abstraction.pl and
% type_guidelines.pl hold the semantics that this kernel checks again):
%   typing_version(1).
%   type_program(Name, Sha256).      optional, informational
%   type_rule(N, Origin, Pattern, Type).  N = 0, 1, ..: the rules in program
%                                    order; Pattern is equals(S), prefix(S),
%                                    suffix(S), regex(R), and(P, Q), or(P, Q)
%                                    or not(P), on the normalized text
%   type_subtype(Sub, Super).        the declared subtypes, by name
%   guideline(N, Prompt, Type).      N = 0, 1, ..: the guidelines, in order
%   cell_text(Id, Text).             the text of every cell of the raster,
%   synthetic_cell(Id).              or that it is padding (typed empty)
%   cell_type(Id, Type, Derivation). one per cell of the raster
% Derivation is one of
%   rules                  the rules decide Type and the cell is not routed
%                          to the guidelines
%   guideline(Batch)       a model chose Type for the routed cell (in the
%                          guideline batch Batch)
%   guideline_none(Batch)  a model was asked and kept the rule type
%   guideline_pending      the cell was routed but has no usable answer yet,
%                          so the rule type stands
% The kernel replays the rules: it normalizes each text (trimmed, runs of
% white space made one space), runs every rule on it (regexes match the
% whole text, with PCRE) and takes the most specific matched type, the first
% matching rule deciding between unrelated ones; no match is untyped, empty
% text empty. From that rule type it decides whether the cell is routed: the
% rule type is not empty, some guideline type lies strictly below it (or it
% is untyped and the text has a letter), and the text is not empty. A cell
% that is not routed must be derived by rules; a routed one must not be, and
% a model may only have chosen one of its allowed types. So everything the
% rules decide is proved, and what a model decided is stated as an
% assumption: which answer it gave is not checked, only that it was allowed.
% A typing section needs library(pcre); without it the certificate is
% rejected (typing_needs_pcre).
%
% Either version may also carry, at most once,
%   checking_kernel(Sha256, Source).  the source text of a kernel, and the
%                                    SHA-256 of its UTF-8 bytes in hex
% which makes the certificate self-contained: run as a program, it loads
% this source as its checker, after checking the hash, and prints the hash
% (table_certify.pl writes the program). The kernel only checks that the
% hash is that of the source. Whether the embedded kernel is one to trust
% is for whoever runs the certificate to decide, by comparing the printed
% hash with that of a kernel they trust, or by checking the certificate as
% data with such a kernel instead (check_certificate_file/2), which never
% runs the embedded one.
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
            transpose_raster/2,           % +Raster, -Transposed
            text_sha256/2,                % +Text, -Hex
            typing_report/2,              % +Facts, -Lines
            typing_explanation/2          % +Facts, -Lines
          ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(pairs)).
:- use_module(library(assoc)).
:- use_module(library(sha)).
% Only a typing section needs PCRE, so a kernel without it still checks the
% geometry.
:- catch(use_module(library(pcre)), _, true).

% certificate_fact(Version, Name, Arity)
certificate_fact(_, certificate_version, 1).
certificate_fact(_, table_uid, 1).
certificate_fact(_, checking_kernel, 2).
certificate_fact(_, raster, 1).
certificate_fact(1, boundary, 2).
certificate_fact(1, claim, 1).
certificate_fact(1, column_path, 2).
certificate_fact(1, row_path, 2).
certificate_fact(2, separator, 2).
certificate_fact(2, subtable, 3).
certificate_fact(2, boundary, 3).
certificate_fact(2, claim, 2).
certificate_fact(2, column_path, 3).
certificate_fact(2, row_path, 3).
certificate_fact(_, Name, Arity) :- typing_fact_signature(Name, Arity).

typing_fact_signature(typing_version, 1).
typing_fact_signature(type_program, 2).
typing_fact_signature(type_rule, 4).
typing_fact_signature(type_subtype, 2).
typing_fact_signature(guideline, 3).
typing_fact_signature(cell_text, 2).
typing_fact_signature(synthetic_cell, 1).
typing_fact_signature(cell_type, 3).

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
   setof(Name/Arity, Version^certificate_fact(Version, Name, Arity), Signatures),
   findall(Fact,
           ( member(Name/Arity, Signatures),
             current_predicate(user:Name/Arity),
             functor(Fact, Name, Arity),
             clause(user:Fact, true) ),
           Facts),
   check_certificate(Facts, Verdict),
   (  Verdict == accepted
   -> format("certificate accepted~n"),
      typing_report(Facts, Report),
      forall(member(Line, Report), format("~s~n", [Line])),
      current_prolog_flag(argv, Argv),
      (  memberchk('--explain', Argv)
      -> typing_explanation(Facts, Lines),
         forall(member(Line, Lines), format("~s~n", [Line]))
      ;  true
      )
   ;  format(user_error, "certificate rejected: ~q~n", [Verdict]),
      fail
   ).

% --- checks, in order ------------------------------------------------------

check_steps(Facts) :-
   require(is_list(Facts), not_a_fact_list),
   facts_named(certificate_version, 1, Facts, Versions),
   (  Versions = [certificate_version(Version)], memberchk(Version, [1, 2])
   -> forall(member(Fact, Facts), known_fact(Version, Fact))
   ;  forall(member(Fact, Facts), known_fact(_AnyVersion, Fact))
   ),
   one_fact(certificate_version(Version), Facts),
   require(memberchk(Version, [1, 2]), unsupported_version(Version)),
   optional_fact(table_uid(_), Facts),
   optional_fact(checking_kernel(_, _), Facts),
   forall(member(checking_kernel(Sha, Source), Facts),
          check_embedded_kernel(Sha, Source)),
   one_fact(raster(Raster), Facts),
   require(rectangular_raster(Raster, Rows, Cols), raster_not_rectangular),
   rectangular_cells(Raster),
   check_version(Version, Facts, Raster, Rows, Cols),
   check_typing(Facts, Raster).

check_version(1, Facts, Raster, Rows, Cols) :-
   one_fact(boundary(Hmd, Vmd), Facts),
   one_fact(claim(Claim), Facts),
   check_table(Raster, Rows, Cols, Hmd, Vmd, Claim, Facts).
check_version(2, Facts, Raster, Rows, Cols) :-
   subtable_keys(Facts, Keys),
   foldl(check_subtable(Facts, Raster, Rows, Cols), Keys, [], Roles),
   separator_slots(Facts, Rows, Cols, Separators),
   check_partition(Raster, Separators, Roles).

% check_table(+Raster, +Rows, +Cols, +Hmd, +Vmd, +Claim, +PathFacts): the
% version 1 checks of a table whose cells are rectangles. PathFacts holds
% its column_path/2 or row_path/2 facts.
check_table(Raster, Rows, Cols, Hmd, Vmd, Claim, PathFacts) :-
   require(( integer(Hmd), integer(Vmd),
             between(0, Rows, Hmd), Hmd < Rows,
             between(0, Cols, Vmd), Vmd < Cols ),
           boundary_out_of_range(Hmd, Vmd)),
   closed_boundary(Raster, Hmd, Vmd),
   claim_axis(Claim, PathFacts, Raster, Hmd, Vmd, AxisRaster, AxisHmd, AxisVmd, Claimed),
   axis_labelable(AxisRaster, AxisHmd, AxisVmd, Claimed).

require(Goal, Reason) :-
   (  call(Goal)
   -> true
   ;  throw(certificate_rejected(Reason))
   ).

% Without a usable version, Version is unbound and a fact of any version is
% known, so the version itself is reported next.
known_fact(Version, Fact) :-
   require(( callable(Fact), functor(Fact, Name, Arity),
             certificate_fact(Version, Name, Arity) ),
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

% one_keyed(+Template, +Facts): Template, with its key bound, matches exactly
% one fact of Facts, which it is unified with.
one_keyed(Template, Facts) :-
   include(subsumes_term(Template), Facts, Found),
   functor(Template, Name, Arity),
   arg(1, Template, Key),
   require(Found = [Template], expected_one_fact(Name/Arity, Key)).

% --- the embedded kernel ---------------------------------------------------

check_embedded_kernel(Sha, Source) :-
   require(( string(Source), atom(Sha) ), embedded_kernel_malformed),
   text_sha256(Source, Actual),
   require(Actual == Sha, embedded_kernel_hash_mismatch(Sha, Actual)).

% text_sha256(+Text, -Hex): the SHA-256 of Text's UTF-8 bytes, as a
% lower-case hex atom (the same as `shasum -a 256` of a UTF-8 file).
text_sha256(Text, Hex) :-
   sha_hash(Text, Hash, [algorithm(sha256), encoding(utf8)]),
   hash_atom(Hash, Hex).

% --- version 2: subtables --------------------------------------------------

% subtable_keys(+Facts, -Keys): the subtables are numbered 0 .. N-1, N >= 1,
% and every keyed fact names one of them.
subtable_keys(Facts, Keys) :-
   findall(K, member(subtable(K, _, _), Facts), Keys0),
   msort(Keys0, Keys),
   length(Keys, N),
   require(N >= 1, no_subtables),
   Last is N - 1,
   require(numlist_or_empty(0, Last, Keys), subtables_not_numbered(Keys)),
   forall(( member(Fact, Facts), keyed_fact(Fact, K) ),
          require(memberchk(K, Keys), unknown_subtable(Fact))).

numlist_or_empty(First, Last, List) :-
   findall(I, between(First, Last, I), List).

keyed_fact(boundary(K, _, _), K).
keyed_fact(claim(K, _), K).
keyed_fact(column_path(K, _, _), K).
keyed_fact(row_path(K, _, _), K).

% check_subtable(+Facts, +Raster, +Rows, +Cols, +K, +Roles0, -Roles)
% Subtable K passes the version 1 checks; Roles adds its slots as
% (R-C)-(K-Role), R and C in the whole raster.
check_subtable(Facts, Raster, Rows, Cols, K, Roles0, Roles) :-
   one_keyed(subtable(K, SubRows, SubCols), Facts),
   one_keyed(boundary(K, Hmd, Vmd), Facts),
   one_keyed(claim(K, Claim), Facts),
   require(index_list(SubRows, Rows), subtable_rows_invalid(K)),
   require(index_list(SubCols, Cols), subtable_columns_invalid(K)),
   findall(column_path(J, Path), member(column_path(K, J, Path), Facts), ColumnPaths),
   findall(row_path(I, Path), member(row_path(K, I, Path), Facts), RowPaths),
   append(ColumnPaths, RowPaths, PathFacts),
   view(Raster, SubRows, SubCols, View),
   length(SubRows, ViewRows),
   length(SubCols, ViewCols),
   catch(( rectangular_cells(View),
           check_table(View, ViewRows, ViewCols, Hmd, Vmd, Claim, PathFacts) ),
         certificate_rejected(Why),
         throw(certificate_rejected(subtable_rejected(K, Why)))),
   findall((R-C)-(K-Role),
           ( nth0(I, SubRows, R), nth0(J, SubCols, C),
             slot_role(Hmd, Vmd, I, J, Role) ),
           Mine),
   append(Roles0, Mine, Roles).

% index_list(+List, +Size): a non-empty, strictly increasing list of
% indices below Size.
index_list(List, Size) :-
   is_list(List),
   List = [_|_],
   forall(member(X, List), ( integer(X), X >= 0, X < Size )),
   sort(List, Sorted),
   Sorted == List.

% The roles of a table split at (Hmd, Vmd); the corner above the VMD is HMD.
slot_role(Hmd, _, I, _, hmd) :- I < Hmd, !.
slot_role(_, Vmd, _, J, vmd) :- J < Vmd, !.
slot_role(_, _, _, _, data).

view(Raster, Rows, Cols, View) :-
   findall(Row,
           ( member(R, Rows), nth0(R, Raster, Full),
             findall(Id, ( member(C, Cols), nth0(C, Full, Id) ), Row) ),
           View).

% separator_slots(+Facts, +Rows, +Cols, -Slots): the R-C slots of every
% separator/2 fact, no slot twice.
separator_slots(Facts, Rows, Cols, Slots) :-
   findall(separator(R, SepCols), member(separator(R, SepCols), Facts), Separators),
   forall(member(separator(R, SepCols), Separators),
          require(( integer(R), R >= 0, R < Rows, index_list(SepCols, Cols) ),
                  separator_invalid(R, SepCols))),
   findall(R-C, ( member(separator(R, SepCols), Separators), member(C, SepCols) ),
           Slots0),
   msort(Slots0, Slots),
   (  append(_, [Slot, Slot|_], Slots)
   -> throw(certificate_rejected(separators_overlap(Slot)))
   ;  true
   ).

% check_partition(+Raster, +Separators, +Roles)
check_partition(Raster, Separators, Roles) :-
   keysort(Roles, Sorted),
   group_pairs_by_key(Sorted, BySlot),
   list_to_assoc(BySlot, SlotRoles),
   forall(member(Slot, Separators),
          require(\+ get_assoc(Slot, SlotRoles, _),
                  separator_overlaps_subtable(Slot))),
   empty_assoc(Empty),
   foldl(put_separator, Separators, Empty, SepAssoc),
   findall(Id-(Slot-Role),
           ( nth0(R, Raster, Row), nth0(C, Row, Id), Slot = R-C,
             slot_label(Slot, SlotRoles, SepAssoc, Role) ),
           Labelled),
   forall(member(_-(Slot-Role), Labelled),
          require(Role \== uncovered, slot_not_covered(Slot))),
   forall(member(_-(Slot-Role), Labelled),
          require(Role \== disagree, slot_roles_disagree(Slot))),
   forall(member(Slot-Entries, BySlot),
          require(( Entries = [_-data] -> true ; \+ memberchk(_-data, Entries) ),
                  data_slot_shared(Slot))),
   keysort(Labelled, ByCell0),
   group_pairs_by_key(ByCell0, ByCell),
   forall(member(Id-Slots, ByCell),
          (  pairs_values(Slots, CellRoles),
             sort(CellRoles, Distinct),
             require(Distinct = [_], cell_roles_disagree(Id)),
             (  Distinct == [data]
             -> findall(K, ( member(S-_, Slots), get_assoc(S, SlotRoles, [K-_]) ), Ks0),
                sort(Ks0, Ks),
                require(Ks = [_], data_cell_split(Id))
             ;  true
             )
          )).

put_separator(Slot, Assoc0, Assoc) :-
   put_assoc(Slot, Assoc0, separator, Assoc).

% slot_label(+Slot, +SlotRoles, +Separators, -Role): separator, the one role
% every subtable holding Slot gives it, uncovered or disagree.
slot_label(Slot, SlotRoles, Separators, Role) :-
   (  get_assoc(Slot, Separators, _)
   -> Role = separator
   ;  get_assoc(Slot, SlotRoles, Entries)
   -> pairs_values(Entries, Roles0),
      sort(Roles0, Roles),
      (  Roles = [Role]
      -> true
      ;  Role = disagree
      )
   ;  Role = uncovered
   ).

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
% Facts are the version 1 path facts: column_path/2 and row_path/2.
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

% --- typing ----------------------------------------------------------------

% check_typing(+Facts, +Raster): the typing section, if there is one.
check_typing(Facts, Raster) :-
   (  has_typing(Facts)
   -> one_fact(typing_version(TypingVersion), Facts),
      require(TypingVersion == 1, unsupported_typing_version(TypingVersion)),
      optional_fact(type_program(_, _), Facts),
      require(pcre_available, typing_needs_pcre),
      cell_derivations(Facts, Raster, _)
   ;  true
   ).

has_typing(Facts) :-
   member(Fact, Facts),
   functor(Fact, Name, Arity),
   typing_fact_signature(Name, Arity), !.

pcre_available :-
   current_predicate(pcre:re_match/2).

% cell_derivations(+Facts, +Raster, -Cells): checks the typing of every cell
% of Raster, and that every cell fact names one; Cells is
% cell(Id, Text, Type, Derivation, RuleType, Why, Allowed) for each, in id
% order. Why is rule(Origin), no_rule, empty_text or synthetic; Allowed the
% guideline types the cell may take, [] if it is not routed.
cell_derivations(Facts, Raster, Cells) :-
   typing_program(Facts, Program),
   findall(Id, ( member(Row, Raster), member(Id, Row) ), Ids0),
   sort(Ids0, Ids),
   forall(( member(Fact, Facts), cell_fact_id(Fact, Id) ),
          require(ord_memberchk(Id, Ids), typing_fact_for_unknown_cell(Fact))),
   maplist(cell_derivation(Program, Facts), Ids, Cells).

cell_fact_id(cell_type(Id, _, _), Id).
cell_fact_id(cell_text(Id, _), Id).
cell_fact_id(synthetic_cell(Id), Id).

cell_derivation(Program, Facts, Id,
                cell(Id, Text, Type, Derivation, RuleType, Why, Allowed)) :-
   findall(T-D, member(cell_type(Id, T, D), Facts), Types),
   require(Types = [Type-Derivation], expected_one_cell_type(Id)),
   findall(text(T), member(cell_text(Id, T), Facts), Texts0),
   findall(synthetic, member(synthetic_cell(Id), Facts), Texts1),
   append(Texts0, Texts1, Texts),
   require(Texts = [Source], expected_one_cell_text(Id)),
   (  Source = text(Text)
   -> require(string(Text), cell_text_not_a_string(Id))
   ;  Text = synthetic
   ),
   rule_type(Program, Source, RuleType, Why, Normalized),
   routes(Program, RuleType, Normalized, Allowed),
   check_derivation(Derivation, Id, Type, RuleType, Allowed).

check_derivation(rules, Id, Type, RuleType, Allowed) :- !,
   require(Allowed == [], routed_cell_typed_by_rules(Id, RuleType, Allowed)),
   require(Type == RuleType, rule_type_mismatch(Id, Type, RuleType)).
check_derivation(guideline(Batch), Id, Type, _, Allowed) :- !,
   require(string(Batch), derivation_malformed(Id)),
   require(Allowed \== [], cell_not_routed(Id)),
   require(memberchk(Type, Allowed), guideline_type_not_allowed(Id, Type, Allowed)).
check_derivation(guideline_none(Batch), Id, Type, RuleType, Allowed) :- !,
   require(string(Batch), derivation_malformed(Id)),
   require(Allowed \== [], cell_not_routed(Id)),
   require(Type == RuleType, rule_type_mismatch(Id, Type, RuleType)).
check_derivation(guideline_pending, Id, Type, RuleType, Allowed) :- !,
   require(Allowed \== [], cell_not_routed(Id)),
   require(Type == RuleType, rule_type_mismatch(Id, Type, RuleType)).
check_derivation(Derivation, Id, _, _, _) :-
   throw(certificate_rejected(unknown_derivation(Id, Derivation))).

% typing_program(+Facts, -Program): program(Rules, Subtypes, GuidelineTypes),
% Rules the N-rule(Origin, Pattern, Type) in order, Subtypes Sub-Super
% pairs and GuidelineTypes the guideline types in order of their first
% guideline.
typing_program(Facts, program(Rules, Subtypes, GuidelineTypes)) :-
   findall(N-rule(O, P, T), member(type_rule(N, O, P, T), Facts), Rules0),
   numbered(Rules0, type_rules_not_numbered, Rules),
   forall(member(N-rule(O, P, T), Rules),
          (  require(( string(O), atom(T), valid_pattern(P) ), rule_malformed(N)),
             forall(sub_regex(P, R),
                    require(catch(( re_compile_anchored(R), true ), _, fail),
                            rule_regex_invalid(N))) )),
   findall(Sub-Super, member(type_subtype(Sub, Super), Facts), Subtypes),
   forall(member(Sub-Super, Subtypes),
          require(( atom(Sub), atom(Super) ), type_subtype_malformed(Sub, Super))),
   findall(N-guideline(Pr, T), member(guideline(N, Pr, T), Facts), Guidelines0),
   numbered(Guidelines0, guidelines_not_numbered, Guidelines),
   forall(member(N-guideline(Pr, T), Guidelines),
          require(( string(Pr), atom(T) ), guideline_malformed(N))),
   findall(T, member(_-guideline(_, T), Guidelines), Ts),
   list_to_set(Ts, GuidelineTypes).

% numbered(+Pairs, +Reason, -Sorted): keys 0 .. N-1, each once.
numbered(Pairs, Reason, Sorted) :-
   keysort(Pairs, Sorted),
   pairs_keys(Sorted, Keys),
   length(Keys, Count),
   Last is Count - 1,
   require(numlist_or_empty(0, Last, Keys), Reason).

valid_pattern(equals(S)) :- string(S).
valid_pattern(prefix(S)) :- string(S).
valid_pattern(suffix(S)) :- string(S).
valid_pattern(regex(R)) :- string(R).
valid_pattern(and(P, Q)) :- valid_pattern(P), valid_pattern(Q).
valid_pattern(or(P, Q)) :- valid_pattern(P), valid_pattern(Q).
valid_pattern(not(P)) :- valid_pattern(P).

sub_regex(regex(R), R).
sub_regex(and(P, Q), R) :- ( sub_regex(P, R) ; sub_regex(Q, R) ).
sub_regex(or(P, Q), R) :- ( sub_regex(P, R) ; sub_regex(Q, R) ).
sub_regex(not(P), R) :- sub_regex(P, R).

% A regex must match the whole text, as type_dsl_engine compiles it.
anchored(R, Anchored) :-
   string_concat("\\A(?:", R, Open),
   string_concat(Open, ")\\z", Anchored).

re_compile_anchored(R) :-
   anchored(R, Anchored),
   pcre:re_compile(Anchored, _, []).

matches(equals(S), Text) :- Text == S.
matches(prefix(S), Text) :- string_concat(S, _, Text).
matches(suffix(S), Text) :- string_concat(_, S, Text).
matches(regex(R), Text) :-
   anchored(R, Anchored),
   pcre:re_match(Anchored, Text).
matches(and(P, Q), Text) :- matches(P, Text), matches(Q, Text).
matches(or(P, Q), Text) :- ( matches(P, Text) -> true ; matches(Q, Text) ).
matches(not(P), Text) :- \+ matches(P, Text).

% rule_type(+Program, +Source, -RuleType, -Why, -Normalized)
% Source is text(Text) or synthetic.
rule_type(_, synthetic, empty, synthetic, "") :- !.
rule_type(program(Rules, Subtypes, _), text(Text), RuleType, Why, Normalized) :-
   normalize_text(Text, Normalized),
   (  Normalized == ""
   -> RuleType = empty, Why = empty_text
   ;  findall(O-T, ( member(_-rule(O, P, T), Rules), once(matches(P, Normalized)) ),
              Matched),
      (  Matched == []
      -> RuleType = untyped, Why = no_rule
      ;  pairs_values(Matched, Types),
         include(most_specific(Subtypes, Types), Matched, Specific),
         % Types that are subtypes of each other (a cycle) eliminate one
         % another; the first matching rule then decides.
         (  Specific = [Origin-RuleType|_]
         -> true
         ;  Matched = [Origin-RuleType|_]
         ),
         Why = rule(Origin)
      )
   ).

normalize_text(Text, Normalized) :-
   split_string(Text, " \t\n\r\u00A0", " \t\n\r\u00A0", Parts0),
   exclude(==(""), Parts0, Parts),
   atomic_list_concat(Parts, ' ', Atom),
   atom_string(Atom, Normalized).

% A matched type is most specific when no other matched type is a strict
% subtype of it.
most_specific(Subtypes, Types, _-Type) :-
   \+ ( member(Other, Types),
        Other \== Type,
        strict_subtype(Subtypes, Other, Type) ).

strict_subtype(Subtypes, Sub, Super) :-
   strict_subtype(Subtypes, Sub, Super, [Sub]).

strict_subtype(Subtypes, Sub, Super, Seen) :-
   member(Sub-Mid, Subtypes),
   \+ memberchk(Mid, Seen),
   (  Mid == Super
   -> true
   ;  strict_subtype(Subtypes, Mid, Super, [Mid|Seen])
   ),
   !.

% routes(+Program, +RuleType, +Normalized, -Allowed): the guideline types a
% cell may take, [] when it is not routed to the guidelines.
routes(program(_, Subtypes, GuidelineTypes), RuleType, Normalized, Allowed) :-
   (  RuleType \== empty,
      Normalized \== "",
      (  RuleType == untyped
      -> has_letter(Normalized),
         Allowed0 = GuidelineTypes
      ;  include(below(Subtypes, RuleType), GuidelineTypes, Allowed0)
      )
   -> Allowed = Allowed0
   ;  Allowed = []
   ).

below(Subtypes, RuleType, Type) :-
   strict_subtype(Subtypes, Type, RuleType).

% A letter: alphanumeric, not a digit, not an underscore.
has_letter(Text) :-
   sub_string(Text, _, 1, _, Char),
   char_type(Char, alpha),
   \+ char_type(Char, digit(_)),
   Char \== "_", !.

% --- typing reports --------------------------------------------------------

% typing_report(+Facts, -Lines): for an accepted certificate with a typing
% section, a summary of how its cells were typed; [] without one.
typing_report(Facts, Lines) :-
   (  has_typing(Facts),
      member(raster(Raster), Facts)
   -> cell_derivations(Facts, Raster, Cells),
      length(Cells, Total),
      aggregate_count(Cells, rule_typed, Rule),
      aggregate_count(Cells, empty_or_untyped, Plain),
      aggregate_count(Cells, model_chosen, Chosen),
      aggregate_count(Cells, model_kept, Kept),
      aggregate_count(Cells, pending, Pending),
      format(string(L1), "typing: ~d cell(s), each checked again by this kernel", [Total]),
      format(string(L2), "  ~d typed by deterministic rules (replayed), ~d empty or untyped by the rules",
             [Rule, Plain]),
      format(string(L3), "  ~d typed by a model following the guidelines (assumed; checked to be allowed)",
             [Chosen]),
      format(string(L4), "  ~d kept at the rule type by a model, ~d routed to the guidelines without an answer",
             [Kept, Pending]),
      Lines = [L1, L2, L3, L4]
   ;  Lines = []
   ).

aggregate_count(Cells, Class, Count) :-
   include(cell_class(Class), Cells, In),
   length(In, Count).

cell_class(rule_typed, cell(_, _, T, rules, _, _, _)) :- \+ memberchk(T, [empty, untyped]).
cell_class(empty_or_untyped, cell(_, _, T, rules, _, _, _)) :- memberchk(T, [empty, untyped]).
cell_class(model_chosen, cell(_, _, _, guideline(_), _, _, _)).
cell_class(model_kept, cell(_, _, _, guideline_none(_), _, _, _)).
cell_class(pending, cell(_, _, _, guideline_pending, _, _, _)).

% typing_explanation(+Facts, -Lines): one line per cell of an accepted
% certificate with a typing section, saying where its type comes from.
typing_explanation(Facts, Lines) :-
   (  has_typing(Facts),
      member(raster(Raster), Facts)
   -> cell_derivations(Facts, Raster, Cells),
      maplist(explain_cell, Cells, Lines)
   ;  Lines = []
   ).

explain_cell(cell(Id, Text, Type, Derivation, RuleType, Why, Allowed), Line) :-
   (  Text == synthetic
   -> Shown = "(padding)"
   ;  format(string(Shown), "~q", [Text])
   ),
   rule_reason(Why, RuleType, Reason),
   (  Derivation == rules
   -> format(string(Line), "cell ~w ~s: ~w, deterministic: ~s", [Id, Shown, Type, Reason])
   ;  Derivation = guideline(Batch)
   -> format(string(Line), "cell ~w ~s: ~w, chosen by a model (guideline batch ~s) from ~w; deterministic rule type ~w (~s)",
             [Id, Shown, Type, Batch, Allowed, RuleType, Reason])
   ;  Derivation = guideline_none(Batch)
   -> format(string(Line), "cell ~w ~s: ~w, deterministic (~s); a model (guideline batch ~s) kept it over ~w",
             [Id, Shown, Type, Reason, Batch, Allowed])
   ;  format(string(Line), "cell ~w ~s: ~w, deterministic (~s); routed to the guidelines (~w), no answer yet",
             [Id, Shown, Type, Reason, Allowed])
   ).

rule_reason(rule(Origin), _, Reason) :- format(string(Reason), "rule ~s", [Origin]).
rule_reason(no_rule, _, "no rule matches").
rule_reason(empty_text, _, "empty text").
rule_reason(synthetic, _, "padding cell").
