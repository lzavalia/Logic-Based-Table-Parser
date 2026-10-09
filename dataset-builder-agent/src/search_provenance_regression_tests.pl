% F06: only PMC IDs displayed by this run's successful search tool calls
% may be selected for download. Fixtures are offline E-utilities responses.
% Run: swipl -q -s search_provenance_regression_tests.pl -g run_tests -t halt

:- use_module(dataset_pipeline).
:- use_module(library(filesex)).
:- use_module(library(apply)).
:- if(exists_source(library(json))).
:- use_module(library(json)).
:- else.
:- use_module(library(http/json)).
:- endif.

make_search_workspace(Root) :-
    tmp_file(table_parser_search_tests, Root),
    make_directory(Root),
    reset_search_provenance.

remove_search_workspace(Root) :-
    reset_search_provenance,
    ( exists_directory(Root) -> delete_directory_and_contents(Root) ; true ).

json_fixture(File, Dict) :-
    setup_call_cleanup(
        open(File, write, Out, [encoding(utf8)]),
        json_write_dict(Out, Dict), close(Out)).

fixture_docs([], Docs, Docs).
fixture_docs([Uid|Rest], Before, Result) :-
    ( integer(Uid) -> number_string(Uid, KeyString)
    ; atom(Uid) -> atom_string(Uid, KeyString)
    ; KeyString = Uid ),
    atom_string(Key, KeyString),
    put_dict(Key, Before,
             json{pubdate:"2026", fulljournalname:"Journal", title:"Example"}, After),
    fixture_docs(Rest, After, Result).

search_fixture(Root, Stem, SearchIds, SummaryIds, SearchPath, SummaryPath) :-
    format(atom(SearchName), '~w.search.json', [Stem]),
    format(atom(SummaryName), '~w.summary.json', [Stem]),
    directory_file_path(Root, SearchName, SearchPath),
    directory_file_path(Root, SummaryName, SummaryPath),
    json_fixture(SearchPath, json{esearchresult:json{idlist:SearchIds}}),
    fixture_docs(SummaryIds, json{uids:SummaryIds}, Result),
    json_fixture(SummaryPath, json{result:Result}).

:- begin_tests(search_provenance_regressions).

test(no_search_means_no_authorization,
     [setup(make_search_workspace(Root)), cleanup(remove_search_workspace(Root))]) :-
    filter_search_selected_ids(["111", "222"], Approved, Rejected),
    Approved == [],
    Rejected == ["111", "222"].

test(only_observed_search_and_summary_ids_are_accepted,
     [setup(make_search_workspace(Root)), cleanup(remove_search_workspace(Root))]) :-
    search_fixture(Root, a, ["111", "222"], ["111", "333"], Search, Summary),
    verified_search_lines(Search, Summary, Lines),
    sub_string(Lines, _, _, _, "PMC111 |"),
    \+ sub_string(Lines, _, _, _, "PMC333 |"),
    filter_search_selected_ids(["333", "222", "111", "444"], Accepted, Rejected),
    Accepted == ["111"],
    Rejected == ["333", "222", "444"].

test(multiple_searches_accumulate_eligible_ids,
     [setup(make_search_workspace(Root)), cleanup(remove_search_workspace(Root))]) :-
    search_fixture(Root, first, ["111", "222"], ["111", "222"], Search1, Summary1),
    search_fixture(Root, second, ["222", "333"], ["222", "333"], Search2, Summary2),
    verified_search_lines(Search1, Summary1, _),
    verified_search_lines(Search2, Summary2, _),
    filter_search_selected_ids(["333", "111", "222"], Accepted, Rejected),
    Accepted == ["333", "111", "222"],
    Rejected == [].

test(reset_prevents_reusing_prior_run_results,
     [setup(make_search_workspace(Root)), cleanup(remove_search_workspace(Root))]) :-
    search_fixture(Root, a, ["111"], ["111"], Search, Summary),
    verified_search_lines(Search, Summary, _),
    reset_search_provenance,
    filter_search_selected_ids(["111"], Approved, Rejected),
    Approved == [], Rejected == ["111"].

