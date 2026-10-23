% **input**: AbstractSyntaxTree (represent successfully parsed type dsl program)
% **output**: Analyzer (predicate that relates a string to a type atom)
% **output**: Guidelines (list of prompt-type pairs that will be used for later analysis)
%
% specification: the type_dsl_analyzer is a meta-programming engine that generates a prolog predicate
% that infers types for arbitrary text that comes from the cells of a table. The abstract abstract
% syntax tree is a list of statements in type DSL. The analyzer predicate should maintain local
% variables for some of these constructs. Below I will enumerate the mapping of statements to actions
% and any local variables used.
% |-------------------------------------------------|
% | Input Statement | Local Variables Used | Action |
% |-------------------------------------------------|
% | import FILENAME | NA | Open FILENAME and pass to type dsl parser then prepend to AbstractSyntaxTree |
% | set-option enable_caption_analysis | CaptionAnalysis (Boolean) | CaptionAnalysis = True |
% | type VARIABLE | BaseType (List) | append VARIABLE to BaseType |
% | type VARIABLE = TypeExpr | TypeAliases | append VARIABLE - TypExpr pair to TypeAliases |
% | TypeExpr <: TypeExpr | NA | call predicate `subtype_check` on lhs and rhs (not implemented, don't implement) |
% | guideline PROMPT decide TypeExpr | NA | append PROMPT - TypeExpr pair to Guidelines |
% | if SYNTAX_PATTERN decide TypeExpr | Rules | call `generate_pattern` on SYNTAX_PATTERN generating `syntax_pattern_predicate`, append syntax_pattern_predicate - TypeExpr pair to Rules |
% |-------------------------------------------------|
% The analyzer predicate should, in turn, accept as input a string and then check it against the rules, record which rules passed and then move then emit the type pair with the rule.
%
% --- implementation notes --------------------------------------------------
%
% From dataset-builder-agent/src/:
%   swipl -g 'use_module(type_dsl_engine),
%             tdsl_file_analyzer("../../type_dsl_examples/num.tdsl", A, _),
%             call(A, "3.14", Matches), print_term(Matches, [])' -t halt
%
%   type_dsl_analyzer_generator(+AST, -Analyzer, -Guidelines)
%   type_dsl_analyzer_generator(+AST, -Analyzer, -Guidelines, +Options)
%       AST is what type_dsl_parser produces: a list of stmt(Line, Statement).
%       Options:
%         base_dir(Dir)   directory that relative imports of AST resolve
%                         against (default: the working directory)
%         source(Source)  name for AST in rule origins (default: '<ast>')
%   tdsl_file_analyzer(+File, -Analyzer, -Guidelines)
%       Parses File and generates its analyzer; imports resolve against the
%       directory of File.
%   generate_pattern(+Pattern, -Predicate)
%       Compiles a syntax pattern into a closure: call(Predicate, Text)
%       succeeds, at most once, iff Text matches.
%   tdsl_analyzer_property(+Analyzer, ?Property)
%       caption_analysis(Bool), base_types(Names), type_aliases(Name-Type
%       pairs), subtypes(Sub-Super pairs), rules(rule(Origin, Pattern)-Type
%       pairs), in declaration order.
%
% The analyzer is a closure of arity 2: call(Analyzer, Text, Matches) runs
% every rule against Text (a string, atom or code list) and unifies Matches
% with the list of rule(Origin, Pattern)-Type pairs of the rules that passed,
% in rule order; [] when none did. Origin is Source:Line. Types and patterns
% keep the abstract syntax of type_dsl_parser (ref(Name), union(...), ...).
%
% Imports are included once: an import is expanded into the statements of
% the file (its own imports first), and a file already included, or one
% currently being included (a cycle), contributes nothing. As the
% specification says, imported statements are prepended: all of them come
% before the importing program's own statements, whatever the position of
% the import statement. An import inside an imported file resolves against
% that file's directory.
%
% Pattern semantics on the cell text, which is matched as given (not
% trimmed):
%   equals S    the text is exactly S
%   prefix S    the text starts with S
%   suffix S    the text ends with S
%   regex R     R (PCRE) matches the whole text, not just a substring
%   and/or/not  conjunction, disjunction, negation
%
% Declaring a type name twice (as a base type or an alias) raises
%   error(tdsl_error(duplicate_type(Name), Origin), _)
% Rules and guidelines may decide undeclared types, as text.tdsl does.

:- module(type_dsl_engine,
          [ type_dsl_analyzer_generator/3,
            type_dsl_analyzer_generator/4,
            tdsl_file_analyzer/3,
            generate_pattern/2,
            tdsl_analyzer_property/2
          ]).

:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(option)).
:- use_module(library(pcre)).
:- use_module(type_dsl_parser).

