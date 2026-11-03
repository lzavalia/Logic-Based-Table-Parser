% Explain, without an LLM, why boundaries are not among the parser's
% candidates (boundary_explainer.pl).
%
% From dataset-builder-agent/src/:
%   swipl explain_disagreements.pl [--dataset=<dir>] [--papers=<ids>]
%                                  [--output=<file.jsonl>]
%   swipl explain_disagreements.pl --targets=<file.jsonl> [--dataset=<dir>]
%                                  [--output=<file.jsonl>]
%
%   --dataset   the dataset, by default dataset/ in the working directory
%   --papers    "all" (the default) or comma-separated PMC ids
%   --targets   boundaries to explain instead of the reviews' (see below)
%   --output    where to write the explanations, by default standard output
%
% Without --targets, every review in papers/PMC<id>/review.jsonl that ended
% unparseable with a boundary from the model is explained. Reviews made
% before review.jsonl carried a disagreement get one this way without asking
% the model again; review.jsonl itself is not changed.
%
% With --targets, each line {table_uid, hmd, vmd} names a table of the
% dataset and a boundary for it, such as a gold label. A line whose hmd is
% null has no single boundary and is only counted, as excluded.
%
% Each explained table is one JSON line {table_uid, source, boundary,
% explanation, repair}, source being "review" or "target", repair that of
% table_repair.pl. The counts by category, by broken rule and by repair
% status follow, on standard error.

:- use_module(library(main)).
:- if(exists_source(library(json))).
:- use_module(library(json)).
:- else.
:- use_module(library(http/json)).
:- endif.
:- use_module(library(readutil)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(pairs)).
:- use_module(library(filesex)).
:- use_module(dataset_pipeline, [explain_boundary/5, repair_boundary/4]).
:- use_module(table_review, [candidate_boundaries/2]).

:- initialization(main, main).

opt_type(dataset, dataset, atom).
opt_type(papers, papers, atom).
opt_type(targets, targets, atom).
opt_type(output, output, atom).

opt_help(dataset, "the dataset directory").
opt_help(papers, "all (the default) or comma-separated PMC ids").
opt_help(targets, "JSONL of {table_uid, hmd, vmd} to explain").
opt_help(output, "the JSONL file to write, by default standard output").

main(Argv) :-
   argv_options(Argv, _, Options),
   option_value(Options, dataset, dataset, Dataset),
   option_value(Options, papers, all, Papers),
   (  memberchk(targets(Targets), Options)
   -> target_items(Dataset, Targets, Items, Excluded)
   ;  review_items(Dataset, Papers, Items), Excluded = 0 ),
   maplist(explained_line, Items, Lines),
   (  memberchk(output(Output), Options)
   -> setup_call_cleanup(open(Output, write, Out, [encoding(utf8)]),
                         write_lines(Out, Lines), close(Out))
   ;  write_lines(user_output, Lines) ),
   report_counts(Lines, Excluded).

option_value(Options, Name, Default, Value) :-
   Option =.. [Name, Value0],
   (  memberchk(Option, Options) -> Value = Value0 ; Value = Default ).

% item(TableUid, Source, Record, Hmd, Vmd)
review_items(Dataset, Papers, Items) :-
   directory_file_path(Dataset, papers, PapersDir),
   directory_files(PapersDir, Entries0),
   msort(Entries0, Entries),
   findall(Item,
           ( member(Name, Entries), sub_atom(Name, 0, _, _, 'PMC'),
             paper_selected(Papers, Name),
             directory_file_path(PapersDir, Name, PaperDir),
             directory_file_path(PaperDir, 'review.jsonl', ReviewFile),
             exists_file(ReviewFile),
             directory_file_path(PaperDir, 'tables.jsonl', TablesFile),
             read_jsonl(TablesFile, Records),
             read_jsonl(ReviewFile, Reviews),
             member(Review, Reviews),
             Review.final_status == "unparseable",
             is_dict(Review.llm_boundary),
             nth0(Review.table_index, Records, Record),
             Item = item(Record.table_uid, "review", Record,
                         Review.llm_boundary.hmd, Review.llm_boundary.vmd) ),
           Items).

