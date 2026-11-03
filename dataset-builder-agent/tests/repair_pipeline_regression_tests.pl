% Tables made valid by the repair (table_repair.pl) through the rest of the
% pipeline, without network or LLM: the review decision, the final page, the
% certificate and the export, and the refusal of a review whose repair
% tables.jsonl no longer gives.
% From dataset-builder-agent/tests/:
%   swipl -q -s repair_pipeline_regression_tests.pl -g run_tests -t halt
:- use_module('../src/dataset_pipeline').
:- use_module('../src/table_review').
:- use_module(review_fixtures).
:- use_module('../src/table_export').
:- use_module(library(filesex)).
:- use_module(library(readutil)).
:- if(exists_source(library(json))).
:- use_module(library(json)).
:- else.
:- use_module(library(http/json)).
:- endif.

% PMC906, built by the real pipeline. Each year is written once, with a
% blank below it, over the same two treatments, so (1, 2) is refused (rule
% 3) until the blanks are merged into the years.
%   t0  the plain table: (1, 2) is a plain boundary after the repair
%   t1  the same under a title row, set aside: (2, 2) is a layout after it
repair_table(0, '<table><tr><th>Year</th><th>Treatment</th><th>Yield</th></tr><tr><td>2014</td><td>N0</td><td>1</td></tr><tr><td></td><td>N1</td><td>2</td></tr><tr><td>2015</td><td>N0</td><td>3</td></tr><tr><td></td><td>N1</td><td>4</td></tr></table>').
repair_table(1, '<table><tr><th colspan="3">Yield by year</th></tr><tr><th>Year</th><th>Treatment</th><th>Yield</th></tr><tr><td>2014</td><td>N0</td><td>1</td></tr><tr><td></td><td>N1</td><td>2</td></tr><tr><td>2015</td><td>N0</td><td>3</td></tr><tr><td></td><td>N1</td><td>4</td></tr></table>').

repair_workspace(Root) :-
    tmp_file(repair_pipeline, Root), make_directory(Root),
    directory_file_path(Root, dataset, Dataset),
    make_directory(Dataset),
    repair_table(0, T0), repair_table(1, T1),
    format(atom(Article),
       '<article><front><article-meta><article-id pub-id-type="pmc">906</article-id></article-meta></front><body>~w~w</body></article>',
       [T0, T1]),
    directory_file_path(Root, 'input.xml', Input),
    write_text(Input, Article),
    process_paper("906", Input, Dataset, _),
    write_inference(Dataset, []).

repair_cleanup(Root) :-
    ( exists_directory(Root) -> delete_directory_and_contents(Root) ; true ).

write_text(File, Text) :-
    setup_call_cleanup(open(File, write, Out, [encoding(utf8)]),
                       write(Out, Text), close(Out)).

paper_file(Root, Name, File) :-
    format(atom(Relative), 'dataset/papers/PMC906/~w', [Name]),
    directory_file_path(Root, Relative, File).

file_text(File, Text) :-
    read_file_to_string(File, Text, [encoding(utf8)]).

settings(Root, Settings) :-
    review_settings(Root, none, none, "test:model", Settings).

answer(H, V, json{parse_correct:false, column_header_rows:H,
                  row_header_columns:V, reason:"test"}).

% Reviews PMC906: t0 at (1, 2), t1 at (2, 2).
review_paper(Root, Results) :-
    directory_file_path(Root, dataset, Dataset),
    settings(Root, S),
    review_queue(Dataset, S, [Paper], _),
    review_paper_items(Paper, [I0, I1]),
    answer(1, 2, A0), answer(2, 2, A1),
    review_answer(I0, A0, 1, done(R0)),
    review_answer(I1, A1, 1, done(R1)),
    Results = [R0, R1],
    publish_paper_review(Dataset, Paper, S, Results, _).

records(Root, Records) :-
    paper_file(Root, 'tables.jsonl', File),
    dataset_pipeline:read_table_jsonl(File, Records).

reviews(Root, Reviews) :-
    paper_file(Root, 'review.jsonl', File),
    dataset_pipeline:read_table_jsonl(File, Reviews).

:- begin_tests(repair_pipeline).

test(the_boundary_is_refused_before_the_repair,
     [setup(repair_workspace(Root)), cleanup(repair_cleanup(Root))]) :-
    records(Root, [T0, T1]),
    \+ ( member(C, T0.candidates), C.hmd =:= 1, C.vmd =:= 2 ),
    \+ ( member(C, T1.candidates), C.vmd =:= 2 ).

test(a_repaired_table_is_valid_by_the_repair,
     [setup(repair_workspace(Root)), cleanup(repair_cleanup(Root))]) :-
    review_paper(Root, [R0, R1]),
    R0.final_status == "valid", R0.decided_by == "repair",
    R0.selected_candidate_id == "PMC906/t0/repaired/h1_v2",
    R0.repair.status == "repaired",
    R0.repair.matched == json{kind:"boundary", hmd:1, vmd:2},
    R0.disagreement.category == "missing_hierarchy_evidence",
    R1.final_status == "valid", R1.decided_by == "repair",
    sub_string(R1.selected_candidate_id, 0, _, _, "PMC906/t1/repaired/layout"),
    R1.repair.matched.kind == "layout", !.

