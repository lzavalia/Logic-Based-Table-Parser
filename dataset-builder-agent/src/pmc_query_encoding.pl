% NCBI E-utilities query-component encoding (RFC 3986).
% Encode Unicode scalar values as UTF-8 bytes before percent-encoding.
% Keep only ASCII letters/digits literal. In particular, PubMed syntax
% characters ([, ], spaces, quotes, &, +, %, ...) must not alter URL syntax.
% Standalone module so native SWI-Prolog can regression-test the same
% implementation that the DeepClause DML agent calls.
:- module(pmc_query_encoding, [url_encode/2]).

% url_encode(+Text:string, -Encoded:string) is det.
url_encode(Text, Encoded) :-
    string_codes(Text, Codepoints),
    encode_codepoints(Codepoints, EncodedCodes),
    string_codes(Encoded, EncodedCodes).

encode_codepoints([], []).
encode_codepoints([Codepoint|Tail], Encoded) :-
    utf8_bytes(Codepoint, Bytes),
    encode_bytes(Bytes, Encoded, Rest),
    encode_codepoints(Tail, Rest).

% UTF-8 encoding of one Unicode scalar value; rejects surrogates and values
% above U+10FFFF instead of silently replacing or dropping anything.
utf8_bytes(C, [C]) :-
    integer(C), C >= 0, C =< 0x7F, !.
utf8_bytes(C, [B1, B2]) :-
    integer(C), C >= 0x80, C =< 0x7FF, !,
    B1 is 0xC0 \/ (C >> 6),
    B2 is 0x80 \/ (C /\ 0x3F).
utf8_bytes(C, [B1, B2, B3]) :-
    integer(C), C >= 0x800, C =< 0xFFFF,
    (C < 0xD800 ; C > 0xDFFF), !,
    B1 is 0xE0 \/ (C >> 12),
    B2 is 0x80 \/ ((C >> 6) /\ 0x3F),
    B3 is 0x80 \/ (C /\ 0x3F).
utf8_bytes(C, [B1, B2, B3, B4]) :-
    integer(C), C >= 0x10000, C =< 0x10FFFF, !,
    B1 is 0xF0 \/ (C >> 18),
    B2 is 0x80 \/ ((C >> 12) /\ 0x3F),
    B3 is 0x80 \/ ((C >> 6) /\ 0x3F),
    B4 is 0x80 \/ (C /\ 0x3F).
utf8_bytes(C, _) :-
    throw(error(domain_error(unicode_scalar_value, C),
                context(url_encode/2, 'Expected a Unicode scalar value'))).

% Difference-list output: no intermediate string conversions or flattening.
encode_bytes([], Tail, Tail).
encode_bytes([B|Bs], Encoded, Rest) :-
    (   ascii_alphanumeric(B)
    ->  Encoded = [B|Next]
    ;   Hi is B >> 4,
        Lo is B /\ 0x0F,
        hex_code(Hi, H),
        hex_code(Lo, L),
        Encoded = [0'%, H, L|Next]
    ),
    encode_bytes(Bs, Next, Rest).

ascii_alphanumeric(B) :-
    ( B >= 0'A, B =< 0'Z
    ; B >= 0'a, B =< 0'z
    ; B >= 0'0, B =< 0'9
    ).

hex_code(N, Code) :-
    ( N < 10 -> Code is 0'0 + N ; Code is 0'A + N - 10 ).
