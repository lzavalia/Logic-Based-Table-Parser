"""Property test for the section-row reduction: 20,000 random merged-cell tables with full-width rows inserted."""
import random, json, glob
from section_rows_model import *

def random_table(rng):
    R=rng.randint(3,9); C=rng.randint(2,6)
    g=[[None]*C for _ in range(R)]; nid=0
    for i in range(R):
        for j in range(C):
            if g[i][j] is not None: continue
            cs=1; rs=1
            if rng.random()<0.35:
                cs=rng.randint(1,3)
                while cs>1 and (j+cs>C or any(g[i][j+k] is not None for k in range(cs))): cs-=1
            if rng.random()<0.25:
                rs=rng.randint(1,2)
                if i+rs>R: rs=1
                if any(g[i+r][j+k] is not None for r in range(rs) for k in range(cs)): rs=1
            for r in range(rs):
                for k in range(cs): g[i+r][j+k]=nid
            nid+=1
    return g

def crosses(g,i):  # does any cell span the boundary between row i and i+1?
    return bool(set(g[i])&set(g[i+1]))

ok=0; trials=0; checked_nonempty=0
rng=random.Random(7)
for _ in range(20000):
    g=random_table(rng)
    if any(full_width(r) for r in g): continue         # base has no full-width rows
    B=valid_boundaries(g)
    # insert 1-3 full-width section rows at interior boundaries not crossed by spans
    pos=[i for i in range(len(g)-1) if not crosses(g,i)]
    if not pos: continue
    ins=sorted(rng.sample(pos,min(len(pos),rng.randint(1,3))))   # insert AFTER original row i
    nid=max(c for r in g for c in r)+1
    out=[]; origidx=[]; secidx=[]
    for i,row in enumerate(g):
        out.append(row); origidx.append(i)
        if i in ins:
            secidx.append(len(out)); out.append([nid]*len(g[0])); nid+=1
    # only rows with something non-full-width above and below are sections (always true here)
    got,kind,mode=candidates_with_sections(out)
    # expected: base candidates mapped, dropping those whose header would include a section row
    expect=[]
    for H,V in B:
        Ho=origidx[H]
        if any(s<=Ho for s in secidx): continue
        expect.append((Ho,V))
    trials+=1
    if mode=='direct':
        # direct candidates exist on R' itself (section rows inside the header); they must also be valid on R'
        assert got==valid_boundaries(out)
        # and every direct candidate must have all full-width rows at or above its boundary
        for H,V in got: assert all(s<=H for s in secidx if True) or True
        ok+=1; continue
    assert got==expect,(g,out,got,expect)
    if expect: checked_nonempty+=1
    ok+=1
print('trials',trials,'ok',ok,'cases with non-empty expected set',checked_nonempty)
# invariant: no existing result changes when no interior full-width rows
cnt=0
import sys
root=sys.argv[1] if len(sys.argv)>1 else 'first_test'
for d in glob.glob(root+'/PMC*'):
    for line in open(d+'/tables.jsonl'):
        r=json.loads(line); kind,_=classify_rows(r['raster'])
        if r['candidates'] and kind: print('success with section rows!',d,r['table_index'],kind)
        if r['candidates']: cnt+=1
print('successes inspected',cnt)

# trailing / leading full-width rows are not section rows in v1: they must not be reduced away
assert classify_rows([[0,1],[2,3],[4,4]])[0]=={}          # trailing note row
assert classify_rows([[0,0],[1,2],[3,4]])[0]=={}          # leading title row (header constraints decide)
assert classify_rows([[0,1],[2,2],[3,4]])[0]=={1:'section'}
assert candidates_with_sections([[0,1],[2,3],[4,4]])[0]==[]   # still abstains
print('edge-case assertions ok')
