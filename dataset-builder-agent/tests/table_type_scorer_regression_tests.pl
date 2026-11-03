% Type inference of a parse (table_type_scorer.pl) on synthetic tables.
% From dataset-builder-agent/tests/:
%   swipl -q -s table_type_scorer_regression_tests.pl -g run_tests -t halt
:- use_module('../src/table_type_scorer').
:- use_module(library(filesex)).
:- use_module(library(readutil)).
:- if(exists_source(library(json))).
:- use_module(library(json)).
:- else.
:- use_module(library(http/json)).
:- endif.

% A header row of Text over a row-header column of Text and Numeric data.
raster([[0, 1, 2], [3, 4, 5], [6, 7, 8], [9, 10, 11]]).
families(["Text", "Text", "Text",
          "Text", "Numeric", "Numeric",
          "Text", "Numeric", "Numeric",
          "Text", "Numeric", "Numeric"]).

boundary_labels(Raster, Hmd, Vmd, Labels) :-
   findall(Id-Region,
           ( nth0(R, Raster, Row), nth0(C, Row, Id), region(R, C, Hmd, Vmd, Region) ),
           Pairs0),
   sort(1, @=<, Pairs0, Pairs),
   findall(json{cell_id:Id, region:Region}, member(Id-Region, Pairs), Labels).

region(R, _, Hmd, _, "hmd") :- R < Hmd, !.
region(_, C, _, Vmd, "vmd") :- C < Vmd, !.
region(_, _, _, _, "data").

candidate(Hmd, Vmd, Candidate) :-
   raster(Raster),
   candidate(Raster, Hmd, Vmd, Candidate).

candidate(Raster, Hmd, Vmd, Candidate) :-
   boundary_labels(Raster, Hmd, Vmd, Labels),
   format(string(Id), "PMC1/t0/h~d_v~d", [Hmd, Vmd]),
   Candidate = json{candidate_id:Id, kind:"boundary", hmd:Hmd, vmd:Vmd, labels:Labels}.

typed(Families, json{cells:Cells}) :-
   findall(json{cell_id:I, type:F, family:F}, nth0(I, Families, F), Cells).

record(Shapes, json{table_uid:"PMC1/t0", pmc_id:"PMC1", table_index:0,
                    raster:Raster, candidates:Candidates}) :-
   raster(Raster),
   findall(C, ( member(H-V, Shapes), candidate(H, V, C) ), Candidates).

options(Changes, Options) :-
   default_scorer_options(Options0),
   put_dict(Changes, Options0, Options).

% No model cost and no roles: the plain description length.
plain(Options) :-
   options(_{model_cost:false, data_roles:[]}, Options).

bits(Families, H, V, Options, Bits) :-
   record([], Record), typed(Families, Typed), candidate(H, V, C),
   candidate_bit_cost(Record, Typed, C, Options, Bits).

:- begin_tests(table_type_scorer).

test(true_boundary_is_cheapest) :-
   families(F), plain(O),
   bits(F, 1, 1, O, Best),
   assertion(Best =:= 0.0),
   % Too little metadata mixes Text into data lines; too much puts Numeric
   % cells into a header row or column.
   forall(member(H-V, [0-1, 1-0, 2-1, 1-2]),
          ( bits(F, H, V, O, Bits), assertion(Bits > 0.0) )).

test(spanning_header_cell_counted_once) :-
   Raster = [[0, 0], [1, 2], [3, 4]],
   Record = json{raster:Raster},
   candidate(Raster, 2, 0, C),
   typed(["Text", "Text", "Numeric", "Numeric", "Numeric"], Typed),
   plain(O),
   candidate_bit_cost(Record, Typed, C, O, Bits),
   % HMD holds cells 0, 1, 2 once each: Text, Text, Numeric.
   Expected is -(2 * log(2 / 3) + log(1 / 3)) / log(2),
   assertion(abs(Bits - Expected) < 1.0e-9).

test(model_cost_penalises_spurious_subtables) :-
   % Two side-by-side subtables, the second with no VMD column: free without
   % a model cost (every line is uniform) but more distributions with one.
   families(F), typed(F, Typed), record([], Record), raster(Raster),
   boundary_labels(Raster, 1, 1, Labels),
   Split = json{candidate_id:"PMC1/t0/layout0", kind:"layout", hmd:1, vmd:1,
                separators:[], labels:Labels,
                subtables:[json{rows:[0, 1, 2, 3], columns:[0, 1], hmd:1, vmd:1},
                           json{rows:[0, 1, 2, 3], columns:[2], hmd:1, vmd:0}]},
   candidate(1, 1, Plain),
   plain(Without),
   options(_{model_cost:true, data_roles:[]}, With),
   candidate_bit_cost(Record, Typed, Split, Without, SplitFree),
   candidate_bit_cost(Record, Typed, Plain, Without, PlainFree),
   assertion(SplitFree =:= 0.0), assertion(PlainFree =:= 0.0),
   candidate_bit_cost(Record, Typed, Split, With, SplitBits),
   candidate_bit_cost(Record, Typed, Plain, With, PlainBits),
   assertion(SplitBits > PlainBits).

