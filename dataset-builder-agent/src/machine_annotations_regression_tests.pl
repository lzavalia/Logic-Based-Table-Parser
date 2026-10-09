% F10: canonical machine-readable table annotations, no network required.
% swipl -q -s machine_annotations_regression_tests.pl -g run_tests -t halt
:- use_module(dataset_pipeline).
:- use_module(library(filesex)).
:- use_module(library(readutil)).

machine_workspace(Root) :-
    tmp_file(table_machine, Root), make_directory(Root).
machine_cleanup(Root) :-
    ( exists_directory(Root) -> delete_directory_and_contents(Root) ; true ).
machine_input(Root, Pmc, Fragment, File) :-
    directory_file_path(Root, 'input.xml', File),
    atom_string(Fragment, FragmentText),
    setup_call_cleanup(open(File, write, Out, [encoding(utf8)]),
       format(Out,
          '<article><front><article-meta><article-id pub-id-type="pmc">~d</article-id></article-meta></front><body>~s</body></article>',
          [Pmc, FragmentText]), close(Out)).
machine_published(Root, Pmc, Name, Path) :-
    format(string(PmcDir), 'PMC~d', [Pmc]),
    directory_file_path(Root, papers, Papers),
    directory_file_path(Papers, PmcDir, Dir),
    directory_file_path(Dir, Name, Path).
machine_outputs(Root, Pmc, Records, Metadata) :-
    machine_published(Root, Pmc, 'tables.jsonl', Jsonl),
    machine_published(Root, Pmc, 'metadata.json', Meta),
    dataset_pipeline:read_table_jsonl(Jsonl, Records),
    dataset_pipeline:read_json_file(Meta, Metadata).

:- begin_tests(machine_annotations).

test(merged_cells_produce_two_distinct_qualified_candidates,
     [setup(machine_workspace(Root)), cleanup(machine_cleanup(Root))]) :-
    Html = '<table id="T"><tr><th>A</th><th>B</th><th>C</th></tr><tr><th rowspan="2">R</th><td>1</td><td>2</td></tr><tr><td>3</td><td>4</td></tr></table>',
    machine_input(Root, 801, Html, File),
    process_paper("801", File, Root, _),
    machine_outputs(Root, 801, [Record], Meta),
    Record.schema_version == "1.0",
    Record.table_uid == "PMC801/t0",
    Record.raster == [[0,1,2],[3,4,5],[3,6,7]],
    Record.status == "ambiguous", Record.abstention_reason == null,
    Record.candidates = [First, Second],
    First.candidate_id == "PMC801/t0/h0_v0",
    Second.candidate_id == "PMC801/t0/h0_v1",
    First.hmd =:= 0, First.vmd =:= 0,
    Second.hmd =:= 0, Second.vmd =:= 1,
    First.failed_constraints == [], Second.failed_constraints == [],
    Meta.parsed_table_count =:= 1,
    Meta.tables = [Context], Context.candidate_count =:= 2,
    Context.annotation_status == "ambiguous",
    machine_published(Root, 801, 'annotated_table0.html', HtmlFile),
    read_file_to_string(HtmlFile, Inspection, [encoding(utf8)]),
    sub_string(Inspection, _, _, _, "Candidate h0_v0"),
    sub_string(Inspection, _, _, _, "Candidate h0_v1"),
    sub_string(Inspection, _, _, _, 'data-candidate-id="PMC801/t0/h0_v0"').

test(merged_id_labels_are_once_per_source_cell_and_have_xpath,
     [setup(machine_workspace(Root)), cleanup(machine_cleanup(Root))]) :-
    Html = '<table><thead><tr><th>A</th><th>B</th></tr></thead><tbody><tr><th rowspan="2">R</th><td>1</td></tr><tr><td>2</td></tr></tbody></table>',
    machine_input(Root, 802, Html, File),
    process_paper("802", File, Root, _),
    machine_outputs(Root, 802, [Record], _),
    Record.raster == [[0,1],[2,3],[2,4]],
    Record.cells = [C0,C1,C2,C3,C4],
    C0.cell_id =:= 0, C4.cell_id =:= 4,
    C2.row =:= 1, C2.column =:= 0,
    C2.kind == "source",
    sub_string(C2.source_xpath, _, _, _, "/*["),
    C3.source_xpath \== C4.source_xpath,
    forall(member(C, [C0,C1,C2,C3,C4]), C.source_xpath \== null),
    forall(member(Candidate, Record.candidates),
           ( length(Candidate.labels, 5),
             findall(Id, (member(Label, Candidate.labels), Id = Label.cell_id), Ids),
             Ids == [0,1,2,3,4] )).

