% Machine-readable, deterministic structural interpretations of JATS tables.
% Consulted in the dataset_pipeline module after the rasterizer/annotator.
% The raster is the source of geometry; HTML colors are never used as labels.
%
% Paths use XPath element-sibling positions (/*[1]/*[2]...), following the
% same element-only numbering as jats_table_records/2. They remain unambiguous
% when attributes/IDs are missing or duplicated, and do not rely on namespaces.
%
% Schema 1.0: one JSON object per table in tables.jsonl. Coordinates and cell
% IDs are zero-based; candidate IDs are stable within a PMC and table index.

machine_table_record(Pmc, Index, Table, Context, Raster, Boundaries,
                     Record, TableMetadata) :-
   format(string(TableUid), '~s/t~d', [Pmc, Index]),
   machine_source_cells(Table, Context, Raster, Cells, FirstSlots),
   maplist(machine_candidate(TableUid, FirstSlots), Boundaries, Candidates),
   length(Candidates, NumCandidates),
   (  NumCandidates =:= 0
   -> Status = "abstained", Abstention = "no_boundary_satisfies_constraints"
   ;  NumCandidates =:= 1
   -> Status = "unique", Abstention = null
   ;  Status = "ambiguous", Abstention = null
   ),
   length(Raster, Rows),
   ( Raster = [FirstRow|_] -> length(FirstRow, Cols) ; Cols = 0 ),
   Record = json{schema_version:"1.0", pmc_id:Pmc, table_index:Index,
                 table_uid:TableUid, source_table_id:Context.table_id,
                 source_path:Context.source_path,
                 source_table_html:Context.source_table_html,
                 context:Context, raster:Raster, rows:Rows, columns:Cols,
                 cells:Cells, candidates:Candidates, status:Status,
                 abstention_reason:Abstention,
                 algorithm:"seven_structural_constraints_v1"},
   put_dict(_{table_uid:TableUid, jsonl_file:"tables.jsonl",
              candidate_count:NumCandidates, annotation_status:Status},
            Context, TableMetadata).

% The rasterizer processes thead rows, body rows, then tfoot rows, even when
% the source DOM places tfoot before tbody. Match precisely that ID order.
machine_source_cell_paths(element(table, _, Children), Context, Paths) :-
   findall(Path-Row,
           ( element_child_at(Children, element(thead, _, Section), S),
             element_child_at(Section, Row, R), is_element(tr, Row),
             Path = [S,R] ),
           Heads),
   findall(Path-Row,
           ( element_child_at(Children, Node, S),
             ( Node = element(tbody, _, Section),
               element_child_at(Section, Row, R), is_element(tr, Row),
               Path = [S,R]
             ; Node = Row, is_element(tr, Row), Path = [S] ) ),
           Bodies),
   findall(Path-Row,
           ( element_child_at(Children, element(tfoot, _, Section), S),
             element_child_at(Section, Row, R), is_element(tr, Row),
             Path = [S,R] ),
           Feet),
   append([Heads, Bodies, Feet], Rows),
   findall(Source,
           ( member(RowPath-element(tr, _, RowChildren), Rows),
             element_child_at(RowChildren, Cell, C), is_cell(Cell),
             append(RowPath, [C], LocalPath),
             machine_source_xpath(Context.source_path, LocalPath, Xpath),
             jats_element_text(Cell, Text),
             Cell = element(Tag, _, _),
             atom_string(Tag, TagName),
             Source = json{source_xpath:Xpath, text:Text, tag:TagName} ),
           Paths).

machine_source_xpath(TablePath, LocalPath, XPath) :-
   ( TablePath == "" -> Prefix = [1]
   ; split_string(TablePath, "/", "", Components),
     maplist(number_string, Prefix, Components) ),
   append(Prefix, LocalPath, Parts),
   maplist(machine_xpath_step, Parts, Steps),
   atomics_to_string(Steps, "", XPath).

machine_xpath_step(Index, Step) :-
   format(string(Step), '/*[~d]', [Index]).

% A synthetic padding cell has an ID but no DOM source. A source cell must
% appear at least once in the raster; otherwise the malformed-span problem
% (F12) is exposed as a typed error rather than silently losing a label.
machine_source_cells(Table, Context, Raster, Cells, FirstSlots) :-
   machine_source_cell_paths(Table, Context, SourcePaths),
   length(SourcePaths, RealCellCount),
   machine_indexed_sources(SourcePaths, SourceAssoc),
   machine_first_slots(Raster, FirstSlots),
   list_to_assoc(FirstSlots, OccupiedAssoc),
   ( RealCellCount =:= 0 -> true
   ; LastId is RealCellCount - 1,
     forall(between(0, LastId, Id),
            ( get_assoc(Id, OccupiedAssoc, _)
            -> true
            ; throw(error(unmapped_source_cell(Id),
                          context(machine_table_record/8,
                                  'DOM cell has no slot in the raster'))) )) ),
   maplist(machine_cell_entry(SourceAssoc, RealCellCount), FirstSlots, Cells).

machine_indexed_sources(Paths, Assoc) :-
   empty_assoc(Empty),
   foldl(machine_indexed_source, Paths, 0-Empty, _-Assoc).

machine_indexed_source(Source, Id-Assoc0, Next-Assoc) :-
   put_assoc(Id, Assoc0, Source, Assoc),
   Next is Id + 1.

machine_first_slots(Raster, FirstSlots) :-
   empty_assoc(Empty),
   foldl(machine_row_slots, Raster, 0-Empty, _-Assoc),
   assoc_to_list(Assoc, FirstSlots).

machine_row_slots(Row, R-Assoc0, Next-Assoc) :-
   foldl(machine_slot(R), Row, 0-Assoc0, _-Assoc),
   Next is R + 1.

machine_slot(R, Id, C-Assoc0, Next-Assoc) :-
   ( get_assoc(Id, Assoc0, _) -> Assoc = Assoc0
   ; put_assoc(Id, Assoc0, R-C, Assoc) ),
   Next is C + 1.

machine_cell_entry(PathsAssoc, RealCount, Id-(Row-Col), Cell) :-
   ( Id < RealCount
   -> get_assoc(Id, PathsAssoc, Source),
      Cell = json{cell_id:Id, kind:"source", row:Row, column:Col,
                  source_xpath:Source.source_xpath, tag:Source.tag,
                  text:Source.text}
   ;  Cell = json{cell_id:Id, kind:"synthetic_gap", row:Row, column:Col,
                  source_xpath: null, tag: null, text:""} ).

machine_candidate(TableUid, FirstSlots, json{hmd:Hmd,vmd:Vmd}, Candidate) :-
   format(string(CandidateId), '~s/h~d_v~d', [TableUid, Hmd, Vmd]),
   maplist(machine_cell_label(Hmd, Vmd), FirstSlots, Labels),
   Candidate = json{candidate_id:CandidateId, hmd:Hmd, vmd:Vmd,
                    labels:Labels, failed_constraints:[]}.

machine_cell_label(Hmd, Vmd, Id-(R-C), json{cell_id:Id, region:Name}) :-
   slot_region(Hmd, Vmd, R, C, Region),
   atom_string(Region, Name).
