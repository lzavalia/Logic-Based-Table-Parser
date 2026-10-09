% Browser-facing table DOM sanitizer (F17 in the original audit).
%
% Treat all parsed source markup as untrusted. This sanitizer is applied only
% when producing human-readable HTML, not to the original raster or the raw
% source strings retained in JSON for reproducibility. It deliberately does
% not accept arbitrary CSS, URLs, event handlers, classes, ids or namespaces.
%
% The limited table markup is enough to inspect cell labels and spans. Other
% harmless source wrappers become <span>; active elements and their entire
% subtree disappear. Text nodes are passed to sgml_write's escaping serializer.

safe_table_dom(element(table, Attrs, Children),
               element(table, SafeAttrs, SafeChildren)) :-
   safe_table_attributes(table, Attrs, SafeAttrs),
   safe_table_children(Children, SafeChildren).

safe_table_children([], []).
safe_table_children([Node|Rest], SafeChildren) :-
   safe_table_node(Node, Nodes),
   safe_table_children(Rest, More),
   append(Nodes, More, SafeChildren).

% Do not keep the body of script/style/template or embeds and interactive
% controls. None of their contents should become visible annotation text.
safe_table_node(element(Tag, _, _), []) :-
   blocked_table_tag(Tag), !.
safe_table_node(element(Tag, Attrs, Children), [element(SafeTag, SafeAttrs, SafeChildren)]) :-
   safe_table_tag(Tag, SafeTag), !,
   safe_table_attributes(SafeTag, Attrs, SafeAttrs),
   safe_table_children(Children, SafeChildren).
% Unsupported JATS or HTML inline elements still carry scientific text.
% Erase the original tag and attributes, keeping only inert text/children.
safe_table_node(element(_, _, Children), [element(span, [], SafeChildren)]) :- !,
   safe_table_children(Children, SafeChildren).
safe_table_node(Text, [Text]) :-
   ( string(Text) ; atom(Text) ; number(Text) ), !.
safe_table_node(_, []).

% Only fixed, non-networked rendering tags; avoid <a href>, <img src>, SVG,
% MathML, forms, media and foreign-document elements entirely.
safe_table_tag(table, table).
safe_table_tag(thead, thead).
safe_table_tag(tbody, tbody).
safe_table_tag(tfoot, tfoot).
safe_table_tag(tr, tr).
safe_table_tag(th, th).
safe_table_tag(td, td).
safe_table_tag(caption, caption).
safe_table_tag(colgroup, colgroup).
safe_table_tag(col, col).
safe_table_tag(p, p).
safe_table_tag(span, span).
safe_table_tag(div, div).
safe_table_tag(br, br).
safe_table_tag(strong, strong).
safe_table_tag(b, b).
safe_table_tag(em, em).
safe_table_tag(i, i).
safe_table_tag(sup, sup).
safe_table_tag(sub, sub).
safe_table_tag(small, small).
safe_table_tag(code, code).
safe_table_tag(abbr, abbr).
safe_table_tag(ul, ul).
safe_table_tag(ol, ol).
safe_table_tag(li, li).
safe_table_tag(italic, em).
safe_table_tag(bold, strong).
safe_table_tag(monospace, code).
safe_table_tag('sc', span).
safe_table_tag('xref', span).
safe_table_tag('ext-link', span).
safe_table_tag('named-content', span).
safe_table_tag('inline-formula', span).

blocked_table_tag(script).
blocked_table_tag(style).
blocked_table_tag(template).
blocked_table_tag(iframe).
blocked_table_tag(frame).
blocked_table_tag(frameset).
blocked_table_tag(object).
blocked_table_tag(embed).
blocked_table_tag(applet).
blocked_table_tag(form).
blocked_table_tag(input).
blocked_table_tag(button).
blocked_table_tag(select).
blocked_table_tag(textarea).
blocked_table_tag(video).
blocked_table_tag(audio).
blocked_table_tag(picture).
blocked_table_tag(source).
blocked_table_tag(track).
blocked_table_tag(img).
blocked_table_tag(image).
blocked_table_tag(svg).
blocked_table_tag(math).
blocked_table_tag(canvas).
blocked_table_tag(link).
blocked_table_tag(meta).
blocked_table_tag(base).
blocked_table_tag(noscript).
blocked_table_tag('foreignObject').
blocked_table_tag('foreignobject').

safe_table_attributes(Tag, Attrs, SafeAttrs) :-
   findall(Attr, (member(Input, Attrs), safe_table_attribute(Tag, Input, Attr)), SafeAttrs).

% Only these attributes affect the structure presented to the user. The
% rasterizer has already checked the spans on the original, unmodified DOM.
safe_table_attribute(Tag, colspan=Value, colspan=Canonical) :-
   memberchk(Tag, [td, th]),
   safe_span_number(Value, positive, Canonical).
safe_table_attribute(Tag, rowspan=Value, rowspan=Canonical) :-
   memberchk(Tag, [td, th]),
   safe_span_number(Value, nonnegative, Canonical).
safe_table_attribute(colgroup, span=Value, span=Canonical) :-
   safe_span_number(Value, positive, Canonical).
safe_table_attribute(col, span=Value, span=Canonical) :-
   safe_span_number(Value, positive, Canonical).
safe_table_attribute(th, scope=Value, scope=Canonical) :-
   ( atom(Value) -> Atom = Value
   ; string(Value) -> atom_string(Atom, Value) ),
   memberchk(Atom, [row, col, rowgroup, colgroup]),
   Canonical = Atom.

safe_span_number(Value, Kind, Canonical) :-
   ( integer(Value) -> N = Value
   ; atom(Value) -> atom_string(Value, Raw), catch(number_string(N, Raw), _, fail)
   ; string(Value) -> catch(number_string(N, Value), _, fail) ),
   integer(N),
   ( Kind == positive -> N > 0 ; N >= 0 ),
   N =< 100000,
   Canonical = N.
