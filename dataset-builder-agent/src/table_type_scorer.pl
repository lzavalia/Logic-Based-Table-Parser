% Type inference of a table's parse: choose one candidate by its cell types.
%
% Reads papers/PMC<id>/tables.jsonl and the type records written next to it
% (guided_types.jsonl when the guideline step has run, else types.jsonl) and
% writes papers/PMC<id>/type_inference.jsonl, which is what the review works
% from. type_inference.pl is the command line; review_agent.sh runs it.
%
%   score_dataset(+DatasetDir, +Papers, +Scorer)
%   score_dataset(+DatasetDir, +Papers, +Scorer, +Level)
%       Papers is none (all papers) or a list of paper names; Level is family
%       (the default) or group.
%   table_type_inference(+Scorer, +Record, +Typed, -Inference)
%   table_type_inference(+Scorer, +Level, +Record, +Typed, -Inference)
%   candidate_bit_cost(+Record, +Typed, +Candidate, +Options, -Bits)
%   candidate_purity(+Record, +Typed, +Candidate, +Options, -Purity)
%   select_candidate(+Scored, +Direction, -Best, -Gap)
%   default_scorer_options(-Options)
%       Options is scorer{level, model_cost, data_roles}.
%
% --- scorers -----------------------------------------------------------------
%
% bit-cost (the default): a description length in bits, lower is better. For
% every subtable of the candidate (a plain boundary is one subtable):
%   data       each data column and each data row has its own type
%              distribution; a line of n typed cells costs n * H(its types).
%              The data cost is the mean of the column view and the row view.
%   hmd, vmd   all HMD cells of the subtable share one distribution, and so do
%              all its VMD cells. A cell spanning several lines counts once.
%   model      each distribution used costs 0.5 * log2(N) bits, N the table's
%              typed cells, as in BIC. Without this, splitting a table into
%              subtables can only lower the cost, so spurious splits win.
%   roles      cells of a data role (Identifier, EntityName) name their row:
%              they are left out of the data rows' distributions, and each
%              one the candidate puts in the VMD costs 0.5 * log2(N) bits.
%
% purity: the mean of column purity and row purity, higher is better. A line's
% purity is the share of its typed cells that have its commonest type; a view's
% purity is the mean over its lines. Purity sees too little metadata but not
% too much, so it ties more often and picks worse (see the experiment README).
%
% Cells whose family is empty, Missing or untyped are left out of every line,
% and separator rows are in no line. Types are compared at the family level
% or, with level group, by each cell's group (table_type_abstraction.pl): a
% program's intermediate types then tell text cells apart, so that a header
% of labels contrasts with a body of statements. Type records written before
% groups existed have none and are an error at that level.
%
% The selection is the best candidate. When two or more share the best score
% (within 1e-9), the tie is broken without types, so a table with candidates
% always has a selection: the fewest steps from one header row and one
% row-header column, then the fewest subtables, then the candidate id.
%
% --- type_inference.jsonl ----------------------------------------------------
%
% One JSON object per table, in the order of tables.jsonl:
%   table_uid, pmc_id, table_index
%   scorer                 "bit-cost" or "purity"
%   level                  "group"; absent at the default family level, so
%                          that its output, which reviews hash, is unchanged
%   types_file             the type records used
%   tables_jsonl_sha256    the tables.jsonl scored
%   status                 "selected", "unique" (one candidate, nothing to
%                          score) or "no_candidates"
%   selected_candidate_id  the chosen candidate, or null without candidates
%   selected_by            "score", "tie_break", "only_candidate" or null
%   margin                 best against runner-up (bit-cost: bits per typed
%                          cell; purity: purity), or null without two candidates
%   scores                 [{candidate_id, score}]

:- module(table_type_scorer, [
      score_dataset/3,
      score_dataset/4,
      table_type_inference/4,
      table_type_inference/5,
      candidate_bit_cost/5,
      candidate_purity/5,
      select_candidate/4,
      default_scorer_options/1
   ]).

