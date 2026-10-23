% Parser for the type DSL of type_dsl_grammar.txt (files ending in .tdsl).
%
% Standalone for now: nothing else in the pipeline loads this module yet.
%
% From dataset-builder-agent/src/:
%   swipl -g 'use_module(type_dsl_parser),
%             parse_tdsl_file("../../type_dsl_examples/num.tdsl", S),
%             print_term(S, [])' -t halt
%
%   parse_tdsl_file(+File, -Statements)
%   parse_tdsl_string(+Text, -Statements)
%       Text is a string, an atom or a code list. A program is a sequence of
%       zero or more statements (Start in the grammar).
%   tdsl_tokens(+Text, -Tokens)
%       The lexer on its own, for debugging.
%
% --- lexical structure -----------------------------------------------------
%
% Whitespace, newlines included, only separates tokens: a statement ends
% where no operator can continue it. `%` starts a comment that runs to the
% end of the line (outside a string literal).
%
% Tokens are tok(Kind, Value, Line:Col), with Line and Col counted from 1:
%   tok(kw, K, _)       keyword K, one of keyword/1; `set-option` is a single
%                       keyword, its hyphen is not a separate token
%   tok(var, N, _)      VARIABLE: an ASCII C identifier [A-Za-z_][A-Za-z0-9_]*
%                       that is not a keyword; N is an atom
%   tok(string, S, _)   STRING_LITERAL in "..." or '...'; S is a string
%   tok(punct, P, _)    one of ( ) , | = <: :>
%   tok(eof, end_of_file, _)   always the last token
%
% A string literal keeps its content as written, so regex escapes such as
% \. or \t survive unchanged. The only rewrite is that a backslash followed
% by the delimiting quote stands for that quote; any other backslash pair,
% \\ included, is kept as both characters. A string literal cannot span
% lines.
%
% --- abstract syntax -------------------------------------------------------
%
% Statements is a list of stmt(Line, Statement), Line being the line of the
% statement's first token:
%   import(Path)                    Path is a string
%   option(enable_caption_analysis)
%   type_decl(Name)                 Name is an atom
%   type_decl(Name, TypeExpr)
%   subtype(Sub, Super)             A :> B is stored as subtype(B, A)
%   guideline(Text, TypeExpr)       Text is a string
%   rule(Pattern, TypeExpr)
%
% TypeExpr ::= ref(Name) | any | null
%            | tuple([T1, T2, ...])   two or more elements
%            | union([T1, T2, ...])   two or more alternatives
% `|` binds tighter than `,`, so (A | B, C) is a pair whose first element is
% a union. Parentheses always make a tuple: there is no grouping in types,
% by design. A union's alternatives are flattened into one list.
%
% Pattern ::= and(P, Q) | or(P, Q) | not(P)
%           | suffix(S) | prefix(S) | regex(S) | equals(S)
% `not` binds tightest, then `and`, then `or`; `and` and `or` are left
% associative, so `a or b and not c or d` is or(or(a, and(b, not(c))), d).
% Parentheses group patterns.
%
% --- errors ----------------------------------------------------------------
%
% Parsing is strict: the first error raises
%   error(syntax_error(tdsl(Expected, Found)), file(Source, Line, Col, _))
% with Source the file name, or '<string>' for parse_tdsl_string/2, so the
% toplevel prints it as Source:Line:Col. Expected is one of
%   keyword(K), punct(P), identifier, string_literal, type_expression,
%   syntax_pattern, statement, subtype_operator, option_name,
%   closing_quote(Q), token
% and Found one of
%   keyword(K), identifier(N), string(S), punct(P), char(C), end_of_line,
%   end_of_file
% An unterminated string literal is reported at its opening quote.

:- module(type_dsl_parser,
          [ parse_tdsl_file/2,
            parse_tdsl_string/2,
            tdsl_tokens/2
          ]).

:- use_module(library(readutil)).

% --- entry points ----------------------------------------------------------

parse_tdsl_file(File, Statements) :-
   read_file_to_codes(File, Codes, [encoding(utf8)]),
   parse_codes(Codes, File, Statements).

