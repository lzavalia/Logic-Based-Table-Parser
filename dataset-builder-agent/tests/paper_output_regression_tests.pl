% Regression tests for identity-safe, replace-not-append paper output.
%
% Run from dataset-builder-agent/src:
%   swipl -q -s paper_output_regression_tests.pl -g run_tests -t halt
%
% No network, LLM or DeepClause dependency.

:- use_module('../src/dataset_pipeline').
:- use_module(library(filesex)).
:- use_module(library(http/json)).

% Deliberately fail AFTER creating a staging artifact. The publication code
% must remove the staging directory while retaining the old complete version.
write_then_throw(StageDir) :-
    directory_file_path(StageDir, 'partial.txt', Partial),
    setup_call_cleanup(open(Partial, write, Out),
                       write(Out, incomplete),
                       close(Out)),
    throw(error(test_staging_failure, _)).

make_test_workspace(Root) :-
    tmp_file(table_parser_paper_output, Root),
    make_directory(Root).

cleanup_test_workspace(Root) :-
    ( exists_directory(Root) -> delete_directory_and_contents(Root) ; true ).

% The input deliberately includes a title that is identical across paper IDs.
write_article(Root, Id, Name, Title, TableCount, File) :-
    directory_file_path(Root, Name, File),
    setup_call_cleanup(
        open(File, write, Out, [encoding(utf8)]),
        ( format(Out, '<article><front><article-meta><article-id pub-id-type="pmc">~w</article-id></article-meta></front><article-title>~s</article-title><body>', [Id, Title]),
          forall(between(1, TableCount, _),
                 write(Out,
                       '<table><tr><td>Country</td><td>Year</td></tr><tr><td>USA</td><td>42</td></tr></table>')),
          write(Out, '</body></article>') ),
        close(Out)).

% An article holding one table given as JATS markup.
write_table_article(Root, Id, Name, TableXml, File) :-
    directory_file_path(Root, Name, File),
    setup_call_cleanup(
        open(File, write, Out, [encoding(utf8)]),
        format(Out, '<article><front><article-meta><article-id pub-id-type="pmc">~w</article-id></article-meta></front><article-title>T</article-title><body>~w</body></article>', [Id, TableXml]),
        close(Out)).

published_file(Root, Pmc, Name, File) :-
    directory_file_path(Root, papers, Papers),
    directory_file_path(Papers, Pmc, Paper),
    directory_file_path(Paper, Name, File).

:- begin_tests(paper_output_regressions).

test(same_title_different_ids_do_not_collide,
     [setup(make_test_workspace(Root)), cleanup(cleanup_test_workspace(Root))]) :-
    write_article(Root, 101, 'a.xml', "A Shared Title", 1, A),
    write_article(Root, 102, 'b.xml', "A Shared Title", 2, B),
    process_paper("101", A, Root, SummaryA),
    process_paper("102", B, Root, SummaryB),
    published_file(Root, 'PMC101', 'candidates0.html', A0),
    published_file(Root, 'PMC102', 'candidates1.html', B1),
    exists_file(A0), exists_file(B1),
    sub_string(SummaryA, _, _, _, "papers/PMC101/"),
    sub_string(SummaryB, _, _, _, "papers/PMC102/").

test(shorter_rerun_drops_stale_tables_and_updates_title,
     [setup(make_test_workspace(Root)), cleanup(cleanup_test_workspace(Root))]) :-
    write_article(Root, 103, 'three.xml', "Old title", 3, Old),
    write_article(Root, 103, 'one.xml', "New title", 1, New),
    process_paper("103", Old, Root, _),
    published_file(Root, 'PMC103', 'candidates2.html', PreviousLast),
    exists_file(PreviousLast),
    process_paper("103", New, Root, _),
    published_file(Root, 'PMC103', 'candidates0.html', Current),
    published_file(Root, 'PMC103', 'candidates1.html', Stale),
    published_file(Root, 'PMC103', 'metadata.json', Metadata),
    exists_file(Current), \+ exists_file(Stale),
    dataset_pipeline:read_json_file(Metadata, Details),
    Details.pmc_id == "PMC103",
    Details.title == "New title",
    Details.table_count =:= 1.

% A paper without tables is never published; a table-free rerun is skipped
% and leaves the previous snapshot as it was.
test(zero_table_rerun_is_skipped_and_keeps_previous_paper,
     [setup(make_test_workspace(Root)), cleanup(cleanup_test_workspace(Root))]) :-
    write_article(Root, 104, 'previous.xml', "First", 1, Previous),
    write_article(Root, 104, 'zero.xml', "Empty", 0, Empty),
    process_paper("104", Previous, Root, _),
    catch(process_paper("104", Empty, Root, _), Error, true),
    Error = error(paper_has_no_tables, _),
    published_file(Root, 'PMC104', 'candidates0.html', Kept),
    published_file(Root, 'PMC104', 'metadata.json', Metadata),
    exists_file(Kept),
    dataset_pipeline:read_json_file(Metadata, Details),
    Details.title == "First",
    Details.table_count =:= 1.

