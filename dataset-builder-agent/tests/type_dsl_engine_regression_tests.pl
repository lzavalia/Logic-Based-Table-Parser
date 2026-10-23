% Regression tests for the type DSL engine (src/type_dsl_engine.pl).
%
% From dataset-builder-agent/tests/:
%   swipl -q -s type_dsl_engine_regression_tests.pl -g run_tests -t halt
%
% No network, LLM, article downloads, or DeepClause installation required.

:- use_module(library(plunit)).
:- use_module(library(filesex)).
:- use_module('../src/type_dsl_parser').
:- use_module('../src/type_dsl_engine').

:- prolog_load_context(directory, Dir),
   atom_concat(Dir, '/../../type_dsl_examples', Examples),
   asserta(user:tdsl_examples_dir(Examples)).

example(Name, Path) :-
   user:tdsl_examples_dir(Dir),
   atomic_list_concat([Dir, '/', Name], Path).

analyzer(Text, Analyzer, Guidelines) :-
   parse_tdsl_string(Text, AST),
   type_dsl_analyzer_generator(AST, Analyzer, Guidelines).

% types(+Analyzer, +Cell, -Types): the decided types, without the rules.
types(Analyzer, Cell, Types) :-
   call(Analyzer, Cell, Matches),
   pairs_values(Matches, Types).

matches(Pattern, Cell) :-
   generate_pattern(Pattern, Predicate),
   call(Predicate, Cell).

% write_tdsl(+Dir, +Name, +Text)
write_tdsl(Dir, Name, Text) :-
   directory_file_path(Dir, Name, Path),
   setup_call_cleanup(open(Path, write, Out),
                      write(Out, Text),
                      close(Out)).

:- begin_tests(type_dsl_engine_examples).

test(num) :-
   example('num.tdsl', File),
   tdsl_file_analyzer(File, A, Guidelines),
   assertion(Guidelines == []),
   types(A, "42", T1),     assertion(T1 == [ref('Integer')]),
   types(A, "-3.14", T2),  assertion(T2 == [ref('Floating')]),
   types(A, "1.5 2.5", T3), assertion(T3 == [ref('Range')]),
   types(A, "abc", T4),    assertion(T4 == []).

test(num_rule_origin) :-
   example('num.tdsl', File),
   tdsl_file_analyzer(File, A, _),
   call(A, "7", Matches),
   absolute_file_name(File, Path),
   assertion(Matches == [rule(Path:11, regex("-?[0-9]+"))-ref('Integer')]).

test(num_declarations) :-
   example('num.tdsl', File),
   tdsl_file_analyzer(File, A, _),
   tdsl_analyzer_property(A, base_types(Base)),
   tdsl_analyzer_property(A, type_aliases(Aliases)),
   tdsl_analyzer_property(A, subtypes(Subtypes)),
   tdsl_analyzer_property(A, caption_analysis(Caption)),
   assertion(Base == ['Numeric', 'Integer', 'Floating']),
   assertion(Aliases == ['Range'-tuple([ref('Floating'), ref('Floating')])]),
   assertion(Subtypes == [ref('Integer')-ref('Numeric'),
                          ref('Floating')-ref('Numeric')]),
   assertion(Caption == false).

test(text) :-
   example('text.tdsl', File),
   tdsl_file_analyzer(File, A, Guidelines),
   assertion(Guidelines ==
      ["List of names, followed by a year, and then a citation number"
       - ref('AbbreviatedCitation')]),
   types(A, "hello", T1), assertion(T1 == [ref('Word')]),
   types(A, "two words", T2), assertion(T2 == []).

:- end_tests(type_dsl_engine_examples).

:- begin_tests(type_dsl_engine_patterns).

test(equals) :-
   assertion(matches(equals("n/a"), "n/a")),
   assertion(\+ matches(equals("n/a"), "n/a ")).

test(prefix_and_suffix) :-
   assertion(matches(prefix("<"), "<0.05")),
   assertion(\+ matches(prefix("<"), "0.05<")),
   assertion(matches(suffix("%"), "12%")),
   assertion(\+ matches(suffix("%"), "%12")).

test(empty_affixes_always_match) :-
   assertion(matches(prefix(""), "")),
   assertion(matches(suffix(""), "abc")).

test(regex_matches_the_whole_text) :-
   assertion(matches(regex("[0-9]+"), "123")),
   assertion(\+ matches(regex("[0-9]+"), "a123")),
   assertion(\+ matches(regex("[0-9]+"), "123\n")).

test(regex_alternation_is_anchored_as_a_whole) :-
   assertion(\+ matches(regex("a|b"), "ab")),
   assertion(matches(regex("a|b"), "b")).

test(regex_escapes) :-
   assertion(matches(regex("\\d+\\.\\d+"), "3.25")),
   assertion(matches(regex("a\\tb"), "a\tb")).

test(connectives) :-
   P = or(and(prefix("("), suffix(")")), not(regex(".*[a-z].*"))),
   assertion(matches(P, "(abc)")),
   assertion(matches(P, "123")),
   assertion(\+ matches(P, "abc)")).

test(predicate_is_deterministic) :-
   generate_pattern(or(suffix("a"), suffix("aa")), Predicate),
   findall(x, call(Predicate, "aaa"), Solutions),
   assertion(Solutions == [x]).

test(predicate_is_reusable) :-
   generate_pattern(equals("x"), Predicate),
   assertion(call(Predicate, "x")),
   assertion(\+ call(Predicate, "y")),
   assertion(call(Predicate, x)).

test(invalid_regex_fails_at_generation, [throws(error(syntax_error(_), _))]) :-
   generate_pattern(regex("("), _).