parse_tdsl_string(Text, Statements) :-
   text_to_string(Text, String),
   string_codes(String, Codes),
   parse_codes(Codes, '<string>', Statements).

tdsl_tokens(Text, Tokens) :-
   text_to_string(Text, String),
   string_codes(String, Codes),
   with_source('<string>', lex(Codes, 1, 1, Tokens)).

parse_codes(Codes, Source, Statements) :-
   with_source(Source,
               ( lex(Codes, 1, 1, Tokens),
                 phrase(program(Statements), Tokens)
               )).

% Errors are raised internally as tdsl_syntax/3 and get their source here.
with_source(Source, Goal) :-
   catch(Goal, tdsl_syntax(Expected, Found, Line:Col),
         throw(error(syntax_error(tdsl(Expected, Found)),
                     file(Source, Line, Col, _)))).

% --- lexer -----------------------------------------------------------------

keyword(import).
keyword('set-option').
keyword(enable_caption_analysis).
keyword(type).
keyword(any).
keyword(null).
keyword(guideline).
keyword(decide).
keyword(if).
keyword(and).
keyword(or).
keyword(not).
keyword(suffix).
keyword(prefix).
keyword(regex).
keyword(equals).

% lex(+Codes, +Line, +Col, -Tokens)
lex([], Line, Col, [tok(eof, end_of_file, Line:Col)]) :-
   !.
