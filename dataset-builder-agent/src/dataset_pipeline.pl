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
%       Wait for Seconds.
%   process_paper(+PmcId, +File, +DatasetDir, -Summary)
%       Extract every <table> of the full text File, rasterize it with
%       table_layout_generator.pl, check every header boundary against
%       parse_constraints.pl, and color the table for each valid boundary
%       with table_annotator.pl. The tables are saved as
%       <DatasetDir>/papers/PMC<id>/annotated_tableN.html, N from 0.
%       The directory is replaced as a whole after a successful run; the
%       title and counts are recorded in metadata.json.
%       Summary is a one-line report.

:- module(dataset_pipeline, [
      esearch_ids/2,
      esummary_lines/2,
      reset_search_provenance/0,
      verified_search_lines/3,
      filter_search_selected_ids/3,
      download_status/2,
      pause/1,
      process_paper/4,
      format_paper_failure/4
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

% Only IDs actually displayed by this run's successful search_pmc calls
% may be downloaded. Kept in the compiled module so tool calls and the main
% DML predicate share one source of truth. Cleared at the start of each run.
:- dynamic observed_search_pmc/1.

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
   retractall(observed_search_pmc(_)).

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

% --- downloads -------------------------------------------------------------

% NCBI answers a request over its rate limit with a short JSON object, e.g.
%   {"error":"API rate limit exceeded","api-key":"...","count":"4","limit":"3"}
% which url_fetch saves as if it were the requested file.
download_status(File, Status) :-
   setup_call_cleanup(
      open(File, read, In, [encoding(utf8)]),
      read_string(In, 400, Start),
      close(In)
   ),
   (  sub_string(Start, _, _, _, "API rate limit exceeded")
   -> Status = rate_limited
   ;  Status = ok
   ).

% sleep/1 is not available in DeepClause's WebAssembly engine (it raises a
% JavaScript error there), so pause/1 falls back to watching the clock.
pause(Seconds) :-
   get_time(Start),
   catch(sleep(Seconds), _, true),
   End is Start + Seconds,
   wait_until(End).

wait_until(End) :-
   repeat,
   get_time(Now),
   Now >= End,
   !.

% --- table pipeline --------------------------------------------------------

% process_paper(+PmcId, +File, +DatasetDir, -Summary)
% A canonical PMC id is the ONLY output identity. Titles never control paths.
% Build a complete replacement under a hidden staging directory, then publish
% it; a smaller rerun cannot leave the previous paper's extra table files.
process_paper(PmcId, File, DatasetDir, Summary) :-
   canonical_pmc_name(PmcId, PaperName),
   read_file_to_string(File, Text, [encoding(utf8)]),
   parse_html(Text, Dom),
   extract_tables(Dom, Tables),
   rasterize_tables_bounded(Tables, Rasters),
   ( paper_title(Dom, Title) -> true ; Title = "" ),
   directory_file_path(DatasetDir, 'papers', PapersDir),
   make_directory_path(PapersDir),
   with_paper_output_staging(PapersDir, PaperName,
                             write_paper_outputs(PaperName, Title, Tables, Rasters, NumParsed)),
   ignore(catch(record_paper_attempt(DatasetDir, PaperName, complete, "published"),
                _, fail)),
   length(Tables, NumTables),
   format(string(Summary),
          "~s: ~d table(s), ~d with a valid header boundary -> papers/~s/",
          [PaperName, NumTables, NumParsed, PaperName]).

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
   \+ exists_directory(Candidate),
   \+ exists_file(Candidate),
   make_directory(Candidate),
   StageDir = Candidate,
   !.

write_paper_outputs(PaperName, Title, Tables, Rasters, NumParsed, StageDir) :-
   % Do not use findall/3 around save_table/4: a failed table write would be
   % silently skipped, letting an incomplete paper look like a success.
   save_numbered_tables(StageDir, Tables, Rasters, 0, BoundaryLists),
   length(Tables, NumTables),
   exclude(==([]), BoundaryLists, Parsed),
   length(Parsed, NumParsed),
   directory_file_path(StageDir, 'metadata.json', MetadataFile),
   setup_call_cleanup(
      open(MetadataFile, write, Stream, [encoding(utf8)]),
      json_write_dict(Stream,
                      json{pmc_id:PaperName, title:Title, status:"complete",
                           table_count:NumTables, parsed_table_count:NumParsed}),
      close(Stream)),
   validate_paper_stage(StageDir, NumTables, NumParsed).

save_numbered_tables(_, [], [], _, []).
save_numbered_tables(StageDir, [Table|Tables], [Raster|Rasters], N,
                     [Boundaries|MoreBoundaries]) :-
   table_file_name(StageDir, N, TableFile),
   % Never let either an exception or plain predicate failure silently skip
   % one table. Include its 0-based index in the diagnostic.
   (  catch(save_table(TableFile, Table, Raster, Boundaries), Error,
            throw(error(table_output_failure(N, Error),
                        context(process_paper/4, 'Writing table failed'))))
   -> true
   ;  throw(error(table_output_failure(N, goal_failed),
                  context(process_paper/4, 'Writing table failed')))
   ),
   Next is N + 1,
   save_numbered_tables(StageDir, Tables, Rasters, Next, MoreBoundaries).

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
   sort(['metadata.json'|TableFiles], Expected),
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
   directory_file_path(StageDir, 'metadata.json', MetadataFile),
   read_json_file(MetadataFile, Metadata),
   (  Metadata.status == "complete",
      Metadata.table_count =:= ExpectedTables,
      Metadata.parsed_table_count =:= ExpectedParsed
   -> true
   ;  throw(error(incomplete_paper_stage(metadata_mismatch),
                  context(process_paper/4, 'Staged metadata is inconsistent')))
   ).

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
   valid_boundaries(Raster, Boundaries),
   table_annotations(Table, Boundaries, Annotations),
   setup_call_cleanup(
      open(TableFile, write, Stream, [encoding(utf8)]),
      forall(member(Annotation, Annotations),
             ( string_length(Annotation, HtmlLength), HtmlLength > 0,
               write(Stream, Annotation), nl(Stream) )),
      close(Stream)).

table_annotations(Table, [], [Html]) :- !,
   table_html(Table, Html).
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

paper_failure_reason(error(table_rasterization_failed(N), _), Reason) :- !,
   format(string(Reason), "table ~d rasterization returned failure", [N]).
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
