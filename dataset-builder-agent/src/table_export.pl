% Export of reviewed tables as structured JSON.
%
% The last stage of the pipeline, run after the LLM review
% (review_dataset.dml). For each paper with a current review.jsonl it writes
% papers/PMC<id>/final_tables.json, with one entry per line of tables.jsonl.
% A table the review found "valid" is exported at the boundary (Hmd, Vmd)
% the parser and the LLM agreed on, as "subtables": a list of subtables, in
% the schema of example_table.json:
%
%   {"horizontal metadata": Forest, "vertical metadata": Forest,
%    "data": Grid, "residual_corner": Forest}
%
% A forest is a list of nodes, and a node is an object with a single key,
% the cell's text, whose value is the list of the cell's children:
% {"HMD 0": [{"HMD 1": []}, {"HMD 1": []}]}. Children are in reading order.
%
%   horizontal metadata  rows 0..Hmd-1 over the data columns (Vmd..). Roots
%                        are the cells in the first row; a cell's children
%                        are the cells directly below it. The leaves, left to
%                        right, head the data columns.
%   vertical metadata    columns 0..Vmd-1 over the data rows (Hmd..), read
%                        left to right: roots are the cells in the first
%                        column, children are the cells directly to the right.
%                        The leaves, top to bottom, head the data rows.
%   data                 rows Hmd.., columns Vmd..: a list of rows of cell
%                        texts. A merged cell is unmerged: its text is
%                        repeated in every slot it covers. Slots that pad
%                        short rows are null.
%   residual_corner      rows 0..Hmd-1, columns 0..Vmd-1 (the labels above
%                        the VMD), as a forest read top to bottom like the
%                        horizontal metadata; [] without HMD rows or VMD
%                        columns.
%
% A cell over both the corner and the data columns (a title row, say)
% appears in both residual_corner and the horizontal metadata. A padding cell
% in a metadata region has the empty text "" as its key.
%
% A plain (Hmd, Vmd) candidate is one subtable. A layout candidate (rows set
% aside, or metadata in the middle of the table) gives one subtable per
% subtable of the layout, and "separators" lists the rows it sets aside with
% their text; it is [] for a plain candidate. The review only selects
% layouts of one subtable for now, so a valid table has one subtable. Every other table (unparseable,
% unreviewed, no candidates) keeps its entry, with its final_status and
% "subtables": null, so table_index still lines up with tables.jsonl and
% review.jsonl.
%
%   export_reviewed_papers(+DatasetDir, +Settings, -Lines)
%   export_paper(+PapersDir, +Name, -Line)
%   table_structure(+Record, +Hmd, +Vmd, -Subtable)

:- module(table_export, [
      export_reviewed_papers/3,
      export_paper/3,
      table_structure/4
   ]).

:- if(exists_source(library(json))).
:- use_module(library(json)).
:- else.
:- use_module(library(http/json)).
:- endif.
:- use_module(library(readutil)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(pairs)).
:- use_module(library(assoc)).
:- use_module(provenance_manifest).

% --- papers ------------------------------------------------------------------

% export_reviewed_papers(+DatasetDir, +Settings, -Lines)
% Exports every published paper (or those in Settings.papers, as built by
% review_settings/5) and gives one status line per paper, in name order.
export_reviewed_papers(DatasetDir, Settings, Lines) :-
   directory_file_path(DatasetDir, papers, PapersDir),
   (  exists_directory(PapersDir)
   -> directory_files(PapersDir, Entries)
   ;  Entries = [] ),
   include(paper_entry, Entries, PaperEntries),
   maplist(atom_string, PaperEntries, Names0),
   msort(Names0, Names1),
   (  Settings.papers == all
   -> Names = Names1
   ;  Wanted = Settings.papers,
      findall(N, ( member(N, Names1), memberchk(N, Wanted) ), Names) ),
   maplist(export_paper(PapersDir), Names, Lines).

paper_entry(Entry) :-
   atom(Entry),
   sub_atom(Entry, 0, 3, _, 'PMC'),
   \+ sub_atom(Entry, _, _, _, '.').

