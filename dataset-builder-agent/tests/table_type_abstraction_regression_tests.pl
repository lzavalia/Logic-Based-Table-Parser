% Regression tests for the type abstraction of tables
% (src/table_type_abstraction.pl) and the scientific-table types of
% type_dsl_examples/sci.tdsl.
%
% From dataset-builder-agent/tests/:
%   swipl -q -s table_type_abstraction_regression_tests.pl -g run_tests -t halt
%
% No network, LLM, article downloads, or DeepClause installation required.

:- use_module(library(plunit)).
:- use_module(library(filesex)).
:- use_module(library(readutil)).
:- if(exists_source(library(json))).
:- use_module(library(json)).
:- else.
:- use_module(library(http/json)).
:- endif.
:- use_module('../src/type_dsl_parser').
:- use_module('../src/type_dsl_engine').
:- use_module('../src/table_type_abstraction').

:- prolog_load_context(directory, Dir),
   atom_concat(Dir, '/../type_dsl_examples/sci.tdsl', Sci),
   asserta(user:sci_tdsl(Sci)).

analyzer(Text, Analyzer) :-
   parse_tdsl_string(Text, AST),
   type_dsl_analyzer_generator(AST, Analyzer, _).

sci(Analyzer) :-
   user:sci_tdsl(File),
   tdsl_file_analyzer(File, Analyzer, _).

sci_text(Analyzer) :-
   user:sci_tdsl(File),
   file_directory_name(File, Dir),
   directory_file_path(Dir, 'sci_text.tdsl', TextFile),
   tdsl_file_analyzer(TextFile, Analyzer, _).

type_of(Analyzer, Text, Type) :-
   cell_type(Analyzer, Text, Type, _).

% cell(+Id, +Row, +Column, +Text, -Cell): a source cell of a tables.jsonl
% record.
cell(Id, Row, Column, Text,
     json{cell_id:Id, row:Row, column:Column, kind:"source", text:Text}).

:- begin_tests(cell_types).

test(empty_and_untyped) :-
   analyzer("type T\nif equals \"x\" decide T", A),
   cell_type(A, "", T1, S1),  assertion(T1-S1 == empty-none),
   cell_type(A, "y", T2, S2), assertion(T2-S2 == untyped-none),
   type_family(A, empty, F1),   assertion(F1 == empty),
   type_family(A, untyped, F2), assertion(F2 == untyped).

test(subtype_beats_supertype_whatever_the_order) :-
   analyzer("type N\ntype I\nI <: N\nif regex \"[0-9]+\" decide N\nif regex \"[0-9]+\" decide I", A),
   type_of(A, "12", T), assertion(T == 'I').

test(subtype_through_a_chain) :-
   analyzer("type A\ntype B\ntype C\nC <: B\nB <: A\nif equals \"x\" decide A\nif equals \"x\" decide C", A),
   type_of(A, "x", T), assertion(T == 'C'),
   type_family(A, 'C', F), assertion(F == 'A').

test(group_is_the_intermediate_type_below_the_family) :-
   analyzer("type T\ntype Q\ntype F\ntype N\ntype I\nQ <: T\nF <: Q\nI <: N\nif equals \"x\" decide F", A),
   type_group(A, 'F', G1), assertion(G1 == 'Q'),
   type_group(A, 'Q', G2), assertion(G2 == 'Q'),
   type_group(A, 'T', G3), assertion(G3 == 'T'),
   % A subtype with no subtypes of its own is not a group.
   type_group(A, 'I', G4), assertion(G4 == 'N'),
   type_group(A, empty, G5), assertion(G5 == empty),
   type_group(A, untyped, G6), assertion(G6 == untyped).

test(group_follows_the_first_declared_supertype) :-
   analyzer("type T\ntype Q\ntype W\ntype F\nQ <: T\nW <: T\nF <: Q\nF <: W\nif equals \"x\" decide F", A),
   type_group(A, 'F', G), assertion(G == 'Q').

test(rule_order_between_unrelated_types) :-
   analyzer("type P\ntype Q\nif prefix \"a\" decide Q\nif prefix \"a\" decide P", A),
   cell_type(A, "ab", T, Source),
   assertion(T == 'Q'),
   assertion(Source = '<ast>':3).

test(own_family_without_supertype) :-
   analyzer("type T\nif equals \"x\" decide T", A),
   type_family(A, 'T', F), assertion(F == 'T').

test(subtype_cycle_terminates) :-
   analyzer("type A\ntype B\nA <: B\nB <: A\nif equals \"x\" decide A\nif equals \"x\" decide B", A),
   type_of(A, "x", T), assertion(T == 'A'),
   type_family(A, 'A', F), assertion(F == 'B').

