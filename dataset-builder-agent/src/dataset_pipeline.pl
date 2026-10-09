% Glue between dataset-builder.dml and the table logic files.
%
% dataset-builder.dml loads this module into DeepClause's own Prolog engine
% (:- load_files('/workspace/dataset_pipeline.pl', [])) and calls the exported
% predicates directly. Loading it as a real module matters: the predicates
% are then imported into the DML session and run as ordinary compiled Prolog.
% Code that DML reads with consult/1 is instead run by DML's meta-interpreter,
% which keeps only the first solution of a clause body and so breaks
% generators such as until/3 and sub_table/2.
%
% Nothing here touches the network or an LLM. The same predicates work in a
% local swipl:
%   ?- use_module(dataset_pipeline).
%   ?- process_paper("123", "dataset/raw/PMC123.xml", "dataset", Summary).
%
%   esearch_ids(+File, -Ids)
%       Ids is the comma-separated PMC ids of an E-utilities esearch response.
%   esummary_lines(+File, -Lines)
%       Lines is one "PMC<id> | <date> | <journal> | <title>" line per paper.
%   download_status(+File, -Status)
%       Status is rate_limited if File holds NCBI's "API rate limit exceeded"
%       reply instead of the requested data, and ok otherwise.
%   pause(+Seconds)
%       Native SWI-Prolog OS-backed sleep (WASM callers use the host helper).
%   process_paper(+PmcId, +File, +DatasetDir, -Summary)
%       Extract every <table> of the full text File, rasterize it with
%       table_layout_generator.pl, check every header boundary against
%       parse_constraints.pl, and color the table for each valid boundary
%       with table_annotator.pl. The tables are saved as
%       <DatasetDir>/papers/PMC<id>/annotated_tableN.html, N from 0.
%       The directory is replaced as a whole after a successful run; the
%       title, counts and per-table JATS context are recorded in metadata.json.
%       Summary is a one-line report.

:- module(dataset_pipeline, [
      esearch_ids/2,
      esummary_lines/2,
      reset_search_provenance/0,
      remember_search_query/1,
      record_dataset_run/8,
      verified_search_lines/3,
      filter_search_selected_ids/3,
      download_status/2,
      download_status/3,
      pause/1,
      process_paper/4,
      process_paper/5,
      format_paper_failure/4,
      allocate_search_cache/5,
      cleanup_search_cache/1,
      reserve_ncbi_request/1,
      ncbi_rate_limit_at/3,
      acquire_paper_ingest_lock/2,
      acquire_paper_ingest_lock_at/3,
      release_paper_ingest_lock/1
   ]).

% library(json) only exists in recent SWI-Prolog; DeepClause's bundled engine
% still has it as library(http/json).
:- if(exists_source(library(json))).
:- use_module(library(json)).
:- else.
:- use_module(library(http/json)).
:- endif.
:- use_module(library(filesex)).
:- use_module(library(readutil)).
:- use_module(library(lists)).
:- use_module(library(apply)).

:- consult(table_layout_generator).
:- consult(parse_constraints).
:- consult(table_annotator).
:- consult(table_machine_records).
:- use_module(provenance_manifest).

% Only IDs actually displayed by this run's successful search_pmc calls
% may be downloaded. Kept in the compiled module so tool calls and the main
% DML predicate share one source of truth. Cleared at the start of each run.
:- dynamic observed_search_pmc/1.
:- dynamic observed_search_query/1.

% --- search results --------------------------------------------------------

esearch_ids(File, Ids) :-
   read_json_file(File, Json),
   atomic_list_concat(Json.esearchresult.idlist, ',', IdsAtom),
   atom_string(IdsAtom, Ids).

esummary_lines(File, Lines) :-
   read_json_file(File, Json),
   Result = Json.result,
   findall(Line, ( member(Uid, Result.uids), summary_line(Result, Uid, Line) ), LineList),
   atomic_list_concat(LineList, '\n', LinesAtom),
   atom_string(LinesAtom, Lines).

% Clear the candidate allowlist *before* invoking the model. Search results
% from previous agent_main invocations must not authorize new selections.
reset_search_provenance :-
   retractall(observed_search_pmc(_)),
   retractall(observed_search_query(_)).

remember_search_query(Query) :-
   ( string(Query) -> Text = Query ; atom(Query), atom_string(Query, Text) ),
   ( observed_search_query(Text) -> true ; assertz(observed_search_query(Text)) ).

% Build a trusted list of selectable PMC IDs from one paired ESearch /
% ESummary response. ESummary UIDs MUST also be in this ESearch ID list.
% Only IDs that are actually rendered into the returned tool text are
% recorded. A failed or empty search records nothing; previous successful
% searches in this run remain eligible.
verified_search_lines(SearchFile, SummaryFile, Lines) :-
   read_json_file(SearchFile, SearchJson),
   read_json_file(SummaryFile, SummaryJson),
   Search = SearchJson.esearchresult,
   is_list(Search.idlist),
   findall(Id,
           ( member(Value, Search.idlist), canonical_search_id(Value, Id) ),
           SearchIds0),
   sort(SearchIds0, SearchIds),
   Result = SummaryJson.result,
   is_list(Result.uids),
   findall(Id-Line,
           ( member(Uid, Result.uids),
             canonical_search_id(Uid, Id),
             memberchk(Id, SearchIds),
             summary_line(Result, Uid, Line) ),
           Pairs0),
   list_to_set(Pairs0, Pairs),
   Pairs \== [],
   findall(Line, member(_-Line, Pairs), VisibleLines),
   atomic_list_concat(VisibleLines, '\n', Text),
   atom_string(Text, Lines),
   forall(member(Id-_, Pairs),
          ( observed_search_pmc(Id) -> true
          ; assertz(observed_search_pmc(Id)) )).

% Canonicalize numeric UIDs to remove leading zero aliases and reject
% empty, negative, nonnumeric or otherwise unsafe values.
canonical_search_id(Value, Digits) :-
   canonical_pmc_name(Value, Name),
   sub_string(Name, 3, _, 0, Digits).

% Preserve the model's preference order but never process an ID not seen
% in this run's search tool output. Report rejected candidates separately.
filter_search_selected_ids(Proposed, Approved, Rejected) :-
   filter_search_selected_ids_(Proposed, RawApproved, Rejected),
   list_to_set(RawApproved, Approved).

filter_search_selected_ids_([], [], []).
filter_search_selected_ids_([Candidate|Rest], Approved, Rejected) :-
   ( canonical_search_id(Candidate, Id), observed_search_pmc(Id)
   -> Approved = [Id|MoreApproved],
      Rejected = MoreRejected
   ;  Approved = MoreApproved,
      Rejected = [Candidate|MoreRejected]
   ),
   filter_search_selected_ids_(Rest, MoreApproved, MoreRejected).

read_json_file(File, Json) :-
   setup_call_cleanup(
      open(File, read, In, [encoding(utf8)]),
      json_read_dict(In, Json, [default_tag(json)]),
      close(In)
   ).

summary_line(Result, Uid, Line) :-
   canonical_search_id(Uid, Digits),
   ( string(Uid) -> atom_string(Key, Uid)
   ; atom(Uid) -> Key = Uid
   ; integer(Uid) -> number_string(Uid, S), atom_string(Key, S) ),
   get_dict(Key, Result, Doc),
   field(Doc, pubdate, Date),
   field(Doc, fulljournalname, Journal),
   field(Doc, title, Title),
   format(string(Line), "PMC~s | ~w | ~w | ~w", [Digits, Date, Journal, Title]).

field(Doc, Key, Value) :-
   (  get_dict(Key, Doc, V), V \== ""
   -> Value = V
   ;  Value = "?"
   ).

% --- Concurrent search / request coordination (F13) -----------------------
%
% Each search gets its own exclusively created directory. ESearch and
% ESummary must be read from the SAME private directory so a concurrent
% DeepClause run can never swap their contents between requests. Files are
% temporary: selectable PMC IDs remain in this engine's per-run allowlist.
%
% allocate_search_cache(+Workspace, -SearchSaveTo, -SearchMounted,
%                       -SummarySaveTo, -SummaryMounted)
% SaveTo paths are relative to the DeepClause workspace (url_fetch input);
% Mounted paths are absolute, for use by the compiled Prolog module.
allocate_search_cache(Workspace, SearchSave, SearchMounted,
                      SummarySave, SummaryMounted) :-
   directory_file_path(Workspace, 'dataset/cache/requests', RequestRoot),
   make_directory_path(RequestRoot),
   fresh_staging_directory(RequestRoot, 'search', SearchDir),
   file_base_name(SearchDir, Name),
   format(string(SearchSave), 'dataset/cache/requests/~w/esearch.json', [Name]),
   format(string(SummarySave), 'dataset/cache/requests/~w/esummary.json', [Name]),
   directory_file_path(SearchDir, 'esearch.json', SearchMounted),
   directory_file_path(SearchDir, 'esummary.json', SummaryMounted).

