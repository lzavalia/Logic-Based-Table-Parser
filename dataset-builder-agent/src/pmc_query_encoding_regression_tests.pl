% F15: test the actual encoding module used by dataset_builder.dml.
% Run: swipl -q -s pmc_query_encoding_regression_tests.pl -g run_tests -t halt
:- use_module(pmc_query_encoding).
:- use_module(library(plunit)).

:- begin_tests(pmc_query_encoding).

test(empty_query) :-
    url_encode("", "").

test(ascii_letters_and_digits_are_literal) :-
    url_encode("AZaz09", "AZaz09").

test(space_and_pubmed_operators_are_escaped) :-
    url_encode("TP53[Title/Abstract] AND lung cancer",
               "TP53%5BTitle%2FAbstract%5D%20AND%20lung%20cancer").

test(reserved_url_delimiters_cannot_inject_parameters) :-
    url_encode("x&db=pubmed?foo#frag", "x%26db%3Dpubmed%3Ffoo%23frag").

test(plus_percent_and_literal_tilde) :-
    url_encode("C++ 100% ~", "C%2B%2B%20100%25%20%7E").

test(newlines_quotes_and_controls) :-
    url_encode("a\n\tb\"'", "a%0A%09b%22%27").

test(latin1_accent_utf8) :-
    url_encode("café", "caf%C3%A9").

test(alpha_synuclein_utf8) :-
    url_encode("α-synuclein", "%CE%B1%2Dsynuclein").

test(other_latin_utf8) :-
    url_encode("naïve", "na%C3%AFve").

test(greek_two_byte_utf8) :-
    url_encode("β", "%CE%B2").

test(cjk_three_byte_utf8) :-
    url_encode("東京", "%E6%9D%B1%E4%BA%AC").

test(four_byte_emoji_utf8) :-
    url_encode("🧬", "%F0%9F%A7%AC").

test(mixed_search_query_preserves_all_characters) :-
    url_encode("CRISPR β-catenin 🧬 [Title]",
               "CRISPR%20%CE%B2%2Dcatenin%20%F0%9F%A7%AC%20%5BTitle%5D").

test(combining_marks_not_dropped_or_normalized) :-
    string_codes(Decomposed, [0'e, 0x0301]),
    url_encode(Decomposed, "e%CC%81").

test(boundaries_between_utf8_lengths) :-
    string_codes(Input, [0x7F, 0x80, 0x7FF, 0x800, 0xFFFF, 0x10000, 0x10FFFF]),
    url_encode(Input, "%7F%C2%80%DF%BF%E0%A0%80%EF%BF%BF%F0%90%80%80%F4%8F%BF%BF").

test(surrogate_rejected,
     [throws(error(domain_error(unicode_scalar_value, 0xD800), _))]) :-
    pmc_query_encoding:utf8_bytes(0xD800, _).

test(above_unicode_max_rejected,
     [throws(error(domain_error(unicode_scalar_value, 0x110000), _))]) :-
    pmc_query_encoding:utf8_bytes(0x110000, _).

test(negative_scalar_rejected,
     [throws(error(domain_error(unicode_scalar_value, -1), _))]) :-
    pmc_query_encoding:utf8_bytes(-1, _).

:- end_tests(pmc_query_encoding).
