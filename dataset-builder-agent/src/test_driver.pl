:- use_module(library(sgml)).
:- use_module(library(readutil)).

:- consult(table_layout_generator).
:- consult(parse_constraints).
:- consult(table_annotator).

% table_file_name(+HtmlFile, +N, -TableFile): tableN.pl, in the directory of
% HtmlFile.
table_file_name(HtmlFile, N, TableFile) :-
   file_directory_name(HtmlFile, Directory),
   format(string(Name), "table~w.pl", [N]),
   directory_file_path(Directory, Name, TableFile).

% test_table_parser(+HtmlFile, -TableFiles)
% Writes one file per table of HtmlFile, numbered from 0 in document order,
% and returns their names. Each file holds the table colored once for every
% layout table_layouts/2 finds; a table with no layout is saved uncolored.
test_table_parser(HtmlFile, TableFiles) :-
   read_file_to_string(HtmlFile, Content, [encoding(utf8)]),
   html_rasters(Content, Tables, Rasters),
   findall(
      TableFile,
      ( nth0(N, Tables, Table),
        nth0(N, Rasters, Raster),
        table_file_name(HtmlFile, N, TableFile),
        save_table(TableFile, Table, Raster) ),
      TableFiles
   ).

save_table(TableFile, Table, Raster) :-
   table_layouts(Raster, Layouts),
   table_annotations(Table, Layouts, Annotations),
   setup_call_cleanup(
      open(TableFile, write, Stream, [encoding(utf8)]),
      forall(member(Annotation, Annotations),
             ( write(Stream, Annotation), nl(Stream) )),
      close(Stream)).

table_annotations(Table, [], [Html]) :- !,
   table_html(Table, Html).
table_annotations(Table, Layouts, Annotations) :-
   findall(
      Annotation,
      ( member(Layout, Layouts),
        annotate_layout_element(Layout, Table, Annotated),
        table_html(Annotated, Annotation) ),
      Annotations
   ).
