% F05: paper snapshots are committed only if complete; failures are
% diagnosed with their phase or table index and recorded independently.
% Run offline from src/:
%   swipl -q -s paper_failure_regression_tests.pl -g run_tests -t halt

:- use_module(dataset_pipeline).
:- use_module(library(filesex)).
:- use_module(library(lists)).

make_failure_workspace(Root) :-
    tmp_file(table_parser_failure_tests, Root),
    make_directory(Root).

remove_failure_workspace(Root) :-
    ( exists_directory(Root) -> delete_directory_and_contents(Root) ; true ).

write_failure_article(Root, Name, Colspan, Path) :-
    directory_file_path(Root, Name, Path),
    setup_call_cleanup(
        open(Path, write, Out, [encoding(utf8)]),
        format(Out,
            '<article><article-title>Sample</article-title><body><table><tr><td colspan="~w">Header</td><td>Year</td></tr><tr><td>Label</td><td>5</td></tr></table></body></article>',
            [Colspan]),
        close(Out)).

file_in_snapshot(Root, Name, Filename, Path) :-
    directory_file_path(Root, papers, Papers),
    directory_file_path(Papers, Name, Dir),
    directory_file_path(Dir, Filename, Path).

attempt_statuses(Root, Statuses) :-
    directory_file_path(Root, attempts, Attempts),
    directory_files(Attempts, Entries),
    findall(Status,
            ( member(Name, Entries),
              sub_atom(Name, _, 5, 0, '.json'),
              directory_file_path(Attempts, Name, File),
              dataset_pipeline:read_json_file(File, Record),
              Status = Record.status ),
            Statuses).

:- begin_tests(paper_failure_regressions).

test(complete_snapshot_is_marked_and_logged,
     [setup(make_failure_workspace(Root)), cleanup(remove_failure_workspace(Root))]) :-
    write_failure_article(Root, 'good.xml', 1, Input),
    process_paper("321", Input, Root, _),
    file_in_snapshot(Root, "PMC321", 'metadata.json', MetadataFile),
    dataset_pipeline:read_json_file(MetadataFile, Metadata),
    Metadata.status == "complete",
    Metadata.table_count =:= 1,
    attempt_statuses(Root, Statuses),
    Statuses == ["complete"].

test(raster_limit_reports_table_index_without_discarding_old_snapshot,
     [setup(make_failure_workspace(Root)), cleanup(remove_failure_workspace(Root))]) :-
    write_failure_article(Root, 'good.xml', 1, Good),
    write_failure_article(Root, 'bad.xml', 1000000000, Bad),
    process_paper("322", Good, Root, _),
    catch(process_paper("322", Bad, Root, _), Error, true),
    nonvar(Error),
    Error = error(table_raster_limit_exceeded(max_colspan, _, _), context(table_index(0), _)),
    format_paper_failure("322", Root, Error, Report),
    sub_string(Report, _, _, _, "failed (table 0 raster limit max_colspan"),
    sub_string(Report, _, _, _, "previous published snapshot retained"),
    file_in_snapshot(Root, "PMC322", 'annotated_table0.html', Published),
    exists_file(Published),
    attempt_statuses(Root, Statuses),
    msort(Statuses, ["complete", "failed"]).

test(initial_failure_reports_absent_snapshot,
     [setup(make_failure_workspace(Root)), cleanup(remove_failure_workspace(Root))]) :-
    format_paper_failure("323", Root, error(existence_error(source_sink, 'missing.xml'), _), Line),
    sub_string(Line, _, _, _, "failed (existence_error)"),
    sub_string(Line, _, _, _, "no published snapshot present"),
    attempt_statuses(Root, ["failed"]).

test(nonexception_goal_failure_has_explicit_status,
     [setup(make_failure_workspace(Root)), cleanup(remove_failure_workspace(Root))]) :-
    format_paper_failure("324", Root, pipeline_goal_failed, Line),
    sub_string(Line, _, _, _, "failed (download or processing returned failure)"),
    attempt_statuses(Root, ["failed"]).

