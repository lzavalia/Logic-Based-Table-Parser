% F12: fail-closed malformed spans, complete source-to-raster coverage and
% publication rollback. Offline: no network, credentials or DeepClause.
% From this directory:
%   swipl -q -s raster_integrity_regression_tests.pl -g run_tests -t halt

:- use_module(dataset_pipeline).
:- use_module(library(assoc)).
:- use_module(library(filesex)).
:- use_module(library(readutil)).

f12_cell(Attrs, element(td, Attrs, [x])).
f12_row(Cells, element(tr, [], Cells)).
f12_table(Rows, element(table, [], Rows)).

f12_overlapping_table(Table) :-
    f12_cell([rowspan='2'], A), f12_cell([], B),
    f12_cell([rowspan='2'], C), f12_cell([colspan='2'], D),
    f12_row([A,B,C], First), f12_row([D], Second),
    f12_table([First,Second], Table).

f12_workspace(Root) :- tmp_file(table_f12, Root), make_directory(Root).
f12_cleanup(Root) :-
    ( exists_directory(Root) -> delete_directory_and_contents(Root) ; true ).
f12_xml(Root, Name, Fragment, File) :-
    atom_string(Fragment, FragmentText),
    directory_file_path(Root, Name, File),
    setup_call_cleanup(
       open(File, write, Out, [encoding(utf8)]),
       format(Out,
          '<article><front><article-meta><article-id pub-id-type="pmc">9292</article-id></article-meta></front><body>~s</body></article>',
          [FragmentText]), close(Out)).

:- begin_tests(raster_integrity).

test(collision_reports_new_and_previous_cell_and_precise_slot,
     [throws(error(table_layout_error(overlapping_cell_spans(3,1,2,2)), _))]) :-
    f12_overlapping_table(Table),
    dataset_pipeline:rasterize_table(Table, _).

test(overlap_propagates_table_index,
     [throws(error(table_layout_error(overlapping_cell_spans(3,1,2,2)),
                   context(table_index(0), _)))]) :-
    f12_overlapping_table(Table),
    dataset_pipeline:rasterize_tables_bounded([Table], _).

test(collision_after_multiple_rowspans,
     [throws(error(table_layout_error(overlapping_cell_spans(2,2,2,1)), _))]) :-
    f12_cell([colspan='2',rowspan='2'], A),
    f12_cell([rowspan='3'], B),
    f12_cell([colspan='3'], D),
    f12_row([A,B], First), f12_row([], Second), f12_row([D], Third),
    f12_table([First,Second,Third], Table),
    dataset_pipeline:rasterize_table(Table, _).

test(nonoverlapping_rowspan_and_colspan_unchanged) :-
    f12_cell([rowspan='2'], A), f12_cell([colspan='2'], B),
    f12_cell([], C), f12_cell([], D),
    f12_row([A,B], First), f12_row([C,D], Second),
    f12_table([First,Second], Table),
    dataset_pipeline:rasterize_table(Table, [[0,1,1],[0,2,3]]).

test(multiple_occupied_start_columns_are_skipped) :-
    f12_cell([colspan='2',rowspan='2'], A),
    f12_cell([], B), f12_cell([], C),
    f12_row([A,B], First), f12_row([C], Second),
    f12_table([First,Second], Table),
    dataset_pipeline:rasterize_table(Table, [[0,0,1],[0,0,2]]).

test(short_rows_create_explicit_padding_not_errors) :-
    f12_cell([], A),f12_cell([], B),f12_cell([], C),
    f12_cell([], D),f12_cell([], E),
    f12_row([A,B,C], First), f12_row([D,E], Second),
    f12_table([First,Second], Table),
    dataset_pipeline:rasterize_table(Table, [[0,1,2],[3,4,5]]).

test(row_entirely_covered_by_rowspan_is_valid) :-
    f12_cell([rowspan='2'], A),
    f12_row([A], First), f12_row([], Second),
    f12_table([First,Second], Table),
    dataset_pipeline:rasterize_table(Table, [[0],[0]]).

test(missing_explicit_spans_default_to_one) :-
    f12_cell([], A), f12_row([A], Row),
    f12_table([Row], Table),
    dataset_pipeline:rasterize_table(Table, [[0]]).

