% The guideline step of the type DSL: rules type every cell, then the cells
% whose type only a model can refine are sent to one, in batches, with the
% program's guidelines as the instructions.
%
% Three stages, so that only the middle one needs a model:
%   1. guideline_requests/3 (this module, SWI-Prolog): route cells and write
%      papers/PMC<id>/guideline_requests.json, the prompt batches for the
%      (text, rule type) pairs not yet answered in the cache.
%   2. type_guidelines.dml (DeepClause): send each batch, check the answers
%      (guideline_answers.pl) and append them to the cache.
%   3. apply_guidelines/3 (this module): write papers/PMC<id>/guided_types.jsonl
%      from types.jsonl and the cache. Needs no model, so it is repeatable.
%
% guideline_agent.sh runs all of this, rule typing first. By hand, from
% dataset-builder-agent/src/, after type_dataset/2
% (table_type_abstraction.pl):
%   swipl -g 'use_module(type_guidelines),
%             guideline_requests("../type_dsl_examples/sci.tdsl", "dataset", S),
%             writeln(S)' -t halt
%   deepclause run type_guidelines.dml --headless
%   swipl -g 'use_module(type_guidelines),
%             apply_guidelines("../type_dsl_examples/sci.tdsl", "dataset", S),
%             writeln(S)' -t halt
%
% guideline_requests/4 and apply_guidelines/4 take the papers to work on: none
% (all papers) or a list of paper names.
%
% --- routing ---------------------------------------------------------------
%
% The guideline types are the types the program's guidelines decide, in
% guideline order. A cell is routed to the guideline step when
%   - no rule types it (type untyped) and it has a letter in it: it may take
%     any guideline type, or
%   - its rule type T has guideline types below it (G <: T, transitively):
%     it may take those.
% Every other cell keeps its rule type and the model never sees it. Empty
% cells are never routed. The answer "none" keeps the rule type.
%
% A type may have rules and guidelines both: a cell its rule matches takes it
% and, with no guideline types below it, is final; any other cell routed to
% the guideline step may still be given it.
%
% --- requests ------------------------------------------------------------------
%
% guideline_requests.json: {paper, program, program_sha256, batches}, each
% batch {batch_id, caption, prompt, items}, each item {id, text, rule_type,
% allowed}. A paper's distinct (text, rule type) pairs, in text order, are
% cut into batches of 40; a pair already answered in the cache is left out,
% and a paper with nothing to send has no request file.
%
% --- the cache ---------------------------------------------------------------
%
% dataset/cache/guideline_answers.jsonl holds one JSON object per answered
% pair: {program_sha256, text, rule_type, caption, answer, batch_id}, answer
% being a guideline type or "none". The key is (program_sha256, text,
% rule_type, caption), so a change to the program file invalidates its
% answers, and the latest line for a key wins. The caption is null unless
% the program sets enable_caption_analysis; then each table is batched on
% its own and its caption is part of the key and of the prompt.
%
% --- guided_types.jsonl ------------------------------------------------------
%
% The records of types.jsonl, in order, with every routed and answered
% cell's type, family, group and source replaced (source "guideline") and its rule
% type kept as rule_type, the type_raster updated, and counts extended with
% routed, guided (answered with a type), kept (answered "none") and pending
% (no usable answer yet).

:- module(type_guidelines, [
      guideline_requests/3,
      guideline_requests/4,
      apply_guidelines/3,
      apply_guidelines/4,
      guideline_types/2,
      guideline_routes/3,
      guideline_prompt/4,
      program_sha256/2,
      guideline_program/2,
      guideline_routed_cell/5,
      guideline_cache_rows/3
   ]).

:- if(exists_source(library(json))).
:- use_module(library(json)).
:- else.
:- use_module(library(http/json)).
:- endif.
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(assoc)).
:- use_module(library(readutil)).
:- use_module(library(filesex)).
:- use_module(library(crypto)).
:- use_module(type_dsl_engine).
:- use_module(table_type_abstraction).

batch_size(40).

% --- stage 1: requests -------------------------------------------------------

guideline_requests(TdslFile, DatasetDir, Summary) :-
   guideline_requests(TdslFile, DatasetDir, none, Summary).

