#!/usr/bin/env python3
"""Build a self-contained HTML page for reviewing gold candidate labels.

  python3 build_review_page.py DATASET_DIR SAMPLE.jsonl GOLD.jsonl OUT.html

SAMPLE lists the tables to review (table_uid, pmc_id, table_index,
complexity); GOLD holds the labels to start from, one row per table as in
gold_complex_test.provisional.jsonl. The page shows one table at a time,
coloured by the chosen candidate; choices are kept in the browser's local
storage and exported as gold JSONL (GOLD's name with ".provisional" replaced
by ".reviewed"), with labeler "human review".
Cell types are deliberately not shown, so the review stays blind to them.
"""
import json
import sys
from pathlib import Path

REGION_CODE = {"hmd": "h", "vmd": "v", "data": "d", "separator": "s"}


def describe(candidate):
    text = f"{candidate['hmd']} HMD row(s), {candidate['vmd']} VMD column(s)"
    if candidate["kind"] == "layout":
        seps = [s["row"] for s in candidate["separators"]]
        subs = candidate["subtables"]
        if seps:
            text += f"; rows {', '.join(map(str, seps))} set aside"
        if len(subs) > 1:
            parts = [f"rows {s['rows'][0]}–{s['rows'][-1]} × cols {s['columns'][0]}–{s['columns'][-1]}"
                     f" ({s['hmd']}H/{s['vmd']}V)" for s in subs]
            text += f"; {len(subs)} subtables: " + "; ".join(parts)
    return text


def table_entry(dataset, row, gold):
    path = Path(dataset, "papers", row["pmc_id"], "tables.jsonl")
    record = next(r for r in map(json.loads, path.read_text().splitlines())
                  if r["table_index"] == row["table_index"])
    n = len(record["cells"])
    candidates = []
    for c in record["candidates"]:
        codes = ["d"] * n
        for label in c["labels"]:
            codes[label["cell_id"]] = REGION_CODE[label["region"]]
        candidates.append({"id": c["candidate_id"], "short": c["candidate_id"].split("/")[-1],
                           "desc": describe(c), "regions": "".join(codes)})
    g = gold.get(row["table_uid"], {})
    return {
        "uid": row["table_uid"], "pmc": row["pmc_id"], "index": row["table_index"],
        "complexity": row.get("complexity", ""),
        "caption": ((record.get("context") or {}).get("caption") or "")[:600],
        "raster": record["raster"],
        "texts": [(c.get("text") or "")[:160] for c in record["cells"]],
        "candidates": candidates,
        "suggested": g.get("gold_candidate", "unset"),
        "confidence": g.get("confidence", ""),
        "note": g.get("note", ""),
    }


