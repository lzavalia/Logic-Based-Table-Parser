% F07/F08: network-independent NCBI download and JATS XML regressions.
% Run: swipl -q -s download_xml_regression_tests.pl -g run_tests -t halt

:- use_module(dataset_pipeline).
:- use_module(library(filesex)).

jats_article(Id, Xml) :-
    format(string(Xml),
           '<pmc-articleset><article><front><article-meta><article-id pub-id-type="pmc">~w</article-id><title-group><article-title>A &amp; B</article-title></title-group></article-meta></front><body><table-wrap><table><thead><tr><th colspan="2">Year</th></tr></thead><tbody><tr><td>A</td><td><italic>x</italic></td></tr></tbody></table></table-wrap></body></article></pmc-articleset>',
           [Id]).

jats_single(Id, Xml) :-
    format(string(Xml),
           '<article><front><article-meta><article-id pub-id-type="pmc">~w</article-id></article-meta></front><body/></article>',
           [Id]).

make_xml_fixture_dir(Root) :-
    tmp_file(table_parser_xml, Root), make_directory(Root).
cleanup_xml_fixture_dir(Root) :-
    (exists_directory(Root) -> delete_directory_and_contents(Root) ; true).
write_xml_fixture(Root, Name, Content, File) :-
    directory_file_path(Root, Name, File),
    setup_call_cleanup(open(File, write, Out, [encoding(utf8)]),
                       write(Out, Content), close(Out)).

:- begin_tests(download_xml_regressions).

test(valid_jats_document_is_accepted,
     [setup(make_xml_fixture_dir(Root)), cleanup(cleanup_xml_fixture_dir(Root))]) :-
    jats_article(123, Xml),
    write_xml_fixture(Root, 'valid.xml', Xml, File),
    download_status(File, jats_xml, ok),
    download_status(File, ok).

test(wrapped_jats_table_geometry_and_entity_text) :-
    jats_article('PMC123', Xml),
    dataset_pipeline:parse_jats_xml(Xml, Dom),
    dataset_pipeline:extract_tables(Dom, [Table]),
    dataset_pipeline:rasterize_table(Table, [[0,0],[1,2]]),
    Table = element(table, _, _),
    dataset_pipeline:paper_title(Dom, "A & B").

test(single_jats_article_with_empty_body) :-
    jats_single(321, Xml),
    dataset_pipeline:parse_jats_xml(Xml, Dom),
    dataset_pipeline:verify_jats_pmc_id(Dom, "PMC321"),
    dataset_pipeline:extract_tables(Dom, []).

test(namespaced_jats_table_normalized) :-
    Xml = '<j:article xmlns:j="urn:jats"><j:front><j:article-meta><j:article-id pub-id-type="pmc">89</j:article-id></j:article-meta></j:front><j:body><j:table><j:tr><j:td>first</j:td><j:td><j:italic/></j:td></j:tr><j:tr><j:td>second</j:td><j:td>fourth</j:td></j:tr></j:table></j:body></j:article>',
    dataset_pipeline:parse_jats_xml(Xml, Dom),
    dataset_pipeline:verify_jats_pmc_id(Dom, "PMC89"),
    dataset_pipeline:extract_tables(Dom, [Table]),
    dataset_pipeline:rasterize_table(Table, [[0,1],[2,3]]).

test(html_entry_point_remains_permissive) :-
    dataset_pipeline:parse_html('<table><tr><td>left<td>right</table>', Dom),
    dataset_pipeline:extract_tables(Dom, [_]).

test(valid_esearch_json,
     [setup(make_xml_fixture_dir(Root)), cleanup(cleanup_xml_fixture_dir(Root))]) :-
    write_xml_fixture(Root, 'esearch.json', '{"esearchresult":{"idlist":["123","456"]}}', File),
    download_status(File, esearch_json, ok),
    download_status(File, ok).

test(valid_esummary_json,
     [setup(make_xml_fixture_dir(Root)), cleanup(cleanup_xml_fixture_dir(Root))]) :-
    write_xml_fixture(Root, 'esummary.json', '{"result":{"uids":["123"]}}', File),
    download_status(File, esummary_json, ok),
    download_status(File, ok).

test(rate_limit_error_is_retryable,
     [setup(make_xml_fixture_dir(Root)), cleanup(cleanup_xml_fixture_dir(Root))]) :-
    write_xml_fixture(Root, 'retry.xml', '{"error":"API rate limit exceeded"}', File),
    download_status(File, jats_xml, rate_limited).

test(server_error_page_is_retryable,
     [setup(make_xml_fixture_dir(Root)), cleanup(cleanup_xml_fixture_dir(Root))]) :-
    write_xml_fixture(Root, 'server.xml', '<html><h1>503 Service Unavailable</h1></html>', File),
    download_status(File, jats_xml, retryable(server_unavailable)).

