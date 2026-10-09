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
%       <DatasetDir>/<paper title>/annotated_tableN.html, N counting from 0.
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
% Creates DatasetDir and the paper's directory inside it if they do not
% exist, then writes one file per table of the full text, numbered from 0 in
% document order (the same layout as test_driver.pl).
process_paper(PmcId, File, DatasetDir, Summary) :-
   read_file_to_string(File, Text, [encoding(utf8)]),
   parse_html(Text, Dom),
   extract_tables(Dom, Tables),
   maplist(rasterize_table, Tables, Rasters),
   paper_directory_name(PmcId, Dom, PaperName),
   directory_file_path(DatasetDir, PaperName, PaperDir),
   make_directory_path(PaperDir),
   findall(
      Boundaries,
      ( nth0(N, Tables, Table),
        nth0(N, Rasters, Raster),
        table_file_name(PaperDir, N, TableFile),
        save_table(TableFile, Table, Raster, Boundaries) ),
      BoundaryLists
   ),
   length(Tables, NumTables),
   exclude(==([]), BoundaryLists, Parsed),
   length(Parsed, NumParsed),
   format(string(Summary),
          "PMC~w: ~w table(s), ~w with a valid header boundary -> ~w/",
          [PmcId, NumTables, NumParsed, PaperName]).

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

% --- paper directory -------------------------------------------------------

% paper_directory_name(+PmcId, +Dom, -Name): the paper's title as a directory
% name, or its PMC id if the full text has no title.
paper_directory_name(PmcId, Dom, Name) :-
   (  paper_title(Dom, Title),
      directory_name(Title, Name),
      Name \== ""
   -> true
   ;  format(string(Name), "PMC~w", [PmcId])
   ).

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

% directory_name(+Title, -Name): Title made safe as a single path component.
% Letters, digits and  - _ . , ( )  are kept, anything else (slashes, colons,
% quotes, ...) becomes a space; the result is at most 80 characters long and
% does not start or end with a dot or a space.
directory_name(Title, Name) :-
   string_chars(Title, Chars),
   maplist(safe_char, Chars, SafeChars),
   string_chars(Safe, SafeChars),
   normalize_space(string(Collapsed), Safe),
   (  string_length(Collapsed, Length), Length > 80
   -> sub_string(Collapsed, 0, 80, _, Cut)
   ;  Cut = Collapsed
   ),
   split_string(Cut, "", " .", [Name]).

safe_char(Char, Safe) :-
   (  ( char_type(Char, alnum) ; memberchk(Char, ['-', '_', '.', ',', '(', ')']) )
   -> Safe = Char
   ;  Safe = ' '
   ).
