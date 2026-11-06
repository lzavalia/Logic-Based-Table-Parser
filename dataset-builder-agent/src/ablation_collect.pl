% Collects the outcome of every arm of an ablation run, table by table, as
% segmentations that can be compared with the gold label (see
% experiments/ablation/README.md). It calls no LLM.
%
% From dataset-builder-agent/src/:
%   swipl ablation_collect.pl --dataset=<dir> --sample=<jsonl> --gold=<jsonl>
%                             [--arms=llm-only,constraints,full] [--calls=<dir>]
%                             --output=<jsonl>
%
%   --dataset  the dataset the arms were run on (src/ablation/<name>/dataset)
%   --sample   the sample (experiments/ablation/make_sample.py)
%   --gold     one line per table: table_uid and gold_candidate, a candidate id
%              of the table's tables.jsonl
%   --arms     the arms to collect, by default all three
%   --calls    the run's results directory: read each table's review and
%              export from its call's copy, <dir>/<arm>/<PMC>_t<N>/, rather
%              than from the paper's directory, where a later call on
%              another table of the paper replaces them
%   --output   one JSON line per table and arm
%
% Each line has the arm's verdict (final_status, decided_by, the selected
% candidate) and three segmentations in the form of ablation_review.pl
% ({separator_rows, subtables}):
%
%   gold_segmentation      the gold candidate's
%   accepted_segmentation  what the arm outputs: for a valid table, the
%                          segmentation it was exported at (for a table the
%                          full arm repaired, the repaired candidate's);
%                          null otherwise
%   llm_segmentation       the model's own answer, also when the arm refused
%                          it. The full arm's model gives only (H, V) when it
%                          rejects the proposal, read as one subtable of the
%                          whole table; when it confirms, its answer is the
%                          proposal.
%
% accepted_correct and llm_correct compare them with the gold (null when
% there is nothing to compare), and export_error is that of the arm's
% final_tables file.

:- use_module(library(main)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- if(exists_source(library(json))).
:- use_module(library(json)).
:- else.
:- use_module(library(http/json)).
:- endif.
:- use_module(table_review, [read_jsonl/2]).
:- use_module(ablation_review, [candidate_segmentation/3, segmentation_json/2,
                                arm_files/3]).
:- use_module(dataset_pipeline, [reviewed_record/3]).

:- initialization(main, main).

opt_type(dataset, dataset, atom).
opt_type(sample, sample, atom).
opt_type(gold, gold, atom).
opt_type(arms, arms, atom).
opt_type(calls, calls, atom).
opt_type(output, output, atom).

main(Argv) :-
   argv_options(Argv, _, Options),
   required(Options, dataset, Dataset),
   required(Options, sample, SampleFile),
   required(Options, gold, GoldFile),
   required(Options, output, Output),
   ( memberchk(arms(ArmsText), Options) -> true ; ArmsText = 'llm-only,constraints,full' ),
   split_string(ArmsText, ",", " ", Arms),
   ( memberchk(calls(Calls), Options) -> true ; Calls = none ),
   read_jsonl(SampleFile, Sample),
   read_jsonl(GoldFile, Gold),
   setup_call_cleanup(
      open(Output, write, Out, [encoding(utf8)]),
      forall(( member(Row, Sample), member(Arm, Arms) ),
             ( collect(Dataset, Calls, Gold, Row, Arm, Line),
               json_write_dict(Out, Line, [width(0)]), nl(Out) )),
      close(Out)),
   length(Sample, N), length(Arms, A),
   format("~d table(s) x ~d arm(s) collected -> ~w~n", [N, A, Output]).

required(Options, Name, Value) :-
   Option =.. [Name, Value],
   (  memberchk(Option, Options)
   -> true
   ;  format(user_error, "error: --~w is required~n", [Name]), halt(2) ).

% collect(+Dataset, +Calls, +Gold, +SampleRow, +Arm, -Line)
collect(Dataset, Calls, Gold, Row, Arm, Line) :-
   get_dict(table_uid, Row, Uid),
   paper_dir(Dataset, Row, PaperDir),
   directory_file_path(PaperDir, 'tables.jsonl', TablesFile),
   read_jsonl(TablesFile, Records),
   member(Record, Records), get_dict(table_uid, Record, Uid), !,
   gold_segmentation(Gold, Uid, Record, GoldId, GoldSeg),
   arm_review_files(Arm, ReviewName, ExportName),
   review_dir(Calls, PaperDir, Arm, Uid, ReviewDir),
   directory_file_path(ReviewDir, ReviewName, ReviewFile),
   (  exists_file(ReviewFile),
      read_jsonl(ReviewFile, Reviews),
      member(Review, Reviews), get_dict(table_uid, Review, Uid)
   -> arm_segmentations(Arm, Record, Review, Accepted, Llm),
      export_error(ReviewDir, ExportName, Record, ExportError),
      Fields = json{review_status:Review.review_status,
                    final_status:Review.final_status,
                    decided_by:Review.decided_by,
                    selected_candidate_id:Review.selected_candidate_id,
                    not_reviewed_reason:Reason,
                    model:Review.model, prompt_version:Review.prompt_version,
                    export_error:ExportError},
      ( get_dict(not_reviewed_reason, Review, Reason) -> true ; Reason = null )
   ;  Accepted = none, Llm = none,
      Fields = json{review_status:"missing", final_status:null, decided_by:null,
                    selected_candidate_id:null, not_reviewed_reason:null,
                    model:null, prompt_version:null, export_error:null} ),
   seg_out(Accepted, AcceptedJson),
   seg_out(Llm, LlmJson),
   seg_out(GoldSeg, GoldJson),
   seg_correct(Accepted, GoldSeg, AcceptedCorrect),
   seg_correct(Llm, GoldSeg, LlmCorrect),
   put_dict(Fields,
            json{table_uid:Uid, set:Row.set, complexity:Row.complexity,
                 arm:Arm, gold_candidate:GoldId,
                 gold_segmentation:GoldJson,
                 accepted_segmentation:AcceptedJson,
                 llm_segmentation:LlmJson,
                 accepted_correct:AcceptedCorrect, llm_correct:LlmCorrect},
            Line).

paper_dir(Dataset, Row, PaperDir) :-
   directory_file_path(Dataset, papers, PapersDir),
   get_dict(pmc_id, Row, Pmc0), atom_string(Pmc, Pmc0),
   directory_file_path(PapersDir, Pmc, PaperDir).

% review_dir(+Calls, +PaperDir, +Arm, +Uid, -Dir): where the table's review
% and export are read from.
review_dir(none, PaperDir, _, _, PaperDir) :- !.
review_dir(Calls, _, Arm, Uid, Dir) :-
   split_string(Uid, "/", "", Parts),
   atomic_list_concat(Parts, '_', Call),
   atomic_list_concat([Calls, Arm, Call], '/', Dir).

gold_segmentation(Gold, Uid, Record, GoldId, Seg) :-
   (  member(G, Gold), get_dict(table_uid, G, Uid),
      get_dict(gold_candidate, G, GoldId), GoldId \== null,
      member(C, Record.candidates), C.candidate_id == GoldId
   -> candidate_segmentation(Record, C, Seg)
   ;  GoldId = null, Seg = none ).

arm_review_files("full", 'review.jsonl', 'final_tables.json') :- !.
arm_review_files(Arm, ReviewName, ExportName) :-
   arm_files(Arm, ReviewName, ExportName).

% arm_segmentations(+Arm, +Record, +Review, -Accepted, -Llm)
arm_segmentations("full", Record, Review, Accepted, Llm) :- !,
   (  Review.final_status == "valid"
   -> reviewed_record(Record, Review, Effective),
      Id = Review.selected_candidate_id,
      member(C, Effective.candidates), C.candidate_id == Id, !,
      candidate_segmentation(Effective, C, Accepted)
   ;  Accepted = none ),
   (  Accepted \== none, Review.decided_by == "llm"
   -> Llm = Accepted
   ;  get_dict(llm_boundary, Review, B), is_dict(B)
   -> LastRow is Record.rows - 1, LastColumn is Record.columns - 1,
      Llm = seg([], [sub(0, LastRow, 0, LastColumn, B.hmd, B.vmd)])
   ;  Llm = none ).
arm_segmentations(_, _, Review, Accepted, Llm) :-
   (  get_dict(segmentation, Review, Json), Json \== null
   -> segmentation_json(Llm, Json)
   ;  Llm = none ),
   ( Review.final_status == "valid" -> Accepted = Llm ; Accepted = none ).

export_error(PaperDir, ExportName, Record, Error) :-
   directory_file_path(PaperDir, ExportName, File),
   (  exists_file(File),
      setup_call_cleanup(open(File, read, In, [encoding(utf8)]),
                         json_read_dict(In, Json, [default_tag(json)]),
                         close(In)),
      member(E, Json.tables), E.table_index =:= Record.table_index
   -> Error = E.export_error
   ;  Error = "no export entry" ).

seg_out(none, null) :- !.
seg_out(Seg, Json) :- segmentation_json(Seg, Json).

seg_correct(none, _, null) :- !.
seg_correct(_, none, null) :- !.
seg_correct(A, B, Correct) :- ( A == B -> Correct = true ; Correct = false ).
