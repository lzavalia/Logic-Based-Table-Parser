% Regression tests for the type DSL parser (src/type_dsl_parser.pl).
%
% From dataset-builder-agent/tests/:
%   swipl -q -s type_dsl_parser_regression_tests.pl -g run_tests -t halt
%
% No network, LLM, article downloads, or DeepClause installation required.

:- use_module(library(plunit)).
:- use_module('../src/type_dsl_parser').

:- prolog_load_context(directory, Dir),
   atom_concat(Dir, '/../../type_dsl_examples', Examples),
   asserta(user:tdsl_examples_dir(Examples)).

example(Name, Path) :-
   user:tdsl_examples_dir(Dir),
   atomic_list_concat([Dir, '/', Name], Path).

% parses(+Text, -Statements) without the stmt(Line, _) wrappers.
parses(Text, Statements) :-
   parse_tdsl_string(Text, Stmts),
   findall(S, member(stmt(_, S), Stmts), Statements).

% fails_with(+Text, -Expected, -Found, -Line:Col)
fails_with(Text, Expected, Found, Line:Col) :-
   catch(( parse_tdsl_string(Text, _), Result = parsed ),
         error(syntax_error(tdsl(Expected, Found)), file(_, Line, Col, _)),
         Result = error),
   Result == error.

:- begin_tests(type_dsl_examples).

test(num) :-
   example('num.tdsl', File),
   parse_tdsl_file(File, Statements),
   assertion(Statements ==
      [ stmt(1, type_decl('Numeric')),
        stmt(2, type_decl('Integer')),
        stmt(3, type_decl('Floating')),
        stmt(5, type_decl('Range', tuple([ref('Floating'), ref('Floating')]))),
        stmt(8, subtype(ref('Integer'), ref('Numeric'))),
        stmt(9, subtype(ref('Floating'), ref('Numeric'))),
        stmt(11, rule(regex("-?[0-9]+"), ref('Integer'))),
        stmt(12, rule(regex("-?[0-9]+\\.[0-9]+"), ref('Floating'))),
        stmt(13, rule(regex("-?[0-9]+\\.[0-9]+[ \\t\\n]*([ \\t\\n]+-?[0-9]+\\.[0-9]+[ \\t\\n]*)"),
                      ref('Range')))
      ]).

test(text) :-
   example('text.tdsl', File),
   parse_tdsl_file(File, Statements),
   assertion(Statements ==
      [ stmt(1, type_decl('Text')),
        stmt(3, type_decl('Word')),
        stmt(5, subtype(ref('Word'), ref('Text'))),
        stmt(7, rule(regex("[a-zA-Z]+"), ref('Word'))),
        stmt(9, type_decl('Citation')),
        stmt(11, subtype(ref('Citation'), ref('Text'))),
        stmt(13, subtype(ref('AbbreviatedCitation'), ref('Citation'))),
        stmt(15, guideline("List of names, followed by a year, and then a citation number",
                           ref('AbbreviatedCitation')))
      ]).

:- end_tests(type_dsl_examples).

:- begin_tests(type_dsl_statements).

test(empty_program) :-
   parses("", S), assertion(S == []).

test(comments_only) :-
   parses("% nothing here\n   % or here", S), assertion(S == []).

test(import) :-
   parses("import \"base.tdsl\"", S), assertion(S == [import("base.tdsl")]).

test(option) :-
   parses("set-option enable_caption_analysis", S),
   assertion(S == [option(enable_caption_analysis)]).

test(supertype_operator_is_normalized) :-
   parses("Numeric :> Integer", S),
   assertion(S == [subtype(ref('Integer'), ref('Numeric'))]).

test(any_and_null) :-
   parses("type T = any | null", S),
   assertion(S == [type_decl('T', union([any, null]))]).

test(statements_on_one_line) :-
   parses("type A type B A <: B if equals 'x' decide A", S),
   assertion(S == [ type_decl('A'), type_decl('B'),
                    subtype(ref('A'), ref('B')),
                    rule(equals("x"), ref('A')) ]).

test(trailing_comment_and_line_numbers) :-
   parse_tdsl_string("% header\ntype A % the A type\n\ntype B", S),
   assertion(S == [stmt(2, type_decl('A')), stmt(4, type_decl('B'))]).

test(percent_inside_string_is_not_a_comment) :-
   parses("if suffix \"%\" decide Percent", S),
   assertion(S == [rule(suffix("%"), ref('Percent'))]).

test(keyword_prefix_is_an_identifier) :-
   parses("type types type if_x type set", S),
   assertion(S == [type_decl(types), type_decl(if_x), type_decl(set)]).

:- end_tests(type_dsl_statements).

:- begin_tests(type_dsl_type_expressions).

test(union_is_flat) :-
   parses("type T = A | B | C", S),
   assertion(S == [type_decl('T', union([ref('A'), ref('B'), ref('C')]))]).

test(union_binds_tighter_than_comma) :-
   parses("type T = (A | B, C)", S),
   assertion(S == [type_decl('T', tuple([union([ref('A'), ref('B')]), ref('C')]))]).

test(nested_tuples) :-
   parses("type T = ((A, B), C, D)", S),
   assertion(S == [type_decl('T',
                     tuple([tuple([ref('A'), ref('B')]), ref('C'), ref('D')]))]).

test(union_of_tuples) :-
   parses("(A, B) | C <: D", S),
   assertion(S == [subtype(union([tuple([ref('A'), ref('B')]), ref('C')]), ref('D'))]).