% --- entry points ----------------------------------------------------------

type_dsl_analyzer_generator(AbstractSyntaxTree, Analyzer, Guidelines) :-
   type_dsl_analyzer_generator(AbstractSyntaxTree, Analyzer, Guidelines, []).

type_dsl_analyzer_generator(AbstractSyntaxTree, Analyzer, Guidelines, Options) :-
   option(base_dir(BaseDir0), Options, '.'),
   option(source(Source), Options, '<ast>'),
   absolute_file_name(BaseDir0, BaseDir, [file_type(directory)]),
   % A file analyzed directly is already included, should it import itself.
   (  atom(Source), exists_file(Source)
   -> absolute_file_name(Source, Path), Seen0 = [Path]
   ;  Seen0 = []
   ),
   expand_imports(AbstractSyntaxTree, Source, BaseDir, Seen0, _, Statements),
   foldl(statement, Statements, state(false, [], [], [], [], []), State),
   State = state(CaptionAnalysis, BaseTypes0, Aliases0, Subtypes0,
                 Guidelines0, Rules0),
   maplist(reverse, [BaseTypes0, Aliases0, Subtypes0, Guidelines0, Rules0],
                    [BaseTypes, Aliases, Subtypes, Guidelines, Rules]),
   Analyzer = type_dsl_engine:analyze(
                 tdsl_program(CaptionAnalysis, BaseTypes, Aliases, Subtypes,
                              Rules)).

tdsl_file_analyzer(File, Analyzer, Guidelines) :-
   absolute_file_name(File, Path, [access(read)]),
   parse_tdsl_file(Path, AST),
   file_directory_name(Path, Dir),
   type_dsl_analyzer_generator(AST, Analyzer, Guidelines,
                               [base_dir(Dir), source(Path)]).

tdsl_analyzer_property(type_dsl_engine:analyze(Program), Property) :-
   program_property(Property, Program).

program_property(caption_analysis(C), tdsl_program(C, _, _, _, _)).
program_property(base_types(B), tdsl_program(_, B, _, _, _)).
program_property(type_aliases(A), tdsl_program(_, _, A, _, _)).
program_property(subtypes(S), tdsl_program(_, _, _, S, _)).
program_property(rules(Summary), tdsl_program(_, _, _, _, Rules)) :-
   findall(rule(Origin, Pattern)-Type,
           member(rule(Origin, Pattern, _, Type), Rules),
           Summary).

% --- imports ---------------------------------------------------------------

% expand_imports(+AST, +Source, +BaseDir, +Seen0, -Seen, -Statements)
% Statements are src(Origin, Statement) with every import replaced by the
% statements of the imported file, all of them ahead of the local ones.
% Seen holds the absolute paths of files included or being included.
expand_imports(AST, Source, BaseDir, Seen0, Seen, Statements) :-
   partition(is_import, AST, Imports, Locals),
   foldl(import(BaseDir), Imports, []-Seen0, Imported-Seen),
   findall(src(Source:Line, S), member(stmt(Line, S), Locals), Own),
   append(Imported, Own, Statements).

is_import(stmt(_, import(_))).

