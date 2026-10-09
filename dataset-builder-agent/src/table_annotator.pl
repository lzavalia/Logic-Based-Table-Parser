% Table annotator.
%
% Colors the cells of a table according to a partition of its raster into
% horizontal metadata (HMD), vertical metadata (VMD) and data, as given by the
% boundaries that parse_constraints.pl validates:
%
%   rows =< Hmd                       horizontal metadata   springgreen
%   rows >  Hmd and columns =< Vmd    vertical metadata     skyblue
%   everything else                   data                  lightgray
%
% A cell's row and column are those of its top-left slot in the raster built
% by table_layout_generator.pl, so merged cells and <thead>/<tfoot> ordering
% are handled exactly as they are during rasterization.
%
% Example:
%   ?- annotate_table(0, 0, "<table><tr><th>k</th><th>v</th></tr>
%                                   <tr><td>a</td><td>1</td></tr></table>", A).
%   A = "<table><tr><th style=\"background-color: springgreen\">k</th>...".
%
% Requires table_layout_generator.pl to be loaded.

:- use_module(library(sgml_write)).
:- use_module(library(assoc)).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- consult(table_html_sanitizer).

region_color(hmd,  springgreen).
region_color(vmd,  skyblue).
region_color(data, lightgray).

% annotate_table(+Hmd, +Vmd, +HtmlTable, -AnnotatedTable)
% HtmlTable is HTML text holding a table; AnnotatedTable is the same table as
% a string, with a background color on every cell. If the text holds several
% tables, the first one in document order is annotated.
annotate_table(Hmd, Vmd, HtmlTable, AnnotatedTable) :-
   parse_html(HtmlTable, Dom),
   extract_tables(Dom, [Table|_]),
   annotate_table_element(Hmd, Vmd, Table, Annotated),
   table_html(Annotated, AnnotatedTable).

% annotate_table_element(+Hmd, +Vmd, +Table, -Annotated)
% Same as annotate_table/4, on a parsed element(table, Attrs, Children) term.
annotate_table_element(Hmd, Vmd, Table, Annotated) :-
   rasterize_table(Table, Raster),
   annotate_table_element_raster(Hmd, Vmd, Table, Raster, Annotated).

% Reuse the already-validated raster when producing several HTML views of
% the same table. The source raster is identical to the one checked by the
% structural solver; no per-candidate rasterization or span allocation.
% Public annotation entry points always sanitize the source before emitting
% a browser-facing DOM. Pipeline code can use the precleaned helper to avoid
% repeating the walk for every boundary of an ambiguous table.
annotate_table_element_raster(Hmd, Vmd, Table, Raster, Annotated) :-
   safe_table_dom(Table, CleanTable),
   annotate_precleaned_table_raster(Hmd, Vmd, CleanTable, Raster, Annotated).

annotate_precleaned_table_raster(Hmd, Vmd, element(table, Attrs, Children),
                                Raster, element(table, Attrs, NewChildren)) :-
   cell_colors(Raster, Hmd, Vmd, Colors),
   first_cell_ids(Children, Ids0),
   annotate_children(Children, Colors, Ids0, _, NewChildren).

% table_html(+Element, -Html): Element serialized as an HTML string.
table_html(Element, Html) :-
   with_output_to(
      string(Html),
      html_write(current_output, Element, [header(false), layout(false)])
   ).

% --- 1) cell id -> color ---------------------------------------------------

% cell_colors(+Raster, +Hmd, +Vmd, -Colors): Colors is an assoc from cell id
% to color. Slots are visited in row-major order, so the first slot seen for
% an id is the top-left slot of that cell.
cell_colors(Raster, Hmd, Vmd, Colors) :-
   empty_assoc(Colors0),
   foldl(row_colors(Hmd, Vmd), Raster, 0-Colors0, _-Colors).

row_colors(Hmd, Vmd, Row, R-Colors0, R1-Colors) :-
   foldl(slot_color(Hmd, Vmd, R), Row, 0-Colors0, _-Colors),
   R1 is R + 1.

slot_color(Hmd, Vmd, R, Id, C-Colors0, C1-Colors) :-
   (  get_assoc(Id, Colors0, _)
   -> Colors = Colors0
   ;  slot_region(Hmd, Vmd, R, C, Region),
      region_color(Region, Color),
      put_assoc(Id, Colors0, Color, Colors)
   ),
   C1 is C + 1.

slot_region(Hmd, Vmd, R, C, Region) :-
   (  R =< Hmd -> Region = hmd
   ;  C =< Vmd -> Region = vmd
   ;  Region = data
   ).

% --- 2) cell numbering -----------------------------------------------------

