% Offline boundary-search microbenchmark. No external services.
% Run: swipl -q -s benchmark_boundaries.pl -g run_benchmark -t halt
% Produces CSV of size, candidate count, time and Prolog global-stack bytes.
:- consult(parse_constraints).

benchmark_raster(Rows, Cols, Raster) :-
   RowsMinus is Rows - 1,
   ColsMinus is Cols - 1,
   findall(Row,
           ( between(0, RowsMinus, I),
             findall(Id, (between(0, ColsMinus, J),
                          Id is I*Cols + J), Row) ), Raster).

benchmark_case(Size) :-
   benchmark_raster(Size, Size, Raster),
   get_time(T0),
   valid_boundaries(Raster, Results),
   get_time(T1),
   length(Results, Candidates),
   statistics(globalused, Bytes),
   Ms is (T1-T0)*1000,
   format('~d,~d,~3f,~d~n',[Size, Candidates, Ms, Bytes]).

run_benchmark :-
   format('side,candidates,time_ms,global_stack_bytes~n', []),
   maplist(benchmark_case, [8,16,32,64,128,256]).