PAGE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Gold Label Review</title>
<style>
:root{--bg:#fafaf9;--fg:#1c1917;--muted:#57534e;--line:#d6d3d1;--card:#fff;
--hmd:#b7e4b0;--vmd:#b3cdf2;--data:#ececec;--sep:#e8dca0;--accent:#2563eb;--warn:#b45309}
@media (prefers-color-scheme: dark){:root{--bg:#1c1917;--fg:#f5f5f4;--muted:#a8a29e;--line:#44403c;--card:#292524;
--hmd:#2f5a2a;--vmd:#2b4466;--data:#3a3633;--sep:#5c5126;--accent:#60a5fa;--warn:#f59e0b}}
*{box-sizing:border-box}
body{margin:0;font:14px/1.45 system-ui,sans-serif;background:var(--bg);color:var(--fg)}
header{position:sticky;top:0;z-index:2;background:var(--bg);border-bottom:1px solid var(--line);padding:10px 16px;display:flex;gap:10px;align-items:center;flex-wrap:wrap}
header b{font-size:15px} button,select{font:inherit;padding:4px 10px;border:1px solid var(--line);border-radius:6px;background:var(--card);color:var(--fg);cursor:pointer}
button.primary{background:var(--accent);color:#fff;border-color:var(--accent)}
.progress{color:var(--muted)} main{padding:12px 16px;max-width:100%}
.meta{color:var(--muted);margin:2px 0 10px} .cap{margin:0 0 10px}
.layout{display:grid;grid-template-columns:minmax(260px,360px) 1fr;gap:16px;align-items:start}
@media (max-width:800px){.layout{grid-template-columns:1fr}}
.panel{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:10px}
.cand{display:block;padding:5px 6px;border-radius:6px;cursor:pointer}
.cand:hover{background:var(--bg)} .cand small{display:block;color:var(--muted);margin-left:22px}
.sugg{color:var(--warn);font-size:12px;margin-left:4px}
.wrap{overflow:auto;max-height:78vh;border:1px solid var(--line);border-radius:8px;background:var(--card)}
table.t{border-collapse:collapse;font-size:12px}
table.t td{border:1px solid var(--line);padding:2px 5px;vertical-align:top;max-width:200px;min-width:28px}
td.h{background:var(--hmd)} td.v{background:var(--vmd)} td.d{background:var(--data)} td.s{background:var(--sep)} td.n{background:var(--card)}
.rowno{color:var(--muted);font-size:10px;text-align:right;background:var(--bg)!important}
.legend span{display:inline-block;padding:0 6px;border-radius:4px;margin-right:4px}
textarea{width:100%;font:inherit;min-height:52px;background:var(--bg);color:var(--fg);border:1px solid var(--line);border-radius:6px;padding:4px}
.status{font-size:12px;color:var(--muted)}
</style></head><body>
<header>
 <b>Gold label review</b>
 <button id="prev">◀ Prev</button><button id="next">Next ▶</button>
 <select id="jump"></select>
 <span class="progress" id="progress"></span>
 <label><input type="checkbox" id="onlyTodo"> only unreviewed</label>
 <button class="primary" id="export">Export gold JSONL</button>
 <span class="legend"><span style="background:var(--hmd)">HMD</span><span style="background:var(--vmd)">VMD</span><span style="background:var(--data)">data</span><span style="background:var(--sep)">set aside</span></span>
</header>
<main>
 <h2 id="title" style="margin:4px 0;font-size:16px"></h2>
 <div class="meta" id="meta"></div>
 <p class="cap" id="caption"></p>
 <div class="layout">
  <div class="panel">
   <div id="cands"></div>
   <p style="margin:10px 0 4px">Confidence:
    <label><input type="radio" name="conf" value="high"> high</label>
    <label><input type="radio" name="conf" value="low"> low</label></p>
   <textarea id="note" placeholder="note"></textarea>
   <p><button id="accept" class="primary">Mark reviewed &amp; next</button></p>
   <p class="status" id="status"></p>
  </div>
  <div class="wrap"><table class="t" id="grid"></table></div>
 </div>
</main>
<script id="data" type="application/json">__DATA__</script>
<script>
const TABLES = JSON.parse(document.getElementById('data').textContent);
const KEY = 'gold-review:' + __KEY__;
let state = {};
try { state = JSON.parse(localStorage.getItem(KEY) || '{}'); } catch (e) { state = {}; }
function save(){ try { localStorage.setItem(KEY, JSON.stringify(state)); } catch (e) {} }
function entry(t){
  if (!state[t.uid]) state[t.uid] = {choice: t.suggested, confidence: t.confidence, note: t.note, reviewed: false};
  return state[t.uid];
}
let i = 0;
const $ = id => document.getElementById(id);
function order(){ return $('onlyTodo').checked ? TABLES.map((t,k)=>k).filter(k=>!entry(TABLES[k]).reviewed) : TABLES.map((t,k)=>k); }
function render(){
  const t = TABLES[i], e = entry(t);
  $('title').textContent = t.uid + '  (' + (i+1) + ' / ' + TABLES.length + ')';
  $('meta').textContent = 'class: ' + t.complexity + ' · ' + t.raster.length + '×' + t.raster[0].length + ' · ' + t.candidates.length + ' candidates' + (e.reviewed ? ' · reviewed' : '');
  $('caption').textContent = t.caption;
  const box = $('cands'); box.innerHTML = '';
  const opts = t.candidates.map(c => ({id:c.id, short:c.short, desc:c.desc})).concat([{id:null, short:'none', desc:'No candidate is correct'}]);
  for (const o of opts){
    const lab = document.createElement('label'); lab.className = 'cand';
    const r = document.createElement('input'); r.type = 'radio'; r.name = 'cand'; r.checked = (e.choice === o.id);
    r.onchange = () => { e.choice = o.id; save(); paint(); };
    lab.append(r, ' ' + o.short);
    if (t.suggested === o.id) { const s = document.createElement('span'); s.className='sugg'; s.textContent='Claude\'s pick'; lab.append(s); }
    const sm = document.createElement('small'); sm.textContent = o.desc; lab.append(sm);
    box.append(lab);
  }
  document.querySelectorAll('input[name=conf]').forEach(r => { r.checked = (r.value === e.confidence); r.onchange = () => { e.confidence = r.value; save(); }; });
  $('note').value = e.note || ''; $('note').oninput = ev => { e.note = ev.target.value; save(); };
  $('jump').value = String(i);
  const done = TABLES.filter(x => entry(x).reviewed).length;
  $('progress').textContent = done + ' reviewed';
  paint();
}
function paint(){
  const t = TABLES[i], e = entry(t);
  const cand = t.candidates.find(c => c.id === e.choice);
  const grid = $('grid'); grid.innerHTML = '';
  const seen = new Set(), ext = {};
  t.raster.forEach((row, r) => row.forEach((id, c) => {
    const x = ext[id]; if (!x) ext[id] = [r, c, r, c]; else { x[2] = Math.max(x[2], r); x[3] = Math.max(x[3], c); }
  }));
  t.raster.forEach((row, r) => {
    const tr = document.createElement('tr');
    const no = document.createElement('td'); no.className = 'rowno'; no.textContent = r; tr.append(no);
    row.forEach((id, c) => {
      if (seen.has(id)) return; seen.add(id);
      const [r0, c0, r1, c1] = ext[id];
      const td = document.createElement('td');
      td.rowSpan = r1 - r0 + 1; td.colSpan = c1 - c0 + 1;
      td.className = cand ? cand.regions[id] : 'n';
      td.textContent = t.texts[id];
      tr.append(td);
    });
    grid.append(tr);
  });
  $('status').textContent = cand ? 'Showing ' + cand.short : 'No candidate selected (none correct)';
}
function go(delta){
  const ord = order(); if (!ord.length) return;
  let k = ord.indexOf(i);
  k = k < 0 ? 0 : Math.min(Math.max(k + delta, 0), ord.length - 1);
  i = ord[k]; render();
}
TABLES.forEach((t, k) => { const o = document.createElement('option'); o.value = k; o.textContent = (k+1) + '. ' + t.uid; $('jump').append(o); });
$('jump').onchange = ev => { i = +ev.target.value; render(); };
$('prev').onclick = () => go(-1); $('next').onclick = () => go(1);
$('onlyTodo').onchange = () => go(0);
$('accept').onclick = () => { entry(TABLES[i]).reviewed = true; save(); go(1); };
document.addEventListener('keydown', ev => {
  if (ev.target.tagName === 'TEXTAREA') return;
  if (ev.key === 'ArrowRight') go(1); if (ev.key === 'ArrowLeft') go(-1);
});
$('export').onclick = () => {
  const lines = TABLES.map(t => { const e = entry(t); return JSON.stringify({
    pmc_id: t.pmc, table_index: t.index, table_uid: t.uid, gold_candidate: e.choice,
    confidence: e.confidence || 'high', note: e.note || '', reviewed: !!e.reviewed,
    labeler: e.reviewed ? 'human review' : 'claude-opus-5-5 (provisional, not human gold)'}); });
  const blob = new Blob([lines.join('\n') + '\n'], {type: 'application/jsonl'});
  const a = document.createElement('a'); a.href = URL.createObjectURL(blob);
  a.download = __EXPORT__; a.click();
};
render();
</script></body></html>
"""


def main():
    dataset, sample_file, gold_file, out = sys.argv[1:5]
    sample = [json.loads(l) for l in Path(sample_file).read_text().splitlines() if l.strip()]
    gold = {r["table_uid"]: r for r in map(json.loads, Path(gold_file).read_text().splitlines()) if r}
    tables = [table_entry(dataset, row, gold) for row in sample]
    data = json.dumps(tables, ensure_ascii=False).replace("</", "<\\/")
    export = Path(gold_file).name.replace(".provisional", "").replace(".jsonl", ".reviewed.jsonl")
    html = (PAGE.replace("__DATA__", data)
                .replace("__KEY__", json.dumps(Path(sample_file).stem))
                .replace("__EXPORT__", json.dumps(export)))
    Path(out).write_text(html, encoding="utf-8")
    print(f"{len(tables)} tables -> {out} ({Path(out).stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