:- if(exists_source(library(json))).
:- use_module(library(json)).
:- else.
:- use_module(library(http/json)).
:- endif.
:- use_module(library(apply)).
:- use_module(library(assoc)).
:- use_module(library(filesex)).
:- use_module(library(lists)).
:- use_module(library(pairs)).
:- use_module(library(readutil)).
:- use_module(provenance_manifest, [file_sha256/2]).

default_scorer_options(scorer{level:family, model_cost:true,
                              data_roles:["Identifier", "EntityName"]}).

ignored_family("empty").
ignored_family("untyped").
ignored_family("Missing").

tie_tolerance(1.0e-9).

% --- files -------------------------------------------------------------------

score_dataset(DatasetDir, Papers, Scorer) :-
   score_dataset(DatasetDir, Papers, Scorer, family).

score_dataset(DatasetDir, Papers, Scorer, Level) :-
   must_be(oneof(['bit-cost', purity]), Scorer),
   must_be(oneof([family, group]), Level),
   directory_file_path(DatasetDir, papers, PapersDir),
   directory_files(PapersDir, Names0),
   msort(Names0, Names),
   forall(( member(Name, Names),
            sub_atom(Name, 0, _, _, 'PMC'),
            \+ sub_atom(Name, _, _, _, '.'),
            ( Papers == none -> true ; memberchk(Name, Papers) ),
            directory_file_path(PapersDir, Name, PaperDir),
            directory_file_path(PaperDir, 'tables.jsonl', TablesFile),
            exists_file(TablesFile) ),
          score_paper(PaperDir, TablesFile, Scorer, Level)).

score_paper(PaperDir, TablesFile, Scorer, Level) :-
   read_jsonl(TablesFile, Records),
   maplist(table_uid, Records, Uids),
   paper_types(PaperDir, Uids, TypesFile, Typed),
   file_sha256(TablesFile, Hash), atom_string(Hash, Sha),
   maplist(file_inference(Scorer, Level, TypesFile, Sha), Records, Typed, Inferences),
   directory_file_path(PaperDir, 'type_inference.jsonl', OutFile),
   setup_call_cleanup(
      open(OutFile, write, Out, [encoding(utf8)]),
      forall(member(Inference, Inferences),
             ( json_write_dict(Out, Inference, [width(0)]), nl(Out) )),
      close(Out)).

% paper_types(+PaperDir, +Uids, -TypesFile, -Typed): the guided types when they
% describe these tables, else the rule types.
paper_types(PaperDir, Uids, 'guided_types.jsonl', Typed) :-
   directory_file_path(PaperDir, 'guided_types.jsonl', File),
   exists_file(File),
   read_jsonl(File, Typed),
   maplist(table_uid, Typed, Uids), !.
paper_types(PaperDir, Uids, 'types.jsonl', Typed) :-
   directory_file_path(PaperDir, 'types.jsonl', File),
   (  exists_file(File)
   -> read_jsonl(File, Typed)
   ;  throw(error(existence_error(type_records, File), _)) ),
   (  maplist(table_uid, Typed, Uids)
   -> true
   ;  throw(error(type_records_mismatch(File), _)) ).

table_uid(Record, Record.table_uid).

file_inference(Scorer, Level, TypesFile, Sha, Record, Typed, Inference) :-
   table_type_inference(Scorer, Level, Record, Typed, Inference0),
   put_dict(json{types_file:TypesFile, tables_jsonl_sha256:Sha}, Inference0, Inference).

read_jsonl(File, Records) :-
   read_file_to_string(File, Text, [encoding(utf8)]),
   split_string(Text, "\n", "\r", Lines),
   exclude(==(""), Lines, Lines1),
   maplist(json_line, Lines1, Records).

json_line(Line, Record) :-
   atom_json_dict(Line, Record, [default_tag(json)]).

% --- tables ------------------------------------------------------------------

table_type_inference(Scorer, Record, Typed, Inference) :-
   table_type_inference(Scorer, family, Record, Typed, Inference).

