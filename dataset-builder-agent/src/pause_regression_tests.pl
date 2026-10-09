% Native SWI-Prolog timing checks.  DeepClause's WASM path uses the host
% ncbi_wait.py helper instead, avoiding the unsupported sleep/1 builtin.
:- use_module(dataset_pipeline).

:- begin_tests(f14_native_timed_wait).

test(zero_pause) :-
    pause(0).

test(negative_pause_rejected, [throws(error(domain_error(pause_seconds_0_to_300, -1), _))]) :-
    pause(-1).

test(non_numeric_pause_rejected, [throws(error(domain_error(pause_seconds_0_to_300, banana), _))]) :-
    pause(banana).

test(excessive_pause_rejected, [throws(error(domain_error(pause_seconds_0_to_300, 301), _))]) :-
    pause(301).

test(native_sleep_does_not_spin) :-
    get_time(Before),
    statistics(cputime, CpuBefore),
    pause(0.25),
    get_time(After),
    statistics(cputime, CpuAfter),
    Elapsed is After - Before,
    CpuUsed is CpuAfter - CpuBefore,
    Elapsed >= 0.23,
    CpuUsed < 0.1.

:- end_tests(f14_native_timed_wait).