test(no_grouping_parentheses) :-
   fails_with("type T = (A)", Expected, Found, Pos),
   assertion(Expected-Found-Pos == punct(',')-punct(')')-(1:12)).

test(no_grouping_parentheses_around_union) :-
   fails_with("type T = (A | B) | C", Expected, Found, _),
   assertion(Expected-Found == punct(',')-punct(')')).

:- end_tests(type_dsl_type_expressions).

:- begin_tests(type_dsl_patterns).

test(and_binds_tighter_than_or) :-
   parses("if equals 'a' or equals 'b' and not equals 'c' or equals 'd' decide T", S),
   assertion(S == [rule(or(or(equals("a"), and(equals("b"), not(equals("c")))),
                           equals("d")),
                        ref('T'))]).

test(and_is_left_associative) :-
   parses("if prefix 'a' and prefix 'b' and prefix 'c' decide T", S),
   assertion(S == [rule(and(and(prefix("a"), prefix("b")), prefix("c")), ref('T'))]).

test(not_binds_tightest) :-
   parses("if not suffix 'a' and suffix 'b' decide T", S),
   assertion(S == [rule(and(not(suffix("a")), suffix("b")), ref('T'))]).

test(double_not) :-
   parses("if not not regex 'a' decide T", S),
   assertion(S == [rule(not(not(regex("a"))), ref('T'))]).

test(parentheses_group_patterns) :-
   parses("if not (equals 'a' or equals 'b') decide T", S),
   assertion(S == [rule(not(or(equals("a"), equals("b"))), ref('T'))]).

test(rule_decides_a_union) :-
   parses("if regex 'x' decide A | B", S),
   assertion(S == [rule(regex("x"), union([ref('A'), ref('B')]))]).

:- end_tests(type_dsl_patterns).

:- begin_tests(type_dsl_strings).

test(single_quotes) :-
   parses("import 'a b.tdsl'", S), assertion(S == [import("a b.tdsl")]).

test(regex_escapes_are_kept) :-
   parses("if regex \"\\d+\\.\\d+\" decide T", S),
   assertion(S == [rule(regex("\\d+\\.\\d+"), ref('T'))]).

test(escaped_delimiter) :-
   parses("if equals \"say \\\"hi\\\"\" decide T", S),
   assertion(S == [rule(equals("say \"hi\""), ref('T'))]).

test(other_quote_needs_no_escape) :-
   parses("if equals \"it's\" decide T", S),
   assertion(S == [rule(equals("it's"), ref('T'))]).

test(escaped_backslash_before_quote) :-
   parses("if suffix \"\\\\\" decide T", S),
   assertion(S == [rule(suffix("\\\\"), ref('T'))]).

test(unterminated_at_end_of_file) :-
   fails_with("if regex \"abc", Expected, Found, Pos),
   assertion(Expected-Found-Pos == closing_quote('"')-end_of_file-(1:10)).

test(unterminated_at_end_of_line) :-
   fails_with("type A\nif regex 'abc\ndecide A", Expected, Found, Pos),
   assertion(Expected-Found-Pos == closing_quote('\'')-end_of_line-(2:10)).

:- end_tests(type_dsl_strings).

:- begin_tests(type_dsl_errors).

test(bare_string_after_if) :-
   fails_with("if \"[a-z]+\" decide Word", Expected, Found, Pos),
   assertion(Expected-Found-Pos == syntax_pattern-string("[a-z]+")-(1:4)).

test(missing_decide) :-
   fails_with("type A\nif regex 'a' Word", Expected, Found, Pos),
   assertion(Expected-Found-Pos == keyword(decide)-identifier('Word')-(2:14)).

test(keyword_as_type_name) :-
   fails_with("type type", Expected, Found, Pos),
   assertion(Expected-Found-Pos == identifier-keyword(type)-(1:6)).

test(keyword_as_type_reference) :-
   fails_with("A <: decide", Expected, Found, _),
   assertion(Expected-Found == type_expression-keyword(decide)).

test(missing_subtype_operator) :-
   fails_with("A B", Expected, Found, Pos),
   assertion(Expected-Found-Pos == subtype_operator-identifier('B')-(1:3)).

test(unknown_option) :-
   fails_with("set-option enable_cpation_analysis", Expected, Found, _),
   assertion(Expected-Found == option_name-identifier(enable_cpation_analysis)).

test(not_a_statement) :-
   fails_with("decide A", Expected, Found, _),
   assertion(Expected-Found == statement-keyword(decide)).

test(unexpected_character) :-
   fails_with("type A\n  A - B", Expected, Found, Pos),
   assertion(Expected-Found-Pos == token-char(-)-(2:5)).

test(truncated_input) :-
   fails_with("guideline 'g' decide", Expected, Found, Pos),
   assertion(Expected-Found-Pos == type_expression-end_of_file-(1:21)).

test(file_name_in_error) :-
   tmp_file_stream(text, Tmp, Out),
   format(Out, "type A~nA <: ~n", []),
   close(Out),
   catch(parse_tdsl_file(Tmp, _),
         error(syntax_error(tdsl(type_expression, end_of_file)),
               file(Source, Line, _, _)),
         true),
   delete_file(Tmp),
   assertion(Source-Line == Tmp-3).

test(error_message_prints) :-
   catch(parse_tdsl_string("type type", _), E, true),
   '$messages':translate_message(E, Lines, []),
   with_output_to(string(Message), print_message_lines(current_output, '', Lines)),
   assertion(sub_string(Message, _, _, _,
                        "<string>:1:6: Syntax error: expected an identifier, found keyword `type`")).

:- end_tests(type_dsl_errors).
