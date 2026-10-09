% F09: Context and source provenance belong to the table they describe.
% Run: swipl -q -s jats_context_regression_tests.pl -g run_tests -t halt
:- use_module(dataset_pipeline).
:- use_module(library(filesex)).
:- use_module(library(readutil)).

context_document(Id, Xml) :-
    atomic_list_concat([
      '<article><front><article-meta><article-id pub-id-type="pmc">~d</article-id></article-meta></front><body>',
      '<table-wrap id="t-1"><label>Table 1</label>',
      '<caption><title>Outcomes &amp; rates</title><p>Values in mg/L</p></caption>',
      '<table id="grid"><tr><th>A</th><th>B</th></tr><tr><td>x</td><td>7</td></tr></table>',
      '<table-wrap-foot><fn id="a"><label>a</label><p>p &lt; 0.05</p></fn>',
      '<fn-group><fn><p>n = 10</p></fn><fn><p>SD = 2</p></fn></fn-group>',
      '<p>Abbreviations: SD = standard deviation</p></table-wrap-foot>',
      '</table-wrap>',
      '<table-wrap id="t-2"><label>Table 2</label><caption><p>Second caption</p></caption>',
      '<table><tr><td>c</td><td>d</td></tr><tr><td>e</td><td>f</td></tr></table></table-wrap>',
      '<table><caption>Standalone</caption><tr><td>e</td><td>f</td></tr>',
      '<tr><td>g</td><td>h</td></tr></table>',
      '</body></article>'], '', Pattern),
    format(string(Xml), Pattern, [Id]).

context_workspace(Root) :-
    tmp_file(jats_context, Root), make_directory(Root).
remove_context_workspace(Root) :-
    ( exists_directory(Root) -> delete_directory_and_contents(Root) ; true ).
context_xml_file(Root, Id, File) :-
    context_document(Id, Xml),
    directory_file_path(Root, 'input.xml', File),
    setup_call_cleanup(open(File, write, Out, [encoding(utf8)]),
                       write(Out, Xml), close(Out)).
context_published_file(Root, Id, Name, File) :-
    format(string(Pmc), 'PMC~d', [Id]),
    directory_file_path(Root, papers, Papers),
    directory_file_path(Papers, Pmc, PaperDir),
    directory_file_path(PaperDir, Name, File).

:- begin_tests(jats_context_regressions).

test(records_match_legacy_table_order_and_rasters) :-
    context_document(701, Xml),
    dataset_pipeline:parse_jats_xml(Xml, Dom),
    dataset_pipeline:extract_tables(Dom, Tables),
    dataset_pipeline:jats_table_records(Dom, Records),
    maplist(dataset_pipeline:record_table, Records, Tables),
    maplist(dataset_pipeline:rasterize_table, Tables, Rasters),
    Rasters == [[[0,1],[2,3]],[[0,1],[2,3]],[[0,1],[2,3]]].

test(external_caption_label_and_distinct_footnotes) :-
    context_document(702, Xml),
    dataset_pipeline:parse_jats_xml(Xml, Dom),
    dataset_pipeline:jats_table_records(Dom, [table_record(_, Info)|_]),
    Info.wrap_id == "t-1",
    Info.table_id == "grid",
    Info.label == "Table 1",
    Info.caption == "Outcomes & rates Values in mg/L",
    Info.notes == ["a p < 0.05", "n = 10", "SD = 2",
                   "Abbreviations: SD = standard deviation"],
    Info.source_path \== "", Info.wrap_path \== "",
    sub_string(Info.source_path, _, _, _, Info.wrap_path),
    sub_string(Info.source_table_html, _, _, _, "<table"),
    sub_string(Info.caption_markup, _, _, _, "<title"),
    sub_string(Info.foot_markup, _, _, _, "fn-group").

test(context_does_not_leak_between_wrappers) :-
    context_document(703, Xml),
    dataset_pipeline:parse_jats_xml(Xml, Dom),
    dataset_pipeline:jats_table_records(Dom, [_, table_record(_, Second), table_record(_, Third)]),
    Second.label == "Table 2", Second.caption == "Second caption", Second.notes == [],
    Second.wrap_id == "t-2",
    Third.wrap_id == "", Third.wrap_path == "", Third.notes == [],
    Third.caption == "Standalone", Third.caption_external == false,
    Second.caption_external == true,
    Second.source_path \== Third.source_path.

test(annotations_retain_context_without_inserting_raster_cells,
     [setup(context_workspace(Root)), cleanup(remove_context_workspace(Root))]) :-
    context_xml_file(Root, 704, Input),
    process_paper("704", Input, Root, _),
    context_published_file(Root, 704, 'annotated_table0.html', HtmlFile),
    read_file_to_string(HtmlFile, Html, [encoding(utf8)]),
    sub_string(Html, _, _, _, "Table 1"),
    sub_string(Html, _, _, _, "Outcomes"),
    sub_string(Html, _, _, _, "p &lt; 0.05"),
    sub_string(Html, _, _, _, "Abbreviations"),
    % Context is displayed before/after the table and not as table cells.
    sub_string(Html, _, _, _, "jats-table-context"),
    sub_string(Html, _, _, _, "jats-table-notes"),
    context_published_file(Root, 704, 'metadata.json', MetaFile),
    dataset_pipeline:read_json_file(MetaFile, Metadata),
    Metadata.table_count =:= 3,
    Metadata.tables = [One, Two, Three],
    One.wrap_id == "t-1", Two.wrap_id == "t-2", Three.wrap_id == "",
    One.notes = [_,_,_,_],
    sub_string(One.source_table_html, _, _, _, "<table"),
    One.caption_external == true, Three.caption_external == false,
    sub_string(One.label_markup, _, _, _, "Table 1"),
    sub_string(One.foot_markup, _, _, _, "fn-group").

test(rerun_replaces_old_context,
     [setup(context_workspace(Root)), cleanup(remove_context_workspace(Root))]) :-
    context_xml_file(Root, 705, Input),
    process_paper("705", Input, Root, _),
    context_published_file(Root, 705, 'metadata.json', MetaFile),
    dataset_pipeline:read_json_file(MetaFile, Old),
    Old.tables = [_,_,_],
    % Same PMC, but a newer no-table article: old captions must disappear.
    directory_file_path(Root, 'empty.xml', Empty),
    setup_call_cleanup(open(Empty, write, Out, [encoding(utf8)]),
       write(Out, '<article><front><article-meta><article-id pub-id-type="pmc">705</article-id></article-meta></front><body/></article>'),
       close(Out)),
    process_paper("705", Empty, Root, _),
    dataset_pipeline:read_json_file(MetaFile, New),
    New.tables == [], New.table_count =:= 0,
    context_published_file(Root, 705, 'annotated_table0.html', OldHtml),
    \+ exists_file(OldHtml).

test(no_wrap_with_namespaced_markup) :-
    Xml = '<j:article xmlns:j="urn:jats"><j:body><j:table-wrap id="T9"><j:label>Table 9</j:label><j:caption><j:p>Cat</j:p></j:caption><j:table><j:tr><j:td>a</j:td></j:tr></j:table></j:table-wrap></j:body></j:article>',
    dataset_pipeline:parse_jats_xml(Xml, Dom),
    dataset_pipeline:jats_table_records(Dom, [table_record(_, Ctx)]),
    Ctx.wrap_id == "T9", Ctx.label == "Table 9", Ctx.caption == "Cat".

:- end_tests(jats_context_regressions).
