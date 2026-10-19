% LLM review of candidate parses (table_review.pl), without an LLM: the
% model's answers are given directly to review_answer/4.
% From dataset-builder-agent/tests/:
%   swipl -q -s table_review_regression_tests.pl -g run_tests -t halt
:- use_module('../src/dataset_pipeline').
:- use_module('../src/table_review').
:- use_module(library(filesex)).
:- use_module(library(readutil)).
:- if(exists_source(library(json))).
:- use_module(library(json)).
:- else.
:- use_module(library(http/json)).
:- endif.

% A workspace with one published paper, PMC901, built by the real pipeline:
%   t0  ambiguous  2x2 grid: h0_v1, h1_v0, h1_v1 (a header row, a header
%                  column, or both; candidate ids give the counts)
%   t1  ambiguous  row header spanning two rows: h1_v0, h1_v1, h1_v2 (no
%                  candidate without header rows: it has a merged cell)
%   t2  abstained  a single cell
review_workspace(Root) :-
    tmp_file(table_review, Root), make_directory(Root),
    directory_file_path(Root, '.deepclause', Config),
    make_directory(Config),
    directory_file_path(Config, 'config.json', ConfigFile),
    write_text(ConfigFile, '{"models":{"run":"test:configured-model"}}'),
    directory_file_path(Root, dataset, Dataset),
    make_directory(Dataset),
    directory_file_path(Root, 'input.xml', Input),
    write_text(Input,
       '<article><front><article-meta><article-id pub-id-type="pmc">901</article-id></article-meta></front><body><table-wrap><label>Table 1</label><caption><p>Doses "high" and low</p></caption><table><tr><th>Drug</th><th>Dose</th></tr><tr><td>A</td><td>1</td></tr></table></table-wrap><table><tr><th>A</th><th>B</th><th>C</th></tr><tr><th rowspan="2">R</th><td>1</td><td>2</td></tr><tr><td>3</td><td>4</td></tr></table><table><tr><td>only</td></tr></table></body></article>'),
    process_paper("901", Input, Dataset, _).

review_cleanup(Root) :-
    ( exists_directory(Root) -> delete_directory_and_contents(Root) ; true ).

write_text(File, Text) :-
    setup_call_cleanup(open(File, write, Out, [encoding(utf8)]),
                       write(Out, Text), close(Out)).

dataset_dir(Root, Dataset) :- directory_file_path(Root, dataset, Dataset).

settings(Root, Settings) :-
    review_settings(Root, none, none, none, Settings).

queued_items(Root, Settings, Items) :-
    dataset_dir(Root, Dataset),
    review_queue(Dataset, Settings, [Paper], []),
    review_paper_items(Paper, Items).

item(Items, Index, Item) :- nth0(Index, Items, Item).

boundary_answer(H, V, json{column_header_rows:H, row_header_columns:V,
                            reason:"test"}).

% Reviews every paper in the queue: Answer(Index) gives the model's answer.
review_all(Root, Settings, Answers, Results) :-
    dataset_dir(Root, Dataset),
    review_queue(Dataset, Settings, [Paper], _),
    review_paper_items(Paper, Items),
    findall(R, ( nth0(I, Items, Item), result_for(Item, I, Answers, R) ), Results),
    publish_paper_review(Dataset, Paper, Settings, Results, _).

result_for(Item, I, Answers, Result) :-
    review_item_action(Item, Action),
    (   Action == skip
    ->  review_skip_result(Item, Result)
    ;   memberchk(I-Answer, Answers),
        review_answer(Item, Answer, 1, Outcome),
        (   Outcome = done(Result) -> true
        ;   Outcome = retry(Why), review_failed_result(Item, Why, 2, Result) )
    ).

review_file(Root, Records) :-
    dataset_dir(Root, Dataset),
    directory_file_path(Dataset, 'papers/PMC901/review.jsonl', File),
    dataset_pipeline:read_table_jsonl(File, Records).

:- begin_tests(table_review).