table_type_inference(Scorer, Level, Record, Typed, Inference) :-
   default_scorer_options(Options0),
   put_dict(level, Options0, Level, Options),
   (  get_dict(candidates, Record, Candidates0), is_list(Candidates0)
   -> Candidates = Candidates0
   ;  Candidates = [] ),
   atom_string(Scorer, ScorerName),
   table_selection(Candidates, Scorer, Record, Typed, Options,
                   Status, Selected, SelectedBy, Margin, Scores),
   Inference0 = json{table_uid:Record.table_uid, pmc_id:Record.pmc_id,
                     table_index:Record.table_index, scorer:ScorerName,
                     status:Status, selected_candidate_id:Selected,
                     selected_by:SelectedBy, margin:Margin, scores:Scores},
   (  Level == family
   -> Inference = Inference0
   ;  atom_string(Level, LevelName),
      put_dict(level, Inference0, LevelName, Inference)
   ).

table_selection([], _, _, _, _, "no_candidates", null, null, null, []) :- !.
table_selection([C], _, _, _, _, "unique", C.candidate_id, "only_candidate", null, []) :- !.
table_selection(Candidates, Scorer, Record, Typed, Options,
                "selected", Selected, SelectedBy, Margin, Scores) :-
   scorer_predicate(Scorer, Score, Direction),
   maplist(scored_candidate(Score, Record, Typed, Options), Candidates, Scored),
   select_candidate(Scored, Direction, Best, Gap),
   (  Best = [Selected]
   -> SelectedBy = "score"
   ;  break_tie(Candidates, Best, Selected), SelectedBy = "tie_break" ),
   margin(Scorer, Typed, Gap, Margin),
   maplist(score_json, Scored, Scores).

scorer_predicate('bit-cost', candidate_bit_cost, lowest).
scorer_predicate(purity, candidate_purity, highest).

scored_candidate(Score, Record, Typed, Options, Candidate, Id-Value) :-
   Id = Candidate.candidate_id,
   call(Score, Record, Typed, Candidate, Options, Value).

score_json(Id-Value, json{candidate_id:Id, score:Value}).

margin('bit-cost', Typed, Gap, Margin) :-
   typed_cell_count(Typed.cells, N),
   (  N =:= 0 -> Margin = 0.0 ; Margin is Gap / N ).
margin(purity, _, Gap, Gap).

% select_candidate(+Scored, +Direction, -Best, -Gap)
% Scored is [Id-Score] with at least two entries, Direction lowest or highest.
% Best lists the Ids that share the best score; Gap is the difference between
% the best score and the runner-up's.
select_candidate(Scored, Direction, Best, Gap) :-
   maplist(sort_key(Direction), Scored, Keyed),
   keysort(Keyed, Sorted),
   Sorted = [Top-_, Runner-_|_],
   Gap is abs(Runner - Top),
   tie_tolerance(Tie),
   findall(Id, ( member(Key-Id, Sorted), Key - Top =< Tie ), Best).

break_tie(Candidates, Best, Selected) :-
   findall(Key,
           ( member(C, Candidates), memberchk(C.candidate_id, Best),
             tie_key(C, Key) ),
           Keys),
   msort(Keys, [key(_, _, Selected)|_]).

tie_key(C, key(Steps, Subtables, C.candidate_id)) :-
   Steps is abs(C.hmd - 1) + abs(C.vmd - 1),
   (  get_dict(subtables, C, Subs) -> length(Subs, Subtables) ; Subtables = 1 ).

sort_key(lowest, Id-Score, Score-Id).
sort_key(highest, Id-Score, Key-Id) :- Key is -Score.

% --- bit cost ----------------------------------------------------------------

candidate_bit_cost(Record, Typed, Candidate, Options, Bits) :-
   cell_index(Typed.cells, Options, Cells),
   typed_cell_count(Typed.cells, N),
   Unit is 0.5 * log(max(N, 2)) / log(2),
   (  Options.model_cost == true -> PerDistribution = Unit ; PerDistribution = 0.0 ),
   raster_grid(Record.raster, Grid),
   candidate_regions(Candidate, Regions),
   candidate_subtables(Record, Candidate, Subtables),
   foldl(subtable_bit_cost(Grid, Regions, Cells, Unit, PerDistribution),
         Subtables, 0.0, Bits).

