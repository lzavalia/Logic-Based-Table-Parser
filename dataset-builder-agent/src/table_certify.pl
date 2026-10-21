% Certificate generator for geometric labelability.
%
% Given a raster and a boundary (Hmd, Vmd), builds a certificate that the
% table can be labelled geometrically, or explains why it cannot. The
% definition, the certificate format and the checks are in
% certificate_kernel.pl. This file is NOT trusted: every certificate it
% returns has been accepted by the kernel, and anyone relying on a written
% certificate checks it again with the kernel alone:
%
%   swipl -p certificate_kernel=<directory of certificate_kernel.pl> CERT.pl
%
% which exits with status 0 if the certificate is accepted and 1 if not.
%
% certify_layout/5 builds the version 2 certificate of a table split into
% subtables (layout_subtables/4 of parse_constraints.pl), certifying each
% subtable with certify/5.
%
% Example:
%   ?- certify([[0,1],[2,3]], 1, 1, R).
%   R = certificate([certificate_version(1), raster([[0,1],[2,3]]),
%                    boundary(1,1), claim(columns), column_path(1,[1])]).

:- use_module(certificate_kernel).

% certify(+Raster, +Hmd, +Vmd, -Result)
% certify(+Raster, +Hmd, +Vmd, +Uid, -Result)
% Result is certificate(Facts), proving the columns claim if it holds and
% otherwise the rows claim, or not_labelable([columns-Why, rows-Why]) with
% the kernel's reason for rejecting each claim. Uid, if not `none`, is
% recorded as table_uid/1.
certify(Raster, Hmd, Vmd, Result) :-
   certify(Raster, Hmd, Vmd, none, Result).

certify(Raster, Hmd, Vmd, Uid, Result) :-
   claim_facts(columns, Raster, Hmd, Vmd, Uid, ColumnFacts),
   check_certificate(ColumnFacts, ColumnVerdict),
   (  ColumnVerdict == accepted
   -> Result = certificate(ColumnFacts)
   ;  claim_facts(rows, Raster, Hmd, Vmd, Uid, RowFacts),
      check_certificate(RowFacts, RowVerdict),
      (  RowVerdict == accepted
      -> Result = certificate(RowFacts)
      ;  ColumnVerdict = rejected(ColumnWhy),
         RowVerdict = rejected(RowWhy),
         Result = not_labelable([columns-ColumnWhy, rows-RowWhy])
      )
   ).

% claim_facts(+Claim, +Raster, +Hmd, +Vmd, +Uid, -Facts): the certificate
% for Claim, whether or not the kernel will accept it. A raster the kernel
% cannot read as a rectangle gets no paths; the kernel then rejects it.
claim_facts(Claim, Raster, Hmd, Vmd, Uid, Facts) :-
   (  Uid == none -> UidFacts = [] ; UidFacts = [table_uid(Uid)] ),
   (  catch(claim_paths(Claim, Raster, Hmd, Vmd, PathFacts), _, fail)
   -> true
   ;  PathFacts = []
   ),
   append([ [certificate_version(1)], UidFacts,
            [raster(Raster), boundary(Hmd, Vmd), claim(Claim)],
            PathFacts ],
          Facts).

claim_paths(columns, Raster, Hmd, Vmd, Facts) :-
   axis_paths(Raster, Hmd, Vmd, Paths),
   findall(column_path(J, Path), member(J-Path, Paths), Facts).
claim_paths(rows, Raster, Hmd, Vmd, Facts) :-
   transpose_raster(Raster, Transposed),
   axis_paths(Transposed, Vmd, Hmd, Paths),
   findall(row_path(I, Path), member(I-Path, Paths), Facts).

% certify_layout(+Raster, +Separators, +Subtables, +Uid, -Result)
% The version 2 certificate of a table split into subtables, as given by
% layout_subtables/4 of parse_constraints.pl: Separators is a list of
% separator(Row, Cols) and Subtables a list of subtable(Rows, Cols, Hmd, Vmd),
% subtable K being the K-th. Each subtable is certified like a table of its
% own (certify/5) and its facts are keyed by K. Result is
% certificate(Facts), or not_labelable(Reasons) with K-Why for every
% subtable certify/5 finds not labelable (Why as in certify/5), or
% rejected(Why) if every subtable is labelable but the kernel rejects the
% whole, e.g. because the subtables do not partition the table.
certify_layout(Raster, Separators, Subtables, Uid, Result) :-
   findall(K-Sub, nth0(K, Subtables, Sub), Keyed),
   maplist(certify_subtable(Raster), Keyed, Results),
   findall(K-Why, member(K-not_labelable(Why), Results), Unlabelable),
   (  Unlabelable \== []
   -> Result = not_labelable(Unlabelable)
   ;  (  Uid == none -> UidFacts = [] ; UidFacts = [table_uid(Uid)] ),
      findall(SubFact,
              ( member(K-certificate(SubFacts), Results),
                member(SubFact0, SubFacts),
                keyed_subtable_fact(K, Subtables, SubFact0, SubFact) ),
              KeyedFacts),
      append([ [certificate_version(2)], UidFacts, [raster(Raster)],
               Separators, KeyedFacts ],
             Facts),
      check_certificate(Facts, Verdict),
      (  Verdict == accepted
      -> Result = certificate(Facts)
      ;  Verdict = rejected(Why),
         Result = rejected(Why)
      )
   ).

certify_subtable(Raster, K-subtable(Rows, Cols, Hmd, Vmd), K-Result) :-
   view_raster(Raster, Rows, Cols, View),
   certify(View, Hmd, Vmd, none, Result).

% The version 1 facts of subtable K, keyed; its raster becomes subtable/3.
keyed_subtable_fact(K, Subtables, raster(_), subtable(K, Rows, Cols)) :-
   nth0(K, Subtables, subtable(Rows, Cols, _, _)).
keyed_subtable_fact(K, _, boundary(Hmd, Vmd), boundary(K, Hmd, Vmd)).
keyed_subtable_fact(K, _, claim(Claim), claim(K, Claim)).
keyed_subtable_fact(K, _, column_path(J, Path), column_path(K, J, Path)).
keyed_subtable_fact(K, _, row_path(I, Path), row_path(K, I, Path)).

view_raster(Raster, Rows, Cols, View) :-
   findall(Row,
           ( member(R, Rows), nth0(R, Raster, Full),
             findall(Id, ( member(C, Cols), nth0(C, Full, Id) ), Row) ),
           View).

% write_certificate(+File, +Facts): writes Facts as a Prolog program that
% loads the kernel and checks itself when run. The kernel is located through
% the certificate_kernel search path, so whoever runs the certificate decides
% which kernel to trust; the certificate cannot choose its own checker.
write_certificate(File, Facts) :-
   setup_call_cleanup(
      open(File, write, Stream, [encoding(utf8)]),
      write_certificate_stream(Stream, Facts),
      close(Stream)).

write_certificate_stream(Stream, Facts) :-
   format(Stream,
          "% Geometric labelability certificate, generated by table_certify.pl.~n\c
           % Check it with the trusted kernel only:~n\c
           %   swipl -p certificate_kernel=<directory of certificate_kernel.pl> <this file>~n\c
           % Exit status 0: accepted. 1: rejected.~n~n\c
           :- use_module(certificate_kernel(certificate_kernel)).~n\c
           :- initialization(check_loaded_certificate, main).~n~n",
          []),
   forall(member(Fact, Facts), portray_clause(Stream, Fact)).
