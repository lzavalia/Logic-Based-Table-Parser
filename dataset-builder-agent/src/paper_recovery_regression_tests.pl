% F17 optional, explicit per-table recovery. /4 remains fail-closed.
% swipl -q -s paper_recovery_regression_tests.pl -g run_tests -t halt
:- use_module(dataset_pipeline).
:- use_module(library(filesex)).

make_recovery_workspace(Root) :-
   tmp_file(table_parser_recovery_tests, Root),
   make_directory(Root).
remove_recovery_workspace(Root) :-
   ( exists_directory(Root) -> delete_directory_and_contents(Root) ; true ).

% Good first and last tables, malformed middle table. Both good tables must
% retain their original table identities and file numbers.
write_recovery_article(Root, Pmc, Name, Tables, Path) :-
   directory_file_path(Root, Name, Path),
   setup_call_cleanup(open(Path, write, Out, [encoding(utf8)]),
      format(Out,
         '<article><front><article-meta><article-id pub-id-type="pmc">~d</article-id></article-meta></front><body>~s</body></article>',
         [Pmc, Tables]),
      close(Out)).

good_table('<table><tr><th>Place</th><th>Year</th></tr><tr><td>A</td><td>1</td></tr></table>').
bad_table('<table><tr><td colspan="0">Broken</td></tr></table>').

snapshot_file(Root, Pmc, Name, File) :-
   format(string(PaperName), 'PMC~d', [Pmc]),
   directory_file_path(Root, papers, Papers),
   directory_file_path(Papers, PaperName, Paper),
   directory_file_path(Paper, Name, File).

read_recovery_snapshot(Root, Pmc, Meta, Records) :-
   snapshot_file(Root, Pmc, 'metadata.json', MetaFile),
   dataset_pipeline:read_json_file(MetaFile, Meta),
   snapshot_file(Root, Pmc, 'tables.jsonl', JsonlFile),
   dataset_pipeline:read_table_jsonl(JsonlFile, Records).

:- begin_tests(paper_recovery_regressions).

test(quarantine_preserves_indices_and_diagnostics,
     [setup(make_recovery_workspace(Root)), cleanup(remove_recovery_workspace(Root))]) :-
   good_table(G), bad_table(B), atomics_to_string([G,B,G], '', Tables),
   write_recovery_article(Root, 401, 'mixed.xml', Tables, Input),
   process_paper("401", Input, Root, [on_table_error(quarantine)], Summary),
   sub_string(Summary, _, _, _, 'partial'),
   sub_string(Summary, _, _, _, '1 quarantined'),
   read_recovery_snapshot(Root, 401, Meta, [R0,R1,R2]),
   Meta.status == "partial", Meta.schema_version == "1.1",
   Meta.table_count =:= 3, Meta.quarantined_table_count =:= 1,
   R0.table_index =:= 0, R1.table_index =:= 1, R2.table_index =:= 2,
   R1.status == "quarantined", R1.error.code == "invalid_layout",
   R1.raster == null, R1.candidates == [],
   R0.status \== "quarantined", R2.status \== "quarantined",
   R2.table_uid == "PMC401/t2",
   snapshot_file(Root, 401, 'annotated_table0.html', First), exists_file(First),
   snapshot_file(Root, 401, 'annotated_table1.html', Missing), \+ exists_file(Missing),
   snapshot_file(Root, 401, 'annotated_table2.html', Third), exists_file(Third).

test(quarantine_only_individual_table_raster_limits,
     [setup(make_recovery_workspace(Root)), cleanup(remove_recovery_workspace(Root))]) :-
   good_table(G),
   B = '<table><tr><td colspan="9999">Huge</td></tr></table>',
   atomics_to_string([G,B], '', Tables),
   write_recovery_article(Root, 410, 'large.xml', Tables, Input),
   process_paper("410", Input, Root, [on_table_error(quarantine)], _),
   read_recovery_snapshot(Root, 410, Meta, [Good,Bad]),
   Meta.status == "partial", Meta.quarantined_table_count =:= 1,
   Good.status \== "quarantined", Bad.status == "quarantined",
   Bad.error.code == "table_raster_limit",
   snapshot_file(Root, 410, 'annotated_table0.html', First), exists_file(First),
   snapshot_file(Root, 410, 'annotated_table1.html', Second), \+ exists_file(Second).