paper_selected(all, _) :- !.
paper_selected(Papers, Name) :-
   atomic_list_concat(Ids, ',', Papers),
   member(Id0, Ids), normalize_space(atom(Id), Id0),
   ( Id == Name ; atom_concat('PMC', Id, Name) ), !.

target_items(Dataset, Targets, Items, Excluded) :-
   read_jsonl(Targets, Lines),
   partition([T]>>get_dict(hmd, T, null), Lines, Skipped, Kept),
   length(Skipped, Excluded),
   maplist(target_item(Dataset), Kept, Items).

target_item(Dataset, Target, item(Uid, "target", Record, Target.hmd, Target.vmd)) :-
   text_to_string(Target.table_uid, Uid),
   split_string(Uid, "/", "", [Paper, TableText]),
   sub_string(TableText, 1, _, 0, IndexText),
   number_string(Index, IndexText),
   directory_file_path(Dataset, papers, PapersDir),
   directory_file_path(PapersDir, Paper, PaperDir),
   directory_file_path(PaperDir, 'tables.jsonl', TablesFile),
   (  exists_file(TablesFile)
   -> read_jsonl(TablesFile, Records),
      nth0(Index, Records, Record)
   ;  throw(error(existence_error(table, Uid), _)) ).

explained_line(item(Uid, Source, Record, Hmd, Vmd),
               json{table_uid:Uid, source:Source,
                    boundary:json{hmd:Hmd, vmd:Vmd}, explanation:Explanation,
                    repair:Repair}) :-
   candidate_boundaries(Record, Candidates),
   explain_boundary(Record, Candidates, Hmd, Vmd, Explanation),
   repair_boundary(Record, Hmd, Vmd, Repair).

write_lines(Out, Lines) :-
   forall(member(Line, Lines),
          ( json_write_dict(Out, Line, [width(0)]), nl(Out) )).

% Counts by category of the explanation (its first broken rule), and of the
% tables that break each rule at all.
report_counts(Lines, Excluded) :-
   length(Lines, N),
   format(user_error, "~d table(s) explained, ~d excluded (no single boundary).~n",
          [N, Excluded]),
   findall(C, ( member(L, Lines), C = L.explanation.category ), Cats),
   counts(Cats, CatCounts),
   format(user_error, "By category (first broken rule):~n", []),
   forall(member(C-K, CatCounts), format(user_error, "  ~w~t~40|~d~n", [C, K])),
   findall(R, ( member(L, Lines), Rules = L.explanation.violations,
                findall(R0, ( member(V, Rules), R0 = V.rule, R0 \== null ), Rs0),
                sort(Rs0, Rs), member(R, Rs) ),
           AllRules),
   counts(AllRules, RuleCounts),
   format(user_error, "Tables breaking each rule:~n", []),
   forall(member(R-K, RuleCounts), format(user_error, "  rule ~w~t~40|~d~n", [R, K])),
   findall(C-S, ( member(L, Lines), C = L.explanation.category, S = L.repair.status ),
           Pairs),
   counts(Pairs, RepairCounts),
   format(user_error, "Repair status by category:~n", []),
   forall(member((C-S)-K, RepairCounts),
          format(user_error, "  ~w, ~w~t~60|~d~n", [C, S, K])).

counts(Items, Counts) :-
   msort(Items, Sorted),
   clumped(Sorted, Counts).

read_jsonl(File, Dicts) :-
   read_file_to_string(File, Text, [encoding(utf8)]),
   split_string(Text, "\n", "\r", Lines0),
   exclude(==(""), Lines0, Lines),
   maplist([L, D]>>atom_json_dict(L, D, [default_tag(json)]), Lines, Dicts).
