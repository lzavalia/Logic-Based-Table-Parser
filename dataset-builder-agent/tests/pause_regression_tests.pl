% Timing checks for pause/1. Native SWI-Prolog blocks in sleep/1; the
% clock-polling fallback used in DeepClause's WASM engine, where sleep/1
% raises, is exercised through wait_until/1.
:- use_module('../src/dataset_pipeline').

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

test(clock_fallback_waits_full_duration) :-
    get_time(Before),
    End is Before + 0.2,
    dataset_pipeline:wait_until(End),
    get_time(After),
    After >= End,
    After - Before < 1.0.

test(clock_fallback_returns_at_once_for_past_deadline) :-
    get_time(Now),
    Past is Now - 5,
    dataset_pipeline:wait_until(Past),
    get_time(After),
    After - Now < 0.1.

:- end_tests(f14_native_timed_wait).
