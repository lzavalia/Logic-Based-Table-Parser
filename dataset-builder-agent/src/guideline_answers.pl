% The model-facing half of the guideline step (see type_guidelines.pl):
% reading the request batches, checking a model's answer to one, and
% appending the accepted answers to the cache. Used by type_guidelines.dml.
%
% Deliberately free of the type DSL engine (and so of PCRE), which
% DeepClause's Prolog may not provide: everything a batch needs to be
% checked, the allowed types of every cell, is in the request file.
%
%   guideline_queue(+DatasetDir, +Papers, -Queue)
%       Queue is a list of batch(Paper, ProgramSha, Batch) from the
%       papers/PMC<id>/guideline_requests.json files, Papers being none (all
%       papers) or a list of paper names.
%   guideline_answer(+Batch, +Reply, -Outcome)
%       Reply is what prompt/2 bound to object(Answer) (a dict or a JSON
%       string), or no_answer or error(E). Outcome is done(Answers, Missing)
%       when at least one cell got a usable answer, Answers a list of
%       Item-Answer (Answer a string, an allowed type or "none") and Missing
%       the number of cells without one; retry(Reason) otherwise.
%   guideline_batch_prompt(+Batch, -Prompt), guideline_batch_id(+Batch, -Id)
%       Accessors for the DML side, which avoids dict notation.
%   append_guideline_answers(+DatasetDir, +ProgramSha, +Batch, +Answers)
%       Appends one cache line per answer to
%       dataset/cache/guideline_answers.jsonl.

:- module(guideline_answers, [
      guideline_queue/3,
      guideline_answer/3,
      append_guideline_answers/4,
      guideline_batch_prompt/2,
      guideline_batch_id/2
   ]).

:- if(exists_source(library(json))).
:- use_module(library(json)).
:- else.
:- use_module(library(http/json)).
:- endif.
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(readutil)).
:- use_module(library(filesex)).

guideline_queue(DatasetDir, Papers, Queue) :-
   directory_file_path(DatasetDir, papers, PapersDir),
   directory_files(PapersDir, Names0),
   msort(Names0, Names),
   findall(batch(Name, Sha, Batch),
           ( member(Name, Names),
             sub_atom(Name, 0, _, _, 'PMC'),
             ( Papers == none -> true ; memberchk(Name, Papers) ),
             directory_file_path(PapersDir, Name, Dir),
             directory_file_path(Dir, 'guideline_requests.json', File),
             exists_file(File),
             read_json_file(File, Request),
             Sha = Request.program_sha256,
             member(Batch, Request.batches) ),
           Queue).

guideline_batch_prompt(Batch, Batch.prompt).
guideline_batch_id(Batch, Batch.batch_id).

% --- checking an answer --------------------------------------------------------

guideline_answer(Batch, Reply, Outcome) :-
   (  reply_dict(Reply, Dict)
   -> foldl(item_answer(Dict), Batch.items, Answers0, 0, Missing),
      exclude(==(missing), Answers0, Answers),
      (  Answers == []
      -> Outcome = retry("no cell got one of its allowed types or \"none\"")
      ;  Outcome = done(Answers, Missing)
      )
   ;  reply_problem(Reply, Problem),
      Outcome = retry(Problem)
   ).

item_answer(Dict, Item, Answer, M0, M) :-
   (  dict_value(Dict, Item.id, Value0),
      ( string(Value0) ; atom(Value0) ),
      text_to_string(Value0, Value1),
      normalize_space(string(Value), Value1),
      (  Value == "none"
      ;  memberchk(Value, Item.allowed)
      )
   -> Answer = Item-Value, M = M0
   ;  Answer = missing, M is M0 + 1
   ).

reply_dict(Reply, Reply) :- is_dict(Reply), !.
reply_dict(Text, Dict) :-
   ( string(Text) ; atom(Text) ),
   catch(atom_json_dict(Text, Dict, [default_tag(json)]), _, fail),
   is_dict(Dict).

reply_problem(no_answer, "the model call failed or returned nothing") :- !.
reply_problem(error(E), Problem) :- !,
   format(string(Problem), "the model call raised ~q", [E]).
reply_problem(_, "the answer is not a JSON object").

% dict_value(+Dict, +Key, -Value): Key is a string; dict keys may be atoms
% or small integers, depending on how the answer was parsed.
dict_value(Dict, Key, Value) :-
   dict_pairs(Dict, _, Pairs),
   member(K-Value, Pairs),
   ( atom(K) -> atom_string(K, KS) ; number_string(K, KS) ),
   KS == Key, !.

% --- the cache -----------------------------------------------------------------

append_guideline_answers(DatasetDir, Sha, Batch, Answers) :-
   directory_file_path(DatasetDir, cache, CacheDir),
   make_directory_path(CacheDir),
   directory_file_path(CacheDir, 'guideline_answers.jsonl', File),
   setup_call_cleanup(
      open(File, append, S, [encoding(utf8)]),
      forall(member(Item-Answer, Answers),
             ( json_write_dict(S, json{program_sha256:Sha, text:Item.text,
                                       rule_type:Item.rule_type,
                                       caption:Batch.caption, answer:Answer,
                                       batch_id:Batch.batch_id}, [width(0)]),
               nl(S) )),
      close(S)).

read_json_file(File, Dict) :-
   setup_call_cleanup(open(File, read, S, [encoding(utf8)]),
                      json_read_dict(S, Dict, [default_tag(json)]),
                      close(S)).