:- end_tests(type_dsl_engine_patterns).

:- begin_tests(type_dsl_engine_statements).

test(all_passing_rules_in_order) :-
   analyzer("if suffix '%' decide Percent
             if regex '[0-9]+%' decide Integer
             if prefix 'x' decide X", A, _),
   types(A, "15%", Types),
   assertion(Types == [ref('Percent'), ref('Integer')]).

test(union_type_is_kept) :-
   analyzer("if equals '-' decide Missing | null", A, _),
   types(A, "-", Types),
   assertion(Types == [union([ref('Missing'), null])]).

test(caption_analysis_option) :-
   analyzer("set-option enable_caption_analysis", A, _),
   assertion(tdsl_analyzer_property(A, caption_analysis(true))).

test(guidelines_in_order) :-
   analyzer("guideline 'first' decide A
             if equals 'a' decide A
             guideline 'second' decide B", _, Guidelines),
   assertion(Guidelines == ["first"-ref('A'), "second"-ref('B')]).

test(atom_and_codes_input) :-
   analyzer("if equals 'ab' decide T", A, _),
   types(A, ab, T1), assertion(T1 == [ref('T')]),
   types(A, `ab`, T2), assertion(T2 == [ref('T')]).

test(empty_program) :-
   type_dsl_analyzer_generator([], A, Guidelines),
   assertion(Guidelines == []),
   types(A, "anything", Types),
   assertion(Types == []).

test(duplicate_base_type,
     [throws(error(tdsl_error(duplicate_type('A'), '<ast>':2), _))]) :-
   analyzer("type A\ntype A", _, _).

test(alias_redeclares_base_type,
     [throws(error(tdsl_error(duplicate_type('A'), _), _))]) :-
   analyzer("type A type A = (B, C)", _, _).

:- end_tests(type_dsl_engine_statements).

:- begin_tests(type_dsl_engine_imports).

test(imports_are_prepended,
     [setup(tmp_dir(Dir)), cleanup(delete_directory_and_contents(Dir))]) :-
   write_tdsl(Dir, 'base.tdsl', "type Base\nif regex '.*' decide Base\n"),
   write_tdsl(Dir, 'main.tdsl',
              "if equals 'x' decide Local\nimport 'base.tdsl'\n"),
   directory_file_path(Dir, 'main.tdsl', Main),
   tdsl_file_analyzer(Main, A, _),
   call(A, "x", Matches),
   directory_file_path(Dir, 'base.tdsl', Base0),
   absolute_file_name(Base0, Base),
   absolute_file_name(Main, MainAbs),
   assertion(Matches == [ rule(Base:2, regex(".*"))-ref('Base'),
                          rule(MainAbs:1, equals("x"))-ref('Local') ]),
   assertion(tdsl_analyzer_property(A, base_types(['Base']))).

test(nested_imports_resolve_against_their_file,
     [setup(tmp_dir(Dir)), cleanup(delete_directory_and_contents(Dir))]) :-
   directory_file_path(Dir, lib, Lib),
   make_directory(Lib),
   write_tdsl(Lib, 'inner.tdsl', "type Inner\n"),
   write_tdsl(Lib, 'outer.tdsl', "import 'inner.tdsl'\ntype Outer\n"),
   write_tdsl(Dir, 'main.tdsl', "import 'lib/outer.tdsl'\ntype Main\n"),
   directory_file_path(Dir, 'main.tdsl', Main),
   tdsl_file_analyzer(Main, A, _),
   assertion(tdsl_analyzer_property(A, base_types(['Inner', 'Outer', 'Main']))).

test(diamond_imports_are_included_once,
     [setup(tmp_dir(Dir)), cleanup(delete_directory_and_contents(Dir))]) :-
   write_tdsl(Dir, 'common.tdsl', "type Common\n"),
   write_tdsl(Dir, 'left.tdsl', "import 'common.tdsl'\ntype Left\n"),
   write_tdsl(Dir, 'right.tdsl', "import 'common.tdsl'\ntype Right\n"),
   write_tdsl(Dir, 'main.tdsl', "import 'left.tdsl' import 'right.tdsl'\n"),
   directory_file_path(Dir, 'main.tdsl', Main),
   tdsl_file_analyzer(Main, A, _),
   assertion(tdsl_analyzer_property(A, base_types(['Common', 'Left', 'Right']))).

test(import_cycle_terminates,
     [setup(tmp_dir(Dir)), cleanup(delete_directory_and_contents(Dir))]) :-
   write_tdsl(Dir, 'a.tdsl', "import 'b.tdsl'\ntype A\n"),
   write_tdsl(Dir, 'b.tdsl', "import 'a.tdsl'\ntype B\n"),
   directory_file_path(Dir, 'a.tdsl', File),
   tdsl_file_analyzer(File, An, _),
   assertion(tdsl_analyzer_property(An, base_types(['B', 'A']))).

test(base_dir_option,
     [setup(tmp_dir(Dir)), cleanup(delete_directory_and_contents(Dir))]) :-
   write_tdsl(Dir, 'base.tdsl', "type Base\n"),
   parse_tdsl_string("import 'base.tdsl'", AST),
   type_dsl_analyzer_generator(AST, A, _, [base_dir(Dir)]),
   assertion(tdsl_analyzer_property(A, base_types(['Base']))).

test(missing_import, [throws(error(existence_error(source_sink, _), _))]) :-
   parse_tdsl_string("import 'no_such_file_here.tdsl'", AST),
   type_dsl_analyzer_generator(AST, _, _).

:- end_tests(type_dsl_engine_imports).

tmp_dir(Dir) :-
   tmp_file(tdsl, Dir),
   make_directory(Dir).