% Cleanup takes a path returned by allocate_search_cache/5, never a
% model-provided path. It is invoked even when downloading/parsing fails.
cleanup_search_cache(SearchMounted) :-
   file_directory_name(SearchMounted, SearchDir),
   ( exists_directory(SearchDir)
   -> delete_directory_and_contents(SearchDir)
   ;  true ).

% Shared host/workspace limiter, not a per-agent sleep. All DeepClause
% processes working in the same /workspace/dataset/cache reserve request
% start times under one OS-atomic mkdir lock. A lock holder sleeps *inside*
% the critical section; other workers cannot reserve conflicting times.
% The gap governs reservations immediately before url_fetch, not HTTP
% completion, since DeepClause's url_fetch is outside the Prolog module.
reserve_ncbi_request(Gap) :-
   ncbi_rate_limit_at('/workspace/dataset/cache', Gap, _).

ncbi_rate_limit_at(CacheRoot, Gap, ReservedAt) :-
   ( number(Gap), Gap >= 0.34
   -> true
   ;  throw(error(domain_error(ncbi_minimum_request_gap, Gap),
                  context(ncbi_rate_limit_at/3, 'Require at least 0.34 seconds without an API key'))) ),
   make_directory_path(CacheRoot),
   directory_file_path(CacheRoot, '.ncbi-request.lock', LockDir),
   acquire_directory_lock(LockDir, 300),
   setup_call_cleanup(
      true,
      rate_limit_under_lock(CacheRoot, Gap, ReservedAt),
      delete_directory(LockDir)).

rate_limit_under_lock(CacheRoot, Gap, ReservedAt) :-
   directory_file_path(CacheRoot, '.ncbi-last-request', StampFile),
   ( exists_file(StampFile)
   -> read_file_to_string(StampFile, Text, [encoding(utf8)]),
      normalize_space(string(Trim), Text),
      ( catch(number_string(Last, Trim), _, fail), number(Last)
      -> true
      ;  throw(error(ncbi_invalid_rate_state(StampFile),
                     context(ncbi_rate_limit_at/3, 'Invalid shared timestamp'))) )
   ;  Last = 0 ),
   get_time(Now),
   ( Last > Now + 60
   -> throw(error(ncbi_rate_clock_skew(Last, Now),
                  context(ncbi_rate_limit_at/3, 'Clock moved backwards')))
   ;  true ),
   Delay is max(0, Last + Gap - Now),
   pause(Delay),
   get_time(ReservedAt),
   % The directory mutex guards the timestamp update, while a temporary
   % file + rename prevents truncated shared state after ordinary failures.
   directory_file_path(CacheRoot, '.ncbi-last-request.new', TempFile),
   setup_call_cleanup(
      open(TempFile, write, Stream, [encoding(utf8)]),
      format(Stream, '~16f~n', [ReservedAt]),
      close(Stream)),
   rename_file(TempFile, StampFile).

% Only the expected 'already locked' case is retried, and lock acquisition
% times out instead of racing the critical section. Crashed-process locks
% are deliberately NOT removed based on age: another process may be slow.
acquire_directory_lock(LockDir, Remaining) :-
   ( catch(make_directory(LockDir), Error,
           ( exists_directory(LockDir) -> fail ; throw(Error) ))
   -> true
   ;  ( Remaining > 0
      -> pause(0.1), Next is Remaining - 1,
         acquire_directory_lock(LockDir, Next)
      ;  throw(error(concurrent_lock_busy(LockDir),
                     context(acquire_directory_lock/2, 'Remove a stale lock only after verifying no owner is running'))) ) ).

% Raw/PMC<ID>.xml is a shared, stable file. Serialize the *entire* download
% and process step (not merely the download) for identical PMC IDs so that
% another worker cannot replace the XML while process_paper/4 reads it.
acquire_paper_ingest_lock(Id, LockDir) :-
   acquire_paper_ingest_lock_at('/workspace/dataset', Id, LockDir).

acquire_paper_ingest_lock_at(DatasetRoot, Id, LockDir) :-
   canonical_pmc_name(Id, Name),
   directory_file_path(DatasetRoot, 'raw', RawDir),
   make_directory_path(RawDir),
   format(string(LockName), '.~s.ingest.lock', [Name]),
   directory_file_path(RawDir, LockName, LockDir),
   % Fail closed when another ingest has this ID. Concurrent different IDs
   % proceed independently. Do not auto-delete possibly live locks.
   ( catch(make_directory(LockDir), Error,
           ( exists_directory(LockDir) -> fail ; throw(Error) ))
   -> true
   ;  throw(error(pmc_ingest_busy(Name),
                  context(acquire_paper_ingest_lock/2, 'Raw download already in progress'))) ).

release_paper_ingest_lock(LockDir) :-
   delete_directory(LockDir).

% --- downloads -------------------------------------------------------------

% Validate the *body* saved by url_fetch.  That primitive does not expose
% an HTTP status/content-type here: an HTTP error page or JSON error body
% must never count as a successfully downloaded PMC article.  Unlike the
% historical first-400-character check, this validates the document shape
% and a complete XML parse.  process_paper/4 subsequently checks PMC identity.
%
% Status is one of ok, rate_limited, retryable(server_unavailable), or
% invalid(Reason).  JSON and XML are validated separately.
download_status(File, Status) :-
   file_base_name(File, Base),
   text_to_string(Base, BaseText),
   ( sub_string(BaseText, _, _, 0, ".xml") -> Kind = jats_xml
   ; sub_string(BaseText, _, _, _, "esummary") -> Kind = esummary_json
   ; Kind = esearch_json ),
   download_status(File, Kind, Status).

download_status(File, Kind, Status) :-
   read_file_to_string(File, Body, [encoding(utf8)]),
   string_length(Body, Length),
   Sniff is min(Length, 2048),
   sub_string(Body, 0, Sniff, _, Prefix),
   string_lower(Prefix, Lower),
   ( Length =:= 0
   -> Status = invalid(empty_body)
   % A complete, single JATS article is never an error response, even when
   % its first 2 KB (e.g. a title) happens to contain a rate-limit phrase.
   % Error bodies that merely look like XML still fall through to the sniffs.
   ; Kind == jats_xml, valid_jats_body(Body)
   -> Status = ok
   ; ( sub_string(Lower, _, _, _, "rate limit exceeded")
     ; sub_string(Lower, _, _, _, "too many requests")
     ; sub_string(Lower, _, _, _, "429 too many requests") )
   -> Status = rate_limited
   ; ( sub_string(Lower, _, _, _, "503 service unavailable")
     ; sub_string(Lower, _, _, _, "502 bad gateway")
     ; sub_string(Lower, _, _, _, "500 internal server error") )
   -> Status = retryable(server_unavailable)
   ; classify_download_body(Kind, Body, Lower, Status)
   ).

valid_jats_body(Body) :-
   catch(( parse_jats_xml(Body, Dom), jats_single_article(Dom, _) ), _, fail).

classify_download_body(_, _, Lower, invalid(http_error_page)) :-
   ( sub_string(Lower, _, _, _, "<html")
   ; sub_string(Lower, _, _, _, "<!doctype html") ), !.
classify_download_body(jats_xml, Body, _, Status) :- !,
   ( catch((parse_jats_xml(Body, Dom), jats_single_article(Dom, _)), _, fail)
   -> Status = ok
   ;  Status = invalid(malformed_or_nonarticle_xml) ).
classify_download_body(Kind, Body, _, Status) :-
   memberchk(Kind, [esearch_json, esummary_json]), !,
   ( catch(setup_call_cleanup(open_string(Body, In),
                             json_read_dict(In, Json, [default_tag(json)]),
                             close(In)), _, fail)
   -> json_response_status(Kind, Json, Status)
   ;  Status = invalid(malformed_json) ).
classify_download_body(_, _, _, invalid(unknown_document_kind)).

json_response_status(_, Json, invalid(api_error)) :-
   is_dict(Json), get_dict(error, Json, _), !.
json_response_status(esearch_json, Json, ok) :-
   is_dict(Json), get_dict(esearchresult, Json, Result),
   is_dict(Result), get_dict(idlist, Result, Ids), is_list(Ids), !.
json_response_status(esummary_json, Json, ok) :-
   is_dict(Json), get_dict(result, Json, Result),
   is_dict(Result), get_dict(uids, Result, Uids), is_list(Uids), !.
json_response_status(_, _, invalid(unexpected_json_shape)).

% Only the canonical JATS forms are accepted.  An HTML response, a random
% XML document and a batch containing multiple articles are not one paper.
jats_single_article(Dom, Article) :-
   include(jats_top_level_element, Dom, [Root]),
   ( Root = element(article, _, _)
   -> Article = Root
   ;  Root = element('pmc-articleset', _, Children),
      include(is_element(article), Children, [Article])
   ).

jats_top_level_element(element(_, _, _)).

