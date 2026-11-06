% Typed certificates: the certificate of the full pipeline (arm C), written
% once the review and its repair are done, with a typing section that says
% how every cell of the certified table was typed: by the rules of the type
% DSL program or by a model following its guidelines (the format and the
% checks are in certificate_kernel.pl).
%
% The types are those the review worked from: the types file that
% type_inference.jsonl names for the table (guided_types.jsonl when the
% guideline step has run, else types.jsonl). A cell the guideline step
% typed records the batch its answer came from, as the answer cache holds
% it. For a table the repair decided, the typing covers the repaired raster,
% whose cells are those of the table less the empty cells merged away, with
% their types unchanged.
%
% This file is NOT trusted: the kernel replays the rules on every cell's
% text and checks the routing, and every certificate is written, read back
% and checked by it (dataset_pipeline:write_checked_certificate/2) before it
% takes the place of the review's geometric certificate of the same name.
% It needs PCRE, so it runs outside DeepClause (certify_reviews.pl, which
% review_agent.sh runs after the full review).
%
%   typing_facts(+Program, +Answers, +Record0, +Record, +TypeRecord, -Facts)
%       Program is type_guidelines:guideline_program/2's, Answers its
%       guideline_cache_rows/3, Record0 the tables.jsonl record, Record the
%       record certified (Record0 or its repair) and TypeRecord the type
%       record of Record0.
%   write_typed_certificates(+Program, +DatasetDir, +PaperDir, -Result)
%       Result is done(Written, Failed): the names written, and Name-Reason
%       for every certificate left as it was, or not_current(Why) when the
%       paper's review is not that of its tables.jsonl and
%       type_inference.jsonl.