test(failed_stage_preserves_previous_paper,
     [setup(make_test_workspace(Root)), cleanup(cleanup_test_workspace(Root))]) :-
    write_article(Root, 105, 'complete.xml', "Complete", 1, Input),
    process_paper("105", Input, Root, _),
    directory_file_path(Root, papers, Papers),
    catch(dataset_pipeline:with_paper_output_staging(
                  Papers, "PMC105", user:write_then_throw),
          error(test_staging_failure, _), Caught = yes),
    Caught == yes,
    published_file(Root, 'PMC105', 'candidates0.html', Completed),
    exists_file(Completed),
    directory_files(Papers, Entries),
    \+ (member(Item, Entries), sub_atom(Item, _, _, _, '.stage.')).

test(failed_publication_restores_previous_paper,
     [setup(make_test_workspace(Root)), cleanup(cleanup_test_workspace(Root))]) :-
    write_article(Root, 106, 'complete.xml', "Complete", 1, Input),
    process_paper("106", Input, Root, _),
    directory_file_path(Root, papers, Papers),
    directory_file_path(Papers, '.not-a-real-stage', Missing),
    \+ catch(dataset_pipeline:publish_paper_directory(Papers, "PMC106", Missing),
             _, fail),
    published_file(Root, 'PMC106', 'candidates0.html', Completed),
    exists_file(Completed),
    directory_files(Papers, Entries),
    \+ (member(Item, Entries), sub_atom(Item, _, _, _, '.backup')).

test(failed_later_table_does_not_publish_partial_paper,
     [setup(make_test_workspace(Root)), cleanup(cleanup_test_workspace(Root))]) :-
    write_article(Root, 109, 'complete.xml', "Complete", 1, Input),
    process_paper("109", Input, Root, _),
    directory_file_path(Root, papers, Papers),
    dataset_pipeline:parse_html(
        "<table><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></table>",
        Dom),
    dataset_pipeline:extract_tables(Dom, [Table]),
    dataset_pipeline:rasterize_table(Table, Raster),
    % Two tables but only one raster: save the first, then fail on the second.
    \+ dataset_pipeline:with_paper_output_staging(
           Papers, "PMC109",
           dataset_pipeline:write_paper_outputs("PMC109", "Updated",
                                                [Table,Table], [Raster], _)),
    published_file(Root, 'PMC109', 'candidates0.html', Completed),
    published_file(Root, 'PMC109', 'candidates1.html', Missing),
    exists_file(Completed), \+ exists_file(Missing),
    directory_files(Papers, Entries),
    \+ (member(Item, Entries), sub_atom(Item, _, _, _, '.stage.')).

test(existing_per_paper_lock_blocks_concurrent_publication,
     [setup(make_test_workspace(Root)), cleanup(cleanup_test_workspace(Root))]) :-
    write_article(Root, 108, 'complete.xml', "Complete", 1, Input),
    process_paper("108", Input, Root, _),
    directory_file_path(Root, papers, Papers),
    dataset_pipeline:paper_lock_directory(Papers, "PMC108", Lock),
    make_directory(Lock),
    \+ catch(process_paper("108", Input, Root, _), _, fail),
    published_file(Root, 'PMC108', 'candidates0.html', Completed),
    exists_file(Completed).

% The review re-parses source_table_html from tables.jsonl. The stored HTML
% writes <col> unclosed and < as &lt;; both must survive the round trip, or
% the table has no rows (empty_table) and "<0.001" becomes "0.001".
test(source_table_html_round_trips_cols_and_entities,
     [setup(make_test_workspace(Root)), cleanup(cleanup_test_workspace(Root))]) :-
    write_table_article(Root, 110, 'cols.xml',
        '<table><col span="1"/><col span="1"/><thead><tr><th>Outcome</th><th>P</th></tr></thead><tbody><tr><td>Response</td><td>&lt;0.001</td></tr></tbody></table>',
        Input),
    process_paper("110", Input, Root, _),
    published_file(Root, 'PMC110', 'tables.jsonl', Jsonl),
    setup_call_cleanup(open(Jsonl, read, In, [encoding(utf8)]),
                       json_read_dict(In, Record, [value_string_as(string)]),
                       close(In)),
    dataset_pipeline:final_source_table(Record, Clean, Raster),
    Raster == [[0,1],[2,3]],
    sub_term(Text, Clean), atom(Text), sub_atom(Text, _, _, _, '<0.001'), !.