lex([0'\n|Cs], Line, _, Tokens) :-
   !,
   Line1 is Line + 1,
   lex(Cs, Line1, 1, Tokens).
lex([C|Cs], Line, Col, Tokens) :-
   code_type(C, space),
   !,
   Col1 is Col + 1,
   lex(Cs, Line, Col1, Tokens).
lex([0'%|Cs], Line, Col, Tokens) :-
   !,
   skip_comment(Cs, Rest, N),
   Col1 is Col + 1 + N,
   lex(Rest, Line, Col1, Tokens).
lex(Cs, Line, Col, [tok(Kind, Value, Line:Col)|Tokens]) :-
   token(Cs, Line:Col, Kind, Value, Rest),
   % No token spans a line, so the column advances by the codes consumed.
   length(Cs, Before),
   length(Rest, After),
   Col1 is Col + Before - After,
   lex(Rest, Line, Col1, Tokens).

% skip_comment(+Codes, -Rest, -N): drops N codes up to the end of the line.
skip_comment([], [], 0).
skip_comment([0'\n|Cs], [0'\n|Cs], 0) :- !.
skip_comment([_|Cs], Rest, N) :-
   skip_comment(Cs, Rest, N0),
   N is N0 + 1.

% token(+Codes, +Pos, -Kind, -Value, -Rest)
token([Q|Cs], Pos, string, Value, Rest) :-
   quote(Q),
   !,
   string_body(Cs, Q, Pos, Body, Rest),
   string_codes(Value, Body).
token([C|Cs], _, Kind, Value, Rest) :-
   ident_start(C),
   !,
   ident_chars(Cs, Chars, Rest0),
   atom_codes(Name, [C|Chars]),
   (  Name == set,
      append(`-option`, Rest, Rest0),
      \+ ( Rest = [Next|_], ident_char(Next) )
   -> Kind = kw, Value = 'set-option'
   ;  keyword(Name)
   -> Kind = kw, Value = Name, Rest = Rest0
   ;  Kind = var, Value = Name, Rest = Rest0
   ).
token(Cs, _, punct, Value, Rest) :-
   punct(Value, Codes),
   append(Codes, Rest, Cs),
   !.
token([C|_], Pos, _, _, _) :-
   char_code(Char, C),
   throw(tdsl_syntax(token, char(Char), Pos)).

quote(0'").
quote(0'\').

% Two-character operators come first so that `<:` is not read as `<`.
punct('<:', `<:`).
punct(':>', `:>`).
punct('(', `(`).
punct(')', `)`).
punct(',', `,`).
punct('|', `|`).
punct('=', `=`).

% string_body(+Codes, +Quote, +StartPos, -Body, -Rest)
string_body([], Q, Pos, _, _) :-
   char_code(Char, Q),
   throw(tdsl_syntax(closing_quote(Char), end_of_file, Pos)).
string_body([0'\n|_], Q, Pos, _, _) :-
   !,
   char_code(Char, Q),
   throw(tdsl_syntax(closing_quote(Char), end_of_line, Pos)).
string_body([Q|Rest], Q, _, [], Rest) :- !.
string_body([0'\\, Q|Cs], Q, Pos, [Q|Body], Rest) :- !,
   string_body(Cs, Q, Pos, Body, Rest).
string_body([0'\\, C|Cs], Q, Pos, [0'\\, C|Body], Rest) :-
   C \== 0'\n,
   !,
   string_body(Cs, Q, Pos, Body, Rest).
string_body([C|Cs], Q, Pos, [C|Body], Rest) :-
   string_body(Cs, Q, Pos, Body, Rest).

ident_start(C) :- between(0'a, 0'z, C), !.
ident_start(C) :- between(0'A, 0'Z, C), !.
ident_start(0'_).

ident_char(C) :- ident_start(C), !.
ident_char(C) :- between(0'0, 0'9, C).

ident_chars([C|Cs], [C|Chars], Rest) :-
   ident_char(C),
   !,
   ident_chars(Cs, Chars, Rest).
ident_chars(Rest, [], Rest).

% --- parser ----------------------------------------------------------------
%
% Recursive descent over the token list. Every choice is decided by the next
% token, so each rule commits with a cut and reports a mismatch with
% syntax_error//1 instead of backtracking.

program([]) -->
   [tok(eof, _, _)],
   !.
program([Statement|Statements]) -->
   statement(Statement),
   program(Statements).

statement(stmt(Line, Statement)) -->
   peek(tok(Kind, Value, Line:_)),
   statement(Kind, Value, Statement).

statement(kw, import, import(Path)) -->
   !,
   [_],
   expect_string(Path).
statement(kw, 'set-option', option(Option)) -->
   !,
   [_],
   option_name(Option).
statement(kw, type, Decl) -->
   !,
   [_],
   expect_identifier(Name),
   (  [tok(punct, '=', _)]
   -> type_expr(Type),
      { Decl = type_decl(Name, Type) }
   ;  { Decl = type_decl(Name) }
   ).
statement(kw, guideline, guideline(Text, Type)) -->
   !,
   [_],
   expect_string(Text),
   expect_keyword(decide),
   type_expr(Type).
statement(kw, if, rule(Pattern, Type)) -->
   !,
   [_],
   pattern(Pattern),
   expect_keyword(decide),
   type_expr(Type).
statement(Kind, Value, subtype(Sub, Super)) -->
   { type_start(Kind, Value) },
   !,
   type_expr(Left),
   (  [tok(punct, '<:', _)]
   -> type_expr(Right),
      { Sub = Left, Super = Right }
   ;  [tok(punct, ':>', _)]
   -> type_expr(Right),
      { Sub = Right, Super = Left }
   ;  syntax_error(subtype_operator)
   ).
statement(_, _, _) -->
   syntax_error(statement).

option_name(enable_caption_analysis) -->
   [tok(kw, enable_caption_analysis, _)],
   !.
option_name(_) -->
   syntax_error(option_name).

% The tokens that can start a TypeExpr, hence a SubtypeDecl.
type_start(var, _).
type_start(kw, any).
type_start(kw, null).
type_start(punct, '(').

% --- type expressions ---

type_expr(Type) -->
   type_primary(First),
   union_rest(Rest),
   { Rest == [] -> Type = First ; Type = union([First|Rest]) }.

union_rest([Type|Types]) -->
   [tok(punct, '|', _)],
   !,
   type_primary(Type),
   union_rest(Types).
union_rest([]) -->
   [].

type_primary(ref(Name)) -->
   [tok(var, Name, _)],
   !.
type_primary(any) -->
   [tok(kw, any, _)],
   !.
type_primary(null) -->
   [tok(kw, null, _)],
   !.
type_primary(tuple([First, Second|Rest])) -->
   [tok(punct, '(', _)],
   !,
   type_expr(First),
   expect_punct(','),
   type_expr(Second),
   tuple_rest(Rest),
   expect_punct(')').
type_primary(_) -->
   syntax_error(type_expression).

tuple_rest([Type|Types]) -->
   [tok(punct, ',', _)],
   !,
   type_expr(Type),
   tuple_rest(Types).
tuple_rest([]) -->
   [].

% --- syntax patterns ---

pattern(Pattern) -->
   and_pattern(First),
   or_rest(First, Pattern).

or_rest(Left, Pattern) -->
   [tok(kw, or, _)],
   !,
   and_pattern(Right),
   or_rest(or(Left, Right), Pattern).
or_rest(Pattern, Pattern) -->
   [].

and_pattern(Pattern) -->
   not_pattern(First),
   and_rest(First, Pattern).

and_rest(Left, Pattern) -->
   [tok(kw, and, _)],
   !,
   not_pattern(Right),
   and_rest(and(Left, Right), Pattern).
and_rest(Pattern, Pattern) -->
   [].

not_pattern(not(Pattern)) -->
   [tok(kw, not, _)],
   !,
   not_pattern(Pattern).
not_pattern(Pattern) -->
   [tok(punct, '(', _)],
   !,
   pattern(Pattern),
   expect_punct(')').
not_pattern(Pattern) -->
   [tok(kw, Matcher, _)],
   { matcher(Matcher) },
   !,
   expect_string(String),
   { Pattern =.. [Matcher, String] }.
not_pattern(_) -->
   syntax_error(syntax_pattern).

matcher(suffix).
matcher(prefix).
matcher(regex).
matcher(equals).

% --- token helpers ---

peek(Token), [Token] -->
   [Token].

expect_keyword(K) -->
   [tok(kw, K, _)],
   !.
expect_keyword(K) -->
   syntax_error(keyword(K)).

expect_punct(P) -->
   [tok(punct, P, _)],
   !.
expect_punct(P) -->
   syntax_error(punct(P)).

expect_identifier(Name) -->
   [tok(var, Name, _)],
   !.
expect_identifier(_) -->
   syntax_error(identifier).

expect_string(String) -->
   [tok(string, String, _)],
   !.
expect_string(_) -->
   syntax_error(string_literal).

% syntax_error(+Expected): raises at the next token, which the token list
% always has since it ends in eof.
syntax_error(Expected) -->
   peek(tok(Kind, Value, Pos)),
   { found(Kind, Value, Found),
     throw(tdsl_syntax(Expected, Found, Pos))
   }.

found(kw, K, keyword(K)).
found(var, N, identifier(N)).
found(string, S, string(S)).
found(punct, P, punct(P)).
found(eof, _, end_of_file).

% --- messages --------------------------------------------------------------

:- multifile prolog:error_message//1.

prolog:error_message(syntax_error(tdsl(Expected, Found))) -->
   [ 'Syntax error: expected ' ],
   expected_message(Expected),
   [ ', found ' ],
   found_message(Found).

expected_message(keyword(K))       --> [ '`~w`'-[K] ].
expected_message(punct(P))         --> [ '`~w`'-[P] ].
expected_message(identifier)       --> [ 'an identifier' ].
expected_message(string_literal)   --> [ 'a string literal' ].
expected_message(type_expression)  --> [ 'a type expression' ].
expected_message(syntax_pattern)   --> [ 'a syntax pattern' ].
expected_message(statement)        --> [ 'a statement' ].
expected_message(subtype_operator) --> [ '`<:` or `:>`' ].
expected_message(option_name)      --> [ 'an option name' ].
expected_message(closing_quote(Q)) --> [ 'closing ~w of the string literal'-[Q] ].
expected_message(token)            --> [ 'a token' ].

found_message(keyword(K))    --> [ 'keyword `~w`'-[K] ].
found_message(identifier(N)) --> [ 'identifier `~w`'-[N] ].
found_message(string(S))     --> [ 'string ~q'-[S] ].
found_message(punct(P))      --> [ '`~w`'-[P] ].
found_message(char(C))       --> [ 'character ~q'-[C] ].
found_message(end_of_line)   --> [ 'end of line' ].
found_message(end_of_file)   --> [ 'end of file' ].
