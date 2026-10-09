% Local table-logic driver: runs the table pipeline on one HTML or XML file,
% without the DeepClause agent, an API key, or the network.
%
% From dataset-builder-agent/src/:
%   swipl -g 'consult(test_driver),
%             test_table_parser("path/to/file.html", Files),
%             writeln(Files)' -t halt
%
% For every <table> in the file (in document order, an outer table before any
% table nested in it) the driver
%   1. rasterizes it (table_layout_generator.pl),
%   2. enumerates the structural header boundaries (parse_constraints.pl),
%   3. writes one sanitized, colored HTML view per candidate boundary
%      (table_annotator.pl), or one uncolored view when no boundary exists.
%
% Output files go to OutDir (default: "<File>.tables"):
%   table<N>_hmd<H>_vmd<V>.html   table N colored for boundary (H,V)
%   table<N>_unannotated.html     table N has no admissible boundary
% N counts from 0. Before writing, previous files named table*.html in OutDir
% are removed so stale candidates from an earlier run cannot be mistaken for
% current ones; any other file in OutDir is left alone.
%
% A file whose extension is .xml or .nxml is parsed as strict JATS XML
% (parse_jats_xml/2); anything else is parsed as loose HTML (parse_html/2).
%
% Candidate boundaries are structural hypotheses, NOT verified semantic labels.
%
% The driver is strict, like process_paper/4: a table that exceeds the raster
% limits or has malformed spans raises the same typed error and writes nothing
% further. A file with no <table> raises error(no_tables_found(File), _).
%
%   test_table_parser(+File, -Files)
%   test_table_parser(+File, +OutDir, -Files)
%       Files is the list of written paths, in table then candidate order.

:- use_module(library(readutil)).
:- use_module(library(filesex)).
:- use_module(library(lists)).
:- use_module(library(apply)).

:- ensure_loaded(table_layout_generator).
:- ensure_loaded(parse_constraints).
:- ensure_loaded(table_annotator).

test_table_parser(File, Files) :-
    atomic_list_concat([File, '.tables'], OutDir),
    test_table_parser(File, OutDir, Files).

test_table_parser(File, OutDir, Files) :-
    driver_tables(File, Tables),
    (   Tables == []
    ->  throw(error(no_tables_found(File),
                    context(test_table_parser/3, 'The file contains no <table>')))
    ;   true
    ),
    prepare_output_directory(OutDir),
    write_tables(Tables, 0, OutDir, FileLists),
    append(FileLists, Files).

% --- input -----------------------------------------------------------------

driver_tables(File, Tables) :-
    read_file_to_string(File, Text, [encoding(utf8)]),
    (   file_name_extension(_, Extension, File),
        memberchk(Extension, [xml, nxml])
    ->  parse_jats_xml(Text, Dom)
    ;   parse_html(Text, Dom)
    ),
    extract_tables(Dom, Tables).

% --- output ----------------------------------------------------------------

prepare_output_directory(OutDir) :-
    make_directory_path(OutDir),
    directory_files(OutDir, Entries),
    forall(( member(Entry, Entries),
             wildcard_match('table*.html', Entry) ),
           ( directory_file_path(OutDir, Entry, Old),
             (   exists_file(Old) -> delete_file(Old) ; true ) )).

% Plain recursion, not findall/3: a failing or throwing table must stop the
% run instead of being silently skipped.
write_tables([], _, _, []).
write_tables([Table|Tables], N, OutDir, [Written|More]) :-
    write_table_views(Table, N, OutDir, Written),
    N1 is N + 1,
    write_tables(Tables, N1, OutDir, More).

write_table_views(Table, N, OutDir, Written) :-
    rasterize_table(Table, Raster),
    valid_boundaries(Raster, Boundaries),
    (   Boundaries == []
    ->  safe_table_dom(Table, Safe),
        table_html(Safe, Html),
        format(atom(Name), 'table~d_unannotated.html', [N]),
        format(atom(Title), 'table ~d: no admissible boundary', [N]),
        write_view(OutDir, Name, Title, Html, Path),
        Written = [Path]
    ;   write_candidates(Boundaries, Table, Raster, N, OutDir, Written)
    ).

write_candidates([], _, _, _, _, []).
write_candidates([json{hmd:Hmd, vmd:Vmd}|Boundaries], Table, Raster, N, OutDir,
                 [Path|Paths]) :-
    % annotate_table_element_raster/5 sanitizes the source before coloring.
    annotate_table_element_raster(Hmd, Vmd, Table, Raster, Annotated),
    table_html(Annotated, Html),
    format(atom(Name), 'table~d_hmd~d_vmd~d.html', [N, Hmd, Vmd]),
    format(atom(Title), 'table ~d: hmd ~d, vmd ~d (structural hypothesis)',
           [N, Hmd, Vmd]),
    write_view(OutDir, Name, Title, Html, Path),
    write_candidates(Boundaries, Table, Raster, N, OutDir, Paths).

% The charset declaration keeps non-ASCII text intact when a browser opens
% the fragment. Title is generated here from integers only.
write_view(OutDir, Name, Title, Html, Path) :-
    directory_file_path(OutDir, Name, Path),
    setup_call_cleanup(
        open(Path, write, Out, [encoding(utf8)]),
        format(Out, '<!DOCTYPE html>~n<meta charset="utf-8">~n<title>~w</title>~n~w~n',
               [Title, Html]),
        close(Out)).
