% Layout candidates through the whole pipeline, without network or LLM:
% records, certificates and HTML (process_paper/4), the review (the model's
% answers are given directly to review_answer/4), the final pages and the
% export. The local driver's layout views are tested in
% test_driver_regression_tests.pl, which loads the same files in its own process.
% From dataset-builder-agent/tests/:
%   swipl -q -s layout_pipeline_regression_tests.pl -g run_tests -t halt
:- use_module('../src/dataset_pipeline').
:- use_module('../src/table_review').
:- use_module('../src/table_export').
:- use_module('../src/certificate_kernel').
:- use_module(library(filesex)).
:- use_module(library(readutil)).
:- if(exists_source(library(json))).
:- use_module(library(json)).
:- else.
:- use_module(library(http/json)).
:- endif.

% PMC905, built by the real pipeline:
%   t0  a title row above the header and a section row in the middle, both
%       covered by one cell: every candidate is a layout of one subtable
%       with rows 0 and 3 set aside.
%   t1  a header band in the middle of the table (rows 3-4): two layouts of
%       two subtables, and the plain boundaries h2_v0 and h2_v1.
layout_table(0, '<table><tr><th colspan="3">Table title</th></tr><tr><th>Drug</th><th>A</th><th>B</th></tr><tr><td>X</td><td>1</td><td>2</td></tr><tr><td colspan="3">Section two</td></tr><tr><td>Y</td><td>3</td><td>4</td></tr></table>').
layout_table(1, '<table><tr><th>k</th><th colspan="2">G1</th><th colspan="2">G2</th></tr><tr><th>s</th><th>a</th><th>b</th><th>c</th><th>d</th></tr><tr><td>r1</td><td>1</td><td>2</td><td>3</td><td>4</td></tr><tr><th>k2</th><th colspan="2">G3</th><th colspan="2">G4</th></tr><tr><th>s2</th><th>e</th><th>f</th><th>g</th><th>h</th></tr><tr><td>r2</td><td>5</td><td>6</td><td>7</td><td>8</td></tr></table>').

layout_workspace(Root) :-
    tmp_file(layout_pipeline, Root), make_directory(Root),
    directory_file_path(Root, dataset, Dataset),
    make_directory(Dataset),
    layout_table(0, T0), layout_table(1, T1),
    format(atom(Article),
       '<article><front><article-meta><article-id pub-id-type="pmc">905</article-id></article-meta></front><body>~w~w</body></article>',
       [T0, T1]),
    directory_file_path(Root, 'input.xml', Input),
    write_text(Input, Article),
    process_paper("905", Input, Dataset, _).

layout_cleanup(Root) :-
    ( exists_directory(Root) -> delete_directory_and_contents(Root) ; true ).

write_text(File, Text) :-
    setup_call_cleanup(open(File, write, Out, [encoding(utf8)]),
                       write(Out, Text), close(Out)).

paper_file(Root, Name, File) :-
    format(atom(Relative), 'dataset/papers/PMC905/~w', [Name]),
    directory_file_path(Root, Relative, File).

records(Root, Records) :-
    paper_file(Root, 'tables.jsonl', File),
    dataset_pipeline:read_table_jsonl(File, Records).

certificate_names(Root, Names) :-
    paper_file(Root, '', Dir),
    directory_files(Dir, Entries),
    include([E]>>sub_atom(E, 0, _, _, certificate), Entries, Names0),
    msort(Names0, Names).

file_text(File, Text) :-
    read_file_to_string(File, Text, [encoding(utf8)]).

% The candidate of Record whose single subtable, or plain boundary, has
% these counts.
layout_with(Record, Hmd, Vmd, Candidate) :-
    member(Candidate, Record.candidates),
    Candidate.kind == "layout",
    Candidate.subtables = [Sub],
    Sub.hmd =:= Hmd, Sub.vmd =:= Vmd, !.

settings(Root, Settings) :-
    review_settings(Root, none, none, "test:model", Settings).

