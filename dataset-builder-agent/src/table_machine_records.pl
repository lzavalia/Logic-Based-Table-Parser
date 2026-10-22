% Machine-readable, deterministic structural interpretations of JATS tables.
% Consulted in the dataset_pipeline module after the rasterizer/annotator.
% The raster is the source of geometry; HTML colors are never used as labels.
%
% Paths use XPath element-sibling positions (/*[1]/*[2]...), following the
% same element-only numbering as jats_table_records/2. They remain unambiguous
% when attributes/IDs are missing or duplicated, and do not rely on namespaces.
%
% Schema 3.0: one JSON object per table in tables.jsonl. Coordinates and cell
% IDs are zero-based; candidate IDs are stable within a PMC and table index.
% Each candidate carries a geometric_certificate (table_certify.pl): either
% the claim proved and the name of the certificate file, or the kernel's
% reason for rejecting each claim. The build writes no certificate files; the
% review writes the file of the candidate it selects (table_review.pl).
%
% A candidate is of one of two kinds (table_candidates/2):
%   "boundary"  a plain (hmd, vmd) boundary, certified by a version 1
%               certificate certificateN_hH_vV.pl;
%   "layout"    a layout with rows set aside or metadata in the middle of
%               the table, id .../layoutK. Its hmd and vmd are those of the
%               top-level block; separators ({row, columns}) and subtables
%               ({rows, columns, hmd, vmd}) give the split that the version 2
%               certificate certificateN_layoutK.pl proves, whose claim is a
%               list, one per subtable. Its labels may also be "separator".

machine_table_record(Pmc, Index, Table, Context, Raster, Boundaries,
                     Record, TableMetadata) :-
   format(string(TableUid), '~s/t~d', [Pmc, Index]),
   machine_source_cells(Table, Context, Raster, Cells, FirstSlots),
   maplist(machine_candidate(TableUid, Index, Raster, FirstSlots),
           Boundaries, Candidates),
   length(Candidates, NumCandidates),
   (  NumCandidates =:= 0
   -> Status = "abstained", Abstention = "no_boundary_satisfies_constraints"
   ;  NumCandidates =:= 1
   -> Status = "unique", Abstention = null
   ;  Status = "ambiguous", Abstention = null
   ),
   length(Raster, Rows),
   ( Raster = [FirstRow|_] -> length(FirstRow, Cols) ; Cols = 0 ),
   Record = json{schema_version:"3.0", pmc_id:Pmc, table_index:Index,
                 table_uid:TableUid, source_table_id:Context.table_id,
                 source_path:Context.source_path,
                 source_table_html:Context.source_table_html,
                 context:Context, raster:Raster, rows:Rows, columns:Cols,
                 cells:Cells, candidates:Candidates, status:Status,
                 abstention_reason:Abstention,
                 algorithm:"ten_structural_constraints_counts_v2",
                 semantic_validation:"unverified",
                 interpretation_kind:"structural_boundary_hypotheses"},
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

machine_candidate(TableUid, Index, Raster, FirstSlots, json{hmd:Hmd,vmd:Vmd},
                  Candidate) :-
   format(string(CandidateId), '~s/h~d_v~d', [TableUid, Hmd, Vmd]),
   maplist(machine_cell_label(Hmd, Vmd), FirstSlots, Labels),
   machine_certificate(TableUid, Index, Raster, Hmd, Vmd, Certificate),
   Candidate = json{candidate_id:CandidateId, kind:"boundary", hmd:Hmd, vmd:Vmd,
                    labels:Labels, failed_constraints:[],
                    geometric_certificate:Certificate}.
% A layout (table_candidates/2): hmd and vmd are those of the top-level
% block, the subtables and separators those of layout_subtables/4, and the
% certificate is the version 2 certificate of the whole layout.
machine_candidate(TableUid, Index, Raster, FirstSlots, layout(K, Layout),
                  Candidate) :-
   format(string(CandidateId), '~s/layout~d', [TableUid, K]),
   Layout = layout(_, block(HmdRows, VmdCols, _)),
   length(HmdRows, Hmd),
   length(VmdCols, Vmd),
   layout_labels(Raster, Layout, Grid),
   maplist(machine_grid_label(Grid), FirstSlots, Labels),
   layout_subtables(Raster, Layout, Separators, Subtables),
   maplist(machine_separator_json, Separators, SeparatorJson),
   maplist(machine_subtable_json, Subtables, SubtableJson),
   machine_layout_certificate(TableUid, Index, Raster, K, Separators,
                              Subtables, Certificate),
   Candidate = json{candidate_id:CandidateId, kind:"layout", hmd:Hmd, vmd:Vmd,
                    separators:SeparatorJson, subtables:SubtableJson,
                    labels:Labels, failed_constraints:[],
                    geometric_certificate:Certificate}.

machine_cell_label(Hmd, Vmd, Id-(R-C), json{cell_id:Id, region:Name}) :-
   slot_region(Hmd, Vmd, R, C, Region),
   atom_string(Region, Name).

machine_grid_label(Grid, Id-(R-C), json{cell_id:Id, region:Name}) :-
   nth0(R, Grid, Row),
   nth0(C, Row, Region),
   atom_string(Region, Name).

machine_separator_json(separator(Row, Cols), json{row:Row, columns:Cols}).

machine_subtable_json(subtable(Rows, Cols, Hmd, Vmd),
                      json{rows:Rows, columns:Cols, hmd:Hmd, vmd:Vmd}).

% candidate_layout_parts(+Candidate, -Separators, -Subtables): the separators
% and subtables a layout candidate's JSON records, as layout_subtables/4
% gives them.
candidate_layout_parts(Candidate, Separators, Subtables) :-
   get_dict(separators, Candidate, SeparatorJson),
   get_dict(subtables, Candidate, SubtableJson),
   maplist(machine_separator_json, Separators, SeparatorJson),
   maplist(machine_subtable_json, Subtables, SubtableJson).

% machine_certificate(+TableUid, +Index, +Raster, +Hmd, +Vmd, -Certificate)
% The JSON summary of certify/5: the claim proved and the file holding the
% certificate, or, for a boundary that is not geometrically labelable, the
% kernel's reason for rejecting each claim.
machine_certificate(TableUid, Index, Raster, Hmd, Vmd, Certificate) :-
   certify(Raster, Hmd, Vmd, TableUid, Result),
   (  Result = certificate(Facts)
   -> memberchk(claim(Claim), Facts),
      atom_string(Claim, ClaimName),
      certificate_file_name(Index, Hmd, Vmd, File),
      atom_string(File, FileName),
      Certificate = json{status:"certified", claim:ClaimName,
                         file:FileName, rejections:null}
   ;  Result = not_labelable([columns-ColumnWhy, rows-RowWhy]),
      format(string(ColumnText), '~q', [ColumnWhy]),
      format(string(RowText), '~q', [RowWhy]),
      Certificate = json{status:"not_labelable", claim:null, file:null,
                         rejections:json{columns:ColumnText, rows:RowText}}
   ).

% machine_layout_certificate(+TableUid, +Index, +Raster, +K, +Separators,
%                            +Subtables, -Certificate)
% The same for a layout, from certify_layout/5. claim lists the claim proved
% for each subtable; rejections lists the subtables that are not labelable,
% or gives the kernel's reason for rejecting the partition.
machine_layout_certificate(TableUid, Index, Raster, K, Separators, Subtables,
                           Certificate) :-
   certify_layout(Raster, Separators, Subtables, TableUid, Result),
   (  Result = certificate(Facts)
   -> findall(ClaimName, ( member(claim(_, Claim), Facts),
                           atom_string(Claim, ClaimName) ), Claims),
      layout_certificate_file_name(Index, K, File),
      atom_string(File, FileName),
      Certificate = json{status:"certified", claim:Claims,
                         file:FileName, rejections:null}
   ;  Result = not_labelable(Reasons)
   -> findall(json{subtable:Sub, columns:ColumnText, rows:RowText},
              ( member(Sub-[columns-ColumnWhy, rows-RowWhy], Reasons),
                format(string(ColumnText), '~q', [ColumnWhy]),
                format(string(RowText), '~q', [RowWhy]) ),
              Rejections),
      Certificate = json{status:"not_labelable", claim:null, file:null,
                         rejections:json{subtables:Rejections}}
   ;  Result = rejected(Why),
      format(string(WhyText), '~q', [Why]),
      Certificate = json{status:"not_labelable", claim:null, file:null,
                         rejections:json{partition:WhyText}}
   ).

certificate_file_name(Index, Hmd, Vmd, File) :-
   format(atom(File), 'certificate~d_h~d_v~d.pl', [Index, Hmd, Vmd]).

layout_certificate_file_name(Index, K, File) :-
   format(atom(File), 'certificate~d_layout~d.pl', [Index, K]).
