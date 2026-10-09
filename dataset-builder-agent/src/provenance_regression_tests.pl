:- use_module(dataset_pipeline).
:- use_module(provenance_manifest).
:- use_module(library(filesex)).

make_prov_workspace(Root) :-
    tmp_file(provenance_tests, Root), make_directory(Root).
cleanup_prov_workspace(Root) :-
    (exists_directory(Root) -> delete_directory_and_contents(Root) ; true).

write_prov_article(Root, Id, Licensed, File) :-
    directory_file_path(Root, 'original.xml', File),
    ( Licensed == yes -> License = '<permissions><license license-type="CC BY"><license-p>Reuse with attribution.</license-p><ext-link xlink:href="https://creativecommons.org/licenses/by/4.0/">CC BY 4.0</ext-link></license></permissions>'
    ; License = '' ),
    setup_call_cleanup(open(File, write, Out, [encoding(utf8)]),
      format(Out, '<article xmlns:xlink="http://www.w3.org/1999/xlink"><front><article-meta><article-id pub-id-type="pmc">~d</article-id>~s</article-meta></front><body><table><tr><th>A</th><th>B</th></tr><tr><td>C</td><td>D</td></tr></table></body></article>', [Id,License]),
      close(Out)).

prov_metadata(Root, Id, Meta) :-
    format(string(Name), 'PMC~d', [Id]),
    directory_file_path(Root, papers, Papers),
    directory_file_path(Papers, Name, Paper),
    directory_file_path(Paper, 'metadata.json', File),
    dataset_pipeline:read_json_file(File, Meta).

:- begin_tests(provenance_manifests).

test(source_hash_and_semantics,[setup(make_prov_workspace(Root)), cleanup(cleanup_prov_workspace(Root))]) :-
    write_prov_article(Root, 613, no, File),
    process_paper('613', File, Root, _),
    prov_metadata(Root, 613, Meta),
    file_sha256(File, Hash), atom_string(Hash, HashText),
    Meta.source_provenance.input_file_sha256 == HashText,
    Meta.source_provenance.hash_scope == "raw_file_bytes",
    Meta.source_provenance.pmc_id == "PMC613",
    Meta.source_provenance.license.status == "missing",
    % Retrieval time is the raw file's mtime, labelled as such.
    time_file(File, Mtime),
    Unix = Meta.source_provenance.retrieval_timestamp_unix,
    number(Unix),
    abs(Unix - Mtime) < 1.0,
    Meta.source_provenance.retrieval_timestamp_basis == "raw_file_mtime",
    Iso = Meta.source_provenance.retrieval_timestamp,
    string(Iso),
    sub_string(Iso, _, 1, 0, "Z"),
    Meta.source_provenance.license.redistribution_status == "requires_manual_review",
    Meta.semantic_validation == "unverified",
    directory_file_path(Root, papers, Papers),
    directory_file_path(Papers, 'PMC613', Paper),
    directory_file_path(Paper, 'tables.jsonl', RecordsFile),
    dataset_pipeline:read_table_jsonl(RecordsFile, [Record]),
    Record.semantic_validation == "unverified".

test(license_is_evidence_not_permission,[setup(make_prov_workspace(Root)), cleanup(cleanup_prov_workspace(Root))]) :-
    write_prov_article(Root, 614, yes, File),
    process_paper('614', File, Root, _),
    prov_metadata(Root, 614, Meta),
    Meta.source_provenance.license.status == "evidence_found_unverified",
    Meta.source_provenance.license.license_type == "CC BY",
    Meta.source_provenance.license.redistribution_status == "requires_manual_review",
    sub_string(Meta.source_provenance.license.license_text_excerpt, _, _, _, 'Reuse').

test(recovery_retains_provenance,[setup(make_prov_workspace(Root)), cleanup(cleanup_prov_workspace(Root))]) :-
    write_prov_article(Root, 615, no, File),
    process_paper('615', File, Root, [on_table_error(quarantine)], _),
    prov_metadata(Root, 615, Meta),
    Meta.source_provenance.pmc_id == "PMC615",
    Meta.semantic_validation == "unverified".

test(run_manifest_captures_selection,[setup(make_prov_workspace(Root)),cleanup(cleanup_prov_workspace(Root))]) :-
    reset_search_provenance,
    remember_search_query('health AND data'),
    record_dataset_run(Root, 'research subject', 'PMC613 PMC999', ['613','999'],
                       ['613'], ['999'], ['PMC613: complete'], RunFile),
    dataset_pipeline:read_json_file(RunFile, Run),
    Run.selected_pmc_ids == ["613"],
    Run.rejected_pmc_ids == ["999"],
    Run.search_queries == ["health AND data"],
    Run.paper_status_lines == ["PMC613: complete"],
    reset_search_provenance.
:- end_tests(provenance_manifests).