% export_paper(+PapersDir, +Name, -Line)
% Writes papers/Name/final_tables.json under the paper's publication lock,
% via a temporary file and a rename. A paper without a review, or whose
% review does not match the current tables.jsonl, is left alone.
export_paper(PapersDir, Name, Line) :-
   directory_file_path(PapersDir, Name, PaperDir),
   format(string(LockName), ".~s.lock", [Name]),
   directory_file_path(PapersDir, LockName, LockDir),
   (  catch(make_directory(LockDir), _, fail)
   -> setup_call_cleanup(
         true,
         export_locked_paper(PaperDir, Name, Line),
         delete_directory(LockDir))
   ;  format(string(Line), "~s: not exported (being published by another run)", [Name])
   ).

export_locked_paper(PaperDir, Name, Line) :-
   directory_file_path(PaperDir, 'tables.jsonl', TablesFile),
   directory_file_path(PaperDir, 'review.jsonl', ReviewFile),
   (  \+ exists_file(TablesFile)
   -> format(string(Line), "~s: not exported (no tables.jsonl)", [Name])
   ;  \+ exists_file(ReviewFile)
   -> format(string(Line), "~s: not exported (not reviewed yet)", [Name])
   ;  file_sha256(TablesFile, Hash), atom_string(Hash, Sha),
      read_jsonl(TablesFile, Records),
      read_jsonl(ReviewFile, Reviews),
      (  \+ count_schema(Records)
      -> format(string(Line),
                "~s: not exported (tables.jsonl uses the old last-index boundaries, schema 1.x; rebuild the paper)",
                [Name])
      ;  current_reviews(Records, Reviews, Sha)
      -> maplist(export_table, Records, Reviews, Tables),
         Json = json{schema_version:"1.0", pmc_id:Name,
                     tables_jsonl_sha256:Sha, tables:Tables},
         write_json_atomically(PaperDir, 'final_tables.json', Json),
         % No lambda: DeepClause's engine mishandles them (see table_review.pl).
         include(exported_entry, Tables, Exported),
         length(Tables, NumTables), length(Exported, NumExported),
         format(string(Line),
                "~s: ~d of ~d table(s) exported -> papers/~s/final_tables.json",
                [Name, NumExported, NumTables, Name])
      ;  format(string(Line),
                "~s: not exported (review.jsonl does not match tables.jsonl; review again)",
                [Name])
      )
   ).

exported_entry(Entry) :-
   Entry.final_status == "valid",
   Entry.export_error == null.

% Schema 2.x and 3.x give hmd and vmd as counts, which the export relies on.
% Schema 1.x gave the last HMD row and VMD column instead.
count_schema(Records) :-
   forall(member(R, Records),
          ( get_dict(schema_version, R, V0), text_to_string(V0, V),
            ( sub_string(V, 0, 2, _, "2.") ; sub_string(V, 0, 2, _, "3.") ) )).

% One review per table, in order, all made from this tables.jsonl.
current_reviews(Records, Reviews, Sha) :-
   length(Records, N), length(Reviews, N),
   maplist(review_of_record(Sha), Records, Reviews).

review_of_record(Sha, Record, Review) :-
   get_dict(table_uid, Review, Uid), Uid == Record.table_uid,
   get_dict(tables_jsonl_sha256, Review, ReviewSha), ReviewSha == Sha.

write_json_atomically(Dir, Name, Json) :-
   get_time(Now), Stamp is floor(Now * 1000000),
   format(atom(TempName), ".~w.~d.tmp", [Name, Stamp]),
   directory_file_path(Dir, TempName, Temp),
   directory_file_path(Dir, Name, File),
   catch(( setup_call_cleanup(
              open(Temp, write, Out, [encoding(utf8)]),
              ( json_write_dict(Out, Json, [width(100)]), nl(Out) ),
              close(Out)),
           rename_file(Temp, File) ),
         Error,
         ( ( exists_file(Temp) -> delete_file(Temp) ; true ),
           throw(Error) )).

% --- tables ------------------------------------------------------------------