guideline_requests(TdslFile, DatasetDir, Papers, Summary) :-
   program(TdslFile, Program),
   read_cache(DatasetDir, Program.sha, Cache),
   paper_dirs(DatasetDir, Papers, Dirs),
   foldl(paper_requests(Program, Cache), Dirs, 0-0, Batches-Items),
   length(Dirs, NumPapers),
   format(string(Summary), "~d paper(s): ~d batch(es), ~d cell text(s) to send",
          [NumPapers, Batches, Items]).

paper_requests(Program, Cache, Dir, B0-I0, B-I) :-
   paper_records(Dir, Pairs),
   file_base_name(Dir, Paper),
   findall(Group-(Key-Allowed),
           ( member(Record-Typed, Pairs),
             member(Cell, Typed.cells),
             routed_cell(Program, Record, Cell, Key, Allowed),
             \+ get_assoc(Key, Cache, _),
             group(Key, Record, Group) ),
           Found),
   sort(Found, Unique),                       % by group, then text
   group_pairs_by_key_sorted(Unique, Groups),
   foldl(group_batches(Program, Paper), Groups, Batches0-0, []-_),
   Batches = Batches0,
   directory_file_path(Dir, 'guideline_requests.json', Out),
   length(Batches, NB), length(Unique, NI),
   (  Batches == []
   -> ( exists_file(Out) -> delete_file(Out) ; true )
   ;  write_json(Out, json{paper:Paper, program:Program.path,
                           program_sha256:Program.sha, batches:Batches})
   ),
   B is B0 + NB, I is I0 + NI.

% Without caption analysis a paper is one group; with it, one per table.
group(key(_, _, null), _, paper) :- !.
group(_, Record, Record.table_uid).

group_pairs_by_key_sorted([], []).
group_pairs_by_key_sorted([G-P|T], [G-[P|Ps]|Gs]) :-
   same_group(G, T, Ps, Rest),
   group_pairs_by_key_sorted(Rest, Gs).

same_group(G, [G-P|T], [P|Ps], Rest) :- !, same_group(G, T, Ps, Rest).
same_group(_, Rest, [], Rest).

% group_batches(+Program, +Paper, +Group-Pairs, +Batches-N, -Tail-N1):
% difference list of batches, numbered from 1 within the paper.
group_batches(Program, Paper, _-Pairs, Batches-N0, Tail-N) :-
   chunks(Pairs, Chunks),
   foldl(chunk_batch(Program, Paper), Chunks, Batches-N0, Tail-N).

chunk_batch(Program, Paper, Chunk, [Batch|Tail]-N0, Tail-N) :-
   N is N0 + 1,
   format(string(Id), "~w/~d", [Paper, N]),
   Chunk = [key(_, _, Caption)-_|_],
   numbered_items(Chunk, 1, Items),
   guideline_prompt(Program, Items, Caption, Prompt),
   Batch = json{batch_id:Id, caption:Caption, prompt:Prompt, items:Items}.

chunks([], []) :- !.
chunks(List, [Chunk|Chunks]) :-
   batch_size(Size),
   length(List, Len),
   Take is min(Size, Len),
   length(Chunk, Take),
   append(Chunk, Rest, List),
   chunks(Rest, Chunks).

numbered_items([], _, []).
numbered_items([key(Text, RuleType, _)-Allowed|Pairs], N, [Item|Items]) :-
   atom_string(RuleType, RuleTypeS),
   maplist(atom_string, Allowed, AllowedS),
   number_string(N, Id),
   Item = json{id:Id, text:Text, rule_type:RuleTypeS, allowed:AllowedS},
   N1 is N + 1,
   numbered_items(Pairs, N1, Items).

% routed_cell(+Program, +Record, +TypedCell, -Key, -Allowed)
routed_cell(Program, Record, Cell, key(Text, RuleType, Caption), Allowed) :-
   atom_string(RuleType, Cell.type),          % types.jsonl holds strings
   RuleType \== empty,
   guideline_routes(Program.analyzer, RuleType, Allowed),
   Allowed \== [],
   cell_text(Record, Cell.cell_id, Text),
   Text \== "",
   ( RuleType == untyped -> has_letter(Text) ; true ),
   caption(Program, Record, Caption).