test(stage_rejects_missing_expected_table,
     [setup(make_failure_workspace(Root)), cleanup(remove_failure_workspace(Root)),
      throws(error(incomplete_paper_stage(file_set_mismatch(_, _)), _))]) :-
    directory_file_path(Root, 'metadata.json', MetadataFile),
    setup_call_cleanup(open(MetadataFile, write, Stream, [encoding(utf8)]),
                       write(Stream, '{}'), close(Stream)),
    dataset_pipeline:validate_paper_stage(Root, 1, 0).

test(stage_rejects_unexpected_file,
     [setup(make_failure_workspace(Root)), cleanup(remove_failure_workspace(Root)),
      throws(error(incomplete_paper_stage(file_set_mismatch(_, _)), _))]) :-
    directory_file_path(Root, 'metadata.json', MetadataFile),
    setup_call_cleanup(open(MetadataFile, write, Meta),
        write(Meta, '{"status":"complete", "table_count":0, "parsed_table_count":0}'),
        close(Meta)),
    directory_file_path(Root, 'stray.html', Stray),
    setup_call_cleanup(open(Stray, write, Stream), write(Stream, 'old'), close(Stream)),
    dataset_pipeline:validate_paper_stage(Root, 0, 0).

test(stage_rejects_empty_table_file,
     [setup(make_failure_workspace(Root)), cleanup(remove_failure_workspace(Root)),
      throws(error(incomplete_paper_stage(empty_table('annotated_table0.html')), _))]) :-
    directory_file_path(Root, 'annotated_table0.html', Empty),
    setup_call_cleanup(open(Empty, write, Stream), true, close(Stream)),
    directory_file_path(Root, 'metadata.json', MetadataFile),
    setup_call_cleanup(open(MetadataFile, write, Out), write(Out, '{}'), close(Out)),
    dataset_pipeline:validate_paper_stage(Root, 1, 0).

test(stage_rejects_inconsistent_metadata,
     [setup(make_failure_workspace(Root)), cleanup(remove_failure_workspace(Root)),
      throws(error(incomplete_paper_stage(metadata_mismatch), _))]) :-
    directory_file_path(Root, 'annotated_table0.html', File),
    setup_call_cleanup(open(File, write, Out), write(Out, '<table></table>'), close(Out)),
    directory_file_path(Root, 'metadata.json', MetadataFile),
    setup_call_cleanup(open(MetadataFile, write, Meta),
        write(Meta, '{"status":"complete", "table_count":4, "parsed_table_count":0}'),
        close(Meta)),
    dataset_pipeline:validate_paper_stage(Root, 1, 0).

test(missing_later_table_is_a_located_failure,
     [setup(make_failure_workspace(Root)), cleanup(remove_failure_workspace(Root))]) :-
    dataset_pipeline:parse_html(
        '<table><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></table>',
        Dom),
    dataset_pipeline:extract_tables(Dom, [Table]),
    dataset_pipeline:rasterize_table(Table, Raster),
    % The first table is valid; the second intentionally cannot be rendered.
    catch(dataset_pipeline:write_paper_outputs("PMC325", "Test", [Table,bad_table],
                                               [Raster,Raster], _, Root), E, true),
    E = error(table_output_failure(1, _), _),
    dataset_pipeline:paper_failure_reason(E, Reason),
    sub_string(Reason, _, _, _, "table 1 output").

test(unwritable_attempt_path_does_not_mask_published_success,
     [setup(make_failure_workspace(Root)), cleanup(remove_failure_workspace(Root))]) :-
    write_failure_article(Root, 'good.xml', 1, Input),
    directory_file_path(Root, 'attempts', Blocker),
    setup_call_cleanup(open(Blocker, write, Stream), write(Stream, 'blocked'), close(Stream)),
    process_paper("326", Input, Root, _),
    file_in_snapshot(Root, "PMC326", 'metadata.json', Metadata),
    exists_file(Metadata),
    format_paper_failure("326", Root, pipeline_goal_failed, Report),
    sub_string(Report, _, _, _, "failed (download or processing returned failure)").

test(boundary_annotation_count_is_preserved) :-
    dataset_pipeline:parse_html(
        '<table><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></table>',
        Dom),
    dataset_pipeline:extract_tables(Dom, [Table]),
    dataset_pipeline:table_annotations(Table, [json{hmd:0,vmd:0}], [Rendered]),
    string_length(Rendered, Size), Size > 0.

:- end_tests(paper_failure_regressions).