% export_table(+Record, +Review, -Entry): Record is a tables.jsonl record,
% Review its review.jsonl record.
export_table(Record, Review, Entry) :-
   Context = Record.context,
   ( get_dict(label, Context, Label) -> true ; Label = null ),
   ( get_dict(caption, Context, Caption) -> true ; Caption = null ),
   Base = json{table_uid:Record.table_uid, table_index:Record.table_index,
               label:Label, caption:Caption,
               final_status:Review.final_status},
   Empty = json{candidate_id:null, boundary:null, geometric_certificate:null,
                export_error:null, subtables:null, separators:null},
   (  Review.final_status == "valid",
      Id = Review.selected_candidate_id,
      member(Candidate, Record.candidates),
      Candidate.candidate_id == Id
   -> Hmd = Candidate.hmd, Vmd = Candidate.vmd,
      ( get_dict(geometric_certificate, Candidate, Certificate) -> true
      ; Certificate = null ),
      Selected = json{candidate_id:Id, boundary:json{hmd:Hmd, vmd:Vmd},
                      geometric_certificate:Certificate},
      (  catch(candidate_structures(Record, Candidate, Structures, Separators),
              export_error(Why), true)
      -> true
      ;  Why = structure_not_built
      ),
      (  var(Why)
      -> put_dict(json{subtables:Structures, separators:Separators}, Selected,
                  Exported)
      ;  format(string(WhyText), "~q", [Why]),
         put_dict(export_error, Selected, WhyText, Exported)
      ),
      put_dict(Exported, Empty, Fields)
   ;  Review.final_status == "valid"
   -> format(string(WhyText), "~q",
             [unknown_candidate(Review.selected_candidate_id)]),
      put_dict(export_error, Empty, WhyText, Fields)
   ;  Fields = Empty
   ),
   put_dict(Fields, Base, Entry).

% candidate_structures(+Record, +Candidate, -Subtables, -Separators)
% A plain candidate is one subtable, the whole table at its boundary. A
% layout candidate (kind "layout") has a subtable for each of its subtables,
% each built from the slots at its rows and columns as a table of its own,
% and Separators gives the rows it sets aside as {row, text}, text being the
% texts of the row's cells, joined by " | ".
candidate_structures(Record, Candidate, Subtables, Separators) :-
   (  get_dict(kind, Candidate, "layout")
   -> maplist(subtable_structure(Record), Candidate.subtables, Subtables),
      cell_texts(Record.cells, Texts),
      maplist(separator_entry(Record.raster, Texts), Candidate.separators, Separators)
   ;  table_structure(Record, Candidate.hmd, Candidate.vmd, Structure),
      Subtables = [Structure],
      Separators = []
   ).

subtable_structure(Record, Sub, Structure) :-
   findall(Row,
           ( member(R, Sub.rows), nth0(R, Record.raster, Full),
             findall(Id, ( member(C, Sub.columns), nth0(C, Full, Id) ), Row) ),
           View),
   put_dict(raster, Record, View, SubRecord),
   table_structure(SubRecord, Sub.hmd, Sub.vmd, Structure).

separator_entry(Raster, Texts, Separator, json{row:R, text:Text}) :-
   R = Separator.row,
   nth0(R, Raster, Full),
   findall(Id, ( member(C, Separator.columns), nth0(C, Full, Id) ), Ids0),
   list_to_set(Ids0, Ids),
   findall(T, ( member(Id, Ids), get_assoc(Id, Texts, T), T \== null, T \== "" ), Parts),
   atomics_to_string(Parts, " | ", Text).

% table_structure(+Record, +Hmd, +Vmd, -Subtable)
% Subtable is the one subtable of the table at the boundary (Hmd, Vmd), as a
% json([...]) term so that its keys are written in the order of the schema.
% Throws export_error(Why) if a metadata cell does not sit under (or right
% of) exactly one parent cell, so that the metadata is not a forest.
table_structure(Record, Hmd, Vmd,
                json(['horizontal metadata'=HmdForest,
                      'vertical metadata'=VmdForest,
                      data=Data,
                      residual_corner=Corner])) :-
   Raster = Record.raster,
   cell_texts(Record.cells, Texts),
   length(Raster, Rows),
   Raster = [First|_], length(First, Cols),
   (  between(0, Rows, Hmd), Hmd < Rows, between(0, Cols, Vmd), Vmd < Cols
   -> true
   ;  throw(export_error(boundary_out_of_range(Hmd, Vmd)))
   ),
   region_texts(Raster, Texts, Hmd, Rows, Vmd, Cols, Data),
   header_forest(Raster, Texts, Hmd, Vmd, Cols, HmdForest),
   transpose_rows(Raster, Transposed),
   header_forest(Transposed, Texts, Vmd, Hmd, Rows, VmdForest),
   (  Vmd =:= 0
   -> Corner = []
   ;  header_forest(Raster, Texts, Hmd, 0, Vmd, Corner)
   ).

