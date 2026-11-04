% Arms A (llm-only) and B (constraints) of the ablation study
% (ablation_review.pl), and the table filter of the full review, without an
% LLM: the model's answers are given directly to ablation_answer/4.
% From dataset-builder-agent/tests/:
%   swipl -q -s ablation_review_regression_tests.pl -g run_tests -t halt
:- use_module('../src/dataset_pipeline').
:- use_module('../src/table_review').
:- use_module('../src/ablation_review').
:- use_module(review_fixtures).
:- use_module(library(filesex)).
:- use_module(library(readutil)).
:- if(exists_source(library(json))).
:- use_module(library(json)).
:- else.
:- use_module(library(http/json)).
:- endif.

% A workspace with one published paper, PMC901, built by the real pipeline:
%   t0  ambiguous  2x2 grid: h0_v1, h1_v0, h1_v1
%   t1  ambiguous  row header spanning two rows (3x3): h1_v0, h1_v1, h1_v2
%   t2  abstained  a single cell
ablation_workspace(Root) :-
    tmp_file(ablation_review, Root), make_directory(Root),
    directory_file_path(Root, '.deepclause', Config),
    make_directory(Config),
    directory_file_path(Config, 'config.json', ConfigFile),
    write_text(ConfigFile, '{"models":{"run":"test:configured-model"}}'),
    directory_file_path(Root, dataset, Dataset),
    make_directory(Dataset),
    directory_file_path(Root, 'input.xml', Input),
    write_text(Input,
       '<article><front><article-meta><article-id pub-id-type="pmc">901</article-id></article-meta></front><body><table-wrap><label>Table 1</label><caption><p>Doses</p></caption><table><tr><th>Drug</th><th>Dose</th></tr><tr><td>A</td><td>1</td></tr></table></table-wrap><table><tr><th>A</th><th>B</th><th>C</th></tr><tr><th rowspan="2">R</th><td>1</td><td>2</td></tr><tr><td>3</td><td>4</td></tr></table><table><tr><td>only</td></tr></table></body></article>'),
    process_paper("901", Input, Dataset, _),
    write_inference(Dataset, []).

ablation_cleanup(Root) :-
    ( exists_directory(Root) -> delete_directory_and_contents(Root) ; true ).

write_text(File, Text) :-
    setup_call_cleanup(open(File, write, Out, [encoding(utf8)]),
                       write(Out, Text), close(Out)).

dataset_dir(Root, Dataset) :- directory_file_path(Root, dataset, Dataset).

settings(Root, Arm, Settings) :-
    ablation_settings(Root, Arm, none, none, none, none, Settings).

items(Root, Settings, Items) :-
    dataset_dir(Root, Dataset),
    ablation_queue(Dataset, Settings, [Paper], []),
    ablation_paper_items(Paper, Items).

% One subtable of the whole table, with H and V, and no separator rows.
answer(LastRow, LastColumn, H, V,
       json{separator_rows:[],
            subtables:[json{first_row:0, last_row:LastRow, first_column:0,
                            last_column:LastColumn, column_header_rows:H,
                            row_header_columns:V}],
            reason:"test"}).

answer_result(Item, Answer, Result) :-
    ablation_answer(Item, Answer, 1, done(Result)).

% Reviews every table of the paper: Answers pairs a table index with the
% model's answer; a table without one must not be asked.
review_all(Root, Settings, Answers, Results) :-
    dataset_dir(Root, Dataset),
    ablation_queue(Dataset, Settings, [Paper], _),
    ablation_paper_items(Paper, Items),
    findall(R, ( nth0(I, Items, Item), result_for(Item, I, Answers, R) ), Results),
    publish_ablation_review(Dataset, Paper, Settings, Results, _).

result_for(Item, I, Answers, Result) :-
    ablation_item_action(Item, Action),
    (   Action == skip
    ->  ablation_skip_result(Item, Result)
    ;   memberchk(I-Answer, Answers),
        ablation_answer(Item, Answer, 1, Outcome),
        (   Outcome = done(Result) -> true
        ;   Outcome = retry(Why), ablation_failed_result(Item, Why, 2, Result) )
    ).

paper_file(Root, Name, File) :-
    dataset_dir(Root, Dataset),
    directory_file_path(Dataset, 'papers/PMC901', Dir),
    directory_file_path(Dir, Name, File).

read_records(File, Records) :- dataset_pipeline:read_table_jsonl(File, Records).

read_json(File, Json) :-
    setup_call_cleanup(open(File, read, In, [encoding(utf8)]),
                       json_read_dict(In, Json, [default_tag(json)]),
                       close(In)).

:- begin_tests(ablation_review).

test(settings_need_a_known_arm,
     [setup(ablation_workspace(Root)), cleanup(ablation_cleanup(Root)),
      throws(error(domain_error(ablation_arm, "full"), _))]) :-
    settings(Root, "full", _).

