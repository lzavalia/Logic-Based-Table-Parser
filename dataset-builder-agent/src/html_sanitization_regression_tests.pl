% F17 (original audit): untrusted table input cannot become active HTML.
% Run: swipl -q -s html_sanitization_regression_tests.pl -g run_tests -t halt
:- use_module(dataset_pipeline).
:- use_module(library(filesex)).
:- use_module(library(readutil)).

unsafe_html_table('<table onclick="evil()"><tr><th scope="col" onmouseover="bad()">Name</th><th>Result</th></tr><tr><td style="background: red !important" onclick="alert(1)"><script>alert(2)</script><img src="https://evil.example/track"/><a href="javascript:evil()">safe</a><span style="color:expression(alert(3))">text</span></td><td><svg onload="evil()"/><b>42</b></td></tr></table>').

sanitized_render(Html, Safe) :-
   dataset_pipeline:parse_html(Html, DOM),
   dataset_pipeline:extract_tables(DOM, [Table|_]),
   dataset_pipeline:safe_table_dom(Table, Safe).

unsafe_fragment(Out) :-
   unsafe_html_table(Input),
   sanitized_render(Input, Safe),
   dataset_pipeline:table_html(Safe, Out).

sanitizer_workspace(Root) :- tmp_file(table_security, Root), make_directory(Root).
sanitizer_cleanup(Root) :-
   ( exists_directory(Root) -> delete_directory_and_contents(Root) ; true ).

security_input(Root, File) :-
   unsafe_html_table(Table),
   atom_string(Table, TableText),
   format(string(Xml), '<article><front><article-meta><article-id pub-id-type="pmc">919</article-id></article-meta></front><body><table-wrap><label>Sec</label><caption><p>&lt;script&gt;inert&lt;/script&gt;</p></caption>~s</table-wrap></body></article>', [TableText]),
   % The fixture table itself is properly closed and unescaped markup.
   directory_file_path(Root, 'article.xml', File),
   setup_call_cleanup(open(File, write, Stream, [encoding(utf8)]),
                      format(Stream, '~s', [Xml]), close(Stream)).

:- begin_tests(html_sanitization).

test(removes_active_tags_and_network_resources) :-
   unsafe_fragment(Out),
   \+ sub_string(Out, _, _, _, '<script'),
   \+ sub_string(Out, _, _, _, '<img'),
   \+ sub_string(Out, _, _, _, '<svg'),
   \+ sub_string(Out, _, _, _, 'evil.example'),
   \+ sub_string(Out, _, _, _, 'alert(2)'),
   sub_string(Out, _, _, _, 'safe'),
   sub_string(Out, _, _, _, 'text'),
   sub_string(Out, _, _, _, '42').

test(removes_source_attributes_including_urls_event_handlers_and_css) :-
   unsafe_fragment(Out),
   \+ sub_string(Out, _, _, _, 'onclick'),
   \+ sub_string(Out, _, _, _, 'onmouseover'),
   \+ sub_string(Out, _, _, _, 'href='),
   \+ sub_string(Out, _, _, _, 'javascript:'),
   \+ sub_string(Out, _, _, _, 'expression('),
   \+ sub_string(Out, _, _, _, '!important'),
   \+ sub_string(Out, _, _, _, 'background:').

test(preserves_safe_table_geometry_and_header_scope) :-
   sanitized_render('<table class="bad"><tr><th rowspan="2" scope="col" onclick="x">Key</th><th colspan="2">Values</th></tr><tr><td>A</td><td>B</td></tr></table>', Safe),
   Safe = element(table, [], _),
   findall(A, dataset_pipeline:sub_element(th, Safe, element(th, A, _)), [First, Second]),
   memberchk(rowspan=2, First), memberchk(scope=col, First),
   memberchk(colspan=2, Second).

test(blocks_both_active_ancestors_and_descendants) :-
   sanitized_render('<table><tr><td><template><img src="evil"/></template>OK<iframe srcdoc="evil">BAD</iframe><style>BADCSS</style></td></tr></table>', Safe),
   dataset_pipeline:table_html(Safe, Text),
   sub_string(Text, _, _, _, 'OK'),
   \+ sub_string(Text, _, _, _, 'BAD'),
   \+ sub_string(Text, _, _, _, 'evil').

test(sanitizer_discards_unrecognized_attributes) :-
   sanitized_render('<table data-x="evil"><tr id="evil"><td headers="x" data-p="y" style="background:red" onload="oops">A</td></tr></table>', Safe),
   Safe = element(table, [], _),
   dataset_pipeline:sub_element(tr, Safe, element(tr, [], _)),
   dataset_pipeline:sub_element(td, Safe, element(td, [], _)).

test(annotated_api_uses_sanitized_dom) :-
   unsafe_html_table(Input),
   dataset_pipeline:annotate_table(0, 0, Input, Annotation),
   sub_string(Annotation, _, _, _, 'background-color: springgreen'),
   \+ sub_string(Annotation, _, _, _, '!important'),
   \+ sub_string(Annotation, _, _, _, 'onmouseover'),
   \+ sub_string(Annotation, _, _, _, 'javascript:').

test(published_html_safe_and_original_source_retained,
     [setup(sanitizer_workspace(Root)), cleanup(sanitizer_cleanup(Root))]) :-
   security_input(Root, File),
   dataset_pipeline:process_paper('919', File, Root, _),
   directory_file_path(Root, 'papers/PMC919/annotated_table0.html', HtmlFile),
   read_file_to_string(HtmlFile, Html, [encoding(utf8)]),
   \+ sub_string(Html, _, _, _, 'onclick'),
   \+ sub_string(Html, _, _, _, '<script'),
   \+ sub_string(Html, _, _, _, '<img'),
   \+ sub_string(Html, _, _, _, 'javascript:'),
   sub_string(Html, _, _, _, 'background-color: springgreen'),
   sub_string(Html, _, _, _, '&lt;script&gt;inert&lt;/script&gt;'),
   directory_file_path(Root, 'papers/PMC919/metadata.json', Metadata),
   dataset_pipeline:read_json_file(Metadata, Meta),
   Meta.tables = [First|_],
   sub_string(First.source_table_html, _, _, _, 'onclick'),
   sub_string(First.source_table_html, _, _, _, '<script').

test(abstaining_table_does_not_emit_untrusted_markup,
     [setup(sanitizer_workspace(Root)), cleanup(sanitizer_cleanup(Root))]) :-
   directory_file_path(Root, 'output.html', File),
   dataset_pipeline:parse_html('<table onload="bad()"><tr><td><img src="https://evil.example/x"/>X</td></tr></table>', DOM),
   dataset_pipeline:extract_tables(DOM, [Table]),
   dataset_pipeline:rasterize_table(Table, Raster),
   dataset_pipeline:save_table(File, Table, Raster, _),
   read_file_to_string(File, Html, [encoding(utf8)]),
   sub_string(Html, _, _, _, 'Abstained'),
   \+ sub_string(Html, _, _, _, '<img'),
   \+ sub_string(Html, _, _, _, 'evil.example'),
   \+ sub_string(Html, _, _, _, 'onload').

:- end_tests(html_sanitization).
