% F13: Offline concurrency and shared-request-budget regression tests.
% Run: swipl -q -s concurrency_regression_tests.pl -g run_tests -t halt

:- use_module(dataset_pipeline).
:- use_module(library(filesex)).
:- use_module(library(readutil)).
:- if(exists_source(library(json))).
:- use_module(library(json)).
:- else.
:- use_module(library(http/json)).
:- endif.

make_f13_workspace(Root) :-
    tmp_file(table_parser_concurrent, Root),
    make_directory(Root),
    reset_search_provenance.

cleanup_f13_workspace(Root) :-
    reset_search_provenance,
    ( exists_directory(Root) -> delete_directory_and_contents(Root) ; true ).

write_f13_json(File, Dict) :-
    setup_call_cleanup(open(File, write, S, [encoding(utf8)]),
                       json_write_dict(S, Dict), close(S)).

write_f13_search(Search, Summary, Id, Title) :-
    write_f13_json(Search, json{esearchresult:json{idlist:[Id]}}),
    atom_string(Key, Id),
    put_dict(Key, json{uids:[Id]},
             json{title:Title, pubdate:"2026", fulljournalname:"J"}, Entry),
    write_f13_json(Summary, json{result:Entry}).

:- begin_tests(f13_concurrent_requests).

test(private_search_paths_are_distinct,
     [setup(make_f13_workspace(Root)), cleanup(cleanup_f13_workspace(Root))]) :-
    allocate_search_cache(Root, Rel1, Abs1, SummaryRel1, SummaryAbs1),
    allocate_search_cache(Root, Rel2, Abs2, SummaryRel2, SummaryAbs2),
    Abs1 \== Abs2, SummaryAbs1 \== SummaryAbs2,
    Rel1 \== Rel2, SummaryRel1 \== SummaryRel2,
    sub_string(Rel1, _, _, _, "dataset/cache/requests/"),
    exists_directory(Root),
    file_directory_name(Abs1, Dir1),
    file_directory_name(Abs2, Dir2),
    exists_directory(Dir1), exists_directory(Dir2),
    cleanup_search_cache(Abs1),
    \+ exists_directory(Dir1),
    exists_directory(Dir2),
    cleanup_search_cache(Abs2).

test(interleaved_search_responses_remain_independent,
     [setup(make_f13_workspace(Root)), cleanup(cleanup_f13_workspace(Root))]) :-
    allocate_search_cache(Root, _, Search1, _, Summary1),
    allocate_search_cache(Root, _, Search2, _, Summary2),
    write_f13_search(Search1, Summary1, "101", "First article"),
    write_f13_search(Search2, Summary2, "202", "Second article"),
    verified_search_lines(Search2, Summary2, Text2),
    verified_search_lines(Search1, Summary1, Text1),
    sub_string(Text1, _, _, _, "First article"),
    \+ sub_string(Text1, _, _, _, "Second article"),
    sub_string(Text2, _, _, _, "Second article"),
    filter_search_selected_ids(["202", "101", "303"], ["202", "101"], ["303"]),
    cleanup_search_cache(Search1),
    exists_file(Search2),
    cleanup_search_cache(Search2).

test(ingest_lock_rejects_same_id_but_allows_other_ids,
     [setup(make_f13_workspace(Root)), cleanup(cleanup_f13_workspace(Root))]) :-
    acquire_paper_ingest_lock_at(Root, "111", Lock1),
    catch(acquire_paper_ingest_lock_at(Root, "000111", _), Error, true),
    nonvar(Error),
    Error = error(pmc_ingest_busy("PMC111"), _),
    acquire_paper_ingest_lock_at(Root, "222", Lock2),
    Lock1 \== Lock2,
    release_paper_ingest_lock(Lock1),
    acquire_paper_ingest_lock_at(Root, "111", Lock1Again),
    release_paper_ingest_lock(Lock1Again),
    release_paper_ingest_lock(Lock2).

test(ingest_lock_released_after_exception,
     [setup(make_f13_workspace(Root)), cleanup(cleanup_f13_workspace(Root))]) :-
    catch(( acquire_paper_ingest_lock_at(Root, "111", Lock),
            setup_call_cleanup(true, throw(simulated_failure),
                               release_paper_ingest_lock(Lock)) ),
          simulated_failure, true),
    acquire_paper_ingest_lock_at(Root, "111", LockAgain),
    release_paper_ingest_lock(LockAgain).

test(reservations_on_same_workspace_respect_gap,
     [setup(make_f13_workspace(Root)), cleanup(cleanup_f13_workspace(Root))]) :-
    directory_file_path(Root, 'shared_cache', Cache),
    ncbi_rate_limit_at(Cache, 0.35, First),
    ncbi_rate_limit_at(Cache, 0.35, Second),
    Delta is Second - First,
    Delta >= 0.345,
    Delta < 10.

test(independent_workers_use_shared_timestamp,
     [setup(make_f13_workspace(Root)), cleanup(cleanup_f13_workspace(Root))]) :-
    directory_file_path(Root, 'shared_cache', Cache),
    ncbi_rate_limit_at(Cache, 0.35, First),
    directory_file_path(Cache, '.ncbi-last-request', StateFile),
    read_file_to_string(StateFile, Before, []),
    normalize_space(string(Trim), Before),
    number_string(Stored, Trim),
    abs(Stored - First) < 0.001,
    ncbi_rate_limit_at(Cache, 0.35, Second),
    Second - First >= 0.345.

test(invalid_shared_stamp_fails_closed,
     [setup(make_f13_workspace(Root)), cleanup(cleanup_f13_workspace(Root))]) :-
    directory_file_path(Root, 'cache', Cache),
    make_directory_path(Cache),
    directory_file_path(Cache, '.ncbi-last-request', State),
    setup_call_cleanup(open(State, write, S),
                       write(S, 'not a number'), close(S)),
    catch(ncbi_rate_limit_at(Cache, 0.35, _), Error, true),
    Error = error(ncbi_invalid_rate_state(State), _),
    directory_file_path(Cache, '.ncbi-request.lock', LockDir),
    \+ exists_directory(LockDir).

test(clock_skew_fails_closed,
     [setup(make_f13_workspace(Root)), cleanup(cleanup_f13_workspace(Root))]) :-
    directory_file_path(Root, 'cache', Cache),
    make_directory_path(Cache),
    directory_file_path(Cache, '.ncbi-last-request', State),
    setup_call_cleanup(open(State, write, S),
                       write(S, '99999999999'), close(S)),
    catch(ncbi_rate_limit_at(Cache, 0.35, _), Error, true),
    Error = error(ncbi_rate_clock_skew(_, _), _),
    directory_file_path(Cache, '.ncbi-request.lock', LockDir),
    \+ exists_directory(LockDir).

test(existing_limiter_lock_never_stolen,
     [setup(make_f13_workspace(Root)), cleanup(cleanup_f13_workspace(Root))]) :-
    directory_file_path(Root, 'already-locked', Lock),
    make_directory(Lock),
    catch(dataset_pipeline:acquire_directory_lock(Lock, 0), Error, true),
    Error = error(concurrent_lock_busy(Lock), _),
    exists_directory(Lock).

:- end_tests(f13_concurrent_requests).