test(settings_take_model_from_config_or_parameter,
     [setup(review_workspace(Root)), cleanup(review_cleanup(Root))]) :-
    review_settings(Root, none, none, none, S1),
    S1.model == "test:configured-model",
    S1.model_source == "deepclause_config_run_slot",
    S1.papers == all, S1.force == false,
    review_settings(Root, "pmc901, 7", "true", "x:y", S2),
    S2.model == "x:y", S2.model_source == "run_parameter",
    S2.papers == ["PMC901", "PMC7"], S2.force == true.

test(settings_reject_malformed_paper_ids,
     [throws(error(domain_error(pmc_id, "PMC12a"), _))]) :-
    review_settings("/nonexistent", "PMC12a", none, none, _).

test(only_tables_with_candidates_are_sent,
     [setup(review_workspace(Root)), cleanup(review_cleanup(Root))]) :-
    settings(Root, S),
    queued_items(Root, S, [I0, I1, I2]),
    review_item_action(I0, ask), review_item_action(I1, ask),
    review_item_action(I2, skip),
    review_item_uid(I2, "PMC901/t2").

test(prompt_is_blind_and_describes_the_table,
     [setup(review_workspace(Root)), cleanup(review_cleanup(Root))]) :-
    settings(Root, S),
    queued_items(Root, S, Items),
    item(Items, 0, I0), review_item_prompt(I0, P0),
    sub_string(P0, _, _, _, "Label: Table 1"),
    sub_string(P0, _, _, _, "Caption: Doses \"high\" and low"),
    sub_string(P0, _, _, _, "row 0: c0* \"Drug\" | c1* \"Dose\""),
    sub_string(P0, _, _, _, "row 1: c0 \"A\" | c1 \"1\""),
    sub_string(P0, _, _, _, "the integer H, from 0 to 1"),
    \+ sub_string(P0, _, _, _, "h0_v0"),
    \+ sub_string(P0, _, _, _, "candidate"),
    item(Items, 1, I1), review_item_prompt(I1, P1),
    % The row header spans rows 1 and 2: written once, then as "part of the
    % cell above".
    sub_string(P1, _, _, _, "row 1: c0* \"R\" | c1 \"1\" | c2 \"2\""),
    sub_string(P1, _, _, _, "row 2: c0 ^ | c1 \"3\" | c2 \"4\"").