% An eFetch response for PMC123 must contain a JATS article with exactly
% that ID in <front><article-meta><article-id pub-id-type="pmc">.
% Reference-list article ids do not count as identity evidence.
verify_jats_pmc_id(Dom, Expected) :-
   ( jats_single_article(Dom, Article)
   -> true
   ;  throw(error(invalid_jats_xml(nonarticle_root),
                  context(process_paper/4, 'No single JATS article in PMC response'))) ),
   findall(Id, article_front_pmc_id(Article, Id), Ids0),
   sort(Ids0, Ids),
   ( Ids == [Expected]
   -> true
   ;  throw(error(pmc_article_identity_mismatch(Expected, Ids),
                  context(process_paper/4, 'Missing or conflicting JATS PMC ID'))) ).

article_front_pmc_id(element(article, _, Children), PmcName) :-
   member(element(front, _, Front), Children),
   member(element('article-meta', _, Meta), Front),
   member(element('article-id', Attrs, Content), Meta),
   memberchk('pub-id-type'=Type, Attrs),
   text_to_string(Type, TypeText),
   string_lower(TypeText, "pmc"),
   findall(Piece, text_piece(Content, Piece), Pieces),
   atomic_list_concat(Pieces, '', Atom),
   normalize_space(string(Raw), Atom),
   string_upper(Raw, Upper),
   ( sub_string(Upper, 0, 3, _, "PMC")
   -> sub_string(Upper, 3, _, 0, Digits)
   ; Digits = Upper ),
   canonical_pmc_name(Digits, PmcName).

% This predicate is for standalone/native Prolog (including plunit tests).
% DeepClause's WebAssembly Prolog may lack sleep/1. Never spin on get_time/1
% as a fallback: that burns CPU and can prevent the host from servicing work.
% The DML agent instead delegates both request reservations and retries to
% the host through ncbi_wait.py, which uses an OS-backed timed wait.
pause(Seconds) :-
   ( number(Seconds), Seconds >= 0, Seconds =< 300
   -> true
   ;  throw(error(domain_error(pause_seconds_0_to_300, Seconds),
                  context(pause/1, 'Expected a nonnegative number of seconds <= 300'))) ),
   ( Seconds =:= 0
   -> true
   ;  catch(sleep(Seconds), Error,
             throw(error(timed_wait_unavailable(Seconds, Error),
                         context(pause/1, 'Use host sleep from DML when running in WebAssembly'))))
   ).

% --- table pipeline --------------------------------------------------------

% process_paper(+PmcId, +File, +DatasetDir, -Summary)
% A canonical PMC id is the ONLY output identity. Titles never control paths.
% Build a complete replacement under a hidden staging directory, then publish
% it; a smaller rerun cannot leave the previous paper's extra table files.
process_paper(PmcId, File, DatasetDir, Summary) :-
   canonical_pmc_name(PmcId, PaperName),
   read_file_to_string(File, Text, [encoding(utf8)]),
   parse_jats_xml(Text, Dom),
   verify_jats_pmc_id(Dom, PaperName),
   % Keep each table paired with its JATS table-wrap and its element path.
   % Rasterization still sees only the <table>, never captions/footnotes.
   jats_table_records(Dom, Records),
   maplist(record_table, Records, Tables),
   rasterize_tables_bounded(Tables, Rasters),
   ( paper_title(Dom, Title) -> true ; Title = "" ),
   directory_file_path(DatasetDir, 'papers', PapersDir),
   make_directory_path(PapersDir),
   paper_source_provenance(File, PaperName, Dom, SourceEvidence),
   with_paper_output_staging(PapersDir, PaperName,
       write_paper_records_with_evidence(PaperName, Title, Records,
                                         Rasters, NumParsed, SourceEvidence)),
   ignore(catch(record_paper_attempt(DatasetDir, PaperName, complete, "published"),
                _, fail)),
   length(Tables, NumTables),
   format(string(Summary),
          "~s: ~d table(s), ~d with a valid header boundary -> papers/~s/",
          [PaperName, NumTables, NumParsed, PaperName]).


% process_paper(+PmcId, +File, +DatasetDir, +Options, -Summary)
% Optional *explicit* per-table recovery. /4 remains strict, including in
% dataset_builder.dml. Quarantine is only for recognized, table-local geometry
% or candidate-budget errors; it never hides XML/identity, paper budget, file
% system, or publication failures. Failed tables retain their original indices
% in tables.jsonl and metadata; they do NOT get a fake HTML annotation.
process_paper(PmcId, File, DatasetDir, Options, Summary) :-
   ( Options == [on_table_error(fail)]
   -> process_paper(PmcId, File, DatasetDir, Summary)
   ; Options == [on_table_error(quarantine)]
   -> process_paper_quarantine(PmcId, File, DatasetDir, Summary)
   ; throw(error(domain_error(paper_processing_options, Options),
                 context(process_paper/5, 'Use [on_table_error(fail|quarantine)]')))
   ).

process_paper_quarantine(PmcId, File, DatasetDir, Summary) :-
   canonical_pmc_name(PmcId, PaperName),
   read_file_to_string(File, Text, [encoding(utf8)]),
   parse_jats_xml(Text, Dom),
   verify_jats_pmc_id(Dom, PaperName),
   jats_table_records(Dom, Records),
   length(Records, NumTables),
   ensure_paper_limit(max_tables, NumTables),
   ( paper_title(Dom, Title) -> true ; Title = "" ),
   directory_file_path(DatasetDir, 'papers', PapersDir),
   make_directory_path(PapersDir),
   paper_source_provenance(File, PaperName, Dom, SourceEvidence),
   with_paper_output_staging(PapersDir, PaperName,
       write_recoverable_paper_with_evidence(PaperName, Title, Records,
                                             NumParsed, NumRejected, SourceEvidence)),
   ( NumRejected =:= 0 -> Status = "complete" ; Status = "partial" ),
   format(string(Detail), '~d table(s), ~d parsed, ~d quarantined',
          [NumTables, NumParsed, NumRejected]),
   ignore(catch(record_paper_attempt(DatasetDir, PaperName, Status, Detail), _, fail)),
   format(string(Summary), '~s: ~s (~s) -> papers/~s/',
          [PaperName, Status, Detail, PaperName]).


% --- JATS table provenance and context (F09) ------------------------------
%
% A table-wrap is a sibling container: its <label>, <caption> and
% <table-wrap-foot> are NOT descendants of <table>. Merely calling
% extract_tables/2 loses these scientific qualifications. Keep the nearest
% enclosing wrap while walking the normalized JATS DOM in document order.
% Paths are 1-based element-child positions, ignoring text nodes. They are
% relative to the root DOM list and can distinguish equal table-wrap ids.
%
% jats_table_records(+Dom, -Records)
% Record = table_record(TableElement, ContextDict).
jats_table_records(Dom, Records) :-
   findall(table_record(Table, Context),
           ( element_child_at(Dom, Root, RootIndex),
             table_in_jats(Root, [RootIndex], none, Table, Context) ),
           Records).

record_table(table_record(Table, _), Table).
record_context(table_record(_, Context), Context).

% Count only elements, not inter-element whitespace or character data.
element_child_at(Children, Child, Index) :-
   element_child_at_(Children, 1, Child, Index).
element_child_at_([element(Name, Attrs, Content)|Rest], N, Child, Index) :- !,
   ( Child = element(Name, Attrs, Content), Index = N
   ; N1 is N + 1, element_child_at_(Rest, N1, Child, Index) ).
element_child_at_([_|Rest], N, Child, Index) :-
   element_child_at_(Rest, N, Child, Index).

table_in_jats(Table, Path, Wrap, Table, Context) :-
   Table = element(table, _, _),
   table_source_context(Table, Path, Wrap, Context).
table_in_jats(element(Name, Attrs, Children), Path, ParentWrap, Table, Context) :-
   ( Name == 'table-wrap'
   -> CurrentWrap = wrap(element(Name, Attrs, Children), Path)
   ;  CurrentWrap = ParentWrap ),
   element_child_at(Children, Child, ChildIndex),
   append(Path, [ChildIndex], ChildPath),
   table_in_jats(Child, ChildPath, CurrentWrap, Table, Context).

source_path_text(Path, Text) :-
   maplist(number_string, Path, Parts),
   atomics_to_string(Parts, '/', Text).

source_id(element(_, Attrs, _), Id) :-
   ( memberchk(id=Value, Attrs)
   -> text_to_string(Value, Id)
   ;  Id = "" ).

% Text is deliberately normalized for a searchable JSON field and for an
% HTML caption. The source table itself is separately serialized in JSON.
jats_element_text(element(_, _, Children), Text) :-
   findall(Piece, text_piece(Children, Piece), Pieces),
   atomic_list_concat(Pieces, ' ', Joined),
   normalize_space(string(Text), Joined).

direct_context_text(Children, Name, Text) :-
   findall(Piece,
           ( member(Node, Children), Node = element(Name, _, _),
             jats_element_text(Node, Piece), Piece \== "" ),
           Pieces),
   atomics_to_string(Pieces, ' ', Text).

