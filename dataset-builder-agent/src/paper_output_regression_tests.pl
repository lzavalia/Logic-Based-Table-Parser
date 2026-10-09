% Regression tests for identity-safe, replace-not-append paper output.
%
% Run from dataset-builder-agent/src:
%   swipl -q -s paper_output_regression_tests.pl -g run_tests -t halt
%
% No network, LLM or DeepClause dependency.

:- use_module(dataset_pipeline).
:- use_module(library(filesex)).

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
    published_file(Root, 'PMC101', 'annotated_table0.html', A0),
    published_file(Root, 'PMC102', 'annotated_table1.html', B1),
    exists_file(A0), exists_file(B1),
    sub_string(SummaryA, _, _, _, "papers/PMC101/"),
    sub_string(SummaryB, _, _, _, "papers/PMC102/").

test(shorter_rerun_drops_stale_tables_and_updates_title,
     [setup(make_test_workspace(Root)), cleanup(cleanup_test_workspace(Root))]) :-
    write_article(Root, 103, 'three.xml', "Old title", 3, Old),
    write_article(Root, 103, 'one.xml', "New title", 1, New),
    process_paper("103", Old, Root, _),
    published_file(Root, 'PMC103', 'annotated_table2.html', PreviousLast),
    exists_file(PreviousLast),
    process_paper("103", New, Root, _),
    published_file(Root, 'PMC103', 'annotated_table0.html', Current),
    published_file(Root, 'PMC103', 'annotated_table1.html', Stale),
    published_file(Root, 'PMC103', 'metadata.json', Metadata),
    exists_file(Current), \+ exists_file(Stale),
    dataset_pipeline:read_json_file(Metadata, Details),
    Details.pmc_id == "PMC103",
    Details.title == "New title",
    Details.table_count =:= 1.

test(zero_table_rerun_drops_all_old_tables,
     [setup(make_test_workspace(Root)), cleanup(cleanup_test_workspace(Root))]) :-
    write_article(Root, 104, 'previous.xml', "First", 1, Previous),
    write_article(Root, 104, 'zero.xml', "Empty", 0, Empty),
    process_paper("104", Previous, Root, _),
    process_paper("104", Empty, Root, _),
    published_file(Root, 'PMC104', 'annotated_table0.html', Obsolete),
    published_file(Root, 'PMC104', 'metadata.json', Metadata),
    \+ exists_file(Obsolete),
    dataset_pipeline:read_json_file(Metadata, Details),
    Details.table_count =:= 0.

test(failed_stage_preserves_previous_paper,
     [setup(make_test_workspace(Root)), cleanup(cleanup_test_workspace(Root))]) :-
    write_article(Root, 105, 'complete.xml', "Complete", 1, Input),
    process_paper("105", Input, Root, _),
    directory_file_path(Root, papers, Papers),
    catch(dataset_pipeline:with_paper_output_staging(
                  Papers, "PMC105", user:write_then_throw),
          error(test_staging_failure, _), Caught = yes),
    Caught == yes,
    published_file(Root, 'PMC105', 'annotated_table0.html', Completed),
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
    published_file(Root, 'PMC106', 'annotated_table0.html', Completed),
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
    published_file(Root, 'PMC109', 'annotated_table0.html', Completed),
    published_file(Root, 'PMC109', 'annotated_table1.html', Missing),
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
    published_file(Root, 'PMC108', 'annotated_table0.html', Completed),
    exists_file(Completed).

test(leading_zeroes_use_one_canonical_identity) :-
    dataset_pipeline:canonical_pmc_name("00107", Name),
    Name == "PMC107".

test(non_digits_and_path_traversal_are_rejected) :-
    forall(member(Invalid, ["../bad", "PMC123", "12/3", "", "000", "123a"]),
           \+ dataset_pipeline:canonical_pmc_name(Invalid, _)).

:- end_tests(paper_output_regressions).
