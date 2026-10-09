:- use_module(pmc_id_parser).
:- begin_tests(pmc_id_parser).

test(common_punctuation_and_tabs) :-
    parse_pmc_ids("(PMC12345)\tPMC23456. ; [pmc34567], {PMC45678}", 10, Ids),
    Ids == ["12345", "23456", "34567", "45678"].
test(malformed_and_bare_numbers_rejected) :-
    parse_pmc_ids("12345 PMCy22 fooPMC333 PMC444x PMC12.3 -PMC43 PMC0", 10, Ids),
    Ids == [].
test(leading_zero_aliases_and_order) :-
    parse_pmc_ids("PMC00042 PMC42 PMC007 PMC00042 PMC9", 5, Ids),
    Ids == ["42", "7", "9"].
test(truncation_after_valid_ids) :-
    parse_pmc_ids("junk PMC12, 22, PMC23, PMC34", 2, ["12", "23"]).
test(zero_limit) :-
    parse_pmc_ids("PMC12 PMC34", 0, []).
test(overlong_and_non_ascii) :-
    parse_pmc_ids("PMC1234567890123 PMC１２３ PMC12", 10, ["12"]).
test(internal_punctuation_rejected) :-
    parse_pmc_ids("PMC1-2 PMC1/2 PM C12 PMCx12", 10, []).
test(case_insensitive) :-
    parse_pmc_ids("pmc100 PmC101", 10, ["100", "101"]).
test(nonnegative_limit_required, [throws(error(domain_error(_, _), _))]) :-
    parse_pmc_ids("PMC12", -1, _).
:- end_tests(pmc_id_parser).
