% Export of reviewed tables to final_tables.json (table_export.pl), without
% an LLM: the model's answers are given directly to review_answer/4.
% From dataset-builder-agent/tests/:
%   swipl -q -s table_export_regression_tests.pl -g run_tests -t halt
:- use_module('../src/dataset_pipeline').
:- use_module('../src/table_review').
:- use_module('../src/table_export').
:- use_module(library(filesex)).
:- use_module(library(readutil)).
:- if(exists_source(library(json))).
:- use_module(library(json)).
:- else.
:- use_module(library(http/json)).
:- endif.

% A workspace with one published paper, PMC902, built by the real pipeline:
%   t0  two header rows (Group A/B over mean/sd), a row header X spanning two
%       rows, and a data cell spanning three columns; candidates h2_v0,
%       h2_v1, h2_v2
%   t1  2x2 grid
%   t2  a single cell (abstained)
export_workspace(Root) :-
    tmp_file(table_export, Root), make_directory(Root),
    directory_file_path(Root, dataset, Dataset),
    make_directory(Dataset),
    directory_file_path(Root, 'input.xml', Input),
    write_text(Input,
       '<article><front><article-meta><article-id pub-id-type="pmc">902</article-id></article-meta></front><body><table-wrap><label>Table 1</label><caption><p>Doses</p></caption><table><tr><th rowspan="2">Gene</th><th colspan="2">Group A</th><th colspan="2">Group B</th></tr><tr><th>mean</th><th>sd</th><th>mean</th><th>sd</th></tr><tr><th rowspan="2">X</th><td>1</td><td>2</td><td>3</td><td>4</td></tr><tr><td>5</td><td colspan="3">6</td></tr><tr><th>Y</th><td>7</td><td>8</td><td>9</td><td>10</td></tr></table></table-wrap><table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table><table><tr><td>only</td></tr></table></body></article>'),
    process_paper("902", Input, Dataset, _).

% A workspace with PMC903, whose only table is example_table.html (the
% reference example of the final_tables.json schema).
example_workspace(Root) :-
    tmp_file(table_export, Root), make_directory(Root),
    directory_file_path(Root, dataset, Dataset),
    make_directory(Dataset),
    directory_file_path(Root, 'input.xml', Input),
    Cell = '<td>DATA</td>',
    atomic_list_concat([Cell, Cell, Cell], Data),
    format(atom(Article),
       '<article><front><article-meta><article-id pub-id-type="pmc">903</article-id></article-meta></front><body><table><thead><tr><th colspan="2" rowspan="2">Corner</th><th colspan="3" rowspan="1">HMD 0</th></tr><tr><th>HMD 1</th><th>HMD 1</th><th>HMD 1</th></tr></thead><tbody><tr><td colspan="1" rowspan="2">VMD 0</td><td>VMD 1</td>~w</tr><tr><td>VMD 1</td>~w</tr><tr><td colspan="1" rowspan="2">VMD 0</td><td>VMD 1</td>~w</tr><tr><td>VMD 1</td>~w</tr></tbody></table></body></article>',
       [Data, Data, Data, Data]),
    write_text(Input, Article),
    process_paper("903", Input, Dataset, _).

% example_table.json
reference_json('{"subtables":[{"horizontal metadata":[{"HMD 0":[{"HMD 1":[]},{"HMD 1":[]},{"HMD 1":[]}]}],"vertical metadata":[{"VMD 0":[{"VMD 1":[]},{"VMD 1":[]}]},{"VMD 0":[{"VMD 1":[]},{"VMD 1":[]}]}],"data":[["DATA","DATA","DATA"],["DATA","DATA","DATA"],["DATA","DATA","DATA"],["DATA","DATA","DATA"]],"residual_corner":[{"Corner":[]}]}]}').

export_cleanup(Root) :-
    ( exists_directory(Root) -> delete_directory_and_contents(Root) ; true ).

write_text(File, Text) :-
    setup_call_cleanup(open(File, write, Out, [encoding(utf8)]),
                       write(Out, Text), close(Out)).