% Also retain the annotated DOM markup in metadata. Superscripts, xrefs,
% emphasis and note identifiers are important scientific context which a
% plain text field by itself cannot faithfully preserve.
direct_context_markup(Children, Name, Markup) :-
   findall(Fragment,
           ( member(Node, Children), Node = element(Name, _, _),
             table_html(Node, Fragment) ),
           Fragments),
   atomics_to_string(Fragments, '\n', Markup).

% One note per direct foot child, or per fn under a fn-group. This preserves
% separate JATS footnote entries rather than flattening the full table-wrap.
wrap_notes(Children, Notes) :-
   findall(Note,
           ( member(element('table-wrap-foot', _, FootChildren), Children),
             member(Node, FootChildren),
             footnote_node(Node, Note), Note \== "" ),
           Notes).

footnote_node(element('fn-group', _, Children), Text) :- !,
   member(Child, Children), footnote_node(Child, Text).
footnote_node(Node, Text) :-
   Node = element(_, _, _),
   jats_element_text(Node, Text).

table_source_context(Table, Path, Wrap, Context) :-
   source_path_text(Path, TablePath),
   source_id(Table, TableId),
   ( Wrap = wrap(WrapElement, WrapPath)
   -> WrapElement = element('table-wrap', _, WrapChildren),
      source_path_text(WrapPath, WrapPathText),
      source_id(WrapElement, WrapId),
      direct_context_text(WrapChildren, label, Label),
      direct_context_text(WrapChildren, caption, Caption),
      direct_context_markup(WrapChildren, label, LabelMarkup),
      direct_context_markup(WrapChildren, caption, CaptionMarkup),
      direct_context_markup(WrapChildren, 'table-wrap-foot', FootMarkup),
      wrap_notes(WrapChildren, Notes)
   ;  WrapPathText = "", WrapId = "", Label = "", Notes = [],
      LabelMarkup = "", CaptionMarkup = "", FootMarkup = "",
      Table = element(table, _, TableChildren),
      direct_context_text(TableChildren, caption, Caption) ),
   % A standalone HTML table can also carry its own caption, even when a
   % wrapping JATS table-wrap is present but has no external caption.
   ( Caption == "", Table = element(table, _, InnerChildren)
   -> direct_context_text(InnerChildren, caption, EffectiveCaption),
      direct_context_markup(InnerChildren, caption, EffectiveCaptionMarkup),
      CaptionExternal = false
   ;  EffectiveCaption = Caption,
      EffectiveCaptionMarkup = CaptionMarkup,
      CaptionExternal = true ),
   table_html(Table, RawTableHtml),
   Context = json{source_path:TablePath, table_id:TableId,
                  wrap_path:WrapPathText, wrap_id:WrapId,
                  label:Label, caption:EffectiveCaption,
                  caption_external:CaptionExternal,
                  notes:Notes, source_table_html:RawTableHtml,
                  label_markup:LabelMarkup,
                  caption_markup:EffectiveCaptionMarkup,
                  foot_markup:FootMarkup}.

% Compatibility entry point for tests and callers supplying parsed <table>
% elements instead of full JATS documents.
plain_table_record(Table, table_record(Table, Context)) :-
   ( Table = element(table, _, _)
   -> table_source_context(Table, [], none, Context)
   ;  % Preserve the F05 table-indexed error for malformed caller input:
      % only the numbered writer should fail, not the upfront conversion.
      empty_table_context(Context) ).

empty_table_context(json{source_path:"", table_id:"", wrap_path:"",
                         wrap_id:"", label:"", caption:"",
                         caption_external:false, notes:[],
                         source_table_html:"", label_markup:"",
                         caption_markup:"", foot_markup:""}).

% Per-paper budgets bound the number and combined raster area of tables
% retained in memory before paper publication. A violation is an exception,
% so F03's previous completed paper remains untouched (no partial outputs).
paper_raster_limit(max_tables, 256).
paper_raster_limit(max_total_slots, 250000).

ensure_paper_limit(Name, Actual) :-
   paper_raster_limit(Name, Maximum),
   (  Actual =< Maximum -> true
   ;  throw(error(paper_raster_limit_exceeded(Name, Maximum, Actual),
                  context(process_paper/4, 'Paper exceeds raster limits')))
   ).

rasterize_tables_bounded(Tables, Rasters) :-
   length(Tables, NumTables),
   ensure_paper_limit(max_tables, NumTables),
   rasterize_tables_bounded(Tables, 0, 0, Rasters).

rasterize_tables_bounded([], _, _, []).
rasterize_tables_bounded([Table|Tables], Used0, Index, [Raster|Rasters]) :-
   % Preserve the original error term (for API compatibility) while adding
   % the table index to its context for actionable build reports.
   (  catch(rasterize_table(Table, Raster), error(Formal, _),
            throw(error(Formal, context(table_index(Index), 'Rasterizing table'))))
   -> true
   ;  throw(error(table_rasterization_failed(Index),
                  context(process_paper/4, 'Rasterizer returned failure')))
   ),
   length(Raster, Rows),
   ( Raster = [FirstRow|_] -> length(FirstRow, Cols) ; Cols = 0 ),
   Used is Used0 + Rows * Cols,
   catch(ensure_paper_limit(max_total_slots, Used), error(Formal2, _),
         throw(error(Formal2, context(table_index(Index), 'Paper slot budget')))),
   Next is Index + 1,
   rasterize_tables_bounded(Tables, Used, Next, Rasters).

% The agent supplies digit strings. Also accept atoms and positive integers in
% local Prolog calls, but never allow unchecked path fragments or alternate
% spellings (e.g. PMC00042 and PMC42) to create different paper identities.
canonical_pmc_name(PmcId, PaperName) :-
   ( integer(PmcId) -> format(string(Text), "~d", [PmcId])
   ; string(PmcId) -> Text = PmcId
   ; atom(PmcId) -> atom_string(PmcId, Text)
   ),
   string_length(Text, Length),
   between(1, 12, Length),
   string_codes(Text, Codes),
   forall(member(Code, Codes), between(0'0, 0'9, Code)),
   number_string(Number, Text),
   Number > 0,
   format(string(PaperName), "PMC~d", [Number]).

% Meta-argument: a goal that receives the fresh staging directory.
% If parsing, coloring, writing or publishing fails, the incomplete staging
% directory is removed and any previously published version is retained.
:- meta_predicate with_paper_output_staging(+, +, 1).
with_paper_output_staging(PapersDir, PaperName, Writer) :-
   paper_lock_directory(PapersDir, PaperName, LockDir),
   % make_directory/1 provides exclusive creation; a second process trying
   % the same PMC id fails instead of racing the two directory renames.
   make_directory(LockDir),
   setup_call_cleanup(
      true,
      staged_paper_write(PapersDir, PaperName, Writer),
      delete_directory(LockDir)).

staged_paper_write(PapersDir, PaperName, Writer) :-
   fresh_staging_directory(PapersDir, PaperName, StageDir),
   setup_call_cleanup(
      true,
      ( call(Writer, StageDir),
        publish_paper_directory(PapersDir, PaperName, StageDir) ),
      ( exists_directory(StageDir)
      -> delete_directory_and_contents(StageDir)
      ;  true )).

paper_lock_directory(PapersDir, PaperName, LockDir) :-
   format(string(LockName), ".~s.lock", [PaperName]),
   directory_file_path(PapersDir, LockName, LockDir).

% Hidden staging/backup names are reserved under the SAME parent as the final
% directory so renames do not cross filesystem boundaries. A fresh directory
% is allocated for each run, even if a crashed earlier run left staging files.
fresh_staging_directory(PapersDir, PaperName, StageDir) :-
   get_time(Now),
   Stamp is floor(Now * 1000000),
   between(0, 9999, Attempt),
   format(string(StageName), ".~s.stage.~d.~d", [PaperName, Stamp, Attempt]),
   directory_file_path(PapersDir, StageName, Candidate),
   catch(make_directory(Candidate), _, fail),
   StageDir = Candidate,
   !.

% The original writer/validator is unchanged. Provenance is appended to
% metadata inside the unpublished stage; a failure retains the old snapshot.
write_paper_records_with_evidence(Pmc, Title, Records, Rasters,
                                   NumParsed, Evidence, StageDir) :-
   write_paper_records(Pmc, Title, Records, Rasters, NumParsed, StageDir),
   store_source_provenance(StageDir, Evidence).

write_recoverable_paper_with_evidence(Pmc, Title, Records,
                                      NumParsed, NumRejected, Evidence, StageDir) :-
   write_recoverable_paper(Pmc, Title, Records, NumParsed, NumRejected, StageDir),
   store_source_provenance(StageDir, Evidence).

% Retain the pre-F09 writer interface for existing local Prolog callers.
write_paper_outputs(PaperName, Title, Tables, Rasters, NumParsed, StageDir) :-
   maplist(plain_table_record, Tables, Records),
   write_paper_records(PaperName, Title, Records, Rasters, NumParsed, StageDir).