% Reviews PMC905: t0 at (2, 1), the title and header rows over one header
% column; t1 at (2, 1).
review_paper(Root) :-
    settings(Root, S),
    directory_file_path(Root, dataset, Dataset),
    review_queue(Dataset, S, [Paper], _),
    review_paper_items(Paper, Items),
    findall(R, ( member(Item, Items),
                 review_answer(Item, json{column_header_rows:2, row_header_columns:1,
                                          reason:"test"}, 1, done(R)) ),
            Results),
    publish_paper_review(Dataset, Paper, S, Results, _).

reviews(Root, Reviews) :-
    paper_file(Root, 'review.jsonl', File),
    dataset_pipeline:read_table_jsonl(File, Reviews).

:- begin_tests(layout_pipeline).

% --- records, certificates and HTML ------------------------------------------

test(rows_covered_by_one_cell_give_layout_candidates,
     [setup(layout_workspace(Root)), cleanup(layout_cleanup(Root))]) :-
    records(Root, [T0, _]),
    T0.status == "ambiguous",
    forall(member(C, T0.candidates),
           ( C.kind == "layout",
             C.separators == [json{row:0, columns:[0,1,2]},
                              json{row:3, columns:[0,1,2]}],
             C.subtables = [Sub],
             Sub.rows == [1,2,4],
             memberchk(json{cell_id:0, region:"separator"}, C.labels),
             memberchk(json{cell_id:7, region:"separator"}, C.labels) )),
    layout_with(T0, 1, 1, C11),
    C11.candidate_id == "PMC905/t0/layout2",
    memberchk(json{cell_id:2, region:"hmd"}, C11.labels),
    memberchk(json{cell_id:4, region:"vmd"}, C11.labels),
    memberchk(json{cell_id:5, region:"data"}, C11.labels).

test(central_metadata_gives_two_subtables_beside_plain_boundaries,
     [setup(layout_workspace(Root)), cleanup(layout_cleanup(Root))]) :-
    records(Root, [_, T1]),
    findall(Id-Kind, ( member(C, T1.candidates),
                       Id = C.candidate_id, Kind = C.kind ), Kinds),
    Kinds == ["PMC905/t1/layout0"-"layout", "PMC905/t1/layout1"-"layout",
              "PMC905/t1/h2_v0"-"boundary", "PMC905/t1/h2_v1"-"boundary"],
    T1.candidates = [L0|_],
    L0.subtables == [json{rows:[0,1,2], columns:[0,1,2,3,4], hmd:2, vmd:0},
                     json{rows:[3,4,5], columns:[0,1,2,3,4], hmd:2, vmd:0}],
    L0.separators == [].

test(every_candidate_is_certified_but_the_build_writes_no_certificate,
     [setup(layout_workspace(Root)), cleanup(layout_cleanup(Root))]) :-
    records(Root, Records),
    forall(( member(R, Records), member(C, R.candidates) ),
           ( Cert = C.geometric_certificate,
             Cert.status == "certified",
             (  C.kind == "layout"
             -> length(C.subtables, N),
                length(Cert.claim, N)
             ;  true ) )),
    certificate_names(Root, []).

test(layouts_are_colored_with_separators,
     [setup(layout_workspace(Root)), cleanup(layout_cleanup(Root))]) :-
    paper_file(Root, 'candidates0.html', File),
    file_text(File, Html),
    sub_string(Html, _, _, _, "class=\"layout-candidate\" data-candidate-id=\"PMC905/t0/layout0\""),
    sub_string(Html, _, _, _, "1 subtable, 2 separator rows"),
    sub_string(Html, _, _, _, "khaki"), !.

% --- review, final page and export -------------------------------------------

test(review_reads_a_layout_of_one_subtable_like_the_whole_table,
     [setup(layout_workspace(Root)), cleanup(layout_cleanup(Root))]) :-
    review_paper(Root),
    reviews(Root, [R0, R1]),
    % H = 2 counts the title row set aside above the one HMD row.
    R0.final_status == "valid",
    R0.selected_candidate_id == "PMC905/t0/layout2",
    % The central layouts share (2, 1)-like counts with their top-level
    % block but are never matched; the plain boundary is.
    R1.final_status == "valid",
    R1.selected_candidate_id == "PMC905/t1/h2_v1",
    \+ memberchk("PMC905/t1/layout0", R1.candidate_ids).