% The rasterizer numbers cells section by section: every <thead>, then the
% body (<tbody> elements and <tr> written directly under <table>), then every
% <tfoot>. first_cell_ids/2 gives the first id of each of the three groups as
% ids(Head, Body, Foot), so the table can be walked in document order.
first_cell_ids(Children, ids(0, Body, Foot)) :-
   foldl(count_cells, Children, 0-0, HeadCells-BodyCells),
   Body = HeadCells,
   Foot is HeadCells + BodyCells.

count_cells(Child, Head0-Body0, Head-Body) :-
   (  is_element(thead, Child)
   -> section_cell_count(Child, N),
      Head is Head0 + N, Body = Body0
   ;  is_element(tbody, Child)
   -> section_cell_count(Child, N),
      Head = Head0, Body is Body0 + N
   ;  is_element(tr, Child)
   -> row_cell_count(Child, N),
      Head = Head0, Body is Body0 + N
   ;  Head = Head0, Body = Body0
   ).

section_cell_count(Section, Count) :-
   section_rows(Section, Rows),
   foldl([Row, N0, N]>>(row_cell_count(Row, K), N is N0 + K), Rows, 0, Count).

row_cell_count(Row, Count) :-
   row_cells(Row, Cells),
   length(Cells, Count).

% --- 3) rewriting the table ------------------------------------------------

% annotate_children(+Children, +Colors, +Ids0, -Ids, -NewChildren)
% Children are the direct children of <table>. Anything that is not a
% section or a row (caption, colgroup, text, ...) is copied unchanged.
annotate_children([], _, Ids, Ids, []).
annotate_children([Child|Children], Colors, Ids0, Ids, [NewChild|NewChildren]) :-
   annotate_child(Child, Colors, Ids0, Ids1, NewChild),
   annotate_children(Children, Colors, Ids1, Ids, NewChildren).

annotate_child(Child, Colors, ids(H0, B0, F0), Ids, NewChild) :-
   (  is_element(thead, Child)
   -> annotate_section(Child, Colors, H0, H, NewChild),
      Ids = ids(H, B0, F0)
   ;  is_element(tbody, Child)
   -> annotate_section(Child, Colors, B0, B, NewChild),
      Ids = ids(H0, B, F0)
   ;  is_element(tfoot, Child)
   -> annotate_section(Child, Colors, F0, F, NewChild),
      Ids = ids(H0, B0, F)
   ;  is_element(tr, Child)
   -> annotate_row(Child, Colors, B0, B, NewChild),
      Ids = ids(H0, B, F0)
   ;  NewChild = Child,
      Ids = ids(H0, B0, F0)
   ).

annotate_section(element(Name, Attrs, Children), Colors, Id0, Id,
                 element(Name, Attrs, NewChildren)) :-
   foldl(annotate_section_child(Colors), Children, NewChildren, Id0, Id).

annotate_section_child(Colors, Child, NewChild, Id0, Id) :-
   (  is_element(tr, Child)
   -> annotate_row(Child, Colors, Id0, Id, NewChild)
   ;  NewChild = Child,
      Id = Id0
   ).

annotate_row(element(tr, Attrs, Children), Colors, Id0, Id,
             element(tr, Attrs, NewChildren)) :-
   foldl(annotate_row_child(Colors), Children, NewChildren, Id0, Id).

annotate_row_child(Colors, Child, NewChild, Id0, Id) :-
   (  is_cell(Child)
   -> color_cell(Child, Colors, Id0, NewChild),
      Id is Id0 + 1
   ;  NewChild = Child,
      Id = Id0
   ).

% Every visible DOM cell needs a source raster slot. Do not leave cells
% uncolored if an inconsistent raster is passed to this public entry point.
color_cell(element(Name, Attrs, Children), Colors, Id, element(Name, NewAttrs, Children)) :-
   (  get_assoc(Id, Colors, Color)
   -> set_background(Color, Attrs, NewAttrs)
   ;  throw(error(table_layout_error(unmapped_annotation_cell(Id)),
                  context(annotate_table_element_raster/5,
                          'DOM cell has no raster slot for annotation')))
   ).

% The color is appended to any existing style, so it wins over an earlier
% background declaration and over a bgcolor attribute.
set_background(Color, Attrs, NewAttrs) :-
   (  selectchk(style = Style, Attrs, Rest)
   -> format(atom(NewStyle), '~w; background-color: ~w', [Style, Color]),
      NewAttrs = [style = NewStyle|Rest]
   ;  format(atom(NewStyle), 'background-color: ~w', [Color]),
      append(Attrs, [style = NewStyle], NewAttrs)
   ).