write_paper_records(PaperName, Title, Records, Rasters, NumParsed, StageDir) :-
   % Publish one JSONL record per table alongside the optional HTML view.
   % Both live in the same staged snapshot and are validated before commit.
   directory_file_path(StageDir, 'tables.jsonl', RecordsFile),
   setup_call_cleanup(
      open(RecordsFile, write, JsonlStream, [encoding(utf8)]),
      save_numbered_records(StageDir, PaperName, Records, Rasters, 0,
                            JsonlStream, BoundaryLists, TableMetadata),
      close(JsonlStream)),
   length(Records, NumTables),
   exclude(==([]), BoundaryLists, Parsed),
   length(Parsed, NumParsed),
   directory_file_path(StageDir, 'metadata.json', MetadataFile),
   setup_call_cleanup(
      open(MetadataFile, write, Stream, [encoding(utf8)]),
      json_write_dict(Stream,
                      json{pmc_id:PaperName, title:Title, status:"complete",
                           schema_version:"1.0", jsonl_file:"tables.jsonl",
                           table_count:NumTables, parsed_table_count:NumParsed,
                           tables:TableMetadata}),
      close(Stream)),
   validate_paper_stage(StageDir, NumTables, NumParsed).

save_numbered_records(_, _, [], [], _, _, [], []).
save_numbered_records(StageDir, PaperName, [table_record(Table,Context)|Rest],
                      [Raster|Rasters], N, JsonlStream,
                      [Boundaries|MoreBoundaries], [Meta|MoreMeta]) :-
   table_file_name(StageDir, N, TableFile),
   format(string(TableUid), '~s/t~d', [PaperName, N]),
   put_dict(table_uid, Context, HtmlContext),
   % Fail closed if any annotation or JSONL record cannot be generated.
   ( catch(( save_table(TableFile, Table, Raster, HtmlContext, Boundaries),
             machine_table_record(PaperName, N, Table, Context, Raster,
                                  Boundaries, MachineRecord, Meta),
             atom_json_dict(JsonLine, MachineRecord, [width(0)]),
             format(JsonlStream, '~w~n', [JsonLine]) ),
           Error, throw(error(table_output_failure(N, Error),
                              context(process_paper/4, 'Writing table failed'))))
   -> true
   ;  throw(error(table_output_failure(N, goal_failed),
                  context(process_paper/4, 'Writing table failed')))
   ),
   Next is N + 1,
   save_numbered_records(StageDir, PaperName, Rest, Rasters, Next,
                         JsonlStream, MoreBoundaries, MoreMeta).


% Opt-in recovery writes a JSONL entry for EVERY input table, including
% rejected tables. This preserves source indices and makes omissions visible.
% A paper with no successfully processed tables is NOT published as partial.
write_recoverable_paper(PaperName, Title, Records, NumParsed, NumRejected,
                        StageDir) :-
   directory_file_path(StageDir, 'tables.jsonl', RecordsFile),
   setup_call_cleanup(
      open(RecordsFile, write, Out, [encoding(utf8)]),
      save_recoverable_records(Records, PaperName, StageDir, Out,
                               0, 0, 0, 0, NumParsed, NumRejected, TableMetadata),
      close(Out)),
   length(Records, NumTables),
   NumKept is NumTables - NumRejected,
   ( NumTables > 0, NumKept =:= 0
   -> throw(error(all_tables_quarantined(NumTables),
                  context(process_paper/5, 'No usable tables; snapshot retained')))
   ; true ),
   ( NumRejected =:= 0 -> Status = "complete", Version = "1.0"
   ; Status = "partial", Version = "1.1" ),
   directory_file_path(StageDir, 'metadata.json', MetadataFile),
   setup_call_cleanup(
      open(MetadataFile, write, Stream, [encoding(utf8)]),
      json_write_dict(Stream,
                      json{pmc_id:PaperName, title:Title, status:Status,
                           schema_version:Version, jsonl_file:"tables.jsonl",
                           table_count:NumTables, parsed_table_count:NumParsed,
                           quarantined_table_count:NumRejected, tables:TableMetadata}),
      close(Stream)),
   validate_recoverable_stage(StageDir, NumTables, NumParsed, NumRejected).

save_recoverable_records([], _, _, _, _, _, Parsed, Rejected,
                         Parsed, Rejected, []).
save_recoverable_records([table_record(Table, Context)|Rest], PaperName,
                         StageDir, Out, Index, Used0, Parsed0, Rejected0,
                         Parsed, Rejected, [Metadata|Metadatas]) :-
   try_recoverable_raster(Table, Index, RasterResult),
   ( RasterResult = ok(Raster)
   -> length(Raster, Rows),
      ( Raster = [FirstRow|_] -> length(FirstRow, Cols) ; Cols = 0 ),
      Used is Used0 + Rows * Cols,
      % An aggregate budget breach is a PAPER error; never quarantine it.
      catch(ensure_paper_limit(max_total_slots, Used), error(Formal, _),
            throw(error(Formal, context(table_index(Index), 'Paper slot budget')))),
      try_recoverable_annotation(StageDir, PaperName, Index, Table, Context,
                                 Raster, AnnotationResult)
   ; Used = Used0, AnnotationResult = RasterResult ),
   ( AnnotationResult = ok(Boundaries, Record, Metadata)
   -> ( Boundaries == [] -> Parsed1 = Parsed0 ; Parsed1 is Parsed0 + 1 ),
      Rejected1 = Rejected0
   ; AnnotationResult = rejected(Code, Message),
     quarantined_machine_record(PaperName, Index, Context, Code, Message,
                                Record, Metadata),
     Parsed1 = Parsed0, Rejected1 is Rejected0 + 1 ),
   atom_json_dict(JsonLine, Record, [width(0)]),
   format(Out, '~w~n', [JsonLine]),
   Next is Index + 1,
   save_recoverable_records(Rest, PaperName, StageDir, Out,
                            Next, Used, Parsed1, Rejected1,
                            Parsed, Rejected, Metadatas).

try_recoverable_raster(Table, Index, Result) :-
   catch(( rasterize_table(Table, Raster)
         -> Result = ok(Raster)
         ; Result = rejected("rasterization_failed", "Rasterizer returned failure") ),
         Error,
         ( recoverable_table_error(Error, Code, Message)
         -> Result = rejected(Code, Message)
         ; throw(error(table_processing_failure(Index, Error),
                       context(process_paper/5, 'Unexpected raster failure'))) )).

try_recoverable_annotation(StageDir, PaperName, Index, Table, Context,
                            Raster, Result) :-
   table_file_name(StageDir, Index, TableFile),
   format(string(TableUid), '~s/t~d', [PaperName, Index]),
   put_dict(table_uid, Context, HtmlContext),
   catch(( save_table(TableFile, Table, Raster, HtmlContext, Boundaries),
           machine_table_record(PaperName, Index, Table, Context, Raster,
                                Boundaries, Machine, Meta)
         -> Result = ok(Boundaries, Machine, Meta)
         ; throw(error(table_output_failed, context(process_paper/5, 'Writer failed'))) ),
         Error,
         ( recoverable_table_error(Error, Code, Message)
         -> ( exists_file(TableFile) -> delete_file(TableFile) ; true ),
            Result = rejected(Code, Message)
         ; throw(error(table_output_failure(Index, Error),
                       context(process_paper/5, 'Unexpected output failure'))) )).

% Only enumerated structural failures qualify for quarantine. In particular
% permission errors, out-of-space, JSON encoding errors, paper budgets and
% bugs must abort publication rather than be mislabeled as bad source tables.
recoverable_table_error(error(table_layout_error(Cause), _),
                        "invalid_layout", Message) :- !,
   format(string(Message), '~w', [Cause]).
recoverable_table_error(error(table_raster_limit_exceeded(Name, Max, Actual), _),
                        "table_raster_limit", Message) :- !,
   format(string(Message), '~w exceeded (~w > ~w)', [Name, Actual, Max]).
recoverable_table_error(error(table_output_limit_exceeded(Name, Max, Actual), _),
                        "candidate_output_limit", Message) :- !,
   format(string(Message), '~w exceeded (~w > ~w)', [Name, Actual, Max]).
recoverable_table_error(error(unmapped_source_cell(Id), _),
                        "unmapped_source_cell", Message) :- !,
   format(string(Message), 'Source cell ~d has no raster slot', [Id]).

quarantined_machine_record(PaperName, Index, Context, Code, Message,
                           Record, Metadata) :-
   format(string(TableUid), '~s/t~d', [PaperName, Index]),
   Diagnostic = json{code:Code, detail:Message},
   Record = json{schema_version:"1.1", pmc_id:PaperName, table_index:Index,
                 table_uid:TableUid, source_table_id:Context.table_id,
                 source_path:Context.source_path,
                 source_table_html:Context.source_table_html,
                 context:Context, raster:null, rows:null, columns:null,
                 cells:[], candidates:[], status:"quarantined",
                 abstention_reason:"table_processing_error", error:Diagnostic,
                 algorithm:"seven_structural_constraints_v1",
                 semantic_validation:"unverified",
                 interpretation_kind:"structural_boundary_hypotheses"},
   put_dict(_{table_uid:TableUid, jsonl_file:"tables.jsonl",
              candidate_count:0, annotation_status:"quarantined",
              error:Diagnostic}, Context, Metadata).