test(default_strict_does_not_publish_partial,
     [setup(make_recovery_workspace(Root)), cleanup(remove_recovery_workspace(Root))]) :-
   good_table(G), bad_table(B), atomics_to_string([G,B], '', Tables),
   write_recovery_article(Root, 402, 'mixed.xml', Tables, Input),
   catch(process_paper("402", Input, Root, _), Error, true),
   nonvar(Error), Error = error(table_layout_error(_), _),
   snapshot_file(Root, 402, 'metadata.json', Published), \+ exists_file(Published).

test(all_tables_quarantined_keeps_old_snapshot,
     [setup(make_recovery_workspace(Root)), cleanup(remove_recovery_workspace(Root))]) :-
   good_table(G), bad_table(B),
   write_recovery_article(Root, 403, 'good.xml', G, Good),
   write_recovery_article(Root, 403, 'bad.xml', B, Bad),
   process_paper("403", Good, Root, _),
   catch(process_paper("403", Bad, Root,
                       [on_table_error(quarantine)], _), Error, true),
   Error = error(all_tables_quarantined(1), _),
   read_recovery_snapshot(Root, 403, Meta, [R]),
   Meta.status == "complete", R.status \== "quarantined".

test(recovery_does_not_swallow_article_identity_error,
     [setup(make_recovery_workspace(Root)), cleanup(remove_recovery_workspace(Root))]) :-
   good_table(G),
   write_recovery_article(Root, 404, 'other.xml', G, Input),
   catch(process_paper("405", Input, Root,
                       [on_table_error(quarantine)], _), Error, true),
   Error = error(pmc_article_identity_mismatch(_, _), _),
   snapshot_file(Root, 405, 'metadata.json', Published), \+ exists_file(Published).

test(all_good_recovery_is_still_complete,
     [setup(make_recovery_workspace(Root)), cleanup(remove_recovery_workspace(Root))]) :-
   good_table(G),
   write_recovery_article(Root, 406, 'good.xml', G, Input),
   process_paper("406", Input, Root, [on_table_error(quarantine)], Summary),
   sub_string(Summary, _, _, _, 'complete'),
   read_recovery_snapshot(Root, 406, Meta, [R]),
   Meta.status == "complete", Meta.quarantined_table_count =:= 0,
   R.status \== "quarantined".

test(default_explicit_fail_mode_matches_default,
     [setup(make_recovery_workspace(Root)), cleanup(remove_recovery_workspace(Root))]) :-
   good_table(G),
   write_recovery_article(Root, 407, 'good.xml', G, Input),
   process_paper("407", Input, Root, [on_table_error(fail)], Summary),
   sub_string(Summary, _, _, _, 'table(s)'),
   read_recovery_snapshot(Root, 407, Meta, [_]), Meta.status == "complete".

test(invalid_options_fail_closed,
     [setup(make_recovery_workspace(Root)), cleanup(remove_recovery_workspace(Root)),
      throws(error(domain_error(paper_processing_options, _), _))]) :-
   process_paper("408", 'missing.xml', Root, [quarantine_everything], _).

test(table_error_allowlist_excludes_io_and_paper_budget) :-
   \+ dataset_pipeline:recoverable_table_error(error(permission_error(write,file,a), _), _, _),
   \+ dataset_pipeline:recoverable_table_error(error(paper_raster_limit_exceeded(max_total_slots, 250000, 250001), _), _, _),
   dataset_pipeline:recoverable_table_error(error(table_layout_error(empty_table), _), "invalid_layout", _),
   dataset_pipeline:recoverable_table_error(error(table_raster_limit_exceeded(max_colspan, 256, 999), _), "table_raster_limit", _).

test(staged_extra_html_is_rejected,
     [setup(make_recovery_workspace(Root)), cleanup(remove_recovery_workspace(Root))]) :-
   good_table(G), bad_table(B), atomics_to_string([G,B], '', Tables),
   write_recovery_article(Root, 409, 'mixed.xml', Tables, Input),
   process_paper("409", Input, Root, [on_table_error(quarantine)], _),
   snapshot_file(Root, 409, 'annotated_table1.html', Unexpected),
   setup_call_cleanup(open(Unexpected, write, Out), write(Out, 'orphan'), close(Out)),
   file_directory_name(Unexpected, Dir),
   read_recovery_snapshot(Root, 409, Meta, _),
   catch(dataset_pipeline:validate_recoverable_stage(Dir, 2, Meta.parsed_table_count, 1), Error, true),
   Error = error(incomplete_paper_stage(file_set_mismatch(_, _)), _).

:- end_tests(paper_recovery_regressions).
