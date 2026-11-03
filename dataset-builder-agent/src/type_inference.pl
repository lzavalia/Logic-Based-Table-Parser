% The type inference stage: type the cells of a dataset's papers by rule and
% choose each table's parse by its types (table_type_scorer.pl). Its output,
% papers/PMC<id>/type_inference.jsonl, is what the review works from, so
% review_agent.sh runs it first. It needs PCRE, so it runs outside DeepClause.
%
% From dataset-builder-agent/src/:
%   swipl type_inference.pl [--scorer=bit-cost|purity] [--level=family|group]
%                           [--papers=<ids>] [--program=<file.tdsl>]
%                           [--dataset=<dir>]
%
%   --scorer    bit-cost (the default) or purity
%   --level     compare types by family (the default) or by group
%   --papers    "all" (the default) or comma-separated PMC ids
%   --program   the type DSL program, by default type_dsl_examples/sci.tdsl
%   --dataset   the dataset, by default dataset/ in the working directory

:- use_module(library(main)).
:- use_module(table_review, [review_settings/5]).
:- use_module(table_type_abstraction).
:- use_module(table_type_scorer).

:- initialization(main, main).

opt_type(scorer, scorer, oneof(['bit-cost', purity])).
opt_type(level, level, oneof([family, group])).
opt_type(papers, papers, atom).
opt_type(program, program, atom).
opt_type(dataset, dataset, atom).

opt_help(scorer, "bit-cost (the default) or purity").
opt_help(level, "compare types by family (the default) or by group").
opt_help(papers, "all (the default) or comma-separated PMC ids").
opt_help(program, "the type DSL program").
opt_help(dataset, "the dataset directory").

main(Argv) :-
   argv_options(Argv, _, Options),
   option_value(Options, scorer, 'bit-cost', Scorer),
   option_value(Options, level, family, Level),
   option_value(Options, papers, all, PapersText),
   option_value(Options, program, '../type_dsl_examples/sci.tdsl', Program),
   option_value(Options, dataset, dataset, Dataset),
   paper_names(PapersText, Papers),
   type_dataset(Program, Dataset, Papers),
   score_dataset(Dataset, Papers, Scorer, Level),
   format("Type inference done (scorer ~w, level ~w).~n", [Scorer, Level]).

option_value(Options, Name, Default, Value) :-
   Option =.. [Name, Value0],
   (  memberchk(Option, Options) -> Value = Value0 ; Value = Default ).

paper_names(all, none) :- !.
paper_names(Text, Papers) :-
   atom_string(Text, String),
   review_settings(".", String, none, none, Settings),
   maplist(atom_string, Papers, Settings.papers).
