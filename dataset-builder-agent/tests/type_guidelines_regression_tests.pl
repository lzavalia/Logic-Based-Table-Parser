% Regression tests for the guideline step of the type DSL
% (src/type_guidelines.pl and src/guideline_answers.pl), with a simulated
% model: the answers are given, so no LLM or DeepClause is needed.
%
% From dataset-builder-agent/tests/:
%   swipl -q -s type_guidelines_regression_tests.pl -g run_tests -t halt

:- use_module(library(plunit)).
:- use_module(library(filesex)).
:- use_module(library(readutil)).
:- if(exists_source(library(json))).
:- use_module(library(json)).
:- else.
:- use_module(library(http/json)).
:- endif.
:- use_module('../src/type_dsl_engine').
:- use_module('../src/table_type_abstraction').
:- use_module('../src/type_guidelines').
:- use_module('../src/guideline_answers').

program_text(Option, Text) :-
   format(string(Text),
"~s
type Text
type Word
type Num
type Name
type Label
Word <: Text
Name <: Text
Name <: Word
Label <: Text
Label <: Word
if regex \"[a-z]+\" decide Word
if regex \"[0-9]+\" decide Num
guideline \"the name of a person\" decide Name
guideline \"a label\" decide Label
", [Option]).

cell(Id, Row, Column, Text,
     json{cell_id:Id, row:Row, column:Column, kind:"source", text:Text}).

% A dataset with one paper and one table: alice (Word, routed to Name or
% Label), 42 (Num, final), "Δ!" (untyped, routed to either), "" (empty),
% bob (Word).
make_dataset(Dir, Option, Tdsl) :-
   directory_file_path(Dir, 'papers/PMC1', Paper),
   make_directory_path(Paper),
   cell(0, 0, 0, "alice", C0), cell(1, 0, 1, "42", C1),
   cell(2, 1, 0, "Δ!", C2), cell(3, 1, 1, "", C3), cell(4, 2, 0, "bob", C4),
   cell(5, 2, 1, "alice", C5),
   Record = json{table_uid:"PMC1/t0", pmc_id:"PMC1", table_index:0,
                 context:json{caption:"People and labels"},
                 cells:[C0, C1, C2, C3, C4, C5],
                 raster:[[0, 1], [2, 3], [4, 5]]},
   directory_file_path(Paper, 'tables.jsonl', Tables),
   write_line(Tables, Record),
   directory_file_path(Dir, 'p.tdsl', Tdsl),
   program_text(Option, Text),
   write_text(Tdsl, Text),
   directory_file_path(Paper, 'types.jsonl', Types),
   type_tables_file(Tdsl, Tables, Types).

write_line(File, Json) :-
   setup_call_cleanup(open(File, write, S, [encoding(utf8)]),
                      ( json_write_dict(S, Json, [width(0)]), nl(S) ),
                      close(S)).

write_text(File, Text) :-
   setup_call_cleanup(open(File, write, S, [encoding(utf8)]),
                      write(S, Text), close(S)).

read_json(File, Dict) :-
   setup_call_cleanup(open(File, read, S, [encoding(utf8)]),
                      json_read_dict(S, Dict, [default_tag(json)]), close(S)).

read_lines(File, Dicts) :-
   read_file_to_string(File, Text, [encoding(utf8)]),
   split_string(Text, "\n", "", Lines),
   findall(D, ( member(L, Lines), L \== "", atom_json_dict(L, D, [default_tag(json)]) ),
           Dicts).

request(Dir, Request) :-
   directory_file_path(Dir, 'papers/PMC1/guideline_requests.json', File),
   read_json(File, Request).

guided_cells(Dir, Cells, Counts) :-
   directory_file_path(Dir, 'papers/PMC1/guided_types.jsonl', File),
   read_lines(File, [Record]),
   Cells = Record.cells, Counts = Record.counts.

tmp_dir(Dir) :- tmp_file(guidelines, Dir), make_directory(Dir).

% Not a lambda: dict access in a lambda body is expanded before the call.
item_triple(Item, Text-RuleType-Allowed) :-
   Text = Item.text, RuleType = Item.rule_type, Allowed = Item.allowed.

:- begin_tests(guideline_step).

test(routes) :-
   tmp_dir(Dir),
   make_dataset(Dir, "", Tdsl),
   tdsl_file_analyzer(Tdsl, A, _),
   guideline_types(A, Types), assertion(Types == ['Name', 'Label']),
   guideline_routes(A, 'Word', W), assertion(W == ['Name', 'Label']),
   guideline_routes(A, 'Num', N), assertion(N == []),
   guideline_routes(A, untyped, U), assertion(U == ['Name', 'Label']),
   delete_directory_and_contents(Dir).

test(rule_first_then_guideline) :-
   tmp_dir(Dir),
   directory_file_path(Dir, 'both.tdsl', Tdsl),
   setup_call_cleanup(
      open(Tdsl, write, S, [encoding(utf8)]),
      format(S,
"type Text
type Unit
type Finding
Unit <: Text
Finding <: Text
if regex \"mg|kg\" decide Unit
if regex \"[a-z ]+\" decide Text
guideline \"a unit of measurement\" decide Unit
guideline \"a finding\" decide Finding
", []),
      close(S)),
   tdsl_file_analyzer(Tdsl, A, _),
   % The rule decides, whatever the rule order, and the cell is final.
   cell_type(A, "mg", T1, _), assertion(T1 == 'Unit'),
   guideline_routes(A, 'Unit', R1), assertion(R1 == []),
   % The rule fails: the fallback routes the cell, and it may still be a Unit.
   cell_type(A, "per litre", T2, _), assertion(T2 == 'Text'),
   guideline_routes(A, 'Text', R2), assertion(R2 == ['Unit', 'Finding']),
   delete_directory_and_contents(Dir).

test(untyped_cell_needs_a_letter) :-
   tmp_dir(Dir),
   make_dataset(Dir, "", Tdsl),
   tdsl_file_analyzer(Tdsl, A, _),
   Program = json{analyzer:A, caption_analysis:false},
   Cell = json{cell_id:0, type:"untyped"},
   forall(member(Text-Routed, ["Δ!"-true, "[ 12 ] 5_"-false, "€9-€9"-false]),
          ( Record = json{cells:[json{cell_id:0, text:Text}]},
            (  type_guidelines:routed_cell(Program, Record, Cell, _, _)
            -> assertion(Routed == true)
            ;  assertion(Routed == false) ) )),
   delete_directory_and_contents(Dir).

test(shared_allowed_types_are_stated_once) :-
   tmp_dir(Dir),
   make_dataset(Dir, "", Tdsl),
   tdsl_file_analyzer(Tdsl, A, _),
   Program = json{analyzer:A},
   Same = [json{id:"1", text:"a", allowed:["Name", "Label"]},
           json{id:"2", text:"b", allowed:["Name", "Label"]}],
   guideline_prompt(Program, Same, null, P1),
   assertion(\+ sub_string(P1, _, _, _, "(allowed:")),
   assertion(sub_string(P1, _, _, _, "1. \"a\"\n2. \"b\"")),
   Mixed = [json{id:"1", text:"a", allowed:["Name", "Label"]},
            json{id:"2", text:"b", allowed:["Name"]}],
   guideline_prompt(Program, Mixed, null, P2),
   assertion(sub_string(P2, _, _, _, "2. \"b\" (allowed: Name)")),
   delete_directory_and_contents(Dir).

test(requests) :-
   tmp_dir(Dir),
   make_dataset(Dir, "", Tdsl),
   guideline_requests(Tdsl, Dir, Summary),
   assertion(Summary == "1 paper(s): 1 batch(es), 3 cell text(s) to send"),
   request(Dir, R),
   R.batches = [B],
   assertion(B.batch_id == "PMC1/1"),
   assertion(B.caption == null),
   % Distinct (text, rule type) pairs in text order; alice is sent once.
   maplist(item_triple, B.items, Got),
   assertion(Got == ["alice"-"Word"-["Name", "Label"],
                     "bob"-"Word"-["Name", "Label"],
                     "Δ!"-"untyped"-["Name", "Label"]]),
   assertion(sub_string(B.prompt, _, _, _, "- Name: the name of a person")),
   assertion(sub_string(B.prompt, _, _, _, "1. \"alice\"\n")),
   delete_directory_and_contents(Dir).

test(answers_cache_apply) :-
   tmp_dir(Dir),
   make_dataset(Dir, "", Tdsl),
   guideline_requests(Tdsl, Dir, _),
   guideline_queue(Dir, none, [batch(Paper, Sha, B)]),
   assertion(Paper == 'PMC1'),
   % alice -> Name; bob -> an answer that is not allowed; Δ! -> none.
   Reply = json{'1':"Name", '2':"Num", '3':"none"},
   guideline_answer(B, Reply, Outcome),
   Outcome = done(Answers, Missing),
   assertion(Missing == 1),
   length(Answers, 2),
   append_guideline_answers(Dir, Sha, B, Answers),
   apply_guidelines(Tdsl, Dir, Summary),
   assertion(Summary == "1 paper(s): 4 routed cell(s), 2 typed by guidelines, 1 kept (\"none\"), 1 pending"),
   guided_cells(Dir, Cells, Counts),
   nth0(0, Cells, Alice), nth0(5, Cells, Alice2), nth0(1, Cells, N42),
   nth0(2, Cells, Odd), nth0(4, Cells, Bob),
   assertion(Alice.type == "Name"), assertion(Alice.source == "guideline"),
   assertion(Alice.rule_type == "Word"), assertion(Alice.family == "Text"),
   % Name's first supertype is Text, so the Word cell loses Word's group.
   assertion(Bob.group == "Word"), assertion(Alice.group == "Text"),
   assertion(Alice2.type == "Name"),
   assertion(N42.type == "Num"), assertion(\+ get_dict(rule_type, N42, _)),
   assertion(Odd.type == "untyped"), assertion(Odd.rule_type == "untyped"),
   assertion(Bob.type == "Word"),
   assertion(Counts.guided == 2), assertion(Counts.pending == 1),
   % Only bob is sent again.
   guideline_requests(Tdsl, Dir, S2),
   assertion(S2 == "1 paper(s): 1 batch(es), 1 cell text(s) to send"),
   delete_directory_and_contents(Dir).

test(reply_forms) :-
   B = json{batch_id:"P/1", caption:null, prompt:"",
            items:[json{id:"1", text:"a", rule_type:"Word", allowed:["Name"]}]},
   guideline_answer(B, "{\"1\": \" Name \"}", O1),
   assertion(O1 = done([_-"Name"], 0)),
   guideline_answer(B, json{1:"Name"}, O2),
   assertion(O2 = done([_-"Name"], 0)),
   guideline_answer(B, json{'1':"Label"}, O3), assertion(O3 = retry(_)),
   guideline_answer(B, no_answer, O4), assertion(O4 = retry(_)),
   guideline_answer(B, "not json", O5), assertion(O5 = retry(_)).

test(program_change_invalidates) :-
   tmp_dir(Dir),
   make_dataset(Dir, "", Tdsl),
   guideline_requests(Tdsl, Dir, _),
   guideline_queue(Dir, none, [batch(_, Sha, B)]),
   guideline_answer(B, json{'1':"Name", '2':"Label", '3':"Label"}, done(As, 0)),
   append_guideline_answers(Dir, Sha, B, As),
   guideline_requests(Tdsl, Dir, S1),
   assertion(S1 == "1 paper(s): 0 batch(es), 0 cell text(s) to send"),
   directory_file_path(Dir, 'papers/PMC1/guideline_requests.json', ReqFile),
   assertion(\+ exists_file(ReqFile)),
   program_text("% edited", Text), write_text(Tdsl, Text),
   guideline_requests(Tdsl, Dir, S2),
   assertion(S2 == "1 paper(s): 1 batch(es), 3 cell text(s) to send"),
   delete_directory_and_contents(Dir).

test(paper_filter) :-
   tmp_dir(Dir),
   make_dataset(Dir, "", Tdsl),
   directory_file_path(Dir, 'papers/PMC2', Other),
   make_directory_path(Other),
   directory_file_path(Dir, 'papers/PMC1/tables.jsonl', Tables),
   directory_file_path(Other, 'tables.jsonl', OtherTables),
   copy_file(Tables, OtherTables),
   type_dataset(Tdsl, Dir, ['PMC2']),
   directory_file_path(Other, 'types.jsonl', OtherTypes),
   assertion(exists_file(OtherTypes)),
   guideline_requests(Tdsl, Dir, ['PMC2'], S1),
   assertion(S1 == "1 paper(s): 1 batch(es), 3 cell text(s) to send"),
   directory_file_path(Dir, 'papers/PMC1/guideline_requests.json', Skipped),
   assertion(\+ exists_file(Skipped)),
   apply_guidelines(Tdsl, Dir, ['PMC2'], _),
   directory_file_path(Other, 'guided_types.jsonl', Guided),
   directory_file_path(Dir, 'papers/PMC1/guided_types.jsonl', NotGuided),
   assertion(exists_file(Guided)),
   assertion(\+ exists_file(NotGuided)),
   delete_directory_and_contents(Dir).

test(caption_analysis) :-
   tmp_dir(Dir),
   make_dataset(Dir, "set-option enable_caption_analysis", Tdsl),
   guideline_requests(Tdsl, Dir, _),
   request(Dir, R),
   R.batches = [B],
   assertion(B.caption == "People and labels"),
   assertion(sub_string(B.prompt, _, _, _, "Table caption: \"People and labels\"")),
   delete_directory_and_contents(Dir).

:- end_tests(guideline_step).
