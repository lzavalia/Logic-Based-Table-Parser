% Parse LLM selections as complete PMC tokens; never accept a bare number.
% The search-result allowlist in dataset_pipeline remains authoritative.
:- module(pmc_id_parser, [parse_pmc_ids/3, pmc_number/2]).

parse_pmc_ids(Text, Max, Ids) :-
    ( (string(Text); atom(Text)), integer(Max), Max >= 0 -> true
    ; throw(error(domain_error(pmc_selection_arguments, Text-Max),
                  context(parse_pmc_ids/3, 'Expected text and nonnegative integer limit'))) ),
    ( atom(Text) -> atom_string(Text, String) ; String = Text ),
    split_string(String, ' ,;\n\r\t', '', Parts),
    findall(Id, (member(Part, Parts), pmc_number(Part, Id)), All),
    list_to_set(All, Unique),
    take_pmc(Max, Unique, Ids).

pmc_number(Token, Digits) :-
    ( atom(Token) -> atom_string(Token, Text) ; string(Token), Text = Token ),
    string_chars(Text, Characters),
    trim_punctuation(Characters, Trimmed),
    string_chars(Bare, Trimmed),
    string_upper(Bare, Upper),
    sub_string(Upper, 0, 3, _, 'PMC'),
    sub_string(Upper, 3, _, 0, RawDigits),
    string_length(RawDigits, Length),
    between(1, 12, Length),
    string_codes(RawDigits, Codes),
    Codes \== [],
    forall(member(Code, Codes), between(0'0, 0'9, Code)),
    number_string(Number, RawDigits), Number > 0,
    number_string(Number, Digits).

trim_punctuation(Chars, Clean) :-
    drop_leading_punctuation(Chars, Front),
    reverse(Front, Reversed),
    drop_leading_punctuation(Reversed, Back),
    reverse(Back, Clean).

drop_leading_punctuation([Char|Rest], Clean) :-
    memberchk(Char, ['(', ')', '[', ']', '{', '}', '.', '!', '?', ':', '"', '\'', '`', '<', '>']), !,
    drop_leading_punctuation(Rest, Clean).
drop_leading_punctuation(Chars, Chars).

take_pmc(_, [], []) :- !.
take_pmc(N, _, []) :- N =< 0, !.
take_pmc(N, [X|Xs], [X|Ys]) :-
    N1 is N - 1, take_pmc(N1, Xs, Ys).