:- module(typed_certificates, [
      typing_facts/6,
      write_typed_certificates/4
   ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(assoc)).
:- use_module(library(filesex)).
:- use_module(provenance_manifest, [file_sha256/2]).
:- use_module(table_review, [read_jsonl/2]).
:- use_module(dataset_pipeline, [selected_certificate/5,
                                 write_checked_certificate/2]).
:- use_module(type_dsl_engine, [tdsl_analyzer_property/2]).
:- use_module(table_type_abstraction, [type_name/2]).
:- use_module(type_guidelines, [guideline_routed_cell/5,
                                guideline_cache_rows/3]).

% --- the typing section ------------------------------------------------------

typing_facts(Program, Answers, Record0, Record, TypeRecord, Facts) :-
   program_facts(Program, ProgramFacts),
   findall(Id, ( member(Row, Record.raster), member(Id, Row) ), Ids0),
   sort(Ids0, Ids),
   id_map(Record.cells, Cells),
   id_map(TypeRecord.cells, Typed),
   foldl(cell_facts(Program, Answers, Record0, Cells, Typed), Ids, CellFacts, []),
   append([[typing_version(1)], ProgramFacts, CellFacts], Facts).

% The program as the kernel replays it: its rules in order, its subtypes and
% the guidelines that decide a named type (the only ones routed to).
program_facts(Program, [type_program(Base, Sha)|Facts]) :-
   Analyzer = Program.analyzer,
   file_base_name(Program.path, Base0), atom_string(Base0, Base),
   atom_string(Program.sha, Sha),
   tdsl_analyzer_property(Analyzer, rules(Rules)),
   findall(type_rule(N, Origin, Pattern, Type),
           ( nth0(N, Rules, rule(Source:Line, Pattern)-TypeExpr),
             file_base_name(Source, SourceBase),
             format(string(Origin), "~w:~w", [SourceBase, Line]),
             type_name(TypeExpr, Type) ),
           RuleFacts),
   tdsl_analyzer_property(Analyzer, subtypes(Subtypes)),
   findall(type_subtype(Sub, Super),
           ( member(Sub0-Super0, Subtypes),
             type_name(Sub0, Sub), type_name(Super0, Super) ),
           SubtypeFacts),
   tdsl_analyzer_property(Analyzer, guidelines(Guidelines)),
   findall(Prompt-Type,
           ( member(Prompt0-ref(Type), Guidelines), text_to_string(Prompt0, Prompt) ),
           Named),
   findall(guideline(N, Prompt, Type), nth0(N, Named, Prompt-Type), GuidelineFacts),
   append([RuleFacts, SubtypeFacts, GuidelineFacts], Facts).

id_map(Dicts, Map) :-
   findall(Id-D, ( member(D, Dicts), get_dict(cell_id, D, Id) ), Pairs),
   list_to_assoc(Pairs, Map).

% cell_facts(+Program, +Answers, +Record0, +Cells, +Typed, +Id)// the text
% and the type of cell Id, as a difference list.
cell_facts(Program, Answers, Record0, Cells, Typed, Id,
           [TextFact, cell_type(Id, Type, Derivation)|Tail], Tail) :-
   (  get_assoc(Id, Cells, Cell)
   -> true
   ;  throw(error(typing_error(cell_not_in_record(Id)), _)) ),
   (  get_assoc(Id, Typed, TypedCell)
   -> true
   ;  throw(error(typing_error(cell_not_typed(Id)), _)) ),
   (  get_dict(kind, Cell, "synthetic_gap")
   -> TextFact = synthetic_cell(Id)
   ;  ( get_dict(text, Cell, Text0), Text0 \== null -> true ; Text0 = "" ),
      text_to_string(Text0, Text),
      TextFact = cell_text(Id, Text)
   ),
   atom_string(Type, TypedCell.type),
   derivation(Program, Answers, Record0, TypedCell, Derivation).

% derivation(+Program, +Answers, +Record0, +TypedCell, -Derivation): how the
% types file reached the cell's type; a guideline answer is looked up again
% under the rule type it was asked with.
derivation(Program, Answers, Record0, Cell, Derivation) :-
   (  get_dict(rule_type, Cell, RuleType)
   -> AskedCell = Cell.put(type, RuleType),
      answer_batch(Program, Answers, Record0, AskedCell, Batch),
      (  Cell.source == "guideline"
      -> Derivation = guideline(Batch)
      ;  Derivation = guideline_none(Batch)
      )
   ;  guideline_routed_cell(Program, Record0, Cell, _, _)
   -> Derivation = guideline_pending
   ;  Derivation = rules
   ).

answer_batch(Program, Answers, Record0, Cell, Batch) :-
   (  guideline_routed_cell(Program, Record0, Cell, Key, _),
      get_assoc(Key, Answers, Row),
      get_dict(batch_id, Row, Batch0), string(Batch0)
   -> Batch = Batch0
   ;  Batch = "unrecorded"
   ).

% --- a paper -------------------------------------------------------------------

write_typed_certificates(Program, DatasetDir, PaperDir, Result) :-
   directory_file_path(PaperDir, 'tables.jsonl', TablesFile),
   directory_file_path(PaperDir, 'review.jsonl', ReviewFile),
   directory_file_path(PaperDir, 'type_inference.jsonl', InferenceFile),
   (  \+ exists_file(ReviewFile)
   -> Result = not_current(no_review)
   ;  \+ exists_file(InferenceFile)
   -> Result = not_current(no_type_inference)
   ;  read_jsonl(TablesFile, Tables),
      read_jsonl(ReviewFile, Reviews),
      read_jsonl(InferenceFile, Inferences),
      file_sha256(TablesFile, H1), atom_string(H1, TablesSha),
      file_sha256(InferenceFile, H2), atom_string(H2, InferenceSha),
      (  length(Tables, N), length(Reviews, N),
         forall(member(R, Reviews),
                ( atom_string(R.tables_jsonl_sha256, TablesSha),
                  get_dict(type_inference_sha256, R, Recorded),
                  atom_string(Recorded, InferenceSha) ))
      -> guideline_cache_rows(DatasetDir, Program.sha, Answers),
         findall(Item,
                 typed_certificate(Program, Answers, PaperDir, Tables, Reviews,
                                   Inferences, Item),
                 Items),
         place_typed(PaperDir, Items, Written, Failed),
         Result = done(Written, Failed)
      ;  Result = not_current(review_predates_tables_or_types)
      )
   ).

% typed_certificate(...,  -Item): Item is Name-temp(Temp) for a certificate
% written and checked into a temporary file, or Name-failed(Reason).
typed_certificate(Program, Answers, PaperDir, Tables, Reviews, Inferences,
                  Name-Outcome) :-
   selected_certificate(Tables, Reviews, Record0, Record, Name-Geometric),
   format(atom(TempName), ".~w.typed.tmp", [Name]),
   directory_file_path(PaperDir, TempName, Temp),
   catch(( type_record(PaperDir, Inferences, Record0.table_uid, TypeRecord),
           typing_facts(Program, Answers, Record0, Record, TypeRecord, Typing),
           append(Geometric, Typing, Facts),
           write_checked_certificate(Temp, Facts),
           Outcome = temp(Temp) ),
         Error,
         ( ( exists_file(Temp) -> delete_file(Temp) ; true ),
           error_reason(Error, Reason),
           Outcome = failed(Reason) )).

error_reason(error(Formal, _), Formal) :- !.
error_reason(Error, Error).

% type_record(+PaperDir, +Inferences, +Uid, -TypeRecord): the table's record
% in the types file its type inference used.
type_record(PaperDir, Inferences, Uid, TypeRecord) :-
   (  member(Inference, Inferences), Inference.table_uid == Uid
   -> true
   ;  throw(error(typing_error(no_type_inference(Uid)), _)) ),
   atom_string(TypesName, Inference.types_file),
   directory_file_path(PaperDir, TypesName, TypesFile),
   read_jsonl(TypesFile, TypeRecords),
   (  member(TypeRecord, TypeRecords), TypeRecord.table_uid == Uid
   -> true
   ;  throw(error(typing_error(no_type_record(Uid, TypesName)), _)) ).

place_typed(PaperDir, Items, Written, Failed) :-
   findall(Name, member(Name-temp(_), Items), Written),
   findall(Name-Reason, member(Name-failed(Reason), Items), Failed),
   forall(member(Name-temp(Temp), Items),
          ( directory_file_path(PaperDir, Name, Final),
            rename_file(Temp, Final) )).