% Independent staged-snapshot validation for the partial format. Check exact
% file membership and every JSONL record before publishing; a quarantined
% record MUST be accompanied by a diagnostic and MUST NOT have an HTML file.
validate_recoverable_stage(StageDir, ExpectedTables, ExpectedParsed,
                            ExpectedRejected) :-
   directory_file_path(StageDir, 'tables.jsonl', JsonlFile),
   read_table_jsonl(JsonlFile, Records),
   directory_file_path(StageDir, 'metadata.json', MetadataFile),
   read_json_file(MetadataFile, Meta),
   ( ExpectedRejected =:= 0 -> Status = "complete", Version = "1.0"
   ; Status = "partial", Version = "1.1" ),
   ( Meta.status == Status, Meta.schema_version == Version,
     Meta.table_count =:= ExpectedTables,
     Meta.parsed_table_count =:= ExpectedParsed,
     Meta.quarantined_table_count =:= ExpectedRejected,
     Meta.jsonl_file == "tables.jsonl",
     length(Records, ExpectedTables),
     is_list(Meta.tables), length(Meta.tables, ExpectedTables),
     recovery_records_consistent(Records, Meta.tables, Meta.pmc_id,
                                 0, 0, 0, ExpectedParsed, ExpectedRejected,
                                 HtmlNames)
   -> true
   ; throw(error(incomplete_paper_stage(recovery_metadata_mismatch),
                 context(process_paper/5, 'Recovery snapshot inconsistent'))) ),
   sort(['metadata.json', 'tables.jsonl'|HtmlNames], ExpectedFiles),
   directory_files(StageDir, RawFiles),
   exclude(is_dot_entry, RawFiles, ActualFiles0),
   sort(ActualFiles0, ActualFiles),
   ( ActualFiles == ExpectedFiles
   -> true
   ; throw(error(incomplete_paper_stage(file_set_mismatch(ExpectedFiles,ActualFiles)),
                 context(process_paper/5, 'Unexpected or missing staged files'))) ),
   forall(member(Name, HtmlNames),
          ( directory_file_path(StageDir, Name, Path),
            size_file(Path, Size),
            ( Size > 0 -> true
            ; throw(error(incomplete_paper_stage(empty_table(Name)),
                          context(process_paper/5, 'Empty staged table'))) ) )),
   size_file(MetadataFile, MetaSize), MetaSize > 0,
   ( ExpectedTables =:= 0 -> true
   ; size_file(JsonlFile, JsonlSize), JsonlSize > 0 ).

recovery_records_consistent([], [], _, _, Parsed, Rejected,
                            Parsed, Rejected, []).
recovery_records_consistent([Record|Records], [Context|Contexts], Pmc,
                            Index, Parsed0, Rejected0, Parsed, Rejected, Files) :-
   is_dict(Record), is_dict(Context),
   format(string(ExpectedUid), '~s/t~d', [Pmc, Index]),
   Record.pmc_id == Pmc, Record.table_index =:= Index,
   Record.table_uid == ExpectedUid,
   Record.table_uid == Context.table_uid,
   Record.source_path == Context.source_path,
   Record.source_table_id == Context.table_id,
   Record.source_table_html == Context.source_table_html,
   Context.jsonl_file == "tables.jsonl",
   format(atom(HtmlName), 'annotated_table~d.html', [Index]),
   ( Record.status == "quarantined"
   -> Record.schema_version == "1.1",
      Record.raster == null,
      Record.cells == [], Record.candidates == [],
      Record.abstention_reason == "table_processing_error",
      Record.error == Context.error,
      string(Record.error.detail),
      memberchk(Record.error.code,
                ["invalid_layout", "table_raster_limit",
                 "candidate_output_limit", "unmapped_source_cell",
                 "rasterization_failed"]),
      Context.annotation_status == "quarantined",
      Context.candidate_count =:= 0,
      Parsed1 = Parsed0, Rejected1 is Rejected0 + 1,
      Files = RestFiles
   ; Record.schema_version == "1.0",
     machine_record_consistent(Record),
     ( Record.status == "abstained"
     -> Record.candidates == [], Record.abstention_reason \== null,
        Parsed1 = Parsed0
     ; ( Record.status == "unique" -> Record.candidates = [_]
       ; Record.status == "ambiguous", Record.candidates = [_,_|_] ),
       Record.abstention_reason == null,
       Parsed1 is Parsed0 + 1 ),
     Context.annotation_status == Record.status,
     length(Record.candidates, Context.candidate_count),
     Rejected1 = Rejected0,
     Files = [HtmlName|RestFiles] ),
   Next is Index + 1,
   recovery_records_consistent(Records, Contexts, Pmc, Next,
                               Parsed1, Rejected1, Parsed, Rejected, RestFiles).

% Each JSON line must be a complete object; embedded HTML/newlines are JSON
% escaped by atom_json_dict/3. Do not parse candidate membership from CSS.
read_table_jsonl(File, Records) :-
   setup_call_cleanup(
      open(File, read, Stream, [encoding(utf8)]),
      read_table_jsonl_stream(Stream, Records),
      close(Stream)).

read_table_jsonl_stream(Stream, Records) :-
   read_line_to_string(Stream, Line),
   ( Line == end_of_file -> Records = []
   ; atom_string(Text, Line),
     atom_json_dict(Text, Record, []),
     Records = [Record|Rest],
     read_table_jsonl_stream(Stream, Rest) ).

% Ensure the entire expected paper snapshot was staged, not merely that
% its writer returned true. A missing, empty or unexpected file is an error;
% in particular we must never publish an empty annotation as a successful
% table or a directory whose metadata disagrees with its contents.
validate_paper_stage(StageDir, ExpectedTables, ExpectedParsed) :-
   directory_files(StageDir, Entries),
   exclude(is_dot_entry, Entries, ActualFiles),
   findall(Name,
           ( ExpectedTables > 0,
             Last is ExpectedTables - 1,
             between(0, Last, N),
             format(atom(Name), 'annotated_table~d.html', [N]) ),
           TableFiles),
   sort(['metadata.json', 'tables.jsonl'|TableFiles], Expected),
   sort(ActualFiles, Actual),
   (  Actual == Expected
   -> true
   ;  throw(error(incomplete_paper_stage(file_set_mismatch(Expected, Actual)),
                  context(process_paper/4, 'Staged paper files mismatch')))
   ),
   forall(member(FileName, TableFiles),
          ( directory_file_path(StageDir, FileName, File),
            size_file(File, Size),
            ( Size > 0
            -> true
            ;  throw(error(incomplete_paper_stage(empty_table(FileName)),
                           context(process_paper/4, 'Staged table is empty')))
            ) )),
   directory_file_path(StageDir, 'tables.jsonl', JsonlFile),
   size_file(JsonlFile, JsonlSize),
   ( ( ( ExpectedTables =:= 0, JsonlSize =:= 0 )
       ; ( ExpectedTables > 0, JsonlSize > 0 ) )
   -> true
   ; throw(error(incomplete_paper_stage(invalid_jsonl_size),
                 context(process_paper/4, 'JSONL size does not match table count'))) ),
   read_table_jsonl(JsonlFile, MachineRecords),
   directory_file_path(StageDir, 'metadata.json', MetadataFile),
   read_json_file(MetadataFile, Metadata),
   (  Metadata.status == "complete",
      Metadata.table_count =:= ExpectedTables,
      Metadata.parsed_table_count =:= ExpectedParsed,
      Metadata.jsonl_file == "tables.jsonl",
      get_dict(tables, Metadata, Contexts),
      is_list(Contexts), length(Contexts, ExpectedTables),
      length(MachineRecords, ExpectedTables),
      machine_records_match_metadata(MachineRecords, Contexts,
                                     Metadata.pmc_id, ExpectedParsed)
   -> true
   ;  throw(error(incomplete_paper_stage(metadata_mismatch),
                  context(process_paper/4, 'Staged metadata is inconsistent')))
   ).

machine_records_match_metadata(Records, Contexts, Pmc, ParsedCount) :-
   machine_records_match_metadata(Records, Contexts, Pmc, 0, 0, ParsedCount).

