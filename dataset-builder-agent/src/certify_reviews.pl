% Writes the certificates of published reviews, without asking the model:
% for every paper of a dataset whose review of the arm is current, the
% certificate of every valid table whose selected candidate is labelable.
% Each one carries its checking kernel (table_certify.pl) and is checked by
% it before it is written.
%
% From dataset-builder-agent/src/:
%   swipl certify_reviews.pl --dataset=<dir> --arm=<arm> [--papers=<ids>]
%                            [--program=<file.tdsl>]
%
%   --dataset  the dataset, e.g. dataset or ablation/<name>/dataset
%   --arm      full: the full pipeline (arm C), whose review already wrote
%              the geometric certificates to papers/PMC<id>/; each is
%              written again with its typing section
%              (typed_certificates.pl). review_agent.sh runs this after
%              every full review.
%              constraints: arm B of the ablation study, written to
%              papers/PMC<id>/certificates.constraints/, without typing
%              (ablation_review:write_arm_certificates/4)
%   --papers   "all" (the default) or comma-separated PMC ids
%   --program  the type DSL program the types come from, for --arm=full;
%              by default ../type_dsl_examples/sci.tdsl
%
% A review is current when its tables_jsonl_sha256 is that of tables.jsonl
% (and, for the full arm, its type_inference_sha256 that of
% type_inference.jsonl). A paper without a review of the arm is left out;
% one whose review is not current, or a certificate the kernel rejects, is
% reported and left as it was, and the exit status is 1.

:- use_module(library(main)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(provenance_manifest, [file_sha256/2]).
:- use_module(table_review, [read_jsonl/2]).
:- use_module(ablation_review, [arm_files/3, arm_certificate_dir/2,
                                write_arm_certificates/4]).
:- use_module(dataset_pipeline, [is_certificate_file_name/1]).
:- use_module(type_guidelines, [guideline_program/2]).
:- use_module(typed_certificates, [write_typed_certificates/4]).

:- initialization(main, main).

opt_type(dataset, dataset, atom).
opt_type(arm, arm, atom).
opt_type(papers, papers, atom).
opt_type(program, program, atom).

opt_help(dataset, "the dataset directory").
opt_help(arm, "the arm whose reviews to certify: full or constraints").
opt_help(papers, "all (the default) or comma-separated PMC ids").
opt_help(program, "the type DSL program, for --arm=full").

main(Argv) :-
   argv_options(Argv, _, Options),
   required(Options, dataset, Dataset),
   required(Options, arm, Arm0),
   atom_string(Arm0, Arm),
   ( memberchk(papers(PapersText), Options) -> true ; PapersText = all ),
   directory_file_path(Dataset, papers, PapersDir),
   paper_names(PapersDir, PapersText, Names),
   (  Arm == "full"
   -> ( memberchk(program(Tdsl), Options) -> true
      ; Tdsl = '../type_dsl_examples/sci.tdsl' ),
      guideline_program(Tdsl, Program),
      foldl(type_paper(Program, Dataset, PapersDir), Names, 0-0, Papers-Stale)
   ;  arm_certificate_dir(Arm, _)
   -> foldl(certify_paper(PapersDir, Arm), Names, 0-0, Papers-Stale)
   ;  format(user_error, "error: --arm must be full or constraints, not ~w~n", [Arm0]),
      halt(2) ),
   format("~w: certificates of ~d paper(s) written, ~d paper(s) not current or rejected~n",
          [Arm, Papers, Stale]),
   (  Stale > 0 -> halt(1) ; true ).

required(Options, Name, Value) :-
   Option =.. [Name, Value],
   (  memberchk(Option, Options)
   -> true
   ;  format(user_error, "error: --~w is required~n", [Name]), halt(2) ).

paper_names(PapersDir, all, Names) :- !,
   directory_files(PapersDir, Entries),
   include(paper_entry, Entries, Names0),
   msort(Names0, Names).
paper_names(_, Text, Names) :-
   split_string(Text, ",", " ", Parts),
   exclude(==(""), Parts, Strings),
   maplist(atom_string, Names, Strings).

paper_entry(Entry) :-
   sub_atom(Entry, 0, _, _, 'PMC').

% type_paper(+Program, +Dataset, +PapersDir, +Name, +Counts0, -Counts)
type_paper(Program, Dataset, PapersDir, Name, Papers0-Stale0, Papers-Stale) :-
   directory_file_path(PapersDir, Name, PaperDir),
   write_typed_certificates(Program, Dataset, PaperDir, Result),
   (  Result = done(Written, [])
   -> length(Written, Count),
      format("~w: ~d typed certificate(s)~n", [Name, Count]),
      Papers is Papers0 + 1, Stale = Stale0
   ;  Result = done(Written, Failed)
   -> length(Written, Count),
      format("~w: ~d typed certificate(s)~n", [Name, Count]),
      forall(member(File-Why, Failed),
             format(user_error, "~w: ~w rejected, left as it was: ~q~n", [Name, File, Why])),
      Papers = Papers0, Stale is Stale0 + 1
   ;  Result = not_current(no_review)
   -> Papers = Papers0, Stale = Stale0
   ;  Result = not_current(Why),
      format(user_error, "~w: ~w; left as it is~n", [Name, Why]),
      Papers = Papers0, Stale is Stale0 + 1
   ).

% certify_paper(+PapersDir, +Arm, +Name, +Counts0, -Counts)
certify_paper(PapersDir, Arm, Name, Papers0-Stale0, Papers-Stale) :-
   directory_file_path(PapersDir, Name, PaperDir),
   arm_files(Arm, ReviewName, _),
   directory_file_path(PaperDir, ReviewName, ReviewFile),
   directory_file_path(PaperDir, 'tables.jsonl', TablesFile),
   (  exists_file(ReviewFile), exists_file(TablesFile)
   -> read_jsonl(TablesFile, Records),
      read_jsonl(ReviewFile, Reviews),
      file_sha256(TablesFile, Hash), atom_string(Hash, Sha),
      (  length(Records, N), length(Reviews, N),
         forall(member(Review, Reviews),
                ( get_dict(tables_jsonl_sha256, Review, Recorded),
                  atom_string(Recorded, Sha) ))
      -> write_arm_certificates(PaperDir, Arm, Records, Reviews),
         arm_certificate_dir(Arm, DirName),
         directory_file_path(PaperDir, DirName, Dir),
         directory_files(Dir, Entries),
         include(is_certificate_file_name, Entries, Written),
         length(Written, Count),
         format("~w: ~d certificate(s) in ~w/~n", [Name, Count, DirName]),
         Papers is Papers0 + 1, Stale = Stale0
      ;  format(user_error, "~w: ~w is not current for tables.jsonl; left as it is~n",
                [Name, ReviewName]),
         Papers = Papers0, Stale is Stale0 + 1 )
   ;  Papers = Papers0, Stale = Stale0 ).

