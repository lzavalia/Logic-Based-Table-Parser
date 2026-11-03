#!/usr/bin/env python3
"""Download the JATS XML of the experiment's papers from NCBI.

  python3 fetch_papers.py OUT_DIR [PAPERS_JSON]

PAPERS_JSON defaults to papers.json next to this script.

The ids are fixed in papers.json because search results change over time.
No API key is needed; requests are spaced 0.45 s apart.
"""
import json
import sys
import time
import urllib.request
from pathlib import Path

EFETCH = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pmc&retmode=xml&id="

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
papers = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).with_name("papers.json")
for pmc in json.loads(papers.read_text()):
    target = out / f"PMC{pmc}.xml"
    if target.exists():
        continue
    time.sleep(0.45)
    with urllib.request.urlopen(EFETCH + pmc, timeout=60) as response:
        target.write_bytes(response.read())