machine_records_match_metadata([], [], _, _, Parsed, Parsed).
machine_records_match_metadata([Record|Records], [Context|Contexts],
                               Pmc, Index, Parsed0, ExpectedParsed) :-
   is_dict(Record), is_dict(Context),
   Record.pmc_id == Pmc, Record.table_index =:= Index,
   Record.table_uid == Context.table_uid,
   Context.jsonl_file == "tables.jsonl",
   get_dict(source_path, Context, SourcePath),
   get_dict(source_table_html, Context, _),
   Record.source_path == SourcePath,
   is_list(Record.raster), is_list(Record.cells),
   is_list(Record.candidates),
   machine_record_consistent(Record),
   length(Record.candidates, Context.candidate_count),
   ( Record.candidates == []
   -> Record.status == "abstained", Record.abstention_reason \== null,
      Context.annotation_status == "abstained", Parsed1 = Parsed0
   ;  Record.abstention_reason == null,
      Context.annotation_status == Record.status,
      ( Record.candidates = [_] -> Record.status == "unique"
      ; Record.status == "ambiguous" ),
      Parsed1 is Parsed0 + 1 ),
   Next is Index + 1,
   machine_records_match_metadata(Records, Contexts, Pmc, Next,
                                  Parsed1, ExpectedParsed).

% The JSONL label map is a scientific data artifact: before publishing,
% check every reported candidate against the structural solver and the
% raster's first-slot cell IDs. A swapped/missing/duplicated label is fatal.
machine_record_consistent(Record) :-
   machine_first_slots(Record.raster, FirstSlots),
   length(FirstSlots, NumCells),
   length(Record.cells, NumCells),
   maplist(machine_record_cell_consistent, FirstSlots, Record.cells),
   % Recompute the complete candidate set once using the indexed checker.
   % This verifies membership, order and completeness as well as labels.
   valid_boundaries(Record.raster, ExpectedBoundaries),
   maplist(machine_record_candidate_consistent(Record.table_uid, FirstSlots),
           ExpectedBoundaries, Record.candidates).

machine_record_cell_consistent(Id-(Row-Col), Cell) :-
   Cell.cell_id =:= Id,
   Cell.row =:= Row,
   Cell.column =:= Col,
   ( Cell.kind == "source"
   -> string(Cell.source_xpath), Cell.source_xpath \== ""
   ; Cell.kind == "synthetic_gap", Cell.source_xpath == null ).

machine_record_candidate_consistent(TableUid, FirstSlots, Boundary, Candidate) :-
   machine_candidate(TableUid, FirstSlots, Boundary, Expected),
   Candidate == Expected.

is_dot_entry('.').
is_dot_entry('..').

% Replacement of a nonempty directory requires two renames. We retain the
% previous complete version under a hidden backup until the staged directory
% is in place; on ordinary errors we restore that previous version. Unlike
% a single file rename, this is NOT crash-atomic: power loss between renames
% may leave a .backup directory requiring recovery.
publish_paper_directory(PapersDir, PaperName, StageDir) :-
   directory_file_path(PapersDir, PaperName, FinalDir),
   ( exists_directory(FinalDir)
   -> backup_directory_path(PapersDir, StageDir, BackupDir),
      rename_file(FinalDir, BackupDir),
      ( catch(rename_file(StageDir, FinalDir), Error,
              ( rename_file(BackupDir, FinalDir), throw(Error) ))
      -> discard_old_backup(BackupDir)
      ;  rename_file(BackupDir, FinalDir),
         fail )
   ;  rename_file(StageDir, FinalDir)
   ).

% Once the new directory has been published, failure to clean an obsolete
% backup must not turn a complete build into a reported failure. Keep it for
% manual review and emit a warning instead.
discard_old_backup(BackupDir) :-
   ( catch(delete_directory_and_contents(BackupDir), _, fail)
   -> true
   ;  format(user_error, "Warning: obsolete paper backup remains at ~s~n", [BackupDir])
   ).

backup_directory_path(PapersDir, StageDir, BackupDir) :-
   file_base_name(StageDir, StageName),
   format(string(BackupName), "~s.backup", [StageName]),
   directory_file_path(PapersDir, BackupName, BackupDir),
   \+ exists_directory(BackupDir),
   \+ exists_file(BackupDir).

table_file_name(PaperDir, N, TableFile) :-
   format(string(Name), "annotated_table~w.html", [N]),
   directory_file_path(PaperDir, Name, TableFile).

% save_table(+TableFile, +Table, +Raster, -Boundaries)
% The file holds the table colored once for every valid (Hmd, Vmd) boundary,
% one copy after another; a table with no valid boundary is saved uncolored.
save_table(TableFile, Table, Raster, Boundaries) :-
   table_source_context(Table, [], none, Context),
   save_table(TableFile, Table, Raster, Context, Boundaries).

save_table(TableFile, Table, Raster, Context, Boundaries) :-
   Table = element(table, _, _),
   valid_boundaries(Raster, Boundaries),
   ensure_candidate_output_budget(Raster, Boundaries),
   % Stream candidate views one by one. Do not materialize the full table
   % once for every surviving boundary, and do not rasterize it again.
   setup_call_cleanup(
      open(TableFile, write, Stream, [encoding(utf8)]),
      save_candidates_stream(Stream, Context, Table, Raster, Boundaries),
      close(Stream)).

% The explicit F10 JSONL label arrays, and the optional per-candidate HTML,
% still require work proportional to candidates * distinct source cells.
% Do not attempt to materialize an unbounded cartesian product on large,
% highly ambiguous tables. This is checked before opening the output file;
% failure aborts the staged paper and leaves the previous publication intact.
% It never truncates a candidate set or misreports a rejected table as parsed.
max_candidate_label_records(500000).

ensure_candidate_output_budget(_, []) :- !.
ensure_candidate_output_budget(Raster, Boundaries) :-
   length(Boundaries, NumCandidates),
   machine_first_slots(Raster, FirstSlots),
   length(FirstSlots, NumCells),
   TotalLabels is NumCandidates * NumCells,
   max_candidate_label_records(MaxLabels),
   (  TotalLabels =< MaxLabels
   -> true
   ;  throw(error(table_output_limit_exceeded(candidate_labels,
                                               MaxLabels, TotalLabels),
                  context(save_table/5,
                          'Full candidate labels would exceed output budget')))
   ).

save_candidates_stream(Stream, Context, Table, _, []) :- !,
   safe_table_dom(Table, SafeTable),
   table_html(SafeTable, Html),
   save_annotated_candidates(Stream, Context, [], [Html]).
save_candidates_stream(Stream, Context, Table, Raster, Boundaries) :-
   % Sanitize once per table, before any candidate is annotated. Trusted
   % background-color styles are introduced only after untrusted CSS is gone.
   safe_table_dom(Table, SafeTable),
   maplist(save_candidate_stream(Stream, Context, SafeTable, Raster), Boundaries).

save_candidate_stream(Stream, Context, Table, Raster, Boundary) :-
   Boundary = json{hmd:Hmd,vmd:Vmd},
   annotate_precleaned_table_raster(Hmd, Vmd, Table, Raster, Annotated),
   table_html(Annotated, Html),
   save_annotated_candidate(Stream, Context, Boundary, Html).

save_annotated_candidates(Stream, Context, [], [Annotation]) :- !,
   contextual_table_annotation(Context, Annotation, WithContext),
   format(Stream, '<h3 class="boundary-status">Abstained: no valid boundary</h3>~n~s~n',
          [WithContext]).
save_annotated_candidates(Stream, Context, Boundaries, Annotations) :-
   % Each rendered candidate has its own explicit coordinates and heading.
   % The JSONL candidate IDs are fully qualified by PMC/table index.
   maplist(save_annotated_candidate(Stream, Context), Boundaries, Annotations).

save_annotated_candidate(Stream, Context, json{hmd:Hmd,vmd:Vmd}, Annotation) :-
   contextual_table_annotation(Context, Annotation, WithContext),
   ( get_dict(table_uid, Context, TableUid)
   -> format(string(CandidateId), '~s/h~d_v~d', [TableUid, Hmd, Vmd])
   ;  format(string(CandidateId), 'h~d_v~d', [Hmd, Vmd]) ),
   format(Stream,
          '<h3 class="boundary-candidate" data-candidate-id="~s" data-hmd="~d" data-vmd="~d">Candidate h~d_v~d (HMD=~d, VMD=~d)</h3>~n~s~n',
          [CandidateId, Hmd, Vmd, Hmd, Vmd, Hmd, Vmd, WithContext]).

% Render external JATS metadata as separate HTML, NEVER as extra table cells:
% otherwise the constraint checker would be given a different raster.
% html_write escapes label/caption/footnote text, including angle brackets.
contextual_table_annotation(Context, TableHtml, Html) :-
   findall(Node,
           ( ( Context.label \== "", Node = element(p, [class='jats-label'], [Context.label]) )
           ; ( Context.caption_external == true, Context.caption \== "",
               Node = element(p, [class='jats-caption'], [Context.caption]) ) ),
           HeadingNodes),
   ( HeadingNodes == [] -> Header = ""
   ; table_html(element(header, [class='jats-table-context'], HeadingNodes), Header) ),
   ( Context.notes == [] -> Footer = ""
   ; maplist(note_list_item, Context.notes, NoteItems),
     table_html(element(footer, [class='jats-table-notes'],
                        [element(ul, [], NoteItems)]), Footer) ),
   format(string(Html), '<section class="jats-table-result">~s~s~s</section>',
          [Header, TableHtml, Footer]).

