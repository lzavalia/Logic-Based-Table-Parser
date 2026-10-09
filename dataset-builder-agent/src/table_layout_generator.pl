% Table rasterizer.
%
% Turns every <table> in an HTML string into a "raster": a list of rows,
% all of the same length, where each element is the integer id of the cell
% covering that grid slot. Cells are numbered from 0 in document order, and
% colspan/rowspan make a cell's id cover a rectangular region of the raster.
%
% Example:
%   ?- html_rasters("<table><tr><td colspan=2>a</td></tr>
%                           <tr><td>b</td><td>c</td></tr></table>", Rs).
%   Rs = [[[0,0],[1,2]]].

:- use_module(library(sgml)).
:- use_module(library(assoc)).
:- use_module(library(apply)).
:- use_module(library(lists)).

% html_rasters(+Html, -Rasters): one raster per <table> in Html, in document
% order (an outer table comes before any table nested inside it).
html_rasters(Html, Rasters) :-
   parse_html(Html, Dom),
   extract_tables(Dom, Tables),
   maplist(rasterize_table, Tables, Rasters).

html_rasters(Html, Tables, Rasters) :-
   parse_html(Html, Dom),
   extract_tables(Dom, Tables),
   maplist(rasterize_table, Tables, Rasters).

% --- 1) parsing ------------------------------------------------------------

% max_errors(-1): real web pages have far more than the parser's default
% limit of 50 syntax errors, which would otherwise abort the parse.
parse_html(Html, Dom) :-
   text_to_string(Html, String),
   load_structure(
      string(String),
      Dom,
      [dialect(html), space(remove), syntax_errors(quiet), max_errors(-1)]
   ).

% PMC eFetch returns JATS XML, *not HTML*.  The XML entry point is
% intentionally separate from parse_html/2: callers accepting loose HTML
% may use HTML recovery, but a PMC article must not silently be repaired.
% syntax_errors(error) is not an option of SWI's SGML library; use its
% error callback instead, which can interrupt parsing even for warnings.
parse_jats_xml(Xml, Dom) :-
   text_to_string(Xml, String),
   load_structure(
      string(String), Raw,
      [dialect(xml), space(remove), syntax_errors(quiet),
       call(error, jats_parse_diagnostic)]
   ),
   normalize_jats_dom(Raw, Dom).

jats_parse_diagnostic(Severity, Message, Parser) :-
   ( get_sgml_parser(Parser, line(Line)) -> true ; Line = unknown ),
   throw(error(invalid_jats_xml(Severity, Line, Message),
               context(parse_jats_xml/2, 'JATS XML parsing reported a diagnostic'))).

% In a JATS document, qualified names such as jats:table mean the same
% table layout element as the unqualified name.  Keep all attributes and
% text intact, but normalize element names for the existing table IR.
normalize_jats_dom([], []).
normalize_jats_dom([Node|Nodes], [Normalized|More]) :-
   normalize_jats_node(Node, Normalized),
   normalize_jats_dom(Nodes, More).

normalize_jats_node(element(Name, Attrs, Children),
                    element(Local, Attrs, NewChildren)) :- !,
   ( atom(Name), sub_atom(Name, _, 1, After, ':')
   -> sub_atom(Name, _, After, 0, Local)
   ;  Local = Name ),
   normalize_jats_dom(Children, NewChildren).
normalize_jats_node(Node, Node).

% --- 2) table extraction ---------------------------------------------------

extract_tables(Dom, Tables) :-
   findall(Table, (member(Node, Dom), sub_table(Node, Table)), Tables).

sub_table(Table, Table) :-
   Table = element(table, _, _).
sub_table(element(_, _, Children), Table) :-
   member(Child, Children),
   sub_table(Child, Table).

% --- 3) rasterization ------------------------------------------------------

% These limits apply to untrusted <td>/<th> spans BEFORE any rectangle or
% dense raster is allocated. Change them together with the per-paper limits
% in dataset_pipeline.pl when processing unusually large trusted tables.
% max_claims also limits work spent on overlapping (malformed) cell spans.
table_raster_limit(max_rows,     1000).
table_raster_limit(max_columns,   256).
table_raster_limit(max_colspan,   256).
table_raster_limit(max_cells,   10000).
table_raster_limit(max_claims, 100000).
table_raster_limit(max_slots,  100000).
table_raster_limit(max_span_chars, 32).