test(synthetic_padding_has_no_false_source_xpath,
     [setup(machine_workspace(Root)), cleanup(machine_cleanup(Root))]) :-
    Html = '<table><tr><td>x</td><td>y</td></tr><tr><td>z</td></tr></table>',
    machine_input(Root, 803, Html, File),
    process_paper("803", File, Root, _),
    machine_outputs(Root, 803, [Record], _),
    Record.raster == [[0,1],[2,3]],
    last(Record.cells, Gap),
    Gap.cell_id =:= 3, Gap.kind == "synthetic_gap",
    Gap.source_xpath == null,
    Record.candidates = [Candidate],
    member(Label, Candidate.labels), Label.cell_id =:= 3,
    Label.region == "data".

test(no_valid_boundary_produces_explicit_abstention,
     [setup(machine_workspace(Root)), cleanup(machine_cleanup(Root))]) :-
    machine_input(Root, 804, '<table><tr><td>only</td></tr></table>', File),
    process_paper("804", File, Root, _),
    machine_outputs(Root, 804, [Record], Meta),
    Record.status == "abstained",
    Record.candidates == [],
    Record.abstention_reason == "no_boundary_satisfies_constraints",
    Meta.parsed_table_count =:= 0,
    machine_published(Root, 804, 'annotated_table0.html', HtmlFile),
    read_file_to_string(HtmlFile, Html, [encoding(utf8)]),
    sub_string(Html, _, _, _, "Abstained: no valid boundary").

test(zero_table_paper_still_publishes_empty_jsonl,
     [setup(machine_workspace(Root)), cleanup(machine_cleanup(Root))]) :-
    machine_input(Root, 805, '<p>No tables</p>', File),
    process_paper("805", File, Root, _),
    machine_outputs(Root, 805, Records, Meta),
    Records == [], Meta.tables == [], Meta.table_count =:= 0,
    machine_published(Root, 805, 'tables.jsonl', Jsonl),
    size_file(Jsonl, 0).

test(rerun_replaces_jsonl_and_candidate_ids_remain_stable,
     [setup(machine_workspace(Root)), cleanup(machine_cleanup(Root))]) :-
    Html = '<table><tr><td>x</td><td>y</td></tr><tr><td>a</td><td>b</td></tr></table>',
    machine_input(Root, 806, Html, File),
    process_paper("806", File, Root, _),
    machine_outputs(Root, 806, [Old], _),
    process_paper("806", File, Root, _),
    machine_outputs(Root, 806, [New], _),
    Old == New,
    machine_input(Root, 806, '<p>No tables</p>', Empty),
    process_paper("806", Empty, Root, _),
    machine_outputs(Root, 806, [], Meta),
    Meta.table_count =:= 0.

test(table_source_xpath_matches_section_order_not_dom_order,
     [setup(machine_workspace(Root)), cleanup(machine_cleanup(Root))]) :-
    Html = '<table><tfoot><tr><td>foot</td><td>f</td></tr></tfoot><tbody><tr><td>body</td><td>b</td></tr></tbody><thead><tr><th>head</th><th>h</th></tr></thead></table>',
    machine_input(Root, 807, Html, File),
    process_paper("807", File, Root, _),
    machine_outputs(Root, 807, [Record], _),
    Record.raster == [[0,1],[2,3],[4,5]],
    Record.cells = [C0,_,C2,_,C4,_],
    C0.text == "head", C2.text == "body", C4.text == "foot",
    C0.source_xpath \== C2.source_xpath,
    C2.source_xpath \== C4.source_xpath.