has_letter(Text) :-
   sub_string(Text, _, 1, _, Char),
   char_type(Char, alpha),
   \+ char_type(Char, digit(_)),
   Char \== "_", !.

caption(Program, Record, Caption) :-
   (  Program.caption_analysis == true,
      get_dict(context, Record, Context), is_dict(Context),
      get_dict(caption, Context, C), C \== null, C \== ""
   -> Caption = C
   ;  Caption = null
   ).

cell_text(Record, Id, Text) :-
   member(C, Record.cells), C.cell_id == Id, !,
   ( get_dict(text, C, T0), T0 \== null -> true ; T0 = "" ),
   split_string(T0, " \t\n\r ", " \t\n\r ", Parts0),
   exclude(==(""), Parts0, Parts),
   atomic_list_concat(Parts, ' ', A),
   atom_string(A, Text).

% guideline_types(+Analyzer, -Types): the type names guidelines decide, in
% the order of their first guideline. Guidelines that decide a type
% expression other than a name are not routed to.
guideline_types(Analyzer, Types) :-
   tdsl_analyzer_property(Analyzer, guidelines(Guidelines)),
   findall(T, member(_-ref(T), Guidelines), Ts),
   list_to_set(Ts, Types).

% guideline_routes(+Analyzer, +RuleType, -Allowed): the guideline types a
% cell of RuleType may take, in guideline order; [] if it is not routed.
guideline_routes(Analyzer, RuleType, Allowed) :-
   guideline_types(Analyzer, All),
   (  RuleType == untyped
   -> Allowed = All
   ;  include(below(Analyzer, RuleType), All, Allowed)
   ).

% A plain predicate, not a lambda: a lambda would copy the analyzer, with
% its compiled regexes, on every call.
below(Analyzer, RuleType, G) :-
   type_strict_subtype(Analyzer, G, RuleType).

% --- the prompt --------------------------------------------------------------

% guideline_prompt(+Program, +Items, +Caption, -Prompt)
guideline_prompt(Program, Items, Caption, Prompt) :-
   guideline_types(Program.analyzer, Types),
   tdsl_analyzer_property(Program.analyzer, guidelines(Guidelines)),
   findall(Line,
           ( member(T, Types),
             findall(P, member(P-ref(T), Guidelines), Ps),
             atomic_list_concat(Ps, '; or ', Desc),
             format(string(Line), "- ~w: ~w", [T, Desc]) ),
           TypeLines),
   atomic_list_concat(TypeLines, '\n', TypeText),
   % A batch whose cells all share their allowed types says so once.
   maplist(item_allowed, Items, Alloweds),
   sort(Alloweds, Distinct),
   (  Distinct = [_]
   -> Listing = "Each cell below has an id and its text, and it may take any of the types listed.",
      Show = false
   ;  Listing = "Each cell below has an id, its text and the types it may take.",
      Show = true
   ),
   maplist(cell_line(Show), Items, CellLines),
   atomic_list_concat(CellLines, '\n', CellText),
   (  Caption == null
   -> Basis = "Decide from the cell text alone; you do not see the rest of the table.",
      CaptionText = ""
   ;  Basis = "Decide from the cell text and the caption of the table it comes from.",
      json_quote(Caption, CQ),
      format(string(CaptionText), "Table caption: ~s\n\n", [CQ])
   ),
   Types = [Example|_],
   format(string(Prompt),
"You assign types to cells taken from tables in scientific papers. ~s For each cell choose the one allowed type whose description fits it best, or \"none\" if none of its allowed types fits. ~s

Types:
~w

~sCells:
~w

Answer with a JSON object that maps every cell id to one of that cell's allowed types or to \"none\", for example {\"1\": \"~w\", \"2\": \"none\"}.",
          [Listing, Basis, TypeText, CaptionText, CellText, Example]).

item_allowed(Item, Item.allowed).

cell_line(Show, Item, Line) :-
   json_quote(Item.text, Q),
   (  Show == true
   -> atomic_list_concat(Item.allowed, ', ', A),
      format(string(Line), "~s. ~s (allowed: ~w)", [Item.id, Q, A])
   ;  format(string(Line), "~s. ~s", [Item.id, Q])
   ).