test(type_expression_names) :-
   analyzer("type F\ntype R = (F, F)\nif equals \"x\" decide (F, F)\nif equals \"y\" decide F | R", A),
   type_of(A, "x", T1), assertion(T1 == '(F, F)'),
   type_of(A, "y", T2), assertion(T2 == 'F | R').

:- end_tests(cell_types).

:- begin_tests(sci_types).

test(numeric) :-
   sci(A),
   forall(member(Text-Type,
                 [ "70"-'Integer', "−0.39"-'Decimal', "0.47"-'Decimal',
                   "12%"-'Percent', "4.1 × 10 −5"-'Scientific',
                   "<0.01"-'Inequality', "6.49ab"-'AnnotatedNumber',
                   "180.24***"-'AnnotatedNumber',
                   "524.58 ± 9.53 a"-'MeanSD', "27.7 d (± 0.57)"-'MeanSD',
                   "123 (40.7%)"-'ValueParen', "0.087 (0.027)"-'ValueParen',
                   "1.06, [0.761, 1.476] ab"-'ValueInterval',
                   "0.36–0.58"-'NumberRange', "90:45:17.5"-'Ratio',
                   "1.02, 1.03"-'NumberList', "P = 0.004"-'TestStatistic',
                   "130 °C"-'Measurement' ]),
          ( type_of(A, Text, T),
            assertion(T-Text == Type-Text),
            type_family(A, T, F),
            assertion(F-Text == 'Numeric'-Text) )).

test(text) :-
   sci(A),
   forall(member(Text-Type,
                 [ "CG"-'Word', "Effect size"-'Phrase',
                   "Crystallite Size (nm)"-'LabelWithUnit',
                   "Age, years"-'LabelWithUnit',
                   "DLB vs AD, P = 0.03"-'LabeledStatistic',
                   "(mmHg)"-'Unit', "%"-'Unit',
                   "100% NPK + HW"-'Phrase', "95% CI"-'Phrase' ]),
          ( type_of(A, Text, T),
            assertion(T-Text == Type-Text),
            type_family(A, T, F),
            assertion(F-Text == 'Text'-Text) )).

test(sci_text_numeric_forms) :-
   sci_text(A),
   forall(member(Text-Type,
                 [ "1,420 (179)"-'ValueParen', "4,170 (48%)"-'ValueParen',
                   "(0.06)"-'ValueParen', "678/6163 (11)"-'ValueParen',
                   "77% (79 of 103)"-'ValueParen', "0.00 (−)"-'ValueParen',
                   "0.387 (0.321, 0.466) < 0.0001"-'ValueInterval',
                   "0.744 (0.640, 0.864) 0.00011"-'ValueInterval',
                   "1.24 (1.08–1.43, P = 0.002)"-'ValueInterval',
                   "74.68% [53.10%–88.88%]"-'ValueInterval',
                   "0.87 (0.76–1.01) I 2 =42%"-'ValueInterval',
                   "(1.797–2.692)"-'ValueInterval',
                   "8.30 a b"-'AnnotatedNumber', "273.10b-e"-'AnnotatedNumber',
                   "37.9 ± 12.7 i"-'MeanSD', "28.6 ± 8.7 (29, 23–35)"-'MeanSD',
                   "1649.72 ± 373.88 a, b,c"-'MeanSD',
                   "< 0.001 ***"-'Inequality', "− 0.006"-'Decimal',
                   "χ 2 = 9.21"-'TestStatistic', "(N = 5332)"-'TestStatistic',
                   "5 / 5"-'NumberList',
                   "[ 35 ]"-'Citation', "[ 74 , 75 ]"-'Citation',
                   "( 4 , 34 – 36 , 38 )"-'Citation' ]),
          ( type_of(A, Text, T), assertion(T-Text == Type-Text) )).

test(sci_text_text_is_left_to_guidelines) :-
   sci_text(A),
   forall(member(Text, [ "Male", "Age, years", "95% CI", "CRF 135", "0–15 cm",
                         "15 May 2023", "Q1 (n = 217)", "100% NPK + HW",
                         "Decreased amplitude responses in the left insula." ]),
          ( type_of(A, Text, T), assertion(T-Text == 'Text'-Text) )),
   type_of(A, "(mmHg)", U), assertion(U == 'Unit'),
   type_of(A, "Smith 2017", C), assertion(C == 'Citation'),
   type_of(A, "NR", N), assertion(N == 'NotAvailable').