paper_file(Root, Name, File) :-
    paper_file(Root, 902, Name, File).

paper_file(Root, Pmc, Name, File) :-
    format(atom(Relative), 'dataset/papers/PMC~d/~w', [Pmc, Name]),
    directory_file_path(Root, Relative, File).

papers_dir(Root, Dir) :- directory_file_path(Root, 'dataset/papers', Dir).

settings(Root, Settings) :-
    review_settings(Root, none, none, "test:model", Settings).

% Reviews PMC902: t0 at (2, 1), which is a candidate (valid); t1 at (0, 0),
% which is not (unparseable); t2 is skipped (parser abstained).
review_paper(Root) :-
    review_paper(Root, 902).

review_paper(Root, Pmc) :-
    settings(Root, S),
    directory_file_path(Root, dataset, Dataset),
    review_queue(Dataset, S, [Paper], _),
    review_paper_items(Paper, Items),
    findall(R, ( nth0(I, Items, Item), result_for(Pmc, Item, I, R) ), Results),
    publish_paper_review(Dataset, Paper, S, Results, _).

result_for(Pmc, Item, I, Result) :-
    review_item_action(Item, Action),
    (   Action == skip
    ->  review_skip_result(Item, Result)
    ;   answer(Pmc, I, H, V),
        review_answer(Item, json{column_header_rows:H, row_header_columns:V,
                                 reason:"test"}, 1, done(Result))
    ).

answer(902, 0, 2, 1).
answer(902, 1, 0, 0).
answer(903, 0, 2, 2).

exported(Root, Json) :-
    exported(Root, 902, Json).

exported(Root, Pmc, Json) :-
    paper_file(Root, Pmc, 'final_tables.json', File),
    setup_call_cleanup(open(File, read, In, [encoding(utf8)]),
                       json_read_dict(In, Json, [default_tag(json)]),
                       close(In)).

% A node {"<text>": [children]} read back as Text-Children, recursively.
node_shape(Node, Text-Children) :-
    dict_pairs(Node, _, [Key-Value]),
    format(string(Text), "~w", [Key]),
    maplist(node_shape, Value, Children).

% The one subtable of an exported entry, as Hmd/Vmd forests, data, corner.
subtable(Entry, Hmd, Vmd, Data, Corner) :-
    Entry.subtables = [Sub],
    maplist(node_shape, Sub.get('horizontal metadata'), Hmd),
    maplist(node_shape, Sub.get('vertical metadata'), Vmd),
    Data = Sub.data,
    maplist(node_shape, Sub.residual_corner, Corner).

% table_structure/4 written as JSON and read back, as in final_tables.json.
structure(Raster, Cells, H, V, Hmd, Vmd, Data, Corner) :-
    table_structure(json{raster:Raster, cells:Cells}, H, V, Sub),
    with_output_to(string(Text), json_write_dict(current_output, Sub)),
    atom_json_dict(Text, Dict, [default_tag(json)]),
    subtable(json{subtables:[Dict]}, Hmd, Vmd, Data, Corner).

cells(Texts, Cells) :-
    findall(json{cell_id:I, kind:"source", text:T}, nth0(I, Texts, T), Cells).

:- begin_tests(table_export).

test(valid_table_is_exported_with_trees_and_unmerged_data,
     [setup(export_workspace(Root)), cleanup(export_cleanup(Root))]) :-
    review_paper(Root),
    settings(Root, S),
    directory_file_path(Root, dataset, Dataset),
    export_reviewed_papers(Dataset, S, [Line]),
    once(sub_string(Line, _, _, _, "PMC902: 1 of 3 table(s) exported")),
    exported(Root, Json),
    Json.pmc_id == "PMC902",
    Json.tables = [T0, T1, T2],
    T0.final_status == "valid", T0.export_error == null,
    T0.candidate_id == "PMC902/t0/h2_v1",
    T0.boundary == json{hmd:2, vmd:1},
    T0.label == "Table 1", T0.caption == "Doses",
    T0.geometric_certificate.status == "certified",
    subtable(T0, Hmd, Vmd, Data, Corner),
    Hmd == ["Group A"-["mean"-[], "sd"-[]], "Group B"-["mean"-[], "sd"-[]]],
    Vmd == ["X"-[], "Y"-[]],
    % The data cell "6" spans three columns: it is repeated in each.
    Data == [["1","2","3","4"], ["5","6","6","6"], ["7","8","9","10"]],
    % "Gene" spans both HMD rows of the corner: one node.
    Corner == ["Gene"-[]],
    T1.final_status == "unparseable", T1.subtables == null,
    T1.candidate_id == null,
    T2.final_status == "unparseable", T2.subtables == null.