json_quote(Text, Quoted) :-
   with_output_to(string(Quoted), json_write(current_output, Text)).

% --- stage 3: apply ----------------------------------------------------------

apply_guidelines(TdslFile, DatasetDir, Summary) :-
   apply_guidelines(TdslFile, DatasetDir, none, Summary).

apply_guidelines(TdslFile, DatasetDir, Papers, Summary) :-
   program(TdslFile, Program),
   read_cache(DatasetDir, Program.sha, Cache),
   paper_dirs(DatasetDir, Papers, Dirs),
   foldl(apply_paper(Program, Cache), Dirs, c(0, 0, 0, 0), c(Ro, G, K, P)),
   length(Dirs, NumPapers),
   format(string(Summary),
          "~d paper(s): ~d routed cell(s), ~d typed by guidelines, ~d kept (\"none\"), ~d pending",
          [NumPapers, Ro, G, K, P]).

apply_paper(Program, Cache, Dir, C0, C) :-
   paper_records(Dir, Pairs),
   foldl(apply_record(Program, Cache), Pairs, Guided, C0, C),
   directory_file_path(Dir, 'guided_types.jsonl', Out),
   setup_call_cleanup(
      open(Out, write, S, [encoding(utf8)]),
      forall(member(G, Guided), ( json_write_dict(S, G, [width(0)]), nl(S) )),
      close(S)).

apply_record(Program, Cache, Record-Typed, Guided, c(Ro0, G0, K0, P0), c(Ro, G, K, P)) :-
   foldl(apply_cell(Program, Cache, Record), Typed.cells, Cells,
         c(0, 0, 0, 0), c(Ro1, G1, K1, P1)),
   include(untyped_cell, Cells, UntypedCells),
   length(UntypedCells, Untyped),
   Counts = Typed.counts.put(json{routed:Ro1, guided:G1, kept:K1, pending:P1,
                                  untyped:Untyped}),
   cell_raster(Cells, Record.raster, Raster),
   Guided = Typed.put(json{cells:Cells, counts:Counts, type_raster:Raster,
                           guidelines_program_sha256:Program.sha}),
   Ro is Ro0 + Ro1, G is G0 + G1, K is K0 + K1, P is P0 + P1.

apply_cell(Program, Cache, Record, Cell0, Cell, c(Ro0, G0, K0, P0), c(Ro, G, K, P)) :-
   (  routed_cell(Program, Record, Cell0, Key, Allowed)
   -> Ro is Ro0 + 1,
      (  get_assoc(Key, Cache, Answer), Answer == "none"
      -> Cell = Cell0.put(rule_type, Cell0.type),
         G = G0, K is K0 + 1, P = P0
      ;  get_assoc(Key, Cache, Answer),
         atom_string(T, Answer), memberchk(T, Allowed)
      -> type_family(Program.analyzer, T, F),
         type_group(Program.analyzer, T, Gr),
         Cell = Cell0.put(json{type:T, family:F, group:Gr, source:"guideline",
                               rule_type:Cell0.type}),
         G is G0 + 1, K = K0, P = P0
      ;  Cell = Cell0, G = G0, K = K0, P is P0 + 1
      )
   ;  Cell = Cell0, Ro = Ro0, G = G0, K = K0, P = P0
   ).

untyped_cell(Cell) :-
   atom_string(untyped, U),
   get_dict(type, Cell, T), text_to_string(T, U).

cell_raster(Cells, Raster, TypeRaster) :-
   maplist(cell_type_pair, Cells, Pairs),
   list_to_assoc(Pairs, A),
   maplist(maplist(slot_type(A)), Raster, TypeRaster).

cell_type_pair(Cell, Cell.cell_id-Cell.type).

slot_type(A, Id, Type) :- get_assoc(Id, A, Type).

% --- for typed certificates (typed_certificates.pl) --------------------------

% guideline_program(+TdslFile, -Program): the program as the stages see it,
% json{path, sha, analyzer, caption_analysis}.
guideline_program(TdslFile, Program) :-
   program(TdslFile, Program).

