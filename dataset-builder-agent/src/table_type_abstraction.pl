% Type abstraction of a table: every cell's text replaced by its type.
%
% The types come from a type DSL program (type_dsl_engine.pl), applied to
% the cells of a tables.jsonl record. Only the program's rules are used; its
% guidelines are left for a later step that types the cells the rules leave
% untyped, which this module lists for that purpose.
%
% From dataset-builder-agent/src/:
%   swipl -g 'use_module(table_type_abstraction),
%             type_dataset("../type_dsl_examples/sci.tdsl", "dataset")' -t halt
%
%   type_dataset(+TdslFile, +DatasetDir)
%       Writes papers/PMC<id>/types.jsonl next to every tables.jsonl of
%       DatasetDir, one record per table, in the same order.
%   type_dataset(+TdslFile, +DatasetDir, +Papers)
%       The same for Papers, none (all papers) or a list of paper names.
%   type_tables_file(+TdslFile, +TablesFile, +OutFile)
%       The same for one tables.jsonl.
%   table_type_record(+Analyzer, +Record, -TypeRecord)
%       Record is a tables.jsonl record (a dict), TypeRecord its type record.
%   cell_type(+Analyzer, +Text, -Type, -Source)
%   type_family(+Analyzer, +Type, -Family)
%   type_group(+Analyzer, +Type, -Group)
%
% --- cell types --------------------------------------------------------------
%
% Before the rules see it, a cell's text is trimmed and every run of white
% space is collapsed into one space. Then:
%   - empty text           type empty, family empty, source none
%   - no rule matches      type untyped, family untyped, source none
%   - otherwise            the most specific of the matched types: the types
%                          that are a strict supertype of another matched
%                          type are dropped, and of the rest the one whose
%                          rule comes first wins. Rule order is therefore the
%                          precedence between unrelated types. Source is
%                          that rule's origin, Base:Line, Base being the
%                          base name of the .tdsl file. If subtyping cycles
%                          leave no type, the first matching rule wins.
% Synthetic cells (kind "synthetic_gap": slots that pad short rows) are
% typed empty with source synthetic, whatever their text.
%
% A type is reported by name: ref(Name) is Name, and a type expression that
% is not a name (a tuple, a union) is written as in the DSL, "(A, B)" or
% "A | B".
%
% The family of a type is its root in the program's subtype declarations:
% the supertype reached by following the first declared supertype of each
% type until there is none (cycles stop where they close). A type with no
% declared supertype is its own family. sci.tdsl has four: Numeric, Text,
% Missing and Symbol; empty and untyped are families of their own.
%
% The group of a type sits between it and its family: on the same chain of
% first declared supertypes, the type just below the family if that type has
% subtypes of its own, else the family. So a family whose subtypes are all
% leaves is one group, and a program splits a family into groups by declaring
% intermediate types (Text > QualitativeData > FindingStatement).
%
% --- type records ------------------------------------------------------------
%
% One JSON object per table:
%   table_uid, pmc_id, table_index   as in the tables.jsonl record
%   type_program                     absolute path of the .tdsl file
%   cells        [{cell_id, type, family, group, source}], in cell order
%   type_raster  the record's raster with each slot's cell id replaced by
%                the cell's type
%   untyped_cells [{cell_id, text}] for the cells no rule typed, text as
%                normalized; the input of the guideline step
%   counts       {cells, typed, untyped, empty}

:- module(table_type_abstraction, [
      type_dataset/2,
      type_dataset/3,
      type_tables_file/3,
      table_type_record/3,
      cell_type/4,
      type_family/3,
      type_group/3,
      type_strict_subtype/3
   ]).

:- if(exists_source(library(json))).
:- use_module(library(json)).
:- else.
:- use_module(library(http/json)).
:- endif.
:- use_module(library(readutil)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(pairs)).
:- use_module(library(assoc)).
:- use_module(library(filesex)).
:- use_module(type_dsl_engine).

% --- files -------------------------------------------------------------------

type_dataset(TdslFile, DatasetDir) :-
   type_dataset(TdslFile, DatasetDir, none).