ensure_table_limit(Name, Actual) :-
   table_raster_limit(Name, Maximum),
   (  Actual =< Maximum -> true
   ;  throw(error(table_raster_limit_exceeded(Name, Maximum, Actual),
                  context(rasterize_table/2, 'Untrusted table exceeds raster limits')))
   ).

% Preflight checks all spans and caps the total number of attempted slot
% claims, including collisions. It does NOT build a list of raster slots.
% This is important even when an attacker uses thousands of modest spans.
preflight_sections(Sections, Height) :-
   preflight_sections(Sections, 0, 0, 0, Height, _, _).

preflight_sections([], Height, Cells, Claims, Height, Cells, Claims).
preflight_sections([Rows|Sections], H0, C0, S0, Height, Cells, Claims) :-
   length(Rows, SectionHeight),
   H1 is H0 + SectionHeight,
   ensure_table_limit(max_rows, H1),
   preflight_rows(Rows, 0, SectionHeight, C0, S0, C1, S1),
   preflight_sections(Sections, H1, C1, S1, Height, Cells, Claims).

preflight_rows([], _, _, Cells, Claims, Cells, Claims).
preflight_rows([Row|Rows], I, SectionHeight, C0, S0, Cells, Claims) :-
   row_cells(Row, RowCells),
   preflight_cells(RowCells, I, SectionHeight, C0, S0, C1, S1),
   Next is I + 1,
   preflight_rows(Rows, Next, SectionHeight, C1, S1, Cells, Claims).

preflight_cells([], _, _, Cells, Claims, Cells, Claims).
preflight_cells([Cell|Rest], I, SectionHeight, C0, S0, Cells, Claims) :-
   C1 is C0 + 1,
   ensure_table_limit(max_cells, C1),
   cell_spans(Cell, I, SectionHeight, ColSpan, RowSpan),
   ensure_table_limit(max_colspan, ColSpan),
   S1 is S0 + ColSpan * RowSpan,
   ensure_table_limit(max_claims, S1),
   preflight_cells(Rest, I, SectionHeight, C1, S1, Cells, Claims).

% rasterize_table(+TableElement, -Raster)
rasterize_table(Table, Raster) :-
   table_sections(Table, Sections),
   preflight_sections(Sections, Height),
   empty_assoc(Grid0),
   place_sections(Sections, 0, 0, Grid0, NumCells, Height, Grid),
   grid_width(Grid, Width),
   ensure_table_limit(max_columns, Width),
   % A source table without any cells cannot yield a meaningful raster.
   % Verify every numbered DOM cell owns a slot before padding short rows.
   verify_source_cell_coverage(Grid, NumCells),
   Slots is Height * Width,
   ensure_table_limit(max_slots, Slots),
   build_raster(Grid, Height, Width, NumCells, Raster).

% table_sections(+Table, -Sections): each section is a list of <tr>
% elements. Header rows come first, then body rows, then footer rows
% (the order a browser renders them in). Rowspans never cross a section.
% Only direct children are inspected, so nested tables are not mixed in.
table_sections(element(table, _, Children), Sections) :-
   include(is_element(thead), Children, Heads),
   include(is_element(tfoot), Children, Foots),
   body_sections(Children, Bodies),
   maplist(section_rows, Heads, HeadSections),
   maplist(section_rows, Foots, FootSections),
   append([HeadSections, Bodies, FootSections], Sections).

% <tbody> elements, plus runs of <tr> written directly under <table>
% (each run acts as an implicit tbody).
body_sections([], []).
body_sections([Child|Children], [Rows|Sections]) :-
   is_element(tbody, Child), !,
   section_rows(Child, Rows),
   body_sections(Children, Sections).
body_sections([Child|Children], [[Child|Trs]|Sections]) :-
   is_element(tr, Child), !,
   take_trs(Children, Trs, Rest),
   body_sections(Rest, Sections).