% example_table.html, built, reviewed at (2, 2) and exported, gives exactly
% example_table.json (the schema's reference example).
test(reference_example_gives_the_reference_json,
     [setup(example_workspace(Root)), cleanup(export_cleanup(Root))]) :-
    review_paper(Root, 903),
    papers_dir(Root, Papers),
    export_paper(Papers, "PMC903", _),
    exported(Root, 903, Json),
    Json.tables = [Entry],
    Entry.final_status == "valid",
    Entry.boundary == json{hmd:2, vmd:2},
    reference_json(Expected),
    atom_json_dict(Expected, ExpectedDict, [default_tag(json)]),
    json{subtables:Entry.subtables} == ExpectedDict,
    % The file keeps the schema's key order.
    paper_file(Root, 903, 'final_tables.json', File),
    read_file_to_string(File, Text, [encoding(utf8)]),
    sub_string(Text, H, _, _, "\"horizontal metadata\""),
    sub_string(Text, V, _, _, "\"vertical metadata\""),
    sub_string(Text, D, _, _, "\"data\""),
    sub_string(Text, C, _, _, "\"residual_corner\""),
    H < V, V < D, D < C, !.

test(paper_without_review_is_not_exported,
     [setup(export_workspace(Root)), cleanup(export_cleanup(Root))]) :-
    papers_dir(Root, Papers),
    export_paper(Papers, "PMC902", Line),
    once(sub_string(Line, _, _, _, "not reviewed yet")),
    paper_file(Root, 'final_tables.json', File),
    \+ exists_file(File).

test(review_of_older_tables_is_not_exported,
     [setup(export_workspace(Root)), cleanup(export_cleanup(Root))]) :-
    review_paper(Root),
    paper_file(Root, 'tables.jsonl', Tables),
    read_file_to_string(Tables, Text, [encoding(utf8)]),
    string_concat(Text, "", Same),
    write_text(Tables, Same),
    papers_dir(Root, Papers),
    export_paper(Papers, "PMC902", Ok),
    once(sub_string(Ok, _, _, _, "exported")),
    % Any change to tables.jsonl makes the review stale.
    atomic_list_concat(Parts, '"Doses"', Text),
    atomic_list_concat(Parts, '"Changed"', Changed),
    write_text(Tables, Changed),
    paper_file(Root, 'final_tables.json', File),
    delete_file(File),
    export_paper(Papers, "PMC902", Line),
    once(sub_string(Line, _, _, _, "does not match tables.jsonl")),
    \+ exists_file(File).

test(papers_with_last_index_boundaries_are_not_exported,
     [setup(export_workspace(Root)), cleanup(export_cleanup(Root))]) :-
    review_paper(Root),
    paper_file(Root, 'tables.jsonl', Tables),
    read_file_to_string(Tables, Text, [encoding(utf8)]),
    atomic_list_concat(Parts, '"schema_version":"3.0"', Text),
    atomic_list_concat(Parts, '"schema_version":"1.0"', Old),
    write_text(Tables, Old),
    papers_dir(Root, Papers),
    export_paper(Papers, "PMC902", Line),
    once(sub_string(Line, _, _, _, "schema 1.x; rebuild the paper")),
    paper_file(Root, 'final_tables.json', File),
    \+ exists_file(File).

test(paper_filter_and_busy_lock_are_respected,
     [setup(export_workspace(Root)), cleanup(export_cleanup(Root))]) :-
    review_paper(Root),
    directory_file_path(Root, dataset, Dataset),
    review_settings(Root, "PMC1", none, "test:model", Other),
    export_reviewed_papers(Dataset, Other, []),
    papers_dir(Root, Papers),
    directory_file_path(Papers, '.PMC902.lock', Lock),
    make_directory(Lock),
    export_paper(Papers, "PMC902", Line),
    delete_directory(Lock),
    once(sub_string(Line, _, _, _, "being published by another run")),
    paper_file(Root, 'final_tables.json', File),
    \+ exists_file(File),
    \+ ( directory_files(Papers, Entries), member(E, Entries),
         sub_atom(E, _, _, 0, '.tmp') ).

% --- table_structure/4 ---------------------------------------------------------

test(vmd_tree_nests_left_to_right) :-
    % Column 0 groups rows 1-2 (G), column 1 splits them (a, b).
    Raster = [[0,1,2],[3,4,5],[3,6,7]],
    cells(["","k1","k2","G","a","1","b","2"], Cells),
    structure(Raster, Cells, 1, 2, Hmd, Vmd, Data, Corner),
    Vmd == ["G"-["a"-[], "b"-[]]],
    Hmd == ["k2"-[]],
    Corner == [""-[], "k1"-[]],
    Data == [["1"], ["2"]].

test(corner_is_a_forest_read_top_to_bottom) :-
    % The corner has a cell over two cells: "Stub" over "a" and "b".
    Raster = [[0,0,1],[2,3,4],[5,6,7]],
    cells(["Stub","K","a","b","k","x","y","1"], Cells),
    structure(Raster, Cells, 2, 2, _, _, _, Corner),
    Corner == ["Stub"-["a"-[], "b"-[]]].

test(no_hmd_rows_give_empty_horizontal_metadata) :-
    cells(["a","1","b","2"], Cells),
    structure([[0,1],[2,3]], Cells, 0, 1, Hmd, Vmd, Data, Corner),
    Hmd == [], Corner == [],
    Vmd == ["a"-[], "b"-[]],
    Data == [["1"], ["2"]].

test(synthetic_gap_slots_are_null_in_data_and_empty_keys_in_metadata) :-
    Cells = [json{cell_id:0, kind:"source", text:"h"},
             json{cell_id:1, kind:"source", text:"k"},
             json{cell_id:2, kind:"source", text:"x"},
             json{cell_id:3, kind:"synthetic_gap", text:""},
             json{cell_id:4, kind:"synthetic_gap", text:""}],
    structure([[0,1],[2,3],[4,3]], Cells, 1, 1, _, Vmd, Data, _),
    Data == [[null], [null]],
    Vmd == ["x"-[], ""-[]].

test(no_vmd_columns_give_an_empty_corner) :-
    cells(["k1","k2","1","2"], Cells),
    structure([[0,1],[2,3]], Cells, 1, 0, Hmd, Vmd, Data, Corner),
    Corner == [], Vmd == [],
    Hmd == ["k1"-[], "k2"-[]],
    Data == [["1","2"]].

test(numeric_texts_stay_text_keys) :-
    cells(["2019","2020","1","2"], Cells),
    table_structure(json{raster:[[0,1],[2,3]], cells:Cells}, 1, 0, Sub),
    with_output_to(string(Text), json_write_dict(current_output, Sub, [width(0)])),
    once(sub_string(Text, _, _, _, "{\"2019\": []}")).

test(cell_under_two_parents_is_an_export_error,
     [throws(export_error(cell_has_several_parents(2, [0,1])))]) :-
    % Inverted hierarchy: cell 2 spans both columns under two cells.
    cells(["a","b","c","d","e","f","g"], Cells),
    table_structure(json{raster:[[0,1],[2,2],[3,4],[5,6]], cells:Cells}, 3, 0, _).

:- end_tests(table_export).