test(sci_text_guideline_types_and_groups) :-
   sci_text(A),
   forall(member(Type-Group,
                 [ 'VariableLabel'-'MetadataText', 'Unit'-'MetadataText',
                   'StatisticLabel'-'MetadataText', 'SectionLabel'-'MetadataText',
                   'ChecklistItem'-'MetadataText',
                   'CategoryLevel'-'CategoricalValue', 'QualityJudgment'-'CategoricalValue',
                   'EntityName'-'EntityText',
                   'StudyCharacteristic'-'QualitativeData',
                   'InterventionDescription'-'QualitativeData',
                   'FindingStatement'-'QualitativeData',
                   'JudgmentRationale'-'QualitativeData',
                   'PhenomenologicalData'-'QualitativeData' ]),
          ( type_family(A, Type, F), assertion(F-Type == 'Text'-Type),
            type_group(A, Type, G), assertion(G-Type == Group-Type) )),
   type_group(A, 'Text', Root), assertion(Root == 'Text'),
   type_group(A, 'MeanSD', Numeric), assertion(Numeric == 'Numeric').

test(missing_and_symbols_before_text) :-
   sci(A),
   type_of(A, "–", T1),  assertion(T1 == 'Dash'),
   type_of(A, "NR", T2), assertion(T2 == 'NotAvailable'),
   type_of(A, "n/a", T3), assertion(T3 == 'NotAvailable'),
   type_of(A, "↑↑", T4), assertion(T4 == 'Arrow'),
   type_family(A, 'NotAvailable', F), assertion(F == 'Missing').

test(identifiers) :-
   sci(A),
   forall(member(Text-Type,
                 [ "Abdurrahman 2017"-'Citation', "Abe 2009 [ 3 ]"-'Citation',
                   "Sawada et al. (2019) [ 16 ]"-'Citation', "Bernard [ 35 ]"-'Citation',
                   "Van der Worp (2007)"-'Citation', "Shargie 2006 ETH"-'Citation',
                   "NCT01193101"-'TrialID', "rs1882694 (AC/CC vs AA)"-'VariantID' ]),
          ( type_of(A, Text, T),
            assertion(T-Text == Type-Text),
            type_family(A, T, F),
            assertion(F-Text == 'Identifier'-Text) )),
   type_of(A, "Year 2014", Y), assertion(Y \== 'Citation'),
   type_of(A, "Phase 3", P), assertion(P \== 'Citation'),
   type_of(A, "Age, years", G), assertion(G == 'LabelWithUnit').

test(untyped) :-
   sci(A),
   type_of(A, "( 13 )", T), assertion(T == untyped).

:- end_tests(sci_types).

:- begin_tests(type_records).

test(record) :-
   analyzer("type N\ntype I\ntype W\nI <: N\nif regex \"[0-9]+\" decide I\nif regex \"[a-z]+\" decide W", A),
   cell(0, 0, 0, "name", C0),
   cell(1, 0, 1, "  ", C1),
   cell(2, 1, 0, "a  b", C2),
   cell(3, 1, 1, "\t42\n", C3),
   Gap = json{cell_id:4, row:1, column:2, kind:"synthetic_gap", text:"7"},
   Record = json{table_uid:"PMC1/t0", pmc_id:"PMC1", table_index:0,
                 cells:[C0, C1, C2, C3, Gap],
                 raster:[[0, 1, 1], [2, 3, 4]]},
   table_type_record(A, Record, R),
   assertion(R.table_uid == "PMC1/t0"),
   assertion(R.type_raster == [['W', empty, empty], [untyped, 'I', empty]]),
   assertion(R.untyped_cells == [json{cell_id:2, text:"a b"}]),
   assertion(R.counts == json{cells:5, typed:2, untyped:1, empty:2}),
   R.cells = [_, _, _, Typed3, Typed4],
   assertion(Typed3 == json{cell_id:3, type:'I', family:'N', group:'N', source:"<ast>:5"}),
   assertion(Typed4.source == "synthetic").

test(file, [setup(tmp_dir(Dir)), cleanup(delete_directory_and_contents(Dir))]) :-
   cell(0, 0, 0, "Age", C0),
   cell(1, 1, 0, "12.5", C1),
   Record = json{table_uid:"PMC1/t0", pmc_id:"PMC1", table_index:0,
                 cells:[C0, C1], raster:[[0], [1]]},
   directory_file_path(Dir, 'tables.jsonl', In),
   directory_file_path(Dir, 'types.jsonl', Out),
   setup_call_cleanup(open(In, write, S, [encoding(utf8)]),
                      ( json_write_dict(S, Record, [width(0)]), nl(S) ),
                      close(S)),
   user:sci_tdsl(Sci),
   type_tables_file(Sci, In, Out),
   read_file_to_string(Out, Text, [encoding(utf8)]),
   split_string(Text, "\n", "", Lines),
   assertion(Lines = [_, ""]),
   Lines = [Line|_],
   atom_json_dict(Line, Json, []),
   assertion(Json.type_raster == [["Word"], ["Decimal"]]),
   absolute_file_name(Sci, SciPath), atom_string(SciPath, SciString),
   assertion(Json.type_program == SciString).

:- end_tests(type_records).

tmp_dir(Dir) :-
   tmp_file(type_abstraction, Dir),
   make_directory(Dir).
