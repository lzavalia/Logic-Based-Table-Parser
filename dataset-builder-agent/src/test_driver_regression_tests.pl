% Regression tests for the local table-logic driver (test_driver.pl).
%
% From dataset-builder-agent/src/:
%   swipl -q -s test_driver_regression_tests.pl -g run_tests -t halt
%
% No network, LLM, article downloads, or DeepClause installation required.

:- use_module(library(filesex)).
:- use_module(library(readutil)).

:- begin_tests(test_driver).
:- consult(test_driver).

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

% A key/value table with one admissible boundary is colored for it.
test(html_table_gets_one_colored_candidate,
     [setup(make_workspace(Root)), cleanup(remove_workspace(Root))]) :-
    write_input(Root, 'a.html',
        '<table><tr><th>k</th><th>v</th></tr><tr><td>a</td><td>1</td></tr></table>',
        File),
    test_table_parser(File, Files),
    Files = [Path],
    basename_is(Path, "table0_hmd0_vmd0.html"),
    contains(Path, "springgreen"),
    contains(Path, "skyblue"),
    contains(Path, "lightgray"),
    contains(Path, "<meta charset=\"utf-8\">").

% A single-row table has no data region, hence no candidate: it is written
% uncolored and clearly named, never silently omitted.
test(table_without_boundary_is_written_uncolored,
     [setup(make_workspace(Root)), cleanup(remove_workspace(Root))]) :-
    write_input(Root, 'b.html',
        '<table><tr><td>a</td><td>b</td></tr></table>', File),
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
    Files = [Path],
    basename_is(Path, "table0_hmd0_vmd0.html").

% Several tables are numbered in document order, from zero.
test(tables_are_numbered_in_document_order,
     [setup(make_workspace(Root)), cleanup(remove_workspace(Root))]) :-
    write_input(Root, 'd.html',
        '<table><tr><th>k</th><th>v</th></tr><tr><td>a</td><td>1</td></tr></table><table><tr><td>x</td><td>y</td></tr></table>',
        File),
    test_table_parser(File, Files),
    Files = [P0, P1],
    basename_is(P0, "table0_hmd0_vmd0.html"),
    basename_is(P1, "table1_unannotated.html").

% Active content and event handlers must not reach the browser-facing view.
test(output_is_sanitized,
     [setup(make_workspace(Root)), cleanup(remove_workspace(Root))]) :-
    write_input(Root, 'e.html',
        '<table><tr><th onclick="evil()">k</th><th>v<script>alert(1)</script></th></tr><tr><td>a</td><td>1</td></tr></table>',
        File),
    test_table_parser(File, [Path]),
    \+ contains(Path, "onclick"),
    \+ contains(Path, "script"),
    \+ contains(Path, "alert").

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
    test_table_parser(File, OutDir, [_]),
    \+ exists_file(Stale),
    exists_file(Notes).

% The default output directory is "<File>.tables".
test(default_output_directory_is_file_dot_tables,
     [setup(make_workspace(Root)), cleanup(remove_workspace(Root))]) :-
    write_input(Root, 'g.html',
        '<table><tr><th>k</th><th>v</th></tr><tr><td>a</td><td>1</td></tr></table>',
        File),
    test_table_parser(File, [Path]),
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