type_dataset(TdslFile, DatasetDir, Papers) :-
   tdsl_file_analyzer(TdslFile, Analyzer, _Guidelines),
   absolute_file_name(TdslFile, Program),
   directory_file_path(DatasetDir, papers, PapersDir),
   directory_files(PapersDir, Names0),
   msort(Names0, Names),
   forall(( member(Name, Names),
            sub_atom(Name, 0, _, _, 'PMC'),
            ( Papers == none -> true ; memberchk(Name, Papers) ),
            directory_file_path(PapersDir, Name, PaperDir),
            directory_file_path(PaperDir, 'tables.jsonl', TablesFile),
            exists_file(TablesFile) ),
          ( directory_file_path(PaperDir, 'types.jsonl', OutFile),
            type_records(Analyzer, Program, TablesFile, OutFile) )).

type_tables_file(TdslFile, TablesFile, OutFile) :-
   tdsl_file_analyzer(TdslFile, Analyzer, _Guidelines),
   absolute_file_name(TdslFile, Program),
   type_records(Analyzer, Program, TablesFile, OutFile).

type_records(Analyzer, Program, TablesFile, OutFile) :-
   read_jsonl(TablesFile, Records),
   maplist(table_type_record(Analyzer), Records, TypeRecords0),
   atom_string(Program, ProgramString),
   maplist(put_program(ProgramString), TypeRecords0, TypeRecords),
   setup_call_cleanup(
      open(OutFile, write, Out, [encoding(utf8)]),
      forall(member(TypeRecord, TypeRecords),
             ( json_write_dict(Out, TypeRecord, [width(0)]), nl(Out) )),
      close(Out)).

put_program(Program, Record0, Record) :-
   put_dict(type_program, Record0, Program, Record).

read_jsonl(File, Records) :-
   setup_call_cleanup(
      open(File, read, Stream, [encoding(utf8)]),
      read_jsonl_stream(Stream, Records),
      close(Stream)).

read_jsonl_stream(Stream, Records) :-
   read_line_to_string(Stream, Line),
   (  Line == end_of_file
   -> Records = []
   ;  Line == ""
   -> read_jsonl_stream(Stream, Records)
   ;  atom_json_dict(Line, Record, [default_tag(json)]),
      Records = [Record|Rest],
      read_jsonl_stream(Stream, Rest)
   ).

% --- tables ------------------------------------------------------------------

table_type_record(Analyzer, Record, TypeRecord) :-
   maplist(typed_cell(Analyzer), Record.cells, Typed),
   maplist(cell_json(Analyzer), Typed, Cells),
   maplist(cell_type_pair, Typed, Pairs),
   list_to_assoc(Pairs, TypeOf),
   maplist(maplist(slot_type(TypeOf)), Record.raster, TypeRaster),
   include(untyped, Typed, Untyped),
   maplist(untyped_json, Untyped, UntypedCells),
   length(Typed, NumCells),
   length(Untyped, NumUntyped),
   aggregate_all(count, member(typed(_, _, empty, _, _), Typed), NumEmpty),
   NumTyped is NumCells - NumUntyped - NumEmpty,
   TypeRecord = json{table_uid:Record.table_uid,
                     pmc_id:Record.pmc_id,
                     table_index:Record.table_index,
                     cells:Cells,
                     type_raster:TypeRaster,
                     untyped_cells:UntypedCells,
                     counts:json{cells:NumCells, typed:NumTyped,
                                 untyped:NumUntyped, empty:NumEmpty}}.

% typed(CellId, Text, Type, Family, Source)
typed_cell(Analyzer, Cell, typed(Id, Text, Type, Family, Source)) :-
   Id = Cell.cell_id,
   ( get_dict(text, Cell, Text0), Text0 \== null -> true ; Text0 = "" ),
   normalize_text(Text0, Text),
   (  Cell.kind == "synthetic_gap"
   -> Type = empty, Family = empty, Source = synthetic
   ;  cell_type(Analyzer, Text, Type, Source),
      type_family(Analyzer, Type, Family)
   ).

