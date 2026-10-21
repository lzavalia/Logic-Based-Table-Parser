% Tests for the boundary and central-metadata searches of
% parse_constraints.pl.
%
%   swipl -g run_tests -t halt tests/table_layouts_regression_tests.pl
%
% Each table is a hand-built raster. A layout is checked through its labels,
% written one string per row: h = HMD, v = VMD, d = data, s = separator.

:- use_module(library(plunit)).
:- use_module(library(apply)).
:- use_module(library(lists)).

:- prolog_load_context(directory, Dir),
   directory_file_path(Dir, '../src/parse_constraints.pl', File),
   consult(File).

% labellings(+Raster, -Labellings): the labels of every layout, in order.
labellings(Raster, Labellings) :-
   table_layouts(Raster, Layouts),
   maplist(labelling(Raster), Layouts, Labellings).

labelling(Raster, Layout, Rows) :-
   layout_labels(Raster, Layout, Labels),
   maplist(row_string, Labels, Rows).

row_string(Labels, String) :-
   maplist(label_char, Labels, Chars),
   string_chars(String, Chars).

label_char(hmd, h).
label_char(vmd, v).
label_char(data, d).
label_char(separator, s).

% boundaries(+Raster, -Pairs): the valid layer counts as Hmd/Vmd pairs.
boundaries(Raster, Pairs) :-
   valid_boundaries(Raster, Boundaries),
   findall(Hmd/Vmd, member(json{hmd: Hmd, vmd: Vmd}, Boundaries), Pairs).

% Layer counts: hmd is the number of HMD rows, vmd the number of VMD columns.
:- begin_tests(boundaries).

% No merged cell on either margin: one layer or none on each axis, but not
% none on both.
test(plain_grid) :-
   boundaries([[0,1,2],[3,4,5],[6,7,8]], Pairs),
   assertion(Pairs == [0/1, 1/0, 1/1]).

% Merged cells in the first row rule out a table without HMD.
test(merged_header) :-
   boundaries([[ 0, 1, 1, 2, 2],
               [ 3, 4, 5, 6, 7],
               [ 8, 9,10,11,12],
               [13,14,15,16,17]], Pairs),
   assertion(Pairs == [2/0, 2/1]).

% Merged cells in the first column: constraint 9 rules out a table without
% HMD, since the table has a merged cell; a table without VMD is not limited.
test(merged_vmd) :-
   boundaries([[ 0, 1, 2, 3],
               [ 4, 5, 6, 7],
               [ 4, 8, 9,10],
               [11,12,13,14],
               [11,15,16,17]], Pairs),
   assertion(Pairs == [1/0, 1/1, 1/2]).

% Only "no metadata at all" satisfies the constraints: not reported.
test(no_metadata_only) :-
   boundaries([[0,0,1],[2,3,3],[4,5,6]], Pairs),
   assertion(Pairs == []).

test(empty) :-
   boundaries([], Pairs),
   assertion(Pairs == []).

:- end_tests(boundaries).

:- begin_tests(central_metadata).

% Without merged cells there is nothing to cut: the marginal readings only.
test(no_merged_cells) :-
   labellings([[0,1,2],[3,4,5],[6,7,8]], Ls),
   assertion(Ls == [["vdd","vdd","vdd"],
                    ["hhh","ddd","ddd"],
                    ["hhh","vdd","vdd"]]).

test(unparseable) :-
   table_layouts([[0,0,1],[2,3,3],[4,5,6]], Layouts),
   assertion(Layouts == []).

% Rows covered by one cell are set aside, wherever they are. Without that,
% the only reading is the title and the header as HMD, with the separators as
% data; set aside, they leave a plain grid, which may also lack HMD.
test(separator_rows) :-
   Raster = [[0,0,0],[1,2,3],[4,5,6],[7,7,7],[8,9,10],[11,11,11]],
   boundaries(Raster, Pairs),
   assertion(Pairs == [2/0]),
   labellings(Raster, Ls),
   assertion(Ls == [["sss","vdd","vdd","sss","vdd","sss"],
                    ["sss","hhh","ddd","sss","ddd","sss"],
                    ["sss","hhh","vdd","sss","vdd","sss"]]).