test(duplicate_ids_and_leading_zero_aliases_are_normalized,
     [setup(make_search_workspace(Root)), cleanup(remove_search_workspace(Root))]) :-
    search_fixture(Root, a, ["000111"], ["111"], Search, Summary),
    verified_search_lines(Search, Summary, Lines),
    sub_string(Lines, _, _, _, "PMC111 |"),
    filter_search_selected_ids(["000111", "111", "000111"], Approved, Rejected),
    Approved == ["111"], Rejected == [].

test(numeric_uids_are_supported,
     [setup(make_search_workspace(Root)), cleanup(remove_search_workspace(Root))]) :-
    search_fixture(Root, a, [111,222], [111,222], Search, Summary),
    verified_search_lines(Search, Summary, Lines),
    sub_string(Lines, _, _, _, "PMC111 |"),
    filter_search_selected_ids(["222", "111"], ["222", "111"], []).

test(empty_summary_must_not_record_ids,
     [setup(make_search_workspace(Root)), cleanup(remove_search_workspace(Root))]) :-
    search_fixture(Root, a, ["111"], [], Search, Summary),
    \+ verified_search_lines(Search, Summary, _),
    filter_search_selected_ids(["111"], [], ["111"]).

test(search_without_matching_ids_must_not_record_any,
     [setup(make_search_workspace(Root)), cleanup(remove_search_workspace(Root))]) :-
    search_fixture(Root, a, ["111"], ["222"], Search, Summary),
    \+ verified_search_lines(Search, Summary, _),
    filter_search_selected_ids(["111", "222"], [], ["111", "222"]).

test(missing_summary_document_must_not_authorize_its_uid,
     [setup(make_search_workspace(Root)), cleanup(remove_search_workspace(Root))]) :-
    search_fixture(Root, a, ["111", "222"], ["111", "222"], Search, Summary),
    % Rewrite to contain UID 222 in uids but no corresponding document.
    json_fixture(Summary,
                 json{result:json{uids:["111", "222"],
                                  '111':json{title:"Example", pubdate:"2026",
                                             fulljournalname:"Journal"}}}),
    verified_search_lines(Search, Summary, Lines),
    sub_string(Lines, _, _, _, "PMC111 |"),
    filter_search_selected_ids(["222", "111"], ["111"], ["222"]).

test(invalid_and_zero_ids_are_never_authorized,
     [setup(make_search_workspace(Root)), cleanup(remove_search_workspace(Root))]) :-
    search_fixture(Root, a, ["0", "-1", "abc", "111"],
                  ["0", "-1", "abc", "111"], Search, Summary),
    verified_search_lines(Search, Summary, _),
    filter_search_selected_ids(["0", "-1", "111", "abc"], ["111"], ["0", "-1", "abc"]).

test(failed_later_search_keeps_prior_verified_ids,
     [setup(make_search_workspace(Root)), cleanup(remove_search_workspace(Root))]) :-
    search_fixture(Root, first, ["111"], ["111"], Search1, Summary1),
    verified_search_lines(Search1, Summary1, _),
    search_fixture(Root, second, ["222"], [], Search2, Summary2),
    \+ verified_search_lines(Search2, Summary2, _),
    filter_search_selected_ids(["111", "222"], ["111"], ["222"]).

test(unreadable_later_search_does_not_authorize_more_ids,
     [setup(make_search_workspace(Root)), cleanup(remove_search_workspace(Root))]) :-
    search_fixture(Root, first, ["111"], ["111"], Search1, Summary1),
    verified_search_lines(Search1, Summary1, _),
    directory_file_path(Root, 'missing.json', Missing),
    catch(verified_search_lines(Search1, Missing, _), _, true),
    filter_search_selected_ids(["111", "999"], ["111"], ["999"]).

:- end_tests(search_provenance_regressions).
