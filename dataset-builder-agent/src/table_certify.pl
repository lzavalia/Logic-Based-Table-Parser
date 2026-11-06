% Certificate generator for geometric labelability.
%
% Given a raster and a boundary (Hmd, Vmd), builds a certificate that the
% table can be labelled geometrically, or explains why it cannot. The
% definition, the certificate format and the checks are in
% certificate_kernel.pl. This file is NOT trusted: every certificate it
% returns has been accepted by the kernel, and anyone relying on a written
% certificate checks it again with a kernel alone. A written certificate
% carries a copy of the kernel (checking_kernel/2), so it checks itself with
% nothing but SWI-Prolog:
%
%   swipl CERT.pl
%
% which prints the SHA-256 of the kernel it carries and exits with status 0
% if the certificate is accepted and 1 if not. To check it with a kernel of
% your own instead, which never runs the copy, read it as data:
%
%   swipl -g "check_certificate_file('CERT.pl', V), print(V), nl" -t halt \
%         <your copy of certificate_kernel.pl>
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

% write_certificate(+File, +Facts): writes Facts, with the kernel added
% (certificate_with_kernel/2), as a Prolog program that checks itself when
% run. The program loads the embedded kernel only after checking it against
% its hash, and prints the hash, so whoever runs it can compare it with a
% kernel they trust; checked as data (check_certificate_file/2), the copy is
% never run.
write_certificate(File, Facts) :-
   certificate_with_kernel(Facts, WithKernel),
   setup_call_cleanup(
      open(File, write, Stream, [encoding(utf8)]),
      write_certificate_stream(Stream, WithKernel),
      close(Stream)).

% certificate_with_kernel(+Facts, -WithKernel): Facts as written: any
% checking_kernel/2 fact replaced by that of the loaded kernel, last, and
% the facts of each predicate together (in their order), so that the
% program loads without discontiguous-clause warnings.
certificate_with_kernel(Facts, WithKernel) :-
   exclude(is_checking_kernel, Facts, Plain),
   grouped_facts(Plain, Grouped),
   embedded_kernel(Kernel),
   append(Grouped, [Kernel], WithKernel).

is_checking_kernel(checking_kernel(_, _)).

grouped_facts(Facts, Grouped) :-
   findall(Name/Arity, ( member(Fact, Facts), functor(Fact, Name, Arity) ), Keys0),
   list_to_set(Keys0, Keys),
   findall(Fact,
           ( member(Name/Arity, Keys),
             member(Fact, Facts), functor(Fact, Name, Arity) ),
           Grouped).

% embedded_kernel(-Fact): checking_kernel(Sha256, Source) for the source
% file of the loaded certificate_kernel module. It is read with open/4:
% DeepClause replaces read_file_to_string/3 with a version that resolves
% paths differently.
embedded_kernel(checking_kernel(Sha, Source)) :-
   module_property(certificate_kernel, file(File)),
   setup_call_cleanup(open(File, read, In, [encoding(utf8)]),
                      read_string(In, _, Source),
                      close(In)),
   text_sha256(Source, Sha).

write_certificate_stream(Stream, Facts) :-
   format(Stream,
          "% Geometric labelability certificate, generated by table_certify.pl.~n\c
           % It carries its checking kernel, the source in checking_kernel/2. Run it:~n\c
           %   swipl <this file>~n\c
           % Exit status 0: accepted. 1: rejected. It prints the SHA-256 of the kernel~n\c
           % it carries; compare it with that of a kernel you trust, or check this file~n\c
           % as data with your own kernel (check_certificate_file/2), which never runs~n\c
           % the copy.~n~n",
          []),
   bootstrap_directive(Directive),
   portray_clause(Stream, Directive),
   nl(Stream),
   forall(member(Fact, Facts), portray_clause(Stream, Fact)).

% The main goal of a written certificate: check the embedded kernel against
% its hash, load it from the string, and check the facts with it.
bootstrap_directive(
   (:- initialization(
         ( checking_kernel(Sha, Source),
           use_module(library(sha)),
           sha_hash(Source, Hash, [algorithm(sha256), encoding(utf8)]),
           hash_atom(Hash, Actual),
           (  Actual == Sha
           -> format("checking kernel sha256 ~w~n", [Sha])
           ;  format(user_error, "the embedded kernel does not match its hash~n", []),
              halt(1)
           ),
           setup_call_cleanup(open_string(Source, In),
                              load_files(certificate_kernel, [stream(In)]),
                              close(In)),
           certificate_kernel:check_loaded_certificate ),
         main))).