test(table_filter_reads_uids_and_rejects_others,
     [throws(error(domain_error(table_uid, "PMC1"), _))]) :-
    review_table_filter("pmc901/t0, PMC12/t3", Uids),
    assertion(Uids == ["PMC901/t0", "PMC12/t3"]),
    review_table_filter(none, All),
    assertion(All == all),
    review_table_filter("PMC1", _).

test(dataset_must_be_a_relative_directory_inside_the_workspace) :-
    review_dataset_dir("/workspace", none, D0),
    assertion(D0 == "/workspace/dataset"),
    review_dataset_dir("/workspace", "ablation/smoke/dataset/", D1),
    assertion(D1 == "/workspace/ablation/smoke/dataset"),
    forall(member(Bad, ["../x", "/abs", "a/../b", ""]),
           assertion(catch(( review_dataset_dir("/workspace", Bad, _), fail ),
                           error(domain_error(dataset_dir, _), _), true))).

test(both_arms_send_the_same_prompt_without_candidates,
     [setup(ablation_workspace(Root)), cleanup(ablation_cleanup(Root))]) :-
    settings(Root, "llm-only", A), items(Root, A, [ItemA|_]),
    settings(Root, "constraints", B), items(Root, B, [ItemB|_]),
    ablation_item_prompt(ItemA, PromptA),
    ablation_item_prompt(ItemB, PromptB),
    assertion(PromptA == PromptB),
    assertion(\+ sub_string(PromptA, _, _, _, "candidate")),
    assertion(\+ sub_string(PromptA, _, _, _, "proposed")),
    % The table is shown exactly as the full review shows it.
    paper_file(Root, 'tables.jsonl', Tables),
    read_records(Tables, [Record|_]),
    table_block(Record, Block),
    assertion(sub_string(PromptA, _, _, 0, Block)),
    assertion(sub_string(PromptA, _, _, _, "row 0: c0* \"Drug\" | c1* \"Dose\"")).

test(only_llm_only_asks_about_a_table_the_parser_abstained_on,
     [setup(ablation_workspace(Root)), cleanup(ablation_cleanup(Root))]) :-
    settings(Root, "llm-only", A), items(Root, A, ItemsA),
    settings(Root, "constraints", B), items(Root, B, ItemsB),
    findall(X, ( member(I, ItemsA), ablation_item_action(I, X) ), ActionsA),
    findall(X, ( member(I, ItemsB), ablation_item_action(I, X) ), ActionsB),
    assertion(ActionsA == [ask, ask, ask]),
    assertion(ActionsB == [ask, ask, skip]),
    nth0(2, ItemsB, Abstained),
    ablation_skip_result(Abstained, R),
    assertion(R.final_status == "unparseable"),
    assertion(R.decided_by == "parser").

test(constraints_arm_selects_the_candidate_the_segmentation_equals,
     [setup(ablation_workspace(Root)), cleanup(ablation_cleanup(Root))]) :-
    settings(Root, "constraints", S), items(Root, S, [T0, T1|_]),
    answer(1, 1, 1, 1, Match),
    answer_result(T0, Match, R0),
    assertion(R0.final_status == "valid"),
    assertion(R0.selected_candidate_id == "PMC901/t0/h1_v1"),
    assertion(R0.decided_by == "llm"),
    % t1 has a merged cell, so no candidate without header rows.
    answer(2, 2, 0, 1, Other),
    answer_result(T1, Other, R1),
    assertion(R1.final_status == "unparseable"),
    assertion(R1.selected_candidate_id == null).

test(llm_only_arm_keeps_any_readable_segmentation,
     [setup(ablation_workspace(Root)), cleanup(ablation_cleanup(Root))]) :-
    settings(Root, "llm-only", S), items(Root, S, [_, T1|_]),
    answer(2, 2, 0, 1, Other),
    answer_result(T1, Other, R),
    assertion(R.final_status == "valid"),
    assertion(R.selected_candidate_id == null),
    assertion(R.segmentation.subtables = [json{first_row:0, last_row:2,
              first_column:0, last_column:2, column_header_rows:0,
              row_header_columns:1}]),
    assertion(R.uncovered_slots == 0).

test(separator_rows_leave_the_subtables_and_gaps_are_counted,
     [setup(ablation_workspace(Root)), cleanup(ablation_cleanup(Root))]) :-
    settings(Root, "llm-only", S), items(Root, S, [_, T1|_]),
    % Row 0 set aside; the subtable covers rows 0-2 but only columns 0-1.
    Answer = json{separator_rows:[0],
                  subtables:[json{first_row:0, last_row:2, first_column:0,
                                  last_column:1, column_header_rows:1,
                                  row_header_columns:1}]},
    answer_result(T1, Answer, R),
    assertion(R.segmentation == json{separator_rows:[0],
              subtables:[json{first_row:1, last_row:2, first_column:0,
                              last_column:1, column_header_rows:1,
                              row_header_columns:1}]}),
    assertion(R.uncovered_slots == 2).