cell_json(Analyzer, typed(Id, _, Type, Family, Source),
          json{cell_id:Id, type:Type, family:Family, group:Group,
               source:SourceString}) :-
   type_group(Analyzer, Type, Group),
   source_string(Source, SourceString).

source_string(File:Line, String) :- !,
   file_base_name(File, Base),
   format(string(String), "~w:~w", [Base, Line]).
source_string(Source, String) :-
   atom_string(Source, String).

cell_type_pair(typed(Id, _, Type, _, _), Id-Type).

slot_type(TypeOf, Id, Type) :-
   get_assoc(Id, TypeOf, Type).

untyped(typed(_, _, untyped, _, _)).

untyped_json(typed(Id, Text, _, _, _), json{cell_id:Id, text:Text}).

normalize_text(Text0, Text) :-
   split_string(Text0, " \t\n\r ", " \t\n\r ", Parts0),
   exclude(==(""), Parts0, Parts),
   atomic_list_concat(Parts, ' ', Atom),
   atom_string(Atom, Text).

% --- cells -------------------------------------------------------------------

cell_type(_, Text, empty, none) :-
   Text == "", !.
cell_type(Analyzer, Text, Type, Source) :-
   call(Analyzer, Text, Matches),
   (  Matches == []
   -> Type = untyped, Source = none
   ;  tdsl_analyzer_property(Analyzer, subtypes(Subtypes)),
      pairs_values(Matches, Types),
      include(most_specific(Subtypes, Types), Matches, Specific),
      % Types that are subtypes of each other (a cycle) eliminate one
      % another; they are equivalent, so the first rule decides.
      (  Specific = [rule(Source, _)-TypeExpr|_]
      -> true
      ;  Matches = [rule(Source, _)-TypeExpr|_]
      ),
      type_name(TypeExpr, Type)
   ).

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

% type_strict_subtype(+Analyzer, ?Sub, ?Super): type names related by the
% program's subtype declarations, transitively.
type_strict_subtype(Analyzer, Sub, Super) :-
   tdsl_analyzer_property(Analyzer, subtypes(Subtypes0)),
   maplist(named_pair, Subtypes0, Subtypes),
   (  atom(Sub)
   -> strict_subtype(Subtypes, Sub, Super)
   ;  setof(S, Mid^member(S-Mid, Subtypes), Subs),
      member(Sub, Subs),
      strict_subtype(Subtypes, Sub, Super)
   ).

type_family(_, Type, Type) :-
   memberchk(Type, [empty, untyped]), !.
type_family(Analyzer, Type, Family) :-
   tdsl_analyzer_property(Analyzer, subtypes(Subtypes0)),
   maplist(named_pair, Subtypes0, Subtypes),
   root(Subtypes, Type, [Type], [Family|_]).

type_group(_, Type, Type) :-
   memberchk(Type, [empty, untyped]), !.
type_group(Analyzer, Type, Group) :-
   tdsl_analyzer_property(Analyzer, subtypes(Subtypes0)),
   maplist(named_pair, Subtypes0, Subtypes),
   root(Subtypes, Type, [Type], Chain),
   (  Chain = [_, Below|_], memberchk(_-Below, Subtypes)
   -> Group = Below
   ;  Chain = [Group|_]
   ).

% root(+Subtypes, +Type, +Seen, -Chain): Seen is the path to Type, nearest
% first; Chain is the whole path up to the root, root first.
root(Subtypes, Type, Seen, Chain) :-
   (  memberchk(Type-Super, Subtypes),
      \+ memberchk(Super, Seen)
   -> root(Subtypes, Super, [Super|Seen], Chain)
   ;  Chain = Seen
   ).

named_pair(Sub0-Super0, Sub-Super) :-
   type_name(Sub0, Sub),
   type_name(Super0, Super).

type_name(ref(Name), Name) :- !.
type_name(any, any) :- !.
type_name(null, null) :- !.
type_name(tuple(Types), Name) :- !,
   maplist(type_name, Types, Names),
   atomic_list_concat(Names, ', ', Inner),
   format(atom(Name), "(~w)", [Inner]).
type_name(union(Types), Name) :-
   maplist(type_name, Types, Names),
   atomic_list_concat(Names, ' | ', Name).