test(empty_download_is_invalid,
     [setup(make_xml_fixture_dir(Root)), cleanup(cleanup_xml_fixture_dir(Root))]) :-
    write_xml_fixture(Root, 'empty.xml', '', File),
    download_status(File, jats_xml, invalid(empty_body)).

test(html_error_page_is_invalid,
     [setup(make_xml_fixture_dir(Root)), cleanup(cleanup_xml_fixture_dir(Root))]) :-
    write_xml_fixture(Root, 'page.xml', '<html><body>article not found</body></html>', File),
    download_status(File, jats_xml, invalid(http_error_page)).

test(json_api_error_is_invalid,
     [setup(make_xml_fixture_dir(Root)), cleanup(cleanup_xml_fixture_dir(Root))]) :-
    write_xml_fixture(Root, 'error.json', '{"error":"invalid UID"}', File),
    download_status(File, esearch_json, invalid(api_error)).

test(unexpected_json_schema_is_invalid,
     [setup(make_xml_fixture_dir(Root)), cleanup(cleanup_xml_fixture_dir(Root))]) :-
    write_xml_fixture(Root, 'error.json', '{"result":{}}', File),
    download_status(File, esearch_json, invalid(unexpected_json_shape)).

test(truncated_json_is_invalid,
     [setup(make_xml_fixture_dir(Root)), cleanup(cleanup_xml_fixture_dir(Root))]) :-
    write_xml_fixture(Root, 'bad.json', '{"esearchresult":', File),
    download_status(File, esearch_json, invalid(malformed_json)).

test(unrelated_xml_is_invalid,
     [setup(make_xml_fixture_dir(Root)), cleanup(cleanup_xml_fixture_dir(Root))]) :-
    write_xml_fixture(Root, 'other.xml', '<not-an-article/>', File),
    download_status(File, jats_xml, invalid(malformed_or_nonarticle_xml)).

test(truncated_jats_is_invalid,
     [setup(make_xml_fixture_dir(Root)), cleanup(cleanup_xml_fixture_dir(Root))]) :-
    write_xml_fixture(Root, 'truncated.xml', '<article><body><table><tr><td>x</td></tr>', File),
    download_status(File, jats_xml, invalid(malformed_or_nonarticle_xml)).

test(conflicting_pmc_identity,
     [throws(error(pmc_article_identity_mismatch("PMC123", ["PMC456"]), _))]) :-
    jats_single(456, Xml),
    dataset_pipeline:parse_jats_xml(Xml, Dom),
    dataset_pipeline:verify_jats_pmc_id(Dom, "PMC123").

test(missing_pmc_identity,
     [throws(error(pmc_article_identity_mismatch("PMC123", []), _))]) :-
    dataset_pipeline:parse_jats_xml('<article><front><article-meta/></front><body/></article>', Dom),
    dataset_pipeline:verify_jats_pmc_id(Dom, "PMC123").

test(reference_pmc_identity_is_not_authoritative,
     [throws(error(pmc_article_identity_mismatch("PMC123", []), _))]) :-
    Xml = '<article><front><article-meta/></front><body><ref><article-id pub-id-type="pmc">123</article-id></ref></body></article>',
    dataset_pipeline:parse_jats_xml(Xml, Dom),
    dataset_pipeline:verify_jats_pmc_id(Dom, "PMC123").

test(foreign_article_does_not_replace_a_complete_snapshot,
     [setup(make_xml_fixture_dir(Root)), cleanup(cleanup_xml_fixture_dir(Root))]) :-
    jats_article(100, GoodXml),
    jats_article(200, WrongXml),
    write_xml_fixture(Root, 'good.xml', GoodXml, Good),
    write_xml_fixture(Root, 'wrong.xml', WrongXml, Wrong),
    process_paper("100", Good, Root, _),
    directory_file_path(Root, 'papers/PMC100/metadata.json', MetadataFile),
    read_file_to_string(MetadataFile, Before, []),
    catch(process_paper("100", Wrong, Root, _), Error, true),
    Error = error(pmc_article_identity_mismatch("PMC100", ["PMC200"]), _),
    read_file_to_string(MetadataFile, Before, []).

test(well_formed_jats_without_tables_is_valid,
     [setup(make_xml_fixture_dir(Root)), cleanup(cleanup_xml_fixture_dir(Root))]) :-
    jats_single(400, Xml),
    write_xml_fixture(Root, 'zero.xml', Xml, File),
    download_status(File, jats_xml, ok),
    process_paper("400", File, Root, Summary),
    sub_string(Summary, _, _, _, "0 table(s)").

:- end_tests(download_xml_regressions).