test(review_writes_only_the_certificates_of_the_selected_candidates,
     [setup(layout_workspace(Root)), cleanup(layout_cleanup(Root))]) :-
    review_paper(Root),
    certificate_names(Root, Names),
    Names == ['certificate0_layout2.pl', 'certificate1_h2_v1.pl'],
    paper_file(Root, 'certificate0_layout2.pl', Layout),
    check_certificate_file(Layout, accepted),
    read_certificate_file(Layout, Facts),
    memberchk(certificate_version(2), Facts),
    memberchk(table_uid("PMC905/t0"), Facts),
    memberchk(separator(0, [0,1,2]), Facts),
    paper_file(Root, 'certificate1_h2_v1.pl', Plain),
    check_certificate_file(Plain, accepted),
    read_certificate_file(Plain, Facts1),
    memberchk(boundary(2, 1), Facts1).

% A new review that selects other candidates, or none, removes the
% certificates of the earlier selection.
test(a_new_review_replaces_the_selected_certificates,
     [setup(layout_workspace(Root)), cleanup(layout_cleanup(Root))]) :-
    review_paper(Root),
    review_settings(Root, none, true, "test:model", S),
    directory_file_path(Root, dataset, Dataset),
    review_queue(Dataset, S, [Paper], _),
    review_paper_items(Paper, Items),
    Items = [I0, I1],
    review_answer(I0, json{column_header_rows:0, row_header_columns:0,
                           reason:"test"}, 1, done(R0)),
    review_answer(I1, json{column_header_rows:2, row_header_columns:0,
                           reason:"test"}, 1, done(R1)),
    publish_paper_review(Dataset, Paper, S, [R0, R1], _),
    certificate_names(Root, ['certificate1_h2_v0.pl']).

% A current review of a paper whose directory still holds the certificate of
% every candidate (as built before the review wrote them) is not asked
% again: the certificates are brought in line with it.
test(current_review_removes_certificates_it_did_not_select,
     [setup(layout_workspace(Root)), cleanup(layout_cleanup(Root))]) :-
    review_paper(Root),
    paper_file(Root, 'certificate1_h2_v1.pl', Kept),
    paper_file(Root, 'certificate1_layout0.pl', Extra),
    copy_file(Kept, Extra),
    settings(Root, S),
    directory_file_path(Root, dataset, Dataset),
    review_queue(Dataset, S, [], [_-Reason]),
    Reason == "review is up to date; final_tableN.html and certificates written from it",
    certificate_names(Root, ['certificate0_layout2.pl', 'certificate1_h2_v1.pl']),
    review_queue(Dataset, S, [], ["PMC905"-"review is up to date"]).

test(final_page_colors_the_selected_layout,
     [setup(layout_workspace(Root)), cleanup(layout_cleanup(Root))]) :-
    review_paper(Root),
    paper_file(Root, 'final_table0.html', File),
    file_text(File, Html),
    sub_string(Html, _, _, _, "Parse Succeeded"),
    sub_string(Html, _, _, _, "khaki"), !.

test(export_gives_the_subtable_and_the_separator_rows,
     [setup(layout_workspace(Root)), cleanup(layout_cleanup(Root))]) :-
    review_paper(Root),
    settings(Root, S),
    directory_file_path(Root, dataset, Dataset),
    export_reviewed_papers(Dataset, S, _),
    paper_file(Root, 'final_tables.json', File),
    setup_call_cleanup(open(File, read, In, [encoding(utf8)]),
                       json_read_dict(In, Json, [default_tag(json)]),
                       close(In)),
    Json.tables = [E0, E1],
    E0.export_error == null,
    E0.separators == [json{row:0, text:"Table title"},
                      json{row:3, text:"Section two"}],
    E0.subtables = [Sub],
    Sub.data == [["1","2"],["3","4"]],
    E1.separators == [],
    length(E1.subtables, 1).

test(table_whose_candidates_are_all_central_is_not_reviewed) :-
    Sub = json{rows:[0], columns:[0], hmd:1, vmd:0},
    Record = json{candidates:[json{candidate_id:"x/layout0", kind:"layout",
                                   hmd:1, vmd:0, subtables:[Sub, Sub]}]},
    table_review:candidate_boundaries(Record, []).

:- end_tests(layout_pipeline).
