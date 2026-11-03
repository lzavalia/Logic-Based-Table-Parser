% The stages of the guideline step that run in SWI-Prolog, as commands for
% guideline_agent.sh (type_guidelines.pl has the whole picture). They need
% PCRE and OpenSSL, so they run outside DeepClause.
%
% From dataset-builder-agent/src/:
%   swipl guideline_steps.pl run-papers <run name>
%       Prints the comma-separated PMC ids the build run selected.
%   swipl guideline_steps.pl prepare <program.tdsl> <papers>
%       Types the papers by rule and writes their guideline_requests.json.
%   swipl guideline_steps.pl apply <program.tdsl> <papers>
%       Writes their guided_types.jsonl.
%
% <papers> is "all" or comma-separated paper names. The dataset is dataset/ in
% the working directory.

:- use_module(library(main)).
:- use_module(library(apply)).
:- use_module(table_review, [review_run_papers/3]).
:- use_module(table_type_abstraction).
:- use_module(type_guidelines).

:- initialization(main, main).

main(['run-papers', Run]) :- !,
   review_run_papers("dataset", Run, Papers),
   writeln(Papers).
main([prepare, Program, Papers0]) :- !,
   papers(Papers0, Papers),
   type_dataset(Program, "dataset", Papers),
   guideline_requests(Program, "dataset", Papers, Summary),
   writeln(Summary).
main([apply, Program, Papers0]) :- !,
   papers(Papers0, Papers),
   apply_guidelines(Program, "dataset", Papers, Summary),
   writeln(Summary).
main(Argv) :-
   format(user_error, "usage: unknown command ~q~n", [Argv]),
   halt(2).

papers(all, none) :- !.
papers(Text, Papers) :-
   split_string(Text, ",", " ", Parts0),
   exclude(==(""), Parts0, Parts),
   maplist(atom_string, Papers, Parts).