subtable_bit_cost(Grid, Regions, Cells, Unit, PerDistribution, Subtable, Bits0, Bits) :-
   subtable_lines(Grid, Regions, Subtable, DataCols, DataRows0, HmdRows, VmdCols),
   maplist(without_data_roles(Cells), DataRows0, DataRows),
   append(VmdCols, VmdCells0),
   sort(VmdCells0, VmdCells),
   include(data_role_cell(Cells), VmdCells, Misplaced),
   length(Misplaced, NumMisplaced),
   append(HmdRows, HmdCells0),
   sort(HmdCells0, HmdCells),
   lines_cost(DataCols, Cells, PerDistribution, ColBits),
   lines_cost(DataRows, Cells, PerDistribution, RowBits),
   lines_cost([HmdCells], Cells, PerDistribution, HmdBits),
   lines_cost([VmdCells], Cells, PerDistribution, VmdBits),
   Bits is Bits0 + Unit * NumMisplaced + (ColBits + RowBits) / 2 + HmdBits + VmdBits.

without_data_roles(Cells, Line0, Line) :-
   exclude(data_role_cell(Cells), Line0, Line).

data_role_cell(Cells, Id) :-
   get_assoc(Id, Cells, cell(_, _, true)).

% The lines with at least one typed cell, each with its model cost.
lines_cost(Lines, Cells, PerDistribution, Bits) :-
   maplist(line_types(Cells), Lines, Typed0),
   exclude(==([]), Typed0, Typed),
   foldl(entropy_bits, Typed, 0.0, Bits0),
   length(Typed, Used),
   Bits is Bits0 + PerDistribution * Used.

entropy_bits(Types, Bits0, Bits) :-
   type_counts(Types, Counts),
   length(Types, N),
   foldl(count_bits(N), Counts, Bits0, Bits).

count_bits(N, _-K, Bits0, Bits) :-
   Bits is Bits0 - K * log(K / N) / log(2).

% --- purity ------------------------------------------------------------------

candidate_purity(Record, Typed, Candidate, Options, Purity) :-
   cell_index(Typed.cells, Options, Cells),
   raster_grid(Record.raster, Grid),
   candidate_regions(Candidate, Regions),
   candidate_subtables(Record, Candidate, Subtables),
   foldl(subtable_purities(Grid, Regions, Cells), Subtables, []-[], Cols-Rows),
   findall(Mean, ( member(View, [Cols, Rows]), View \== [], mean(View, Mean) ), Means),
   (  Means == [] -> Purity = 0.0 ; mean(Means, Purity) ).

subtable_purities(Grid, Regions, Cells, Subtable, Cols0-Rows0, Cols-Rows) :-
   subtable_lines(Grid, Regions, Subtable, DataCols, DataRows, _, _),
   line_purities(DataCols, Cells, ColPurities),
   line_purities(DataRows, Cells, RowPurities),
   append(Cols0, ColPurities, Cols),
   append(Rows0, RowPurities, Rows).

line_purities(Lines, Cells, Purities) :-
   maplist(line_types(Cells), Lines, Typed0),
   exclude(==([]), Typed0, Typed),
   maplist(purity, Typed, Purities).

purity(Types, Purity) :-
   type_counts(Types, Counts),
   pairs_values(Counts, Ks),
   max_list(Ks, Most),
   length(Types, N),
   Purity is Most / N.

mean(Values, Mean) :-
   sum_list(Values, Sum),
   length(Values, N),
   Mean is Sum / N.

% --- cells -------------------------------------------------------------------

% Id -> cell(Type, Family, DataRole), Type at the options' level.
cell_index(Typed, Options, Cells) :-
   foldl(index_cell(Options), Typed, t, Cells).

index_cell(Options, Cell, Cells0, Cells) :-
   text_to_string(Cell.family, Family),
   text_to_string(Cell.type, Fine),
   level_type(Options.level, Cell, Family, Fine, Type),
   (  ( memberchk(Family, Options.data_roles) ; memberchk(Fine, Options.data_roles) )
   -> Role = true
   ;  Role = false ),
   put_assoc(Cell.cell_id, Cells0, cell(Type, Family, Role), Cells).