note_list_item(Note, element(li, [], [Note])).

table_annotations(Table, [], [Html]) :- !,
   safe_table_dom(Table, SafeTable),
   table_html(SafeTable, Html).
table_annotations(Table, Boundaries, Annotations) :-
   % findall/3 silently drops candidates whose annotation fails. A table
   % with valid candidate boundaries must render exactly one result per
   % candidate; maplist/3 propagates ordinary failure to the table writer.
   maplist(render_boundary(Table), Boundaries, Annotations).

render_boundary(Table, json{hmd:Hmd, vmd:Vmd}, Annotation) :-
   annotate_table_element(Hmd, Vmd, Table, Annotated),
   table_html(Annotated, Annotation).

% --- paper metadata --------------------------------------------------------

% The first <article-title> in document order is the paper's own; the ones
% in the reference list come later.
paper_title(Dom, Title) :-
   member(Node, Dom),
   sub_element('article-title', Node, element(_, _, Children)),
   !,
   findall(Piece, text_piece(Children, Piece), Pieces),
   atomic_list_concat(Pieces, ' ', Joined),
   normalize_space(string(Title), Joined).

sub_element(Name, Element, Element) :-
   Element = element(Name, _, _).
sub_element(Name, element(_, _, Children), Element) :-
   member(Child, Children),
   sub_element(Name, Child, Element).

text_piece(Children, Piece) :-
   member(Child, Children),
   (  Child = element(_, _, GrandChildren)
   -> text_piece(GrandChildren, Piece)
   ;  Piece = Child
   ).


% --- build diagnostics -----------------------------------------------------
%
% In the DML agent a failure is reported instead of being swallowed by an
% anonymous catch/3. The *previous published paper* is not modified on
% failed reruns; this is distinct from an unsuccessful raw XML download.
% Failure records are outside papers/ and never mark an incomplete snapshot
% as complete. Logging is best effort and must not hide the original error.
format_paper_failure(PmcId, DatasetDir, Error, Line) :-
   (  canonical_pmc_name(PmcId, PaperName)
   -> true
   ;  PaperName = "PMC-invalid-id"
   ),
   paper_failure_reason(Error, Reason),
   directory_file_path(DatasetDir, 'papers', PapersDir),
   directory_file_path(PapersDir, PaperName, FinalDir),
   (  exists_directory(FinalDir)
   -> Previous = "previous published snapshot retained"
   ;  Previous = "no published snapshot present"
   ),
   format(string(Line), "~s: failed (~s); ~s", [PaperName, Reason, Previous]),
   ignore(catch(record_paper_attempt(DatasetDir, PaperName, failed, Reason), _, fail)).

paper_failure_reason(error(all_tables_quarantined(Count), _), Reason) :- !,
   format(string(Reason), "all ~d source tables quarantined; no replacement published", [Count]).
paper_failure_reason(error(table_processing_failure(Index, Cause), _), Reason) :- !,
   exception_class(Cause, Class),
   format(string(Reason), "table ~d processing: ~s", [Index, Class]).
paper_failure_reason(error(table_rasterization_failed(N), _), Reason) :- !,
   format(string(Reason), "table ~d rasterization returned failure", [N]).
paper_failure_reason(error(table_layout_error(Cause),
                           context(table_index(Index), _)), Reason) :- !,
   format(string(Reason), "table ~d invalid layout: ~w", [Index, Cause]).
paper_failure_reason(error(table_layout_error(Cause), _), Reason) :- !,
   format(string(Reason), "invalid table layout: ~w", [Cause]).
paper_failure_reason(error(table_output_failure(N, Cause), _), Reason) :- !,
   exception_class(Cause, Class),
   format(string(Reason), "table ~d output: ~s", [N, Class]).
paper_failure_reason(error(incomplete_paper_stage(Cause), _), Reason) :- !,
   exception_class(Cause, Class),
   format(string(Reason), "stage validation: ~s", [Class]).
paper_failure_reason(error(table_raster_limit_exceeded(Name, Maximum, Actual),
                           context(table_index(Index), _)), Reason) :- !,
   format(string(Reason), "table ~d raster limit ~w exceeded (~w > ~w)",
          [Index, Name, Actual, Maximum]).
paper_failure_reason(error(table_raster_limit_exceeded(Name, Maximum, Actual), _), Reason) :- !,
   format(string(Reason), "raster limit ~w exceeded (~w > ~w)", [Name, Actual, Maximum]).
paper_failure_reason(error(paper_raster_limit_exceeded(Name, Maximum, Actual),
                           context(table_index(Index), _)), Reason) :- !,
   format(string(Reason), "table ~d paper raster limit ~w exceeded (~w > ~w)",
          [Index, Name, Actual, Maximum]).
paper_failure_reason(error(paper_raster_limit_exceeded(Name, Maximum, Actual), _), Reason) :- !,
   format(string(Reason), "paper raster limit ~w exceeded (~w > ~w)", [Name, Actual, Maximum]).
paper_failure_reason(error(ncbi_download_invalid(Kind, Cause), _), Reason) :- !,
   format(string(Reason), "NCBI ~w response invalid: ~w", [Kind, Cause]).
paper_failure_reason(error(pmc_article_identity_mismatch(Expected, Seen), _), Reason) :- !,
   format(string(Reason), "PMC article identity mismatch (expected ~s, found ~w)", [Expected, Seen]).
paper_failure_reason(error(invalid_jats_xml(Cause), _), Reason) :- !,
   format(string(Reason), "invalid JATS XML: ~w", [Cause]).
paper_failure_reason(error(invalid_jats_xml(Severity, Line, Message), _), Reason) :- !,
   format(string(Reason), "invalid JATS XML (~w line ~w): ~w", [Severity, Line, Message]).
paper_failure_reason(pipeline_goal_failed, "download or processing returned failure").
paper_failure_reason(Error, Reason) :-
   exception_class(Error, Class),
   format(string(Reason), "~s", [Class]).

exception_class(error(Formal, _), Class) :- !,
   exception_class(Formal, Class).
exception_class(Formal, Class) :-
   (  compound(Formal) -> functor(Formal, Name, _) ; Name = Formal ),
   format(string(Class), "~w", [Name]).

% Each attempt gets a unique status file, so a failed rerun does not alter
% earlier successful attempt records or the published paper metadata.
% Cleanup/reporting errors are deliberately non-fatal once publication occurs.
record_paper_attempt(DatasetDir, PaperName, Status, Detail) :-
   directory_file_path(DatasetDir, 'attempts', AttemptsDir),
   make_directory_path(AttemptsDir),
   get_time(Now),
   Stamp is floor(Now * 1000000),
   between(0, 9999, Sequence),
   format(string(FileName), "~s.~d.~d.json", [PaperName, Stamp, Sequence]),
   directory_file_path(AttemptsDir, FileName, File),
   \+ exists_file(File),
   setup_call_cleanup(
      open(File, write, Out, [encoding(utf8)]),
      json_write_dict(Out, json{pmc_id:PaperName, status:Status, detail:Detail,
                               timestamp_unix:Now}),
      close(Out)),
   !.

% One run record stores the source topic, actual successful search queries,
% model-proposed tokens, grounded selections and each paper's outcome.
% It is deliberately separate from immutable per-PMC snapshots. A unique
% directory avoids cross-process collisions and incomplete file replacement.
record_dataset_run(DatasetDir, Topic, RawModelIds, ProposedIds, SelectedIds, RejectedIds,
                   Results, RunFile) :-
   findall(Query, observed_search_query(Query), Queries),
   findall(Pmc, observed_search_pmc(Pmc), Allowed),
   directory_file_path(DatasetDir, 'runs', RunsDir),
   make_directory_path(RunsDir),
   fresh_staging_directory(RunsDir, 'run', StageDir),
   file_base_name(StageDir, StageName),
   format(string(FinalName), 'run-~w', [StageName]),
   directory_file_path(RunsDir, FinalName, FinalDir),
   directory_file_path(StageDir, 'manifest.json', StageFile),
   get_time(Now),
   setup_call_cleanup(
      true,
      ( setup_call_cleanup(open(StageFile, write, Out, [encoding(utf8)]),
            json_write_dict(Out,
               json{schema_version:"1.0", topic:Topic,
                    timestamp_unix:Now, search_queries:Queries,
                    authorized_pmc_ids:Allowed, model_selection_raw:RawModelIds,
                    parsed_pmc_ids:ProposedIds, selected_pmc_ids:SelectedIds,
                    rejected_pmc_ids:RejectedIds, paper_status_lines:Results,
                    policy:"Only IDs observed in paired ESearch and ESummary can be selected; license review required before redistribution"}),
            close(Out)),
        % Only a completed manifest is made visible as a run directory.
        rename_file(StageDir, FinalDir) ),
      ( exists_directory(StageDir)
      -> delete_directory_and_contents(StageDir)
      ;  true )),
   directory_file_path(FinalDir, 'manifest.json', RunFile).