body_sections([_|Children], Sections) :-
   body_sections(Children, Sections).

take_trs([Child|Children], [Child|Trs], Rest) :-
   is_element(tr, Child), !,
   take_trs(Children, Trs, Rest).
take_trs(Rest, [], Rest).

section_rows(element(_, _, Children), Rows) :-
   include(is_element(tr), Children, Rows).

row_cells(element(tr, _, Children), Cells) :-
   include(is_cell, Children, Cells).

is_element(Name, element(Name, _, _)).

is_cell(element(td, _, _)).
is_cell(element(th, _, _)).

% place_sections(+Sections, +RowOffset, +Id0, +Grid0, -Id, -Height, -Grid)
% Grid is an assoc from Row-Col to the id of the cell occupying that slot.
place_sections([], Height, Id, Grid, Id, Height, Grid).
place_sections([Rows|Sections], Offset, Id0, Grid0, Id, Height, Grid) :-
   length(Rows, NumRows),
   place_rows(Rows, 0, NumRows, Offset, Id0, Grid0, Id1, Grid1),
   Offset1 is Offset + NumRows,
   place_sections(Sections, Offset1, Id1, Grid1, Id, Height, Grid).

% I is the row index within its section, NumRows the section's row count.
place_rows([], _, _, _, Id, Grid, Id, Grid).
place_rows([Tr|Trs], I, NumRows, Offset, Id0, Grid0, Id, Grid) :-
   row_cells(Tr, Cells),
   Row is Offset + I,
   place_cells(Cells, Row, 0, I, NumRows, Id0, Grid0, Id1, Grid1),
   I1 is I + 1,
   place_rows(Trs, I1, NumRows, Offset, Id1, Grid1, Id, Grid).

place_cells([], _, _, _, _, Id, Grid, Id, Grid).
place_cells([Cell|Cells], Row, Col0, I, NumRows, Id0, Grid0, Id, Grid) :-
   cell_spans(Cell, I, NumRows, ColSpan, RowSpan),
   first_free_col(Grid0, Row, Col0, Col),
   EndCol is Col + ColSpan,
   ensure_table_limit(max_columns, EndCol),
   LastRow is Row + RowSpan - 1,
   LastCol is EndCol - 1,
   claim_rectangle(Id0, Row, LastRow, Col, LastCol, Grid0, Grid1),
   Id1 is Id0 + 1,
   Col1 is Col + ColSpan,
   place_cells(Cells, Row, Col1, I, NumRows, Id1, Grid1, Id, Grid).

% Skip slots already covered by a rowspan from an earlier row. Bound the
% search too: a fully occupied row must not scan arbitrary column offsets.
first_free_col(Grid, Row, Col0, Col) :-
   CandidateWidth is Col0 + 1,
   ensure_table_limit(max_columns, CandidateWidth),
   (  get_assoc(Row-Col0, Grid, _)
   -> Col1 is Col0 + 1,
      first_free_col(Grid, Row, Col1, Col)
   ;  Col = Col0
   ).

% Stream rectangle cells directly into the grid; do not allocate a
% findall/3 list of Row-Col pairs (even for a bounded 100,000-slot span).
claim_rectangle(_, R, LastRow, _, _, Grid, Grid) :- R > LastRow, !.
claim_rectangle(Id, R, LastRow, FirstCol, LastCol, Grid0, Grid) :-
   claim_rectangle_row(Id, R, FirstCol, LastCol, Grid0, Grid1),
   NextRow is R + 1,
   claim_rectangle(Id, NextRow, LastRow, FirstCol, LastCol, Grid1, Grid).

claim_rectangle_row(_, _, C, LastCol, Grid, Grid) :- C > LastCol, !.
claim_rectangle_row(Id, R, C, LastCol, Grid0, Grid) :-
   claim_slot(Id, R-C, Grid0, Grid1),
   NextCol is C + 1,
   claim_rectangle_row(Id, R, NextCol, LastCol, Grid1, Grid).

