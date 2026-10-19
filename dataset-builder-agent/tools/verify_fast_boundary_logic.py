#!/usr/bin/env python3
"""Independent algebraic cross-check, not Prolog execution.

Replays the ten constraint conditions of parse_constraints.pl directly, with
boundaries as counts (hmd HMD rows, vmd VMD columns, either may be 0), and
compares them against the indexed-summary formulas in fast_boundaries.pl,
including exact ordering. Native SWI-Prolog differential tests are in
tests/*scaling*tests.pl.
"""
from itertools import product
from random import Random


def reference(m):
    r, c = len(m), len(m[0])
    plain = len({x for row in m for x in row}) == r * c
    pairs = []
    for hmd in range(r + 1):
        for vmd in range(c + 1):
            h, v = hmd - 1, vmd - 1      # last HMD row / last VMD column
            conditions = (
                hmd > 0 or vmd > 0,                       # 7: not all data
                hmd < r and vmd < c,                      # 8: not all metadata
                hmd > 0 or plain,                         # 9: no HMD only if plain
                vmd == 0 or vmd == c or
                all(m[i][v] != m[i][v + 1] for i in range(hmd, r)),
                hmd == 0 or hmd == r or
                all(m[h][j] != m[h + 1][j] for j in range(max(0, v), c)),
                all(any(m[i][j] == m[i][j + 1] and m[i + 1][j] != m[i + 1][j + 1]
                        for j in range(vmd, c - 1)) for i in range(hmd - 1)),
                all(any(m[i][j] == m[i + 1][j] and m[i][j + 1] != m[i + 1][j + 1]
                        for i in range(hmd, r - 1)) for j in range(vmd - 1)),
                all(not (m[i][j] != m[i][j + 1] and m[i + 1][j] == m[i + 1][j + 1])
                    for i in range(hmd - 1) for j in range(vmd, c - 1)),
                all(not (m[i][j] != m[i + 1][j] and m[i][j + 1] == m[i + 1][j + 1])
                    for j in range(vmd - 1) for i in range(max(0, h), r - 1)),
                hmd == 0 or
                all(m[h][j] != m[h][j + 1] for j in range(max(0, v), c - 1)),
            )
            if all(conditions):
                pairs.append((hmd, vmd))
    return pairs


def fast(m):
    r, c = len(m), len(m[0])
    key = [-1] * r
    crossing = [-1] * (r - 1)
    r_split = [-1] * (r - 1)
    r_invert = [-1] * (r - 1)
    c_same = [-1] * (c - 1)
    c_split = [-1] * (c - 1)
    c_invert = [-1] * (c - 1)
    for i in range(r):
        for j in range(c - 1):
            if m[i][j] == m[i][j + 1]:
                key[i] = j
                c_same[j] = i
        if i == r - 1:
            break
        for j in range(c):
            if m[i][j] == m[i + 1][j]:
                crossing[i] = j
            if j == c - 1:
                continue
            if m[i][j] == m[i][j + 1] and m[i + 1][j] != m[i + 1][j + 1]:
                r_split[i] = j
            if m[i][j] != m[i][j + 1] and m[i + 1][j] == m[i + 1][j + 1]:
                r_invert[i] = j
            if m[i][j] == m[i + 1][j] and m[i][j + 1] != m[i + 1][j + 1]:
                c_split[j] = i
            if m[i][j] != m[i + 1][j] and m[i][j + 1] == m[i + 1][j + 1]:
                c_invert[j] = i

    def prefixes(ws, ivs, sentinel):
        mn, mx = [sentinel], [-1]
        for w, x in zip(ws, ivs):
            mn.append(min(mn[-1], w))
            mx.append(max(mx[-1], x))
        return mn, mx

    r_split_min, r_inv_max = prefixes(r_split, r_invert, c)
    c_split_min, c_inv_max = prefixes(c_split, c_invert, r)
    def column_checks(h, v):
        return c_same[v] <= h and c_split_min[v] > h and c_inv_max[v] < max(h, 0)

    found = []
    # No HMD rows: only for a plain grid (9); then only the column rules
    # apply, and vmd >= 1 by constraint 7.
    plain = len({x for row in m for x in row}) == r * c
    for v in range(c - 1):
        if plain and column_checks(-1, v):
            found.append((0, v + 1))
    for h in range(r - 1):
        # No VMD columns: the row rules apply from column 0.
        if (key[h] < 0 and crossing[h] < 0 and r_inv_max[h] < 0
                and r_split_min[h] >= 0):
            found.append((h + 1, 0))
        lo = max(0, crossing[h] + 1, key[h] + 1, r_inv_max[h])
        hi = min(c - 2, r_split_min[h] - 1)
        for v in range(lo, hi + 1):
            if column_checks(h, v):
                found.append((h + 1, v + 1))
    return found


def main():
    count = 0
    for rows, cols in [(1, 1), (1, 4), (4, 1), (2, 2), (2, 3), (3, 2), (3, 3), (3, 4), (4, 3)]:
        for flat in product(range(2), repeat=rows * cols):
            raster = [flat[i * cols:(i + 1) * cols] for i in range(rows)]
            assert fast(raster) == reference(raster), (raster, fast(raster), reference(raster))
            count += 1
    rnd = Random(20261009)
    for _ in range(30000):
        rows, cols = rnd.randint(1, 18), rnd.randint(1, 18)
        distinct = rnd.randint(1, 8)
        raster = [[rnd.randrange(distinct) for _ in range(cols)] for _ in range(rows)]
        assert fast(raster) == reference(raster), (raster, fast(raster), reference(raster))
        count += 1
    print(f'PASS: {count} independently replayed grids; exact candidate sets and order match')


if __name__ == '__main__':
    main()
