#!/usr/bin/env python3
"""Independent geometry-model replay for F12 (NOT a SWI-Prolog execution).

Valid layouts must not change with strict collision detection. Deliberate
conflicts must not silently lose source cells. Requires only Python stdlib.
"""
from __future__ import annotations

import random


class Overlap(Exception):
    def __init__(self, new_id: int, row: int, col: int, previous: int):
        self.info = new_id, row, col, previous


def rasterize(rows: list[list[tuple[int, int]]], *, strict: bool):
    grid: dict[tuple[int, int], int] = {}
    next_id = 0
    for r, row in enumerate(rows):
        col = 0
        for colspan, rowspan in row:
            assert colspan >= 1 and rowspan >= 1
            while (r, col) in grid:
                col += 1
            for rr in range(r, min(len(rows), r + rowspan)):
                for cc in range(col, col + colspan):
                    key = rr, cc
                    if key in grid:
                        if strict:
                            raise Overlap(next_id, rr, cc, grid[key])
                    else:
                        grid[key] = next_id
            col += colspan
            next_id += 1
    if not next_id:
        raise ValueError('empty source table')
    ids = set(grid.values())
    missing = set(range(next_id)) - ids
    if missing and strict:
        raise ValueError(f'unmapped source cells {sorted(missing)}')
    width = max(c for _, c in grid) + 1
    padded = [[grid.get((r, c)) for c in range(width)] for r in range(len(rows))]
    nxt = next_id
    for row in padded:
        for c, cell_id in enumerate(row):
            if cell_id is None:
                row[c] = nxt
                nxt += 1
    return padded, next_id, missing


def main() -> None:
    cases = [
        ( [[(1, 2), (1, 1), (1, 2)], [(2, 1)]], (3, 1, 2, 2)),
        ( [[(2, 2), (1, 3)], [], [(3, 1)]], (2, 2, 2, 1)),
    ]
    for rows, expected in cases:
        try:
            rasterize(rows, strict=True)
        except Overlap as exc:
            assert exc.info == expected, (exc.info, expected)
        else:
            raise AssertionError('missed overlap')
    assert rasterize([[(1, 2), (2, 1)], [(1, 1), (1, 1)]], strict=True)[0] == [
        [0, 1, 1], [0, 2, 3]]
    assert rasterize([[(1, 1), (1, 1), (1, 1)], [(1, 1), (1, 1)]], strict=True)[0] == [
        [0, 1, 2], [3, 4, 5]]
    rng = random.Random(20261009)
    counts = {'safe': 0, 'overlap': 0}
    for _ in range(25000):
        height = rng.randint(1, 8)
        rows = [[(rng.randint(1, 4), rng.randint(1, 5))
                 for _ in range(rng.randint(0, 6))]
                for _ in range(height)]
        if not any(rows):
            continue
        original, _, missing = rasterize(rows, strict=False)
        try:
            checked, _, _ = rasterize(rows, strict=True)
        except Overlap:
            counts['overlap'] += 1
            # first_free_col protects the starting slot, but a later slot
            # in the same rectangle can be lost silently in the old policy.
        else:
            assert checked == original, 'valid-table raster changed'
            assert not missing, 'valid-table source cell lost'
            counts['safe'] += 1
    assert counts['safe'] and counts['overlap']
    print('Independent model replay passed:', counts,
          '(25,000 seeded geometry configurations; not native Prolog tests)')


if __name__ == '__main__':
    main()