% An overlapping claim is malformed input, not a reason to drop part of a
% cell silently. The caller's staging transaction quarantines the entire
% paper on this typed error and preserves any previously published version.
claim_slot(Id, Row-Col, Grid0, Grid) :-
   (  get_assoc(Row-Col, Grid0, PreviousId)
   -> throw(error(table_layout_error(
                     overlapping_cell_spans(Id, Row, Col, PreviousId)),
                  context(rasterize_table/2,
                          'Two source cells claim the same raster slot')))
   ;  put_assoc(Row-Col, Grid0, Id, Grid)
   ).

% Every source cell must cover at least one grid slot. Synthetic padding
% slots (for ragged but otherwise valid tables) are added only AFTER this
% check and remain explicitly tagged in the JSONL output.
verify_source_cell_coverage(_, 0) :- !,
   throw(error(table_layout_error(empty_table),
               context(rasterize_table/2, 'Table contains no source cells'))).
verify_source_cell_coverage(Grid, NumCells) :-
   assoc_to_values(Grid, Values),
   sort(Values, ObservedIds),
   LastId is NumCells - 1,
   numlist(0, LastId, ExpectedIds),
   (  ExpectedIds == ObservedIds
   -> true
   ;  subtract(ExpectedIds, ObservedIds, MissingIds),
      throw(error(table_layout_error(unmapped_source_cells(MissingIds)),
                  context(rasterize_table/2,
                          'A DOM source cell has no raster slot')))
   ).

% Missing span attributes default to one; malformed explicit attributes
% are errors. rowspan="0" is valid and extends to the end of its section.
% Oversized numeric values retain F04's preallocation limit behavior.
cell_spans(element(_, Attrs, _), I, NumRows, ColSpan, RowSpan) :-
   span_attr(colspan, Attrs, ColSpan),
   span_attr(rowspan, Attrs, R),
   Remaining is NumRows - I,
   (  R =:= 0 -> RowSpan = Remaining
   ;  RowSpan is min(R, Remaining)
   ).

span_attr(Name, Attrs, N) :-
   (  memberchk(Name = Value, Attrs)
   -> (  to_integer(Value, Number), valid_span_number(Name, Number)
      -> N = Number
      ;  throw(error(table_layout_error(invalid_span(Name, Value)),
                     context(rasterize_table/2,
                             'Explicit span must be a valid nonnegative integer')))
      )
   ;  N = 1
   ).

valid_span_number(colspan, Number) :- Number >= 1.
valid_span_number(rowspan, Number) :- Number >= 0.

to_integer(Value, N) :-
   (  integer(Value)
   -> N = Value
   ;  atom(Value)
   -> atom_length(Value, Size),
      ensure_table_limit(max_span_chars, Size),
      catch(atom_number(Value, N), _, fail), integer(N)
   ;  string(Value)
   -> string_length(Value, Size),
      ensure_table_limit(max_span_chars, Size),
      catch(number_string(N, Value), _, fail), integer(N)
   ).

grid_width(Grid, Width) :-
   assoc_to_keys(Grid, Slots),
   foldl([_-C, W0, W]>>(W is max(W0, C + 1)), Slots, 0, Width).

% build_raster(+Grid, +Height, +Width, +NextId, -Raster)
% Slots no cell covers (short rows) each get a fresh id, numbered after the
% real cells in row-major order, so every row has length Width.
build_raster(_, 0, _, _, []) :- !.
build_raster(Grid, Height, Width, NextId, Raster) :-
   LastRow is Height - 1,
   numlist(0, LastRow, Rows),
   foldl(build_row(Grid, Width), Rows, Raster, NextId, _).

build_row(_, 0, _, [], Id, Id) :- !.
build_row(Grid, Width, R, Row, Id0, Id) :-
   LastCol is Width - 1,
   numlist(0, LastCol, Cols),
   foldl(slot_id(Grid, R), Cols, Row, Id0, Id).

slot_id(Grid, R, C, Value, Id0, Id) :-
   (  get_assoc(R-C, Grid, Value)
   -> Id = Id0
   ;  Value = Id0,
      Id is Id0 + 1
   ).
