% Regression tests for the local table-logic driver (test_driver.pl).
%
% From dataset-builder-agent/tests/:
%   swipl -q -s test_driver_regression_tests.pl -g run_tests -t halt
%
% No network, LLM, article downloads, or DeepClause installation required.

:- use_module(library(filesex)).
:- use_module(library(readutil)).

:- begin_tests(test_driver).
:- consult('../src/test_driver').

% Each test gets a private workspace through plunit's setup/cleanup options;
% Root is shared between those options and the test body.
make_workspace(Root) :-
    tmp_file(table_parser_driver, Root),
    make_directory(Root).

remove_workspace(Root) :-
    (   exists_directory(Root) -> delete_directory_and_contents(Root) ; true ).

write_input(Dir, Name, Text, File) :-
    directory_file_path(Dir, Name, File),
    setup_call_cleanup(open(File, write, Out, [encoding(utf8)]),
                       write(Out, Text), close(Out)).

contains(File, Needle) :-
    read_file_to_string(File, Content, [encoding(utf8)]),
    sub_string(Content, _, _, _, Needle), !.

basename_is(Path, Expected) :-
    file_base_name(Path, Base),
    atom_string(Base, Text),
    Text == Expected.

% A 2x2 key/value table without merged cells admits a header row, a header
% column, or both; each candidate gets its own colored view, named by counts.
test(html_table_gets_one_colored_view_per_candidate,
     [setup(make_workspace(Root)), cleanup(remove_workspace(Root))]) :-
    write_input(Root, 'a.html',
        '<table><tr><th>k</th><th>v</th></tr><tr><td>a</td><td>1</td></tr></table>',
        File),
    test_table_parser(File, Files),
    maplist([P, B]>>(file_base_name(P, B0), atom_string(B0, B)), Files, Names),
    Names == ["table0_hmd0_vmd1.html", "table0_hmd1_vmd0.html", "table0_hmd1_vmd1.html"],
    last(Files, Both),
    contains(Both, "springgreen"),
    contains(Both, "skyblue"),
    contains(Both, "lightgray"),
    contains(Both, "<meta charset=\"utf-8\">"),
    Files = [VmdOnly|_],
    \+ contains(VmdOnly, "springgreen").

% A single cell is entirely data or entirely metadata, hence no candidate:
% it is written uncolored and clearly named, never silently omitted.
test(table_without_boundary_is_written_uncolored,
     [setup(make_workspace(Root)), cleanup(remove_workspace(Root))]) :-
    write_input(Root, 'b.html',
        '<table><tr><td>a</td></tr></table>', File),
    test_table_parser(File, Files),
    Files = [Path],
    basename_is(Path, "table0_unannotated.html"),
    \+ contains(Path, "background-color").

% Strict JATS XML is selected by the .xml extension.
test(xml_extension_uses_jats_parser,
     [setup(make_workspace(Root)), cleanup(remove_workspace(Root))]) :-
    write_input(Root, 'c.xml',
        '<article><body><table-wrap><table><thead><tr><th>k</th><th>v</th></tr></thead><tbody><tr><td>a</td><td>1</td></tr></tbody></table></table-wrap></body></article>',
        File),
    test_table_parser(File, Files),
    Files = [Path|_],
    basename_is(Path, "table0_hmd0_vmd1.html").

% Several tables are numbered in document order, from zero.
test(tables_are_numbered_in_document_order,
     [setup(make_workspace(Root)), cleanup(remove_workspace(Root))]) :-
    write_input(Root, 'd.html',
        '<table><tr><th>k</th><th>v</th></tr><tr><td>a</td><td>1</td></tr></table><table><tr><td>x</td></tr></table>',
        File),
    test_table_parser(File, Files),
    Files = [P0, _, _, P1],
    basename_is(P0, "table0_hmd0_vmd1.html"),
    basename_is(P1, "table1_unannotated.html").

% Active content and event handlers must not reach the browser-facing view.
test(output_is_sanitized,
     [setup(make_workspace(Root)), cleanup(remove_workspace(Root))]) :-
    write_input(Root, 'e.html',
        '<table><tr><th onclick="evil()">k</th><th>v<script>alert(1)</script></th></tr><tr><td>a</td><td>1</td></tr></table>',
        File),
    test_table_parser(File, Paths),
    forall(member(Path, Paths),
           ( \+ contains(Path, "onclick"),
             \+ contains(Path, "script"),
             \+ contains(Path, "alert") )).

% Rerunning replaces earlier table views but never touches unrelated files.
test(rerun_removes_stale_views_only,
     [setup(make_workspace(Root)), cleanup(remove_workspace(Root))]) :-
    write_input(Root, 'f.html',
        '<table><tr><th>k</th><th>v</th></tr><tr><td>a</td><td>1</td></tr></table>',
        File),
    directory_file_path(Root, out, OutDir),
    make_directory(OutDir),
    write_input(OutDir, 'table9_hmd9_vmd9.html', stale, Stale),
    write_input(OutDir, 'notes.txt', keep, Notes),
    test_table_parser(File, OutDir, [_|_]),
    \+ exists_file(Stale),
    exists_file(Notes).

% The default output directory is "<File>.tables".
test(default_output_directory_is_file_dot_tables,
     [setup(make_workspace(Root)), cleanup(remove_workspace(Root))]) :-
    write_input(Root, 'g.html',
        '<table><tr><th>k</th><th>v</th></tr><tr><td>a</td><td>1</td></tr></table>',
        File),
    test_table_parser(File, [Path|_]),
    atomic_list_concat([File, '.tables'], Expected),
    file_directory_name(Path, Dir),
    atom_string(DirAtom, Dir),
    atom_string(ExpectedAtom, Expected),
    DirAtom == ExpectedAtom.

test(file_without_tables_is_an_error,
     [setup(make_workspace(Root)), cleanup(remove_workspace(Root)),
      throws(error(no_tables_found(_), _))]) :-
    write_input(Root, 'h.html', '<p>no tables here</p>', File),
    test_table_parser(File, _).

% Strictness is shared with process_paper/4: oversized spans are rejected by
% the raster limits before any large allocation.
test(oversized_colspan_is_rejected,
     [setup(make_workspace(Root)), cleanup(remove_workspace(Root)),
      throws(error(table_raster_limit_exceeded(max_colspan, _, _), _))]) :-
    write_input(Root, 'i.html',
        '<table><tr><td colspan="1000000000">a</td></tr></table>', File),
    test_table_parser(File, _).

:- end_tests(test_driver).