% guideline_routed_cell(+Program, +Record, +TypedCell, -Key, -Allowed): the
% cell is routed to the guidelines, with its cache key and allowed types.
guideline_routed_cell(Program, Record, Cell, Key, Allowed) :-
   routed_cell(Program, Record, Cell, Key, Allowed).

% guideline_cache_rows(+DatasetDir, +Sha, -Rows): as read_cache/3, but each
% key maps to the whole cache line (answer, batch_id, ...).
guideline_cache_rows(DatasetDir, Sha, Rows) :-
   directory_file_path(DatasetDir, 'cache/guideline_answers.jsonl', File),
   (  exists_file(File)
   -> read_jsonl(File, Lines)
   ;  Lines = []
   ),
   empty_assoc(E),
   foldl(cache_line(Sha), Lines, E, Rows).

cache_line(Sha, Row, A0, A) :-
   (  Row.program_sha256 == Sha
   -> atom_string(RuleType, Row.rule_type),
      put_assoc(key(Row.text, RuleType, Row.caption), A0, Row, A)
   ;  A = A0
   ).

% --- shared ------------------------------------------------------------------

program(TdslFile, json{path:Path, sha:Sha, analyzer:Analyzer,
                       caption_analysis:Caption}) :-
   absolute_file_name(TdslFile, Path0, [access(read)]),
   atom_string(Path0, Path),
   tdsl_file_analyzer(Path0, Analyzer, _Guidelines),
   tdsl_analyzer_property(Analyzer, caption_analysis(Caption)),
   program_sha256(Path0, Sha).

% program_sha256(+File, -Hex): of the file's content. Imported files are not
% included; touch the importing file when an import changes.
program_sha256(File, Hex) :-
   read_file_to_string(File, Text, [encoding(utf8)]),
   crypto_data_hash(Text, Hex0, [algorithm(sha256), encoding(utf8)]),
   atom_string(Hex0, Hex).

% read_cache(+DatasetDir, +Sha, -Cache): key(Text, RuleType, Caption) ->
% Answer for the program's answers; the latest line for a key wins.
read_cache(DatasetDir, Sha, Cache) :-
   directory_file_path(DatasetDir, 'cache/guideline_answers.jsonl', File),
   (  exists_file(File)
   -> read_jsonl(File, Rows)
   ;  Rows = []
   ),
   empty_assoc(E),
   foldl(cache_row(Sha), Rows, E, Cache).

cache_row(Sha, Row, A0, A) :-
   (  Row.program_sha256 == Sha
   -> atom_string(RuleType, Row.rule_type),
      put_assoc(key(Row.text, RuleType, Row.caption), A0, Row.answer, A)
   ;  A = A0
   ).

% paper_records(+Dir, -Pairs): Record-Typed for each table, matched by
% table_uid.
paper_records(Dir, Pairs) :-
   directory_file_path(Dir, 'tables.jsonl', TablesFile),
   directory_file_path(Dir, 'types.jsonl', TypesFile),
   read_jsonl(TablesFile, Records),
   read_jsonl(TypesFile, Types),
   findall(R-T, ( member(T, Types), member(R, Records),
                  R.table_uid == T.table_uid ), Pairs).

paper_dirs(DatasetDir, Papers, Dirs) :-
   directory_file_path(DatasetDir, papers, PapersDir),
   directory_files(PapersDir, Names0),
   msort(Names0, Names),
   findall(Dir,
           ( member(Name, Names), sub_atom(Name, 0, _, _, 'PMC'),
             ( Papers == none -> true ; memberchk(Name, Papers) ),
             directory_file_path(PapersDir, Name, Dir),
             directory_file_path(Dir, 'types.jsonl', T), exists_file(T) ),
           Dirs).

read_jsonl(File, Records) :-
   read_file_to_string(File, Text, [encoding(utf8)]),
   split_string(Text, "\n", "\r", Lines),
   findall(R, ( member(L, Lines), L \== "",
                atom_json_dict(L, R, [default_tag(json)]) ), Records).

write_json(File, Json) :-
   setup_call_cleanup(open(File, write, S, [encoding(utf8)]),
                      ( json_write_dict(S, Json, [width(100)]), nl(S) ),
                      close(S)).