test(identifier_column_is_data_by_role) :-
   % Column 0 holds study citations. Without the role it reads as a VMD; with
   % it, the boundary without a VMD is cheaper.
   F = ["Text", "Text", "Text",
        "Identifier", "Numeric", "Numeric",
        "Identifier", "Numeric", "Numeric",
        "Identifier", "Numeric", "Numeric"],
   options(_{data_roles:[]}, NoRole),
   default_scorer_options(Role),
   bits(F, 1, 1, NoRole, B11), bits(F, 1, 0, NoRole, B10),
   assertion(B11 < B10),
   bits(F, 1, 1, Role, R11), bits(F, 1, 0, Role, R10),
   assertion(R10 < R11).

test(fine_type_can_hold_the_role) :-
   families(F0),
   typed(F0, Typed0),
   Cells = Typed0.cells,
   nth0(3, Cells, C0, Rest),
   put_dict(type, C0, "EntityName", C1),
   nth0(3, Cells1, C1, Rest),
   Typed = Typed0.put(cells, Cells1),
   record([], Record), candidate(1, 1, C),
   default_scorer_options(Role),
   options(_{data_roles:[]}, NoRole),
   candidate_bit_cost(Record, Typed, C, Role, WithRole),
   candidate_bit_cost(Record, Typed, C, NoRole, Without),
   assertion(WithRole > Without).

% An all-text table: a Metadata header row and first column over Qualitative
% statements. Every cell's family is Text.
grouped(Typed) :-
   Groups = ["Metadata", "Metadata", "Metadata",
             "Metadata", "Qualitative", "Qualitative",
             "Metadata", "Qualitative", "Qualitative",
             "Metadata", "Qualitative", "Qualitative"],
   findall(json{cell_id:I, type:"Leaf", family:"Text", group:G},
           nth0(I, Groups, G), Cells),
   Typed = json{cells:Cells}.

test(group_level_separates_a_family) :-
   grouped(Typed),
   record([1-1, 0-1, 1-0], Record),
   table_type_inference('bit-cost', family, Record, Typed, Family),
   Family.selected_by == "tie_break",
   \+ get_dict(level, Family, _),
   table_type_inference('bit-cost', group, Record, Typed, Group),
   Group.selected_by == "score",
   Group.selected_candidate_id == "PMC1/t0/h1_v1",
   Group.level == "group".

test(group_level_needs_groups, [throws(error(existence_error(type_group, 0), _))]) :-
   families(F), typed(F, Typed),
   record([1-1, 0-1], Record),
   table_type_inference('bit-cost', group, Record, Typed, _).

test(ignored_families_do_not_count) :-
   families(F0),
   nth0(5, F0, _, F1), nth0(5, F2, "Missing", F1),
   nth0(8, F2, _, F3), nth0(8, F, "untyped", F3),
   plain(O),
   bits(F, 1, 1, O, Bits),
   assertion(Bits =:= 0.0).

test(purity_is_the_mean_of_the_two_views) :-
   % Without headers, columns are 4/4 Text, 3/4 and 3/4 Numeric; the first
   % row is 3/3 Text and the other three 2/3 Numeric.
   families(F), typed(F, Typed), record([], Record), candidate(0, 0, C),
   default_scorer_options(O),
   candidate_purity(Record, Typed, C, O, Purity),
   Expected is ((1.0 + 0.75 + 0.75) / 3 + (1.0 + 3 * 2 / 3) / 4) / 2,
   assertion(abs(Purity - Expected) < 1.0e-9),
   candidate(1, 1, Best),
   candidate_purity(Record, Typed, Best, O, BestPurity),
   assertion(BestPurity =:= 1.0).

test(purity_cannot_see_too_much_metadata) :-
   families(F), typed(F, Typed), record([], Record),
   default_scorer_options(O),
   candidate(1, 1, Right), candidate(1, 2, TooMuch),
   candidate_purity(Record, Typed, Right, O, P1),
   candidate_purity(Record, Typed, TooMuch, O, P2),
   assertion(P1 =:= P2).

test(selection_takes_the_best_and_reports_ties) :-
   select_candidate([a-3.0, b-1.0], lowest, [b], 2.0),
   select_candidate([a-3.0, b-1.0], highest, [a], 2.0),
   select_candidate([a-1.0, b-1.0], lowest, [a, b], 0.0),
   select_candidate([a-1.0, b-1.0, c-0.5], highest, [a, b], 0.0).