% import(+BaseDir, +Import, +Acc0-Seen0, -Acc-Seen)
import(BaseDir, stmt(_, import(File)), Acc0-Seen0, Acc-Seen) :-
   absolute_file_name(File, Path,
                      [relative_to(BaseDir), access(read)]),
   (  memberchk(Path, Seen0)
   -> Acc = Acc0, Seen = Seen0
   ;  parse_tdsl_file(Path, AST),
      file_directory_name(Path, Dir),
      expand_imports(AST, Path, Dir, [Path|Seen0], Seen, Statements),
      append(Acc0, Statements, Acc)
   ).

% --- statements ------------------------------------------------------------

% statement(+Src, +State0, -State)
% State is state(CaptionAnalysis, BaseTypes, Aliases, Subtypes, Guidelines,
% Rules), the lists in reverse order of declaration. statement/4 takes the
% statement first so that first-argument indexing keeps the fold
% deterministic.
statement(src(Origin, Statement), State0, State) :-
   statement(Statement, Origin, State0, State).

statement(option(enable_caption_analysis), _,
          state(_, B, A, S, G, R), state(true, B, A, S, G, R)).
statement(type_decl(Name), Origin,
          state(C, B, A, S, G, R), state(C, [Name|B], A, S, G, R)) :-
   fresh_type(Name, Origin, B, A).
statement(type_decl(Name, Type), Origin,
          state(C, B, A, S, G, R), state(C, B, [Name-Type|A], S, G, R)) :-
   fresh_type(Name, Origin, B, A).
% Recorded for subtype_check, which is not implemented yet.
statement(subtype(Sub, Super), _,
          state(C, B, A, S, G, R), state(C, B, A, [Sub-Super|S], G, R)).
statement(guideline(Prompt, Type), _,
          state(C, B, A, S, G, R), state(C, B, A, S, [Prompt-Type|G], R)).
statement(rule(Pattern, Type), Origin,
          state(C, B, A, S, G, R),
          state(C, B, A, S, G, [rule(Origin, Pattern, Predicate, Type)|R])) :-
   generate_pattern(Pattern, Predicate).

fresh_type(Name, Origin, BaseTypes, Aliases) :-
   (  ( memberchk(Name, BaseTypes) ; memberchk(Name-_, Aliases) )
   -> throw(error(tdsl_error(duplicate_type(Name), Origin), _))
   ;  true
   ).

% --- syntax patterns -------------------------------------------------------

generate_pattern(Pattern, type_dsl_engine:match_pattern(Text, Goal)) :-
   pattern_goal(Pattern, Text, Goal).

% pattern_goal(+Pattern, ?Text, -Goal): Goal succeeds iff the string bound
% to Text matches Pattern. Regexes are compiled here, once.
pattern_goal(and(P, Q), Text, (G1, G2)) :-
   pattern_goal(P, Text, G1),
   pattern_goal(Q, Text, G2).
pattern_goal(or(P, Q), Text, (G1 ; G2)) :-
   pattern_goal(P, Text, G1),
   pattern_goal(Q, Text, G2).
pattern_goal(not(P), Text, \+ G) :-
   pattern_goal(P, Text, G).
pattern_goal(equals(S), Text, Text == S).
pattern_goal(prefix(S), Text, string_concat(S, _, Text)).
pattern_goal(suffix(S), Text, string_concat(_, S, Text)).
pattern_goal(regex(R), Text, pcre:re_match(Regex, Text)) :-
   string_concat("\\A(?:", R, Open),
   string_concat(Open, ")\\z", Anchored),
   re_compile(Anchored, Regex, []).

match_pattern(Var, Goal, Text) :-
   text_to_string(Text, String),
   copy_term(Var-Goal, String-Instance),
   once(Instance).

% --- the analyzer ----------------------------------------------------------

analyze(tdsl_program(_, _, _, _, Rules), Text, Matches) :-
   text_to_string(Text, String),
   findall(rule(Origin, Pattern)-Type,
           ( member(rule(Origin, Pattern, Predicate, Type), Rules),
             call(Predicate, String)
           ),
           Matches).

% --- messages --------------------------------------------------------------

:- multifile prolog:error_message//1.

prolog:error_message(tdsl_error(duplicate_type(Name), Source:Line)) -->
   [ '~w:~w: type `~w` is already declared'-[Source, Line, Name] ].