test(quotes_and_long_texts_are_escaped_and_marked) :-
    Record = json{rows:2, columns:2, raster:[[0,1],[2,3]],
                  context:json{label:"", caption:"", notes:[]},
                  cells:[json{cell_id:0, row:0, column:0, text:"say \"hi\"", tag:"th"},
                         json{cell_id:1, row:0, column:1, text:"B", tag:"th"},
                         json{cell_id:2, row:1, column:0, text:"x", tag:"td"},
                         json{cell_id:3, row:1, column:1, text:Long, tag:"td"}]},
    length(Codes, 300), maplist(=(0'a), Codes), string_codes(Long, Codes),
    table_review_prompt(Record, _, Prompt),
    sub_string(Prompt, _, _, _, "c0* \"say \\\"hi\\\"\""),
    sub_string(Prompt, _, _, _, " [...]\""),
    \+ sub_string(Prompt, _, _, _, "Label:").

test(matching_answer_validates_and_selects_the_candidate,
     [setup(review_workspace(Root)), cleanup(review_cleanup(Root))]) :-
    settings(Root, S),
    queued_items(Root, S, Items),
    item(Items, 1, I1),
    boundary_answer(1, 2, A),
    review_answer(I1, A, 1, done(R)),
    R.review_status == "reviewed",
    R.final_status == "valid", R.decided_by == "llm",
    R.selected_candidate_id == "PMC901/t1/h1_v2",
    R.candidate_ids == ["PMC901/t1/h1_v0", "PMC901/t1/h1_v1", "PMC901/t1/h1_v2"],
    R.llm_boundary == json{hmd:1, vmd:2},
    R.parser_status == "ambiguous",
    R.semantic_validation == "llm_reviewed_not_human_verified".

test(other_boundary_or_none_makes_the_table_unparseable,
     [setup(review_workspace(Root)), cleanup(review_cleanup(Root))]) :-
    settings(Root, S),
    queued_items(Root, S, Items),
    item(Items, 1, I1),
    boundary_answer(2, 1, Other),
    review_answer(I1, Other, 1, done(R1)),
    R1.final_status == "unparseable", R1.selected_candidate_id == null,
    R1.llm_boundary == json{hmd:2, vmd:1},
    % "No headers at all" is (0, 0): never a candidate (constraint 7).
    review_answer(I1, json{column_header_rows:0, row_header_columns:0,
                           reason:"list"}, 1, done(R2)),
    R2.final_status == "unparseable", R2.llm_boundary == json{hmd:0, vmd:0},
    R2.llm_reason == "list".

test(answers_as_json_text_or_numeric_strings_are_read,
     [setup(review_workspace(Root)), cleanup(review_cleanup(Root))]) :-
    settings(Root, S),
    queued_items(Root, S, Items),
    item(Items, 0, I0),
    review_answer(I0, "{\"column_header_rows\":\"1\",\"row_header_columns\":1.0}",
                  2, done(R)),
    R.final_status == "valid", R.attempts =:= 2, R.llm_reason == "".

test(unusable_answers_ask_for_a_retry,
     [setup(review_workspace(Root)), cleanup(review_cleanup(Root))]) :-
    settings(Root, S),
    queued_items(Root, S, Items),
    item(Items, 0, I0),
    forall(member(Bad, [ no_answer,
                         error(timeout),
                         "not json",
                         json{structure:"boundary"},
                         json{column_header_rows:3, row_header_columns:1},
                         json{column_header_rows:1, row_header_columns: -1},
                         json{column_header_rows:"x", row_header_columns:1} ]),
           review_answer(I0, Bad, 1, retry(_))).

test(skipped_and_failed_tables_are_recorded_honestly,
     [setup(review_workspace(Root)), cleanup(review_cleanup(Root))]) :-
    settings(Root, S),
    queued_items(Root, S, Items),
    item(Items, 2, I2),
    review_skip_result(I2, Skip),
    Skip.final_status == "unparseable", Skip.decided_by == "parser",
    Skip.not_reviewed_reason == "parser_abstained",
    item(Items, 0, I0),
    review_failed_result(I0, "no answer", 2, Failed),
    Failed.review_status == "review_failed",
    Failed.final_status == "unreviewed",
    Failed.error == "no answer", Failed.attempts =:= 2.

test(review_file_has_one_record_per_table_and_is_not_redone,
     [setup(review_workspace(Root)), cleanup(review_cleanup(Root))]) :-
    settings(Root, S),
    boundary_answer(1, 1, A0), boundary_answer(1, 2, A1),
    review_all(Root, S, [0-A0, 1-A1], _),
    review_file(Root, Records),
    findall(U-F, (member(R, Records), U = R.table_uid, F = R.final_status), Pairs),
    Pairs == ["PMC901/t0"-"valid", "PMC901/t1"-"valid", "PMC901/t2"-"unparseable"],
    Records = [First|_], string(First.tables_jsonl_sha256),
    dataset_dir(Root, Dataset),
    review_queue(Dataset, S, [], [Skipped]),
    Skipped == ("PMC901"-"review is up to date"),
    review_settings(Root, none, "true", none, Forced),
    review_queue(Dataset, Forced, [_], []),
    review_settings(Root, none, none, "other:model", OtherModel),
    review_queue(Dataset, OtherModel, [_], []).

test(failed_reviews_are_queued_again,
     [setup(review_workspace(Root)), cleanup(review_cleanup(Root))]) :-
    settings(Root, S),
    boundary_answer(1, 1, A0),
    review_all(Root, S, [0-A0, 1-no_answer], _),
    review_file(Root, [_, R1, _]),
    R1.review_status == "review_failed",
    dataset_dir(Root, Dataset),
    review_queue(Dataset, S, [_], []).

test(paper_filter_selects_and_reports_missing_papers,
     [setup(review_workspace(Root)), cleanup(review_cleanup(Root))]) :-
    dataset_dir(Root, Dataset),
    review_settings(Root, "PMC5", none, none, S1),
    review_queue(Dataset, S1, [], ["PMC5"-"not in dataset/papers"]),
    review_settings(Root, "PMC901", none, none, S2),
    review_queue(Dataset, S2, [P], []),
    review_paper_name(P, "PMC901").

test(changed_tables_file_is_not_overwritten_with_a_stale_review,
     [setup(review_workspace(Root)), cleanup(review_cleanup(Root)),
      throws(error(tables_changed_during_review("PMC901"), _))]) :-
    settings(Root, S),
    dataset_dir(Root, Dataset),
    review_queue(Dataset, S, [Paper], []),
    review_paper_items(Paper, Items),
    findall(R, (member(I, Items), review_failed_result(I, "x", 1, R)), Results),
    directory_file_path(Dataset, 'papers/PMC901/tables.jsonl', Tables),
    setup_call_cleanup(open(Tables, append, Out), nl(Out), close(Out)),
    publish_paper_review(Dataset, Paper, S, Results, _).

test(busy_paper_is_reported,
     [setup(review_workspace(Root)), cleanup(review_cleanup(Root)),
      throws(error(paper_busy("PMC901"), _))]) :-
    settings(Root, S),
    dataset_dir(Root, Dataset),
    review_queue(Dataset, S, [Paper], []),
    review_paper_items(Paper, Items),
    findall(R, (member(I, Items), review_failed_result(I, "x", 1, R)), Results),
    directory_file_path(Dataset, 'papers/.PMC901.lock', Lock),
    make_directory(Lock),
    publish_paper_review(Dataset, Paper, S, Results, _).

test(results_must_match_the_tables,
     [setup(review_workspace(Root)), cleanup(review_cleanup(Root)),
      throws(error(review_result_mismatch("PMC901"), _))]) :-
    settings(Root, S),
    dataset_dir(Root, Dataset),
    review_queue(Dataset, S, [Paper], []),
    review_paper_items(Paper, [I0|_]),
    review_failed_result(I0, "x", 1, R0),
    publish_paper_review(Dataset, Paper, S, [R0], _).

test(oversized_table_is_not_sent) :-
    Rows = 60, Cols = 50,
    numlist(1, Rows, Rs),
    findall(Row, ( member(R, Rs), R0 is R - 1,
                   findall(Id, (between(0, 49, C), Id is R0*Cols + C), Row) ), Raster),
    Record = json{table_uid:"PMC1/t0", pmc_id:"PMC1", table_index:0,
                  status:"unique", rows:Rows, columns:Cols, raster:Raster,
                  cells:[], context:json{label:"", caption:"", notes:[]},
                  candidates:[json{candidate_id:"PMC1/t0/h1_v1", hmd:1, vmd:1}]},
    review_settings("/nonexistent", none, none, "m:m", S),
    table_review:review_item_for(S, Record, Item),
    review_item_action(Item, skip),
    review_skip_result(Item, Result),
    Result.final_status == "unreviewed",
    Result.not_reviewed_reason == "too_large_for_review".

test(run_manifest_records_settings_and_lines,
     [setup(review_workspace(Root)), cleanup(review_cleanup(Root))]) :-
    settings(Root, S),
    dataset_dir(Root, Dataset),
    record_review_run(Dataset, S, ["PMC901: done"], ["PMC5"-"not in dataset/papers"], File),
    dataset_pipeline:read_json_file(File, M),
    M.model == "test:configured-model",
    M.prompt_version == "table-review-blind-v2-counts",
    M.paper_status_lines == ["PMC901: done"],
    M.skipped_papers = [Skipped], Skipped.pmc_id == "PMC5".

write_run_manifest(Root, Name, Json) :-
    dataset_dir(Root, Dataset),
    directory_file_path(Dataset, runs, Runs),
    directory_file_path(Runs, Name, Dir),
    make_directory_path(Dir),
    directory_file_path(Dir, 'manifest.json', File),
    write_text(File, Json).

test(build_run_selects_the_papers_to_review,
     [setup(review_workspace(Root)), cleanup(review_cleanup(Root))]) :-
    write_run_manifest(Root, 'run-a', '{"selected_pmc_ids":["901","5"]}'),
    dataset_dir(Root, Dataset),
    review_run_papers(Dataset, "run-a", Papers),
    Papers == "901,5",
    review_run_papers(Dataset, "/workspace/dataset/runs/run-a/manifest.json", Same),
    Same == Papers,
    review_settings(Root, Papers, none, none, S),
    review_queue(Dataset, S, [P], ["PMC5"-"not in dataset/papers"]),
    review_paper_name(P, "PMC901").

test(run_without_papers_is_an_error,
     [setup(review_workspace(Root)), cleanup(review_cleanup(Root)),
      throws(error(empty_run("run-b"), _))]) :-
    write_run_manifest(Root, 'run-b', '{"selected_pmc_ids":[]}'),
    dataset_dir(Root, Dataset),
    review_run_papers(Dataset, "run-b", _).

test(missing_or_unsafe_run_names_are_errors,
     [setup(review_workspace(Root)), cleanup(review_cleanup(Root))]) :-
    dataset_dir(Root, Dataset),
    catch(review_run_papers(Dataset, "run-missing", _), E1, true),
    E1 = error(existence_error(run_manifest, _), _),
    catch(review_run_papers(Dataset, "../papers", _), E2, true),
    E2 = error(domain_error(run_name, _), _).

final_page(Root, Index, Html) :-
    dataset_dir(Root, Dataset),
    format(atom(Rel), 'papers/PMC901/final_table~d.html', [Index]),
    directory_file_path(Dataset, Rel, File),
    read_file_to_string(File, Html, [encoding(utf8)]).

test(final_pages_show_success_misalignment_and_nothing_to_do,
     [setup(review_workspace(Root)), cleanup(review_cleanup(Root))]) :-
    settings(Root, S),
    boundary_answer(1, 1, A0),
    boundary_answer(2, 1, A1),
    review_all(Root, S, [0-A0, 1-A1], _),
    final_page(Root, 0, P0),
    sub_string(P0, _, _, _, "<h2 class=\"final-status\">Parse Succeeded</h2>"),
    sub_string(P0, _, _, _, "<p class=\"llm-reason\">test</p>"),
    sub_string(P0, _, _, _, "Table 1"),
    sub_string(P0, _, _, _, "background-color: springgreen\">Drug<"),
    sub_string(P0, _, _, _, "background-color: skyblue\">A<"),
    sub_string(P0, _, _, _, "background-color: lightgray\">1<"),
    % Heading, then reason, then table.
    sub_string(P0, B1, _, _, "Parse Succeeded"),
    sub_string(P0, B2, _, _, "llm-reason"),
    sub_string(P0, B3, _, _, "<table"),
    B1 < B2, B2 < B3,
    final_page(Root, 1, P1),
    sub_string(P1, _, _, _, "Error: Misalignment Between LLM And Formal Table Parser"),
    sub_string(P1, _, _, _, "<p class=\"llm-reason\">test</p>"),
    sub_string(P1, _, _, _, "LLM: 2 HMD rows, 1 VMD column."),
    sub_string(P1, _, _, _, "PMC901/t1/h1_v0 (1 HMD row, no VMD columns); PMC901/t1/h1_v1"),
    \+ sub_string(P1, _, _, _, "<table"),
    final_page(Root, 2, P2),
    sub_string(P2, _, _, _, "<h2 class=\"final-status\">Nothing To Do.</h2>"),
    \+ sub_string(P2, _, _, _, "<table").

test(final_page_colors_the_candidate_the_llm_chose,
     [setup(review_workspace(Root)), cleanup(review_cleanup(Root))]) :-
    settings(Root, S),
    boundary_answer(1, 1, A0),
    boundary_answer(1, 2, A1),
    review_all(Root, S, [0-A0, 1-A1], _),
    final_page(Root, 1, P1),
    sub_string(P1, _, _, _, "Parse Succeeded"),
    % h1_v2: column 1 below the header is row-header (skyblue), not data.
    sub_string(P1, _, _, _, "background-color: skyblue\">1<"),
    sub_string(P1, _, _, _, "background-color: lightgray\">2<").

test(final_page_escapes_the_llm_reason,
     [setup(review_workspace(Root)), cleanup(review_cleanup(Root))]) :-
    settings(Root, S),
    A0 = json{column_header_rows:1, row_header_columns:1,
              reason:"<script>alert(1)</script> & more"},
    review_all(Root, S, [0-A0, 1-no_answer], _),
    final_page(Root, 0, P0),
    \+ sub_string(P0, _, _, _, "<script>"),
    sub_string(P0, _, _, _, "&lt;script&gt;"),
    final_page(Root, 1, P1),
    sub_string(P1, _, _, _, "<h2 class=\"final-status\">Not Reviewed</h2>"),
    sub_string(P1, _, _, _, "No usable answer from the LLM").

test(current_review_without_pages_gets_them_without_a_new_review,
     [setup(review_workspace(Root)), cleanup(review_cleanup(Root))]) :-
    settings(Root, S),
    boundary_answer(1, 1, A0), boundary_answer(1, 2, A1),
    review_all(Root, S, [0-A0, 1-A1], _),
    dataset_dir(Root, Dataset),
    directory_file_path(Dataset, 'papers/PMC901', Dir),
    forall(between(0, 2, I),
           ( format(atom(N), 'final_table~d.html', [I]),
             directory_file_path(Dir, N, F), delete_file(F) )),
    review_queue(Dataset, S, [], [Skipped]),
    Skipped == ("PMC901"-"review is up to date; final_tableN.html written from it"),
    final_page(Root, 1, P1),
    sub_string(P1, _, _, _, "Parse Succeeded"),
    review_queue(Dataset, S, [], ["PMC901"-"review is up to date"]),
    directory_files(Dir, Entries),
    \+ ( member(E, Entries), sub_atom(E, _, _, 0, '.tmp') ).

test(final_table_rejects_a_review_of_another_table) :-
    catch(dataset_pipeline:final_table_html(json{table_uid:"PMC1/t0", candidates:[]},
                                            json{table_uid:"PMC1/t1"}, _), E, true),
    E = error(final_table_error(review_mismatch("PMC1/t0", "PMC1/t1")), _).

test(papers_built_with_last_index_boundaries_are_not_reviewed,
     [setup(review_workspace(Root)), cleanup(review_cleanup(Root))]) :-
    settings(Root, S),
    dataset_dir(Root, Dataset),
    directory_file_path(Dataset, 'papers/PMC901/tables.jsonl', Tables),
    read_file_to_string(Tables, Text, [encoding(utf8)]),
    atomic_list_concat(Parts, '"schema_version":"3.0"', Text),
    atomic_list_concat(Parts, '"schema_version":"1.0"', Old),
    write_text(Tables, Old),
    review_queue(Dataset, S, [], [Skipped]),
    Skipped = "PMC901"-Reason,
    sub_string(Reason, _, _, _, "rebuild the paper").

% Schema 3.x only added geometric certificates, so 2.x papers still count.
test(papers_built_before_certificates_are_still_reviewed,
     [setup(review_workspace(Root)), cleanup(review_cleanup(Root))]) :-
    settings(Root, S),
    dataset_dir(Root, Dataset),
    directory_file_path(Dataset, 'papers/PMC901/tables.jsonl', Tables),
    read_file_to_string(Tables, Text, [encoding(utf8)]),
    atomic_list_concat(Parts, '"schema_version":"3.0"', Text),
    atomic_list_concat(Parts, '"schema_version":"2.0"', Old),
    write_text(Tables, Old),
    review_queue(Dataset, S, [_], []).

:- end_tests(table_review).