test(tie_prefers_one_header_row_and_column_then_fewer_subtables_then_id) :-
   Candidates = [json{candidate_id:"a", hmd:1, vmd:1, subtables:[x, y]},
                 json{candidate_id:"b", hmd:1, vmd:1, subtables:[x]},
                 json{candidate_id:"c", hmd:2, vmd:1},
                 json{candidate_id:"d", hmd:0, vmd:1},
                 json{candidate_id:"e", hmd:1, vmd:1}],
   table_type_scorer:break_tie(Candidates, ["a", "b", "c", "d"], S1),
   S1 == "b",
   table_type_scorer:break_tie(Candidates, ["a", "c"], S2),
   S2 == "a",
   table_type_scorer:break_tie(Candidates, ["c", "d"], S3),
   S3 == "c",
   table_type_scorer:break_tie(Candidates, ["b", "e"], S4),
   S4 == "b".

test(inference_of_each_status) :-
   families(F), typed(F, Typed),
   record([1-1, 0-1, 1-0], R3),
   table_type_inference('bit-cost', R3, Typed, I3),
   I3.status == "selected", I3.selected_by == "score",
   I3.selected_candidate_id == "PMC1/t0/h1_v1",
   I3.scorer == "bit-cost",
   length(I3.scores, 3),
   assertion(I3.margin > 0.0),
   record([1-1], R1),
   table_type_inference('bit-cost', R1, Typed, I1),
   I1.status == "unique", I1.selected_candidate_id == "PMC1/t0/h1_v1",
   I1.selected_by == "only_candidate",
   I1.margin == null,
   record([], R0),
   table_type_inference(purity, R0, Typed, I0),
   I0.status == "no_candidates", I0.selected_candidate_id == null,
   length(Texts, 12), maplist(=("Text"), Texts), typed(Texts, Same),
   table_type_inference('bit-cost', R3, Same, Tied),
   Tied.status == "selected", Tied.selected_by == "tie_break",
   % With the model cost, h0_v1 and h1_v0 use the fewest distributions.
   Tied.selected_candidate_id == "PMC1/t0/h0_v1".

test(purity_ties_where_bit_cost_decides) :-
   families(F), typed(F, Typed),
   record([1-1, 1-2], Record),
   table_type_inference('bit-cost', Record, Typed, Bits),
   table_type_inference(purity, Record, Typed, Purity),
   Bits.selected_by == "score", Purity.selected_by == "tie_break".

test(dataset_uses_guided_types_when_they_fit,
     [setup(paper_dir(Root, Dir)), cleanup(delete_directory_and_contents(Root))]) :-
   families(F), typed(F, Typed0),
   Typed = Typed0.put(json{table_uid:"PMC1/t0"}),
   write_record(Dir, 'types.jsonl', Typed),
   score_dataset(Root, none, 'bit-cost'),
   inference(Dir, I1),
   I1.types_file == "types.jsonl",
   I1.selected_candidate_id == "PMC1/t0/h1_v1",
   string(I1.tables_jsonl_sha256),
   write_record(Dir, 'guided_types.jsonl', Typed),
   score_dataset(Root, none, purity),
   inference(Dir, I2),
   I2.types_file == "guided_types.jsonl",
   I2.scorer == "purity",
   % Guided types of other tables (an older build) are not used.
   write_record(Dir, 'guided_types.jsonl', Typed.put(table_uid, "PMC1/t9")),
   score_dataset(Root, none, 'bit-cost'),
   inference(Dir, I3),
   I3.types_file == "types.jsonl".

test(dataset_without_type_records_is_an_error,
     [setup(paper_dir(Root, _)), cleanup(delete_directory_and_contents(Root)),
      throws(error(existence_error(type_records, _), _))]) :-
   score_dataset(Root, none, 'bit-cost').

test(unknown_scorer_is_an_error,
     [setup(paper_dir(Root, _)), cleanup(delete_directory_and_contents(Root)),
      throws(error(_, _))]) :-
   score_dataset(Root, none, nonsense).

:- end_tests(table_type_scorer).

paper_dir(Root, Dir) :-
   tmp_file(table_type_scorer, Root),
   directory_file_path(Root, 'papers/PMC1', Dir),
   make_directory_path(Dir),
   record([1-1, 0-1, 1-0], Record),
   write_record(Dir, 'tables.jsonl', Record).

write_record(Dir, Name, Record) :-
   directory_file_path(Dir, Name, File),
   setup_call_cleanup(open(File, write, Out, [encoding(utf8)]),
                      ( json_write_dict(Out, Record, [width(0)]), nl(Out) ),
                      close(Out)).

inference(Dir, Inference) :-
   directory_file_path(Dir, 'type_inference.jsonl', File),
   read_file_to_string(File, Text, [encoding(utf8)]),
   split_string(Text, "\n", "", [Line|_]),
   atom_json_dict(Line, Inference, [default_tag(json)]).