% serialize_source_table/2 reads its own output back. Markup found in JATS
% table cells must survive that check.
test(source_table_html_round_trips_cell_markup) :-
    dataset_pipeline:parse_jats_xml(
        "<table><colgroup><col span=\"1\"/><col span=\"2\"/></colgroup><thead><tr><th>Dose&#160;(mg)</th><th colspan=\"2\">P &gt; 0.05 &amp; n</th></tr></thead><tbody><tr><td><bold>A</bold><break/>B</td><td><italic>x</italic><sup>2</sup></td><td>β <xref ref-type=\"fn\" rid=\"n1\">a</xref></td></tr></tbody></table>",
        Dom),
    dataset_pipeline:extract_tables(Dom, [Table]),
    dataset_pipeline:serialize_source_table(Table, Html),
    dataset_pipeline:deserialize_source_table(Html, Back),
    \+ dataset_pipeline:source_table_difference(Table, Back, _).

% parse_html/2 must not share its DTD with html_write: reading <break></break>
% once taught the shared DTD that break is empty, so the next table with a
% <break/> was written as an unclosed <break> that swallowed the cell text.
test(source_table_html_does_not_depend_on_earlier_tables) :-
    Table = element(table, [], [element(tr, [], [element(td, [], ['Younger', element(break, [], []), 'Older'])])]),
    dataset_pipeline:serialize_source_table(Table, First),
    dataset_pipeline:serialize_source_table(Table, Second),
    First == Second.

% Attribute values are compared as text: the HTML reader returns span=1
% where the XML reader returns span='1'.
test(source_table_difference_ignores_attribute_value_types) :-
    \+ dataset_pipeline:source_table_difference(
           element(table, [], [element(tr, [], [element(td, [colspan='1'], [a])])]),
           element(table, [], [element(tr, [], [element(td, [colspan=1], [a])])]),
           _).

test(source_table_difference_finds_changed_text) :-
    dataset_pipeline:source_table_difference(
        element(table, [], [element(tr, [], [element(td, [], ['<0.001'])])]),
        element(table, [], [element(tr, [], [element(td, [], ['0.001'])])]),
        Difference),
    Difference == difference([1,1,1,1], text("<0.001"), text("0.001")).

test(source_table_difference_finds_missing_row) :-
    dataset_pipeline:source_table_difference(
        element(table, [], [element(tr, [], [element(td, [], [a])]),
                            element(tr, [], [element(td, [], [b])])]),
        element(table, [], [element(tr, [], [element(td, [], [a])])]),
        Difference),
    Difference == difference([1,2], element(tr, []), end).

% A <p> inside a <p> is valid JATS, but HTML closes the outer <p> first, so
% the stored HTML would read back as two sibling paragraphs. The writer must
% stop the paper at parse time, in strict and in quarantine mode alike (it is
% a serialization bug, not a bad source table), and keep the previous paper.
test(source_html_round_trip_failure_stops_the_paper,
     [setup(make_test_workspace(Root)), cleanup(cleanup_test_workspace(Root))]) :-
    write_table_article(Root, 111, 'good.xml',
        '<table><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></table>',
        Good),
    process_paper("111", Good, Root, _),
    write_table_article(Root, 111, 'nested.xml',
        '<table><tr><td>a</td><td><p>b<p>c</p></p></td></tr><tr><td>d</td><td>e</td></tr></table>',
        Nested),
    catch(process_paper("111", Nested, Root, _), Strict, true),
    Strict = error(source_html_round_trip(difference(_, _, _)),
                   context(source_path(_), _)),
    catch(process_paper("111", Nested, Root, [on_table_error(quarantine)], _),
          Quarantine, true),
    Quarantine = error(source_html_round_trip(_), _),
    format_paper_failure("111", Root, Strict, Line),
    once(sub_string(Line, _, _, _, "source_table_html does not read back")),
    published_file(Root, 'PMC111', 'candidates0.html', Previous),
    exists_file(Previous).

test(leading_zeroes_use_one_canonical_identity) :-
    dataset_pipeline:canonical_pmc_name("00107", Name),
    Name == "PMC107".

test(non_digits_and_path_traversal_are_rejected) :-
    forall(member(Invalid, ["../bad", "PMC123", "12/3", "", "000", "123a"]),
           \+ dataset_pipeline:canonical_pmc_name(Invalid, _)).

:- end_tests(paper_output_regressions).