% Cell id -> text; a synthetic gap (padding) cell has no text: null.
cell_texts(Cells, Texts) :-
   findall(Id-Text,
           ( member(Cell, Cells), Id = Cell.cell_id,
             ( Cell.kind == "synthetic_gap" -> Text = null ; Text = Cell.text ) ),
           Pairs),
   list_to_assoc(Pairs, Texts).

% region_texts(+Raster, +Texts, +Row0, +RowEnd, +Col0, +ColEnd, -Grid)
% The texts of rows Row0..RowEnd-1 and columns Col0..ColEnd-1, slot by slot.
region_texts(Raster, Texts, Row0, RowEnd, Col0, ColEnd, Grid) :-
   LastRow is RowEnd - 1, LastCol is ColEnd - 1,
   findall(Line,
           ( between(Row0, LastRow, I), nth0(I, Raster, Row),
             findall(Text,
                     ( between(Col0, LastCol, J), nth0(J, Row, Id),
                       get_assoc(Id, Texts, Text) ),
                     Line) ),
           Grid).

% header_forest(+Raster, +Texts, +Hmd, +Col0, +ColEnd, -Roots)
% The cells of rows 0..Hmd-1 over columns Col0..ColEnd-1, as a forest. Each
% cell's parent is the cell above its top row, which must be the same cell
% all along the cell's columns.
header_forest(_, _, 0, _, _, []) :- !.
header_forest(Raster, Texts, Hmd, Col0, ColEnd, Roots) :-
   length(Header, Hmd),
   append(Header, _, Raster),
   findall(Id-(I-J),
           ( nth0(I, Header, Row), nth0(J, Row, Id), J >= Col0, J < ColEnd ),
           Slots),
   keysort(Slots, Sorted),
   group_pairs_by_key(Sorted, Cells),
   maplist(header_node(Header), Cells, Nodes),
   forest_children(root, Nodes, Texts, Roots).

% node(Id, Parent, First, Last)
header_node(Header, Id-Coords, node(Id, Parent, First, Last)) :-
   pairs_keys_values(Coords, Is, Js),
   min_list(Is, Top),
   min_list(Js, First), max_list(Js, Last),
   (  Top =:= 0
   -> Parent = root
   ;  Above is Top - 1,
      nth0(Above, Header, Row),
      findall(P, ( between(First, Last, J), nth0(J, Row, P) ), Ps0),
      sort(Ps0, Ps),
      (  Ps = [Parent]
      -> true
      ;  throw(export_error(cell_has_several_parents(Id, Ps)))
      )
   ).

forest_children(Parent, Nodes, Texts, Children) :-
   findall(First-node(Id, Parent, First, Last),
           member(node(Id, Parent, First, Last), Nodes),
           Keyed),
   keysort(Keyed, Ordered),
   pairs_values(Ordered, Mine),
   maplist(forest_node(Nodes, Texts), Mine, Children).

% {"<text>": [children]}; a padding cell has the empty text.
forest_node(Nodes, Texts, node(Id, _, _, _), json([Key=Children])) :-
   get_assoc(Id, Texts, Text),
   (  Text == null
   -> Key = ''
   ;  atom_string(Key, Text)
   ),
   forest_children(Id, Nodes, Texts, Children).

% --- helpers -----------------------------------------------------------------

transpose_rows([], []).
transpose_rows([Row|Rows], Columns) :-
   transpose_rows(Row, [Row|Rows], Columns).

transpose_rows([], _, []).
transpose_rows([_|More], Rows, [Column|Columns]) :-
   maplist(split_head, Rows, Column, Rests),
   transpose_rows(More, Rests, Columns).

split_head([Head|Tail], Head, Tail).

read_jsonl(File, Records) :-
   setup_call_cleanup(
      open(File, read, Stream, [encoding(utf8)]),
      read_jsonl_stream(Stream, Records),
      close(Stream)).

read_jsonl_stream(Stream, Records) :-
   read_line_to_string(Stream, Line),
   (  Line == end_of_file
   -> Records = []
   ;  Line == ""
   -> read_jsonl_stream(Stream, Records)
   ;  atom_json_dict(Line, Record, [default_tag(json)]),
      Records = [Record|Rest],
      read_jsonl_stream(Stream, Rest)
   ).
