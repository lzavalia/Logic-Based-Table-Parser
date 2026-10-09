% Offline regressions for F04 (untrusted raster dimensions and spans).
% From dataset-builder-agent/src/:
%   swipl -q -s raster_limits_regression_tests.pl -g run_tests -t halt
% SWI-Prolog required; no network, DeepClause or API token needed.

:- use_module(dataset_pipeline).
:- use_module(library(filesex)).

simple_cell(Attrs, element(td, Attrs, [value])).
simple_row(Attrs, element(tr, [], [Cell])) :- simple_cell(Attrs, Cell).

large_row_list(Count, Attrs, Rows) :-
   simple_row(Attrs, Row),
   length(Rows, Count),
   maplist(=(Row), Rows).

table_with_rows(Rows, element(table, [], Rows)).

make_raster_test_workspace(Root) :-
   tmp_file(table_raster_limits, Root),
   make_directory(Root).

cleanup_raster_test_workspace(Root) :-
   (exists_directory(Root) -> delete_directory_and_contents(Root) ; true).

write_raster_fixture(Root, Name, Span, File) :-
   directory_file_path(Root, Name, File),
   setup_call_cleanup(
      open(File, write, Out, [encoding(utf8)]),
      format(Out,
             '<article><article-title>Title</article-title><body><table><tr><td colspan="~w">A</td></tr><tr><td>B</td></tr></table></body></article>',
             [Span]),
      close(Out)).

:- begin_tests(table_raster_limits).

test(ordinary_merged_table_retains_cell_ids) :-
   simple_cell([colspan='2'], Merged),
   simple_cell([], BottomLeft),
   simple_cell([], BottomRight),
   table_with_rows([element(tr, [], [Merged]),
                    element(tr, [], [BottomLeft, BottomRight])], Table),
   dataset_pipeline:rasterize_table(Table, [[0,0],[1,2]]).

test(rowspan_across_two_rows_retained) :-
   simple_cell([rowspan='2'], Spanning),
   simple_cell([], Top),
   simple_cell([], Bottom),
   table_with_rows([element(tr, [], [Spanning, Top]),
                    element(tr, [], [Bottom])], Table),
   dataset_pipeline:rasterize_table(Table, [[0,1],[0,2]]).

test(rowspan_zero_extends_to_section_end) :-
   simple_cell([rowspan='0'], Spanning),
   simple_cell([], A), simple_cell([], B), simple_cell([], C),
   table_with_rows([element(tr, [], [Spanning,A]),
                    element(tr, [], [B]),
                    element(tr, [], [C])], Table),
   dataset_pipeline:rasterize_table(Table, [[0,1],[0,2],[0,3]]).

test(allowed_span_at_exact_column_limit) :-
   simple_row([colspan='256'], Row),
   table_with_rows([Row], Table),
   dataset_pipeline:rasterize_table(Table, [RasterRow]),
   length(RasterRow, 256),
   forall(member(Id, RasterRow), Id == 0).

test(billion_column_span_rejected_before_allocation,
     [throws(error(table_raster_limit_exceeded(max_colspan, 256, 1000000000), _))]) :-
   simple_row([colspan='1000000000'], Row),
   table_with_rows([Row], Table),
   dataset_pipeline:rasterize_table(Table, _).

test(huge_span_text_is_not_converted_to_bigint,
     [throws(error(table_raster_limit_exceeded(max_span_chars, 32, _), _))]) :-
   simple_row([colspan='9999999999999999999999999999999999999999999999'], Row),
   table_with_rows([Row], Table),
   dataset_pipeline:rasterize_table(Table, _).

test(adjacent_spans_cannot_exceed_column_limit,
     [throws(error(table_raster_limit_exceeded(max_columns, 256, 300), _))]) :-
   simple_cell([colspan='200'], Left),
   simple_cell([colspan='100'], Right),
   table_with_rows([element(tr, [], [Left, Right])], Table),
   dataset_pipeline:rasterize_table(Table, _).

test(fully_spanned_row_cannot_push_a_new_cell_outside_limit,
     [throws(error(table_raster_limit_exceeded(max_columns, 256, 257), _))]) :-
   simple_cell([colspan='256',rowspan='2'], Top),
   simple_cell([], Bottom),
   table_with_rows([element(tr, [], [Top]),element(tr, [], [Bottom])], Table),
   dataset_pipeline:rasterize_table(Table, _).

test(excessive_rows_rejected,
     [throws(error(table_raster_limit_exceeded(max_rows, 1000, 1001), _))]) :-
   large_row_list(1001, [], Rows),
   table_with_rows(Rows, Table),
   dataset_pipeline:rasterize_table(Table, _).

test(excessive_real_cells_rejected,
     [throws(error(table_raster_limit_exceeded(max_cells, 10000, 10001), _))]) :-
   simple_cell([], Cell),
   length(Cells, 10001), maplist(=(Cell), Cells),
   table_with_rows([element(tr, [], Cells)], Table),
   dataset_pipeline:rasterize_table(Table, _).

test(total_claim_budget_applies_before_any_slot_allocation,
     [throws(error(table_raster_limit_exceeded(max_claims, 100000, _), _))]) :-
   large_row_list(400, [colspan='256'], Rows),
   table_with_rows(Rows, Table),
   dataset_pipeline:rasterize_table(Table, _).

test(dense_raster_area_budget_applies_to_sparse_tables,
     [throws(error(table_raster_limit_exceeded(max_slots, 100000, 102656), _))]) :-
   simple_row([colspan='256'], WideRow),
   large_row_list(400, [], NarrowRows),
   table_with_rows([WideRow|NarrowRows], Table),
   dataset_pipeline:rasterize_table(Table, _).

test(invalid_span_falls_back_to_one) :-
   simple_row([colspan='garbage'], Row),
   table_with_rows([Row], Table),
   dataset_pipeline:rasterize_table(Table, [[0]]).

test(huge_rowspan_is_clipped_to_section_size) :-
   simple_row([rowspan='1000000000'], Row),
   table_with_rows([Row], Table),
   dataset_pipeline:rasterize_table(Table, [[0]]).

test(paper_table_count_limit,
     [throws(error(paper_raster_limit_exceeded(max_tables, 256, 257), _))]) :-
   length(Tables, 257),
   dataset_pipeline:rasterize_tables_bounded(Tables, _).

test(paper_combined_slot_limit,
     [throws(error(paper_raster_limit_exceeded(max_total_slots, 250000, 250001), _))]) :-
   dataset_pipeline:ensure_paper_limit(max_total_slots, 250001).

test(rejected_rerun_preserves_published_paper,
     [setup(make_raster_test_workspace(Root)),
      cleanup(cleanup_raster_test_workspace(Root))]) :-
   write_raster_fixture(Root, 'good.xml', 2, Good),
   write_raster_fixture(Root, 'bad.xml', 1000000000, Bad),
   process_paper('2026', Good, Root, _),
   directory_file_path(Root, 'papers/PMC2026/annotated_table0.html', Published),
   exists_file(Published),
   catch(process_paper('2026', Bad, Root, _),
         error(table_raster_limit_exceeded(max_colspan, _, _), _), Caught = yes),
   Caught == yes,
   exists_file(Published),
   directory_file_path(Root, 'papers/PMC2026/metadata.json', Metadata),
   dataset_pipeline:read_json_file(Metadata, Details),
   Details.table_count =:= 1.

:- end_tests(table_raster_limits).
