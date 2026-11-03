% Test fixture: a type_inference.jsonl for every paper of a dataset, so a test
% can decide what the review is given without running the scorer.

:- module(review_fixtures, [write_inference/2]).

:- if(exists_source(library(json))).
:- use_module(library(json)).
:- else.
:- use_module(library(http/json)).
:- endif.
:- use_module(library(apply)).
:- use_module(library(filesex)).
:- use_module(library(lists)).
:- use_module('../src/dataset_pipeline').
:- use_module('../src/provenance_manifest').

% write_inference(+Dataset, +Picks): Picks is [TableUid-CandidateId]. Every
% other table with candidates has its first candidate selected.
write_inference(Dataset, Picks) :-
   directory_file_path(Dataset, papers, PapersDir),
   directory_files(PapersDir, Names),
   forall(( member(Name, Names), sub_atom(Name, 0, 3, _, 'PMC'),
            \+ sub_atom(Name, _, _, _, '.'),
            directory_file_path(PapersDir, Name, Dir),
            directory_file_path(Dir, 'tables.jsonl', Tables),
            exists_file(Tables) ),
          paper_inference(Dir, Tables, Picks)).

paper_inference(Dir, Tables, Picks) :-
   dataset_pipeline:read_table_jsonl(Tables, Records),
   file_sha256(Tables, Hash), atom_string(Hash, Sha),
   directory_file_path(Dir, 'type_inference.jsonl', File),
   setup_call_cleanup(
      open(File, write, Out, [encoding(utf8)]),
      forall(member(Record, Records),
             ( inference(Picks, Sha, Record, Inference),
               json_write_dict(Out, Inference, [width(0)]), nl(Out) )),
      close(Out)).

inference(Picks, Sha, Record, Inference) :-
   Uid = Record.table_uid,
   (  memberchk(Uid-Id, Picks) -> Selected = Id
   ;  get_dict(candidates, Record, [First|_]) -> Selected = First.candidate_id
   ;  Selected = null ),
   (  Selected == null -> Status = "no_candidates" ; Status = "selected" ),
   Inference = json{table_uid:Uid, pmc_id:Record.pmc_id,
                    table_index:Record.table_index, scorer:"bit-cost",
                    types_file:"types.jsonl", tables_jsonl_sha256:Sha,
                    status:Status, selected_candidate_id:Selected,
                    selected_by:"score", margin:null, scores:[]}.
