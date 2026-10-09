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
      download_status/2,
      pause/1,
      process_paper/4
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

read_json_file(File, Json) :-
   setup_call_cleanup(
      open(File, read, In, [encoding(utf8)]),
      json_read_dict(In, Json, [default_tag(json)]),
      close(In)
   ).

summary_line(Result, Uid, Line) :-
   atom_string(Key, Uid),
   get_dict(Key, Result, Doc),
   field(Doc, pubdate, Date),
   field(Doc, fulljournalname, Journal),
   field(Doc, title, Title),
   format(string(Line), "PMC~w | ~w | ~w | ~w", [Uid, Date, Journal, Title]).

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
   maplist(rasterize_table, Tables, Rasters),
   ( paper_title(Dom, Title) -> true ; Title = "" ),
   directory_file_path(DatasetDir, 'papers', PapersDir),
   make_directory_path(PapersDir),
   with_paper_output_staging(PapersDir, PaperName,
                             write_paper_outputs(PaperName, Title, Tables, Rasters, NumParsed)),
   length(Tables, NumTables),
   format(string(Summary),
          "~s: ~d table(s), ~d with a valid header boundary -> papers/~s/",
          [PaperName, NumTables, NumParsed, PaperName]).

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
                      json{pmc_id:PaperName, title:Title,
                           table_count:NumTables, parsed_table_count:NumParsed}),
      close(Stream)).

save_numbered_tables(_, [], [], _, []).
save_numbered_tables(StageDir, [Table|Tables], [Raster|Rasters], N,
                     [Boundaries|MoreBoundaries]) :-
   table_file_name(StageDir, N, TableFile),
   save_table(TableFile, Table, Raster, Boundaries),
   Next is N + 1,
   save_numbered_tables(StageDir, Tables, Rasters, Next, MoreBoundaries).

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
             ( write(Stream, Annotation), nl(Stream) )),
      close(Stream)).

table_annotations(Table, [], [Html]) :- !,
   table_html(Table, Html).
table_annotations(Table, Boundaries, Annotations) :-
   findall(
      Annotation,
      ( member(json{hmd: Hmd, vmd: Vmd}, Boundaries),
        annotate_table_element(Hmd, Vmd, Table, Annotated),
        table_html(Annotated, Annotation) ),
      Annotations
   ).

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

