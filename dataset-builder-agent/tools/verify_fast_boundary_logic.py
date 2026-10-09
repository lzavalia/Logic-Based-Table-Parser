#!/usr/bin/env python3
"""Independent algebraic cross-check, not Prolog execution.

Replays the seven predicate conditions directly and compares their results
against the indexed-summary formulas in fast_boundaries.pl, including exact
ordering. Native SWI-Prolog differential tests are in src/*scaling*tests.pl.
"""
from itertools import product
from random import Random


def reference(m):
    r, c = len(m), len(m[0])
    pairs = []
    for h in range(r - 1):
        for v in range(c - 1):
            conditions = (
                all(m[i][v] != m[i][v + 1] for i in range(h + 1, r)),
                all(m[h][j] != m[h + 1][j] for j in range(v, c)),
                all(any(m[i][j] == m[i][j + 1] and m[i + 1][j] != m[i + 1][j + 1]
                        for j in range(v + 1, c - 1)) for i in range(h)),
                all(any(m[i][j] == m[i + 1][j] and m[i][j + 1] != m[i + 1][j + 1]
                        for i in range(h + 1, r - 1)) for j in range(v)),
                all(not (m[i][j] != m[i][j + 1] and m[i + 1][j] == m[i + 1][j + 1])
                    for i in range(h) for j in range(v + 1, c - 1)),
                all(not (m[i][j] != m[i + 1][j] and m[i][j + 1] == m[i + 1][j + 1])
                    for j in range(v) for i in range(h, r - 1)),
                all(m[h][j] != m[h][j + 1] for j in range(v, c - 1)),
            )
            if all(conditions):
                pairs.append((h, v))
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
    found = []
    for h in range(r - 1):
        lo = max(0, crossing[h] + 1, key[h] + 1, r_inv_max[h])
        hi = min(c - 2, r_split_min[h] - 1)
        for v in range(lo, hi + 1):
            if c_same[v] <= h and c_split_min[v] > h and c_inv_max[v] < h:
                found.append((h, v))
    return found


def main():
    count = 0
    for rows, cols in [(2, 2), (2, 3), (3, 2), (3, 3), (3, 4), (4, 3)]:
        for flat in product(range(2), repeat=rows * cols):
            raster = [flat[i * cols:(i + 1) * cols] for i in range(rows)]
            assert fast(raster) == reference(raster), (raster, fast(raster), reference(raster))
            count += 1
    rnd = Random(20261009)
    for _ in range(30000):
        rows, cols = rnd.randint(2, 18), rnd.randint(2, 18)
        distinct = rnd.randint(1, 8)
        raster = [[rnd.randrange(distinct) for _ in range(cols)] for _ in range(rows)]
        assert fast(raster) == reference(raster), (raster, fast(raster), reference(raster))
        count += 1
    print(f'PASS: {count} independently replayed grids; exact candidate sets and order match')


if __name__ == '__main__':
    main()
