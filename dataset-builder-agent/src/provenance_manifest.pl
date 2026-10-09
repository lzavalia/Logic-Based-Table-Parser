% Source and license evidence for paper snapshots. No assertion of redistribution
% permission follows from a PMC open-access search filter or a license tag.
:- module(provenance_manifest, [paper_source_provenance/3,
                                store_source_provenance/2]).
% crypto is not included in every WASM SWI build. The bundled lightweight
% SHA package provides a fallback, without weakening the SHA-256 requirement.
:- if(exists_source(library(crypto))).
:- use_module(library(crypto)).
:- endif.
:- if(exists_source(library(sha))).
:- use_module(library(sha)).
:- endif.
:- use_module(library(readutil)).
:- use_module(library(filesex)).
:- if(exists_source(library(json))).
:- use_module(library(json)).
:- else.
:- use_module(library(http/json)).
:- endif.

file_sha256(File, Hash) :-
    ( current_predicate(crypto_file_hash/3)
    -> crypto_file_hash(File, Hash, [algorithm(sha256)])
    ; current_predicate(sha_hash/3)
    -> setup_call_cleanup(open(File, read, In, [type(binary)]),
                          read_stream_to_codes(In, Bytes), close(In)),
       sha_hash(Bytes, RawHash, [algorithm(sha256), encoding(octet)]),
       hash_atom(RawHash, Hash)
    ; throw(error(sha256_backend_unavailable,
                  context(file_sha256/2,
                          'SWI-Prolog crypto or sha package is required'))) ).

paper_source_provenance(File, Pmc, Dom, Manifest) :-
    file_sha256(File, Hash),
    atom_string(Hash, HashText),
    size_file(File, Bytes),
    file_base_name(File, FileName),
    get_time(Now),
    % The agent deletes and re-downloads dataset/raw/PMC<id>.xml for every run,
    % so the file's modification time is when NCBI's response was written.
    % For a pre-existing local file passed to process_paper/4 it is only when
    % that file was last written; retrieval_timestamp_basis says which source
    % this is so no reader mistakes it for an observed NCBI request time.
    time_file(File, Mtime),
    stamp_date_time(Mtime, MtimeUtc, 'UTC'),
    format_time(string(MtimeIso), '%FT%TZ', MtimeUtc),
    format(string(ArticleUrl), 'https://pmc.ncbi.nlm.nih.gov/articles/~s/', [Pmc]),
    license_evidence(Dom, License),
    Manifest = json{schema_version:"1.0", pmc_id:Pmc,
                    input_file_name:FileName,
                    input_file_sha256:HashText,
                    hash_scope:"raw_file_bytes",
                    input_file_size_bytes:Bytes,
                    article_reference_url:ArticleUrl,
                    retrieval_timestamp:MtimeIso,
                    retrieval_timestamp_unix:Mtime,
                    retrieval_timestamp_basis:"raw_file_mtime",
                    processing_timestamp_unix:Now,
                    software:"logic_based_table_parser",
                    segmentation_semantics:"structural_hypotheses_not_verified_semantic_labels",
                    license:License}.

license_evidence(Dom, License) :-
    member(Root, Dom),
    nested_element(license, Root, element(license, Attrs, Children)), !,
    ( memberchk('license-type'=Type0, Attrs) -> as_text(Type0, Type)
    ; Type = "unknown" ),
    ( member(Node, Children),
      nested_element('ext-link', Node, element('ext-link', LinkAttrs, _)),
      ( memberchk('xlink:href'=Href0, LinkAttrs)
      ; memberchk(href=Href0, LinkAttrs) )
    -> as_text(Href0, Href)
    ; Href = null ),
    findall(Piece, nested_text(Children, Piece), Pieces),
    atomic_list_concat(Pieces, ' ', Joined),
    normalize_space(string(Text), Joined),
    string_length(Text, Length),
    Keep is min(Length, 1024),
    sub_string(Text, 0, Keep, _, Snippet),
    License = json{status:"evidence_found_unverified", license_type:Type,
                   license_url:Href, license_text_excerpt:Snippet,
                   redistribution_status:"requires_manual_review"}.
license_evidence(_, json{status:"missing", license_type:null,
                        license_url:null, license_text_excerpt:"",
                        redistribution_status:"requires_manual_review"}).

nested_element(Tag, element(Tag, Attrs, Children), element(Tag, Attrs, Children)).
nested_element(Tag, element(_, _, Children), Match) :-
    member(Child, Children), nested_element(Tag, Child, Match).

nested_text([H|_], Piece) :-
    ( string(H) -> Piece=H
    ; atom(H) -> Piece=H
    ; H=element(_, _, Children), nested_text(Children, Piece) ).
nested_text([_|T], Piece) :- nested_text(T, Piece).

as_text(Value, Text) :-
    ( string(Value) -> Text=Value
    ; atom(Value) -> atom_string(Value, Text)
    ; format(string(Text), '~w', [Value]) ).

% Called as a meta-goal before staged publication. The table writer has
% already validated its files. Only metadata.json is amended, then read back
% to ensure that the hash and paper identity survived serialization.
store_source_provenance(StageDir, Evidence) :-
    directory_file_path(StageDir, 'metadata.json', File),
    setup_call_cleanup(open(File, read, In, [encoding(utf8)]),
                       json_read_dict(In, Existing), close(In)),
    Existing.pmc_id == Evidence.pmc_id,
    put_dict(_{source_provenance:Evidence,
               semantic_validation:"unverified",
               annotation_kind:"structural_boundary_hypotheses"},
             Existing, Updated),
    setup_call_cleanup(open(File, write, Out, [encoding(utf8)]),
                       json_write_dict(Out, Updated), close(Out)),
    setup_call_cleanup(open(File, read, Verify, [encoding(utf8)]),
                       json_read_dict(Verify, Recheck), close(Verify)),
    Recheck.source_provenance.input_file_sha256 == Evidence.input_file_sha256,
    Recheck.semantic_validation == "unverified".