test(each_of_multiple_tables_has_independent_stable_ids,
     [setup(machine_workspace(Root)), cleanup(machine_cleanup(Root))]) :-
    Html = '<table id="same"><tr><td>x</td><td>y</td></tr><tr><td>a</td><td>b</td></tr></table><table id="same"><tr><td>x</td><td>y</td></tr><tr><td>a</td><td>b</td></tr></table>',
    machine_input(Root, 808, Html, File),
    process_paper("808", File, Root, _),
    machine_outputs(Root, 808, [One, Two], Meta),
    One.table_uid == "PMC808/t0", Two.table_uid == "PMC808/t1",
    One.source_table_id == Two.source_table_id,
    One.source_path \== Two.source_path,
    One.candidates = [C1], Two.candidates = [C2],
    C1.candidate_id \== C2.candidate_id,
    Meta.table_count =:= 2.

test(a_corrupted_jsonl_does_not_pass_stage_validation,
     [setup(machine_workspace(Root)), cleanup(machine_cleanup(Root))]) :-
    Html = '<table><tr><td>x</td><td>y</td></tr><tr><td>a</td><td>b</td></tr></table>',
    machine_input(Root, 809, Html, File),
    process_paper("809", File, Root, _),
    machine_published(Root, 809, 'tables.jsonl', Jsonl),
    setup_call_cleanup(open(Jsonl, write, Out), write(Out, ''), close(Out)),
    machine_published(Root, 809, 'metadata.json', MetaPath),
    file_directory_name(MetaPath, Dir),
    catch(dataset_pipeline:validate_paper_stage(Dir, 1, 1), Error, true),
    Error = error(incomplete_paper_stage(invalid_jsonl_size), _).

test(jsonl_escapes_source_newlines_and_quotes,
     [setup(machine_workspace(Root)), cleanup(machine_cleanup(Root))]) :-
    Html = '<table><tr><td>alpha &quot; beta\ngamma</td><td>café</td></tr><tr><td>z</td><td>x</td></tr></table>',
    machine_input(Root, 810, Html, File),
    process_paper("810", File, Root, _),
    machine_outputs(Root, 810, [Record], _),
    Record.cells = [First, Second|_],
    sub_string(First.text, _, _, _, "beta"),
    Second.text == "café",
    machine_published(Root, 810, 'tables.jsonl', JsonlFile),
    read_file_to_string(JsonlFile, Text, [encoding(utf8)]),
    split_string(Text, "\n", "\n", Lines),
    length(Lines, 1).

test(orphaned_source_cell_is_an_error_not_unlabeled,
     [throws(error(unmapped_source_cell(3), _))]) :-
    dataset_pipeline:parse_html(
       '<table><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></table>',
       Dom),
    dataset_pipeline:extract_tables(Dom, [Table]),
    dataset_pipeline:table_source_context(Table, [], none, Context),
    dataset_pipeline:machine_table_record("PMC811", 0, Table, Context,
                                         [[0,1],[2,2]], [], _, _).

test(stage_rejects_tampered_candidate_label_map,
     [setup(machine_workspace(Root)), cleanup(machine_cleanup(Root)),
      throws(error(incomplete_paper_stage(metadata_mismatch), _))]) :-
    Html = '<table><tr><td>x</td><td>y</td></tr><tr><td>a</td><td>b</td></tr></table>',
    machine_input(Root, 812, Html, File),
    process_paper("812", File, Root, _),
    machine_outputs(Root, 812, [Original], _),
    Original.candidates = [Candidate],
    put_dict(labels, Candidate, [], CorruptCandidate),
    put_dict(candidates, Original, [CorruptCandidate], CorruptRecord),
    machine_published(Root, 812, 'tables.jsonl', JsonlFile),
    setup_call_cleanup(open(JsonlFile, write, Out, [encoding(utf8)]),
        ( atom_json_dict(Text, CorruptRecord, [width(0)]), format(Out, '~w~n', [Text]) ),
        close(Out)),
    file_directory_name(JsonlFile, Dir),
    dataset_pipeline:validate_paper_stage(Dir, 1, 1).

:- end_tests(machine_annotations).