test(zero_rowspan_is_supported) :-
    f12_cell([rowspan='0'], A),
    f12_row([A], First), f12_row([], Second),
    f12_table([First,Second], Table),
    dataset_pipeline:rasterize_table(Table, [[0],[0]]).

test(zero_colspan_rejected,
     [throws(error(table_layout_error(invalid_span(colspan, '0')), _))]) :-
    f12_cell([colspan='0'], A), f12_row([A], Row),
    f12_table([Row], Table),dataset_pipeline:rasterize_table(Table, _).

test(negative_colspan_rejected,
     [throws(error(table_layout_error(invalid_span(colspan, '-2')), _))]) :-
    f12_cell([colspan='-2'], A), f12_row([A], Row),
    f12_table([Row], Table),dataset_pipeline:rasterize_table(Table, _).

test(negative_rowspan_rejected,
     [throws(error(table_layout_error(invalid_span(rowspan, '-1')), _))]) :-
    f12_cell([rowspan='-1'], A), f12_row([A], Row),
    f12_table([Row], Table),dataset_pipeline:rasterize_table(Table, _).

test(nonnumeric_rowspan_rejected,
     [throws(error(table_layout_error(invalid_span(rowspan, 'bad')), _))]) :-
    f12_cell([rowspan=bad], A), f12_row([A], Row),
    f12_table([Row], Table),dataset_pipeline:rasterize_table(Table, _).

test(empty_table_rejected,
     [throws(error(table_layout_error(empty_table), _))]) :-
    f12_table([], Table), dataset_pipeline:rasterize_table(Table, _).

test(rows_without_source_cells_rejected,
     [throws(error(table_layout_error(empty_table), _))]) :-
    f12_row([], Row), f12_table([Row], Table),
    dataset_pipeline:rasterize_table(Table, _).

test(unmapped_source_id_detected_by_postcondition,
     [throws(error(table_layout_error(unmapped_source_cells([1])), _))]) :-
    empty_assoc(G0),put_assoc(0-0,G0,0,Grid),
    dataset_pipeline:verify_source_cell_coverage(Grid,2).

test(orphan_annotation_cell_rejected,
     [throws(error(table_layout_error(unmapped_annotation_cell(1)), _))]) :-
    f12_cell([], A), f12_cell([], B), f12_row([A,B], Row),
    f12_table([Row], Table),
    dataset_pipeline:annotate_table_element_raster(0,0,Table,[[0]],_).

test(rollback_retains_previous_paper_after_collision,
     [setup(f12_workspace(Root)), cleanup(f12_cleanup(Root))]) :-
    f12_xml(Root,'valid.xml',
        '<table><tr><td>A</td><td>B</td></tr><tr><td>C</td><td>D</td></tr></table>',
        Good),
    f12_xml(Root,'invalid.xml',
        '<table><tr><td rowspan="2">A</td><td>B</td><td rowspan="2">C</td></tr><tr><td colspan="2">D</td></tr></table>',
        Bad),
    process_paper('9292', Good, Root, _),
    directory_file_path(Root,'papers/PMC9292/metadata.json',Metadata),
    read_file_to_string(Metadata, Before, [encoding(utf8)]),
    catch(process_paper('9292',Bad,Root,_),
          error(table_layout_error(overlapping_cell_spans(3,1,2,2)),
                context(table_index(0),_)), Caught=yes),
    Caught == yes,
    read_file_to_string(Metadata, After, [encoding(utf8)]),
    Before == After,
    directory_file_path(Root,'papers/PMC9292/tables.jsonl',Jsonl),
    exists_file(Jsonl).

test(diagnostic_identifies_table_and_layout_issue,
     [setup(f12_workspace(Root)), cleanup(f12_cleanup(Root))]) :-
    format_paper_failure('9292',Root,
        error(table_layout_error(overlapping_cell_spans(3,1,2,2)),
              context(table_index(4),'bad span')),Text),
    sub_string(Text,_,_,_,'table 4 invalid layout'),
    sub_string(Text,_,_,_,'overlapping_cell_spans').

:- end_tests(raster_integrity).
