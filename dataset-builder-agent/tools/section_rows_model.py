"""Reference model for section-row support (design doc: docs/section-rows-design.md).
Independent Python port of the seven constraints plus the proposed reduction."""
import json, glob, sys

def rng(a,b): return range(a,b)

def constraints(R,H,V):
    NR=len(R); NC=len(R[0]); res={}
    res[0]=not any(R[i][V]==R[i][V+1] for i in rng(H+1,NR))
    res[1]=not any(R[H][j]==R[H+1][j] for j in rng(V,NC))
    res[2]=all(any(R[i][j]==R[i][j+1] and R[i+1][j]!=R[i+1][j+1] for j in rng(V+1,NC-1)) for i in rng(0,H))
    res[3]=all(any(R[i][j]==R[i+1][j] and R[i][j+1]!=R[i+1][j+1] for i in rng(H+1,NR-1)) for j in rng(0,V))
    res[4]=not any(R[i][j]!=R[i][j+1] and R[i+1][j]==R[i+1][j+1] for i in rng(0,H) for j in rng(V+1,NC-1))
    res[5]=not any(R[i][j]!=R[i+1][j] and R[i][j+1]==R[i+1][j+1] for j in rng(0,V) for i in rng(H,NR-1))
    res[6]=not any(R[H][j]==R[H][j+1] for j in rng(V,NC-1))
    return res

def valid_boundaries(R):
    if len(R)<2 or len(R[0])<2: return []
    out=[]
    for H in range(len(R)-1):
        for V in range(len(R[0])-1):
            if all(constraints(R,H,V).values()): out.append((H,V))
    return out

def full_width(row): return len(row)>=2 and len(set(row))==1

def classify_rows(R):
    """v1: a section row is a full-width row with a non-full-width row above AND below.
       Leading full-width rows (title rows inside the header) are left to the existing
       constraints; trailing full-width rows (notes, footers) are NOT handled in v1."""
    fw=[full_width(r) for r in R]
    nf=[i for i,f in enumerate(fw) if not f]
    if not nf: return {}, []
    first,last=nf[0],nf[-1]
    kind={i:'section' for i,f in enumerate(fw) if f and first<i<last}
    return kind, nf

def reduce_raster(R, drop):
    keep=[i for i in range(len(R)) if i not in drop]
    return [R[i] for i in keep], keep

def candidates_with_sections(R):
    base=valid_boundaries(R)
    if base: return base,{},'direct'
    kind,_=classify_rows(R)
    if not kind: return [],{},'none'
    Rr,keep=reduce_raster(R,set(kind))
    cands=[]
    for H,V in valid_boundaries(Rr):
        Ho=keep[H]
        # reject if a removed row lies inside the header (rows 0..Ho)
        if any(k<=Ho for k in kind): continue
        cands.append((Ho,V))
    return cands,kind,'reduced'

if __name__=='__main__':
    # usage: python3 section_rows_model.py path/to/first_test   (dir holding PMC*/tables.jsonl)
    root=sys.argv[1] if len(sys.argv)>1 else 'first_test'
    tot=0; direct=0; rec=0; still=[]
    for d in sorted(glob.glob(root+'/PMC*')):
        for line in open(d+'/tables.jsonl'):
            r=json.loads(line); R=r['raster']; tot+=1
            orig=[(c['hmd'],c['vmd']) for c in r['candidates']]
            c,kind,mode=candidates_with_sections(R)
            name=f"{d.split('/')[-1]} t{r['table_index']} {r['rows']}x{r['columns']}"
            if orig:
                assert c==orig and mode=='direct', (name,c,orig,mode)   # no regression
                direct+=1
            else:
                if c: rec+=1
                print(name,'abstained -> ',c,'sections',kind,mode)
                if not c: still.append(name)
    print('tables',tot,'unchanged successes',direct,'recovered',rec,'still abstained',still)