level_type(family, _, Family, _, Family) :- !.
level_type(group, Cell, _, _, Group) :- !,
   (  get_dict(group, Cell, Group0)
   -> text_to_string(Group0, Group)
   ;  throw(error(existence_error(type_group, Cell.cell_id), _))
   ).
level_type(_, _, _, Fine, Fine).

typed_cell_count(Typed, N) :-
   include(typed_cell, Typed, Cells),
   length(Cells, N).

typed_cell(Cell) :-
   text_to_string(Cell.family, Family),
   \+ ignored_family(Family).

line_types(Cells, Line, Types) :-
   findall(Type,
           ( member(Id, Line), get_assoc(Id, Cells, cell(Type, Family, _)),
             \+ ignored_family(Family) ),
           Types).

type_counts(Types, Counts) :-
   msort(Types, Sorted),
   clumped_types(Sorted, Counts).

clumped_types([], []).
clumped_types([Type|Types], [Type-K|Counts]) :-
   same_type(Types, Type, 1, K, Rest),
   clumped_types(Rest, Counts).

same_type([Type|Types], Type, K0, K, Rest) :- !,
   K1 is K0 + 1,
   same_type(Types, Type, K1, K, Rest).
same_type(Rest, _, K, K, Rest).

% --- geometry ----------------------------------------------------------------

raster_grid(Raster, Grid) :-
   maplist(row_term, Raster, Rows),
   Grid =.. [grid|Rows].

row_term(Row, Term) :-
   Term =.. [row|Row].

slot(Grid, R, C, Id) :-
   R1 is R + 1, C1 is C + 1,
   arg(R1, Grid, Row),
   arg(C1, Row, Id).

candidate_regions(Candidate, Regions) :-
   foldl(add_region, Candidate.labels, t, Regions).

add_region(Label, Regions0, Regions) :-
   put_assoc(Label.cell_id, Regions0, Label.region, Regions).

% sub(Rows, Columns, Hmd, Vmd) of each subtable of the candidate.
candidate_subtables(Record, Candidate, Subtables) :-
   (  get_dict(kind, Candidate, "layout")
   -> maplist(layout_subtable, Candidate.subtables, Subtables)
   ;  length(Record.raster, NumRows),
      Record.raster = [First|_],
      length(First, NumCols),
      LastRow is NumRows - 1, LastCol is NumCols - 1,
      numlist(0, LastRow, Rows),
      numlist(0, LastCol, Columns),
      Subtables = [sub(Rows, Columns, Candidate.hmd, Candidate.vmd)] ).

layout_subtable(S, sub(S.rows, S.columns, S.hmd, S.vmd)).

% Cell ids, each once per line, of the data columns, data rows, HMD rows and
% VMD columns of one subtable, by the candidate's region labels.
subtable_lines(Grid, Regions, sub(Rows, Columns, Hmd, Vmd),
               DataCols, DataRows, HmdRows, VmdCols) :-
   split_at(Hmd, Rows, HeadRows, BodyRows),
   split_at(Vmd, Columns, HeadCols, BodyCols),
   maplist(column_line(Grid, Regions, "data", BodyRows), BodyCols, DataCols),
   maplist(row_line(Grid, Regions, "data", BodyCols), BodyRows, DataRows),
   maplist(row_line(Grid, Regions, "hmd", Columns), HeadRows, HmdRows),
   maplist(column_line(Grid, Regions, "vmd", BodyRows), HeadCols, VmdCols).

split_at(N, List, Head, Tail) :-
   length(List, Length),
   Take is min(N, Length),
   length(Head, Take),
   append(Head, Tail, List).

column_line(Grid, Regions, Region, Rows, C, Line) :-
   findall(R-C, member(R, Rows), Slots),
   region_cells(Grid, Regions, Region, Slots, Line).

row_line(Grid, Regions, Region, Columns, R, Line) :-
   findall(R-C, member(C, Columns), Slots),
   region_cells(Grid, Regions, Region, Slots, Line).

region_cells(Grid, Regions, Region, Slots, Line) :-
   findall(Id,
           ( member(R-C, Slots), slot(Grid, R, C, Id),
             get_assoc(Id, Regions, Label), Label == Region ),
           Ids),
   sort(Ids, Line).
