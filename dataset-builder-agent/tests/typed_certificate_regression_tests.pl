% Typed certificates through the whole full pipeline, without network or
% LLM: the paper is built (process_paper/4), typed by rule
% (type_dataset/3), its guideline answers are given in the answer cache and
% applied (apply_guidelines/4), type inference selects a candidate
% (score_dataset/3), the review's answers are given to review_answer/4, and
% typed_certificates.pl then writes the certificate with its typing.
%
% From dataset-builder-agent/tests/:
%   swipl -q -s typed_certificate_regression_tests.pl -g run_tests -t halt

:- use_module(library(plunit)).
:- use_module(library(filesex)).
:- use_module(library(readutil)).
:- use_module(library(process)).
:- if(exists_source(library(json))).
:- use_module(library(json)).
:- else.
:- use_module(library(http/json)).
:- endif.
:- use_module('../src/dataset_pipeline').
:- use_module('../src/table_review').
:- use_module('../src/table_type_abstraction').
:- use_module('../src/table_type_scorer').
:- use_module('../src/type_guidelines').
:- use_module('../src/typed_certificates').
:- use_module('../src/certificate_kernel').

% PMC906, one table:
%   Drug         Dose      Word, Word      routed with [Label]
%   Placebo arm  10        untyped, Integer   routed with [Label, Arm]; not
%   Aspirin      20        Word, Integer      routed; not
% The cache answers Drug -> Label, Placebo arm -> Arm and Dose -> none;
% Aspirin has no answer.
program_text("type Numeric
type Integer
Integer <: Numeric
type Text
type Word
Word <: Text
type Label
Label <: Word
if regex \"[0-9]+\" decide Integer
if regex \"\\p{L}+\" decide Word
guideline \"a label naming a column or row\" decide Label
guideline \"a treatment arm\" decide Arm
").

typed_workspace(Root) :-
   tmp_file(typed_certificates, Root), make_directory(Root),
   directory_file_path(Root, dataset, Dataset),
   make_directory(Dataset),
   directory_file_path(Root, 'input.xml', Input),
   write_text(Input,
      '<article><front><article-meta><article-id pub-id-type="pmc">906</article-id></article-meta></front><body><table-wrap><label>Table 1</label><caption><p>Doses</p></caption><table><tr><th>Drug</th><th>Dose</th></tr><tr><td>Placebo arm</td><td>10</td></tr><tr><td>Aspirin</td><td>20</td></tr></table></table-wrap></body></article>'),
   process_paper("906", Input, Dataset, _),
   program_file(Root, Tdsl),
   program_text(Text),
   write_text(Tdsl, Text),
   type_dataset(Tdsl, Dataset, none),
   program_sha256(Tdsl, Sha),
   directory_file_path(Dataset, cache, CacheDir),
   make_directory(CacheDir),
   directory_file_path(CacheDir, 'guideline_answers.jsonl', Cache),
   setup_call_cleanup(
      open(Cache, write, Out, [encoding(utf8)]),
      forall(member(T-R-A, ["Drug"-"Word"-"Label", "Placebo arm"-"untyped"-"Arm",
                            "Dose"-"Word"-"none"]),
             ( json_write_dict(Out, json{program_sha256:Sha, text:T, rule_type:R,
                                         caption:null, answer:A,
                                         batch_id:"PMC906/1"}, [width(0)]),
               nl(Out) )),
      close(Out)),
   apply_guidelines(Tdsl, Dataset, none, _),
   score_dataset(Dataset, none, 'bit-cost'),
   review(Root).

typed_cleanup(Root) :-
   ( exists_directory(Root) -> delete_directory_and_contents(Root) ; true ).

write_text(File, Text) :-
   setup_call_cleanup(open(File, write, Out, [encoding(utf8)]),
                      write(Out, Text), close(Out)).

program_file(Root, File) :- directory_file_path(Root, 't.tdsl', File).

paper_dir(Root, Dir) :- directory_file_path(Root, 'dataset/papers/PMC906', Dir).

% The model gives (1, 1), the drug column under the header row.
review(Root) :-
   review_settings(Root, none, none, "test:model", S),
   directory_file_path(Root, dataset, Dataset),
   review_queue(Dataset, S, [Paper], _),
   review_paper_items(Paper, Items),
   findall(R, ( member(Item, Items),
                review_answer(Item, json{parse_correct:false, column_header_rows:1,
                                         row_header_columns:1, reason:"test"},
                              1, done(R)) ),
           Results),
   publish_paper_review(Dataset, Paper, S, Results, _).

write_typed(Root, Result) :-
   program_file(Root, Tdsl),
   guideline_program(Tdsl, Program),
   directory_file_path(Root, dataset, Dataset),
   paper_dir(Root, Dir),
   write_typed_certificates(Program, Dataset, Dir, Result).

certificate_facts(Root, Facts) :-
   paper_dir(Root, Dir),
   directory_file_path(Dir, 'certificate0_h1_v1.pl', File),
   read_certificate_file(File, Facts).

text_type(Facts, Text, Type, Derivation) :-
   member(cell_text(Id, Text), Facts),
   member(cell_type(Id, Type, Derivation), Facts), !.

:- begin_tests(typed_certificates).

test(review_writes_the_geometric_certificate_without_typing,
     [setup(typed_workspace(Root)), cleanup(typed_cleanup(Root))]) :-
   certificate_facts(Root, Facts),
   assertion(\+ memberchk(typing_version(_), Facts)),
   assertion(memberchk(checking_kernel(_, _), Facts)).

test(typed_certificate_says_how_each_cell_was_typed,
     [setup(typed_workspace(Root)), cleanup(typed_cleanup(Root))]) :-
   write_typed(Root, Result),
   assertion(Result == done(['certificate0_h1_v1.pl'], [])),
   certificate_facts(Root, Facts),
   assertion(check_certificate(Facts, accepted)),
   assertion(memberchk(typing_version(1), Facts)),
   assertion(memberchk(type_rule(0, "t.tdsl:9", regex("[0-9]+"), 'Integer'), Facts)),
   assertion(memberchk(guideline(1, "a treatment arm", 'Arm'), Facts)),
   assertion(text_type(Facts, "Drug", 'Label', guideline("PMC906/1"))),
   assertion(text_type(Facts, "Placebo arm", 'Arm', guideline("PMC906/1"))),
   assertion(text_type(Facts, "Dose", 'Word', guideline_none("PMC906/1"))),
   assertion(text_type(Facts, "Aspirin", 'Word', guideline_pending)),
   assertion(text_type(Facts, "10", 'Integer', rules)),
   % The certificate checks itself, with the kernel it carries, and reports
   % the typing.
   paper_dir(Root, Dir),
   directory_file_path(Dir, 'certificate0_h1_v1.pl', File),
   current_prolog_flag(executable, Swipl),
   process_create(Swipl, ['-q', File], [stdout(pipe(Out)), stderr(null), process(Pid)]),
   read_string(Out, _, Output), close(Out),
   process_wait(Pid, exit(Status)),
   assertion(Status == 0),
   assertion(once(sub_string(Output, _, _, _, "2 typed by a model"))),
   assertion(once(sub_string(Output, _, _, _, "1 kept at the rule type by a model, 1 routed"))).

% A types file that disagrees with the rules is caught by the kernel: the
% certificate is left as the review wrote it.
test(types_the_rules_do_not_give_are_rejected,
     [setup(typed_workspace(Root)), cleanup(typed_cleanup(Root))]) :-
   paper_dir(Root, Dir),
   directory_file_path(Dir, 'guided_types.jsonl', Guided),
   read_file_to_string(Guided, Text0, [encoding(utf8)]),
   re_replace("\"type\":\"Integer\""/g, "\"type\":\"Numeric\"", Text0, Text),
   write_text(Guided, Text),
   write_typed(Root, done([], ['certificate0_h1_v1.pl'-Why])),
   assertion(Why = invalid_certificate(_)),
   certificate_facts(Root, Facts),
   assertion(\+ memberchk(typing_version(_), Facts)),
   assertion(check_certificate(Facts, accepted)).

test(a_review_older_than_its_types_is_not_certified,
     [setup(typed_workspace(Root)), cleanup(typed_cleanup(Root))]) :-
   paper_dir(Root, Dir),
   directory_file_path(Dir, 'type_inference.jsonl', Inference),
   read_file_to_string(Inference, Text, [encoding(utf8)]),
   string_concat(Text, "\n", Changed),
   write_text(Inference, Changed),
   write_typed(Root, Result),
   assertion(Result == not_current(review_predates_tables_or_types)).

test(certify_reviews_writes_the_typed_certificates,
     [setup(typed_workspace(Root)), cleanup(typed_cleanup(Root))]) :-
   directory_file_path(Root, dataset, Dataset),
   program_file(Root, Tdsl),
   current_prolog_flag(executable, Swipl),
   atom_concat('--dataset=', Dataset, DatasetArg),
   atom_concat('--program=', Tdsl, ProgramArg),
   process_create(Swipl, ['certify_reviews.pl', DatasetArg, '--arm=full', ProgramArg],
                  [cwd('../src'), stdout(null), stderr(null), process(Pid)]),
   process_wait(Pid, exit(Status)),
   assertion(Status == 0),
   certificate_facts(Root, Facts),
   assertion(memberchk(typing_version(1), Facts)).

:- end_tests(typed_certificates).