test(unreadable_segmentations_are_retried,
     [setup(ablation_workspace(Root)), cleanup(ablation_cleanup(Root))]) :-
    settings(Root, "llm-only", S), items(Root, S, [_, T1|_]),
    Sub = json{first_row:0, last_row:2, first_column:0, last_column:2,
               column_header_rows:1, row_header_columns:0},
    Overlap = json{separator_rows:[], subtables:[Sub, Sub]},
    OutOfRange = json{separator_rows:[], subtables:[Sub.put(last_row, 3)]},
    TooManyHeaders = json{separator_rows:[1], subtables:[Sub.put(column_header_rows, 3)]},
    BadSeparator = json{separator_rows:[5], subtables:[Sub]},
    NoSubtables = json{separator_rows:[], subtables:[]},
    forall(member(A, [Overlap, OutOfRange, TooManyHeaders, BadSeparator,
                      NoSubtables, no_answer, "not json"]),
           ( ablation_answer(T1, A, 1, Outcome),
             assertion(Outcome = retry(_)) )),
    % Numbers as strings, JSON text and a missing separator_rows are read.
    Text = '{"subtables":[{"first_row":"0","last_row":2,"first_column":0,"last_column":2,"column_header_rows":1,"row_header_columns":0}]}',
    ablation_answer(T1, Text, 1, done(R)),
    assertion(R.final_status == "valid").

test(published_review_and_export_use_the_arm_files,
     [setup(ablation_workspace(Root)), cleanup(ablation_cleanup(Root))]) :-
    settings(Root, "llm-only", S),
    answer(1, 1, 1, 1, A0),
    answer(1, 1, 2, 0, AllHeaders),
    answer(0, 0, 0, 0, A2),
    review_all(Root, S, [0-A0, 2-A2, 1-AllHeaders], _),
    paper_file(Root, 'review.llm-only.jsonl', ReviewFile),
    read_records(ReviewFile, Reviews),
    assertion(length(Reviews, 3)),
    paper_file(Root, 'final_tables.llm-only.json', ExportFile),
    read_json(ExportFile, Export),
    Export.tables = [E0, E1, E2],
    assertion(E0.final_status == "valid"),
    assertion(E0.export_error == null),
    E0.subtables = [Sub0],
    assertion(get_dict('vertical metadata', Sub0, [json{'A':[]}])),
    % A header of every row leaves no data: the export cannot build it.
    assertion(E1.final_status == "valid"),
    assertion(E1.export_error \== null),
    assertion(E1.subtables == null),
    assertion(E2.final_status == "valid"),
    % The full pipeline's files are not written.
    paper_file(Root, 'review.jsonl', Full),
    assertion(\+ exists_file(Full)),
    % A current review is not redone.
    dataset_dir(Root, Dataset),
    ablation_queue(Dataset, S, Queue, [_-Reason]),
    assertion(Queue == []),
    assertion(Reason == "review is up to date").

test(constraints_export_is_that_of_the_matched_candidate,
     [setup(ablation_workspace(Root)), cleanup(ablation_cleanup(Root))]) :-
    settings(Root, "constraints", S),
    answer(1, 1, 1, 1, A0),
    answer(2, 2, 1, 1, A1),
    review_all(Root, S, [0-A0, 1-A1], _),
    paper_file(Root, 'final_tables.constraints.json', ExportFile),
    read_json(ExportFile, Export),
    Export.tables = [E0, E1, E2],
    assertion(E0.candidate_id == "PMC901/t0/h1_v1"),
    assertion(E1.candidate_id == "PMC901/t1/h1_v1"),
    assertion(E1.export_error == null),
    assertion(E2.final_status == "unparseable").

test(a_review_with_a_table_filter_is_never_current,
     [setup(ablation_workspace(Root)), cleanup(ablation_cleanup(Root))]) :-
    ablation_settings(Root, "llm-only", none, "PMC901/t1", none, none, S),
    items(Root, S, Items),
    findall(X, ( member(I, Items), ablation_item_action(I, X) ), Actions),
    assertion(Actions == [skip, ask, skip]),
    answer(2, 2, 1, 1, A1),
    review_all(Root, S, [1-A1], [R0, R1, _]),
    assertion(R0.not_reviewed_reason == "not_selected"),
    assertion(R0.final_status == "unreviewed"),
    assertion(R1.final_status == "valid"),
    dataset_dir(Root, Dataset),
    ablation_queue(Dataset, S, Queue, _),
    assertion(Queue = [_]).

test(full_review_sends_only_the_filtered_tables,
     [setup(ablation_workspace(Root)), cleanup(ablation_cleanup(Root))]) :-
    review_filtered_settings(Root, none, "PMC901/t1", none, none, S),
    dataset_dir(Root, Dataset),
    review_queue(Dataset, S, [Paper], []),
    review_paper_items(Paper, Items),
    findall(X, ( member(I, Items), review_item_action(I, X) ), Actions),
    assertion(Actions == [skip, ask, skip]),
    Items = [T0|_],
    review_skip_result(T0, R0),
    assertion(R0.not_reviewed_reason == "not_selected"),
    assertion(R0.final_status == "unreviewed").

:- end_tests(ablation_review).