% A title over the data columns only is a separator of the data region. With
% no VMD the title no longer covers its whole row of the region, and is data.
test(data_title) :-
   labellings([[0,1,1],[2,3,4],[5,6,6],[7,8,9]], Ls),
   assertion(Ls == [["hhh","hhh","ddd","ddd"],
                    ["hhh","hhh","vss","vdd"]]).

% The header band is found with and without VMD; the marginal readings last.
test(central_hmd) :-
   Raster = [[ 0, 1, 1, 2, 2],
             [ 3, 4, 5, 6, 7],
             [ 8, 9,10,11,12],
             [13,14,14,15,15],
             [16,17,18,19,20],
             [21,22,23,24,25]],
   labellings(Raster, Ls),
   assertion(Ls == [["hhhhh","hhhhh","ddddd","hhhhh","hhhhh","ddddd"],
                    ["hhhhh","hhhhh","vdddd","hhhhh","hhhhh","vdddd"],
                    ["hhhhh","hhhhh","ddddd","ddddd","ddddd","ddddd"],
                    ["hhhhh","hhhhh","vdddd","vdddd","vdddd","vdddd"]]).

% The column of the merged cell can be the only VMD column of the right
% piece, or the first of two; each under every marginal reading. The table
% has a merged cell, so every marginal reading has HMD (constraint 9).
test(central_vmd) :-
   Raster = [[ 0, 1, 2, 3, 4],
             [ 5, 6, 7, 8, 9],
             [10,11, 7,12,13]],
   labellings(Raster, Ls),
   assertion(Ls == [["hhhhh","ddvdd","ddvdd"],
                    ["hhhhh","ddvvd","ddvvd"],
                    ["hhhhh","vdvdd","vdvdd"],
                    ["hhhhh","vdvvd","vdvvd"],
                    ["hhhhh","ddddd","ddddd"],
                    ["hhhhh","vdddd","vdddd"]]).

% Two header bands: both, either one, or neither, under each of the two
% marginal readings.
test(nested) :-
   Raster = [[ 0, 1, 2, 3, 4],
             [ 5, 6, 7, 8, 9],
             [10,11,11,12,12],
             [13,14,15,16,17],
             [18,19,20,21,22],
             [23,24,24,25,25],
             [26,27,28,29,30],
             [31,32,33,34,35]],
   table_layouts(Raster, Layouts),
   maplist(layout_cuts, Layouts, Cuts),
   assertion(Cuts == [2,2, 1,1,1,1, 0,0]),
   labellings(Raster, Ls),
   assertion(memberchk(["hhhhh","vdddd","hhhhh","hhhhh","vdddd","hhhhh","hhhhh","vdddd"], Ls)),
   assertion(memberchk(["hhhhh","vdddd","vdddd","vdddd","vdddd","hhhhh","hhhhh","vdddd"], Ls)),
   assertion(memberchk(["hhhhh","vdddd","hhhhh","hhhhh","vdddd","vdddd","vdddd","vdddd"], Ls)).

% A horizontal cut whose upper region is then cut vertically.
test(mixed_cuts) :-
   Raster = [[ 0, 1, 2, 3, 4],
             [ 5, 6, 7, 8, 9],
             [10,11, 7,12,13],
             [14,15,15,16,16],
             [17,18,19,20,21],
             [22,23,24,25,26]],
   labellings(Raster, Ls),
   assertion(memberchk(["hhhhh","vdvvd","vdvvd","hhhhh","hhhhh","vdddd"], Ls)).

% A merged cell above a row of distinct cells parses as a header band, so it
% is offered both as metadata and as data.
test(merged_data_cell) :-
   Raster = [[ 0, 1, 2, 3],
             [ 4, 5, 6, 7],
             [ 8, 9, 9,10],
             [11,12,13,14],
             [15,16,17,18]],
   labellings(Raster, Ls),
   assertion(Ls == [["hhhh","dddd","hhhh","hhhh","dddd"],
                    ["hhhh","vddd","hhhh","hhhh","vddd"],
                    ["hhhh","dddd","dddd","dddd","dddd"],
                    ["hhhh","vddd","vddd","vddd","vddd"]]).

% The piece below the cut has no data row, so only the marginal layouts are
% left.
test(failed_cut) :-
   labellings([[0,1,2,3],[4,5,6,7],[8,9,9,10]], Ls),
   assertion(Ls == [["hhhh","dddd","dddd"],
                    ["hhhh","vddd","vddd"]]).

:- end_tests(central_metadata).