test(the_repaired_record_drops_the_merged_cells,
     [setup(repair_workspace(Root)), cleanup(repair_cleanup(Root))]) :-
    review_paper(Root, _),
    records(Root, [T0, _]), reviews(Root, [V0, _]),
    reviewed_record(T0, V0, E0),
    E0.table_uid == "PMC906/t0/repaired",
    E0.source_table_uid == "PMC906/t0",
    E0.source_raster == T0.raster,
    E0.raster == [[0, 1, 2], [3, 4, 5], [3, 7, 8], [9, 10, 11], [9, 13, 14]],
    length(T0.cells, 15), length(E0.cells, 13),
    \+ ( member(C, E0.cells), memberchk(C.cell_id, [6, 12]) ),
    % A review not decided by the repair keeps the record.
    reviewed_record(T0, V0.put(decided_by, "llm"), Same),
    Same == T0.

test(final_page_says_the_table_was_repaired,
     [setup(repair_workspace(Root)), cleanup(repair_cleanup(Root))]) :-
    review_paper(Root, _),
    paper_file(Root, 'final_table0.html', F0), file_text(F0, P0),
    sub_string(P0, _, _, _, "<h2 class=\"final-status\">Parse Succeeded After Repair</h2>"),
    sub_string(P0, _, _, _, "<p class=\"repair\">Merging 2 empty cells"),
    % The blank below 2014 is colored as row header, like 2014.
    sub_string(P0, _, _, _, "background-color: skyblue\">2014<"),
    sub_string(P0, _, _, _, "background-color: skyblue\"></td>"),
    paper_file(Root, 'final_table1.html', F1), file_text(F1, P1),
    sub_string(P1, _, _, _, "Parse Succeeded After Repair"),
    sub_string(P1, _, _, _, "khaki"), !.

test(the_certificate_is_that_of_the_repaired_table,
     [setup(repair_workspace(Root)), cleanup(repair_cleanup(Root))]) :-
    review_paper(Root, _),
    paper_file(Root, '', Dir),
    directory_files(Dir, Entries),
    include([E]>>sub_atom(E, 0, _, _, certificate), Entries, Names0),
    msort(Names0, Names),
    Names = [N0, N1],
    N0 == 'certificate0_repaired_h1_v2.pl',
    sub_atom(N1, 0, _, _, 'certificate1_repaired_layout'),
    settings(Root, S), directory_file_path(Root, dataset, Dataset),
    review_queue(Dataset, S, [], ["PMC906"-"review is up to date"]).

test(export_reads_the_repaired_table,
     [setup(repair_workspace(Root)), cleanup(repair_cleanup(Root))]) :-
    review_paper(Root, _),
    settings(Root, S), directory_file_path(Root, dataset, Dataset),
    export_reviewed_papers(Dataset, S, _),
    paper_file(Root, 'final_tables.json', File),
    setup_call_cleanup(open(File, read, In, [encoding(utf8)]),
                       json_read_dict(In, Json, [default_tag(json)]),
                       close(In)),
    Json.tables = [E0, E1],
    E0.table_uid == "PMC906/t0",
    E0.candidate_id == "PMC906/t0/repaired/h1_v2",
    E0.export_error == null,
    E0.repair.repair_version == "empty-merge-v3",
    length(E0.repair.merges, 2),
    E0.subtables = [Sub],
    Sub.get('vertical metadata') ==
        [json{'2014':[json{'N0':[]}, json{'N1':[]}]},
         json{'2015':[json{'N0':[]}, json{'N1':[]}]}],
    E1.export_error == null,
    E1.separators == [json{row:0, text:"Yield by year"}].

test(a_review_whose_repair_no_longer_holds_is_refused,
     [setup(repair_workspace(Root)), cleanup(repair_cleanup(Root))]) :-
    review_paper(Root, _),
    records(Root, [T0, _]), reviews(Root, [V0, _]),
    % Another merge than the repair gives.
    V0.repair.merges = [M|Ms],
    Edited = V0.put(repair, V0.repair.put(merges, [M.put(into, 4)|Ms])),
    catch(final_table_html(T0, Edited, _), error(repair_mismatch(U1), _), true),
    U1 == "PMC906/t0",
    % A boundary the repair does not make a candidate.
    Moved = V0.put(llm_boundary, json{hmd:1, vmd:1}),
    catch(selected_certificates([T0], [Moved], _), error(repair_mismatch(U2), _), true),
    U2 == "PMC906/t0",
    % No repair recorded at all.
    Bare = V0.put(repair, null),
    catch(table_export:export_table(T0, Bare, _), error(repair_mismatch(U3), _), true),
    U3 == "PMC906/t0".

:- end_tests(repair_pipeline).
