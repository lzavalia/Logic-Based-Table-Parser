#!/usr/bin/env python3
"""Search PubMed Central for open-access papers and record their ids.

  python3 search_papers.py OUT.json PER_QUERY "query one" "query two" ...

Writes {pmc_id: query} for the first PER_QUERY results of each query, by
relevance, skipping ids already listed in papers.json (the first dataset) and
ids found by an earlier query.
"""
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ESEARCH = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"

out, per_query, queries = Path(sys.argv[1]), int(sys.argv[2]), sys.argv[3:]
known = set(json.loads(Path(__file__).with_name("papers.json").read_text()))
found = {}
for query in queries:
    term = urllib.parse.quote(f"{query} AND open access[filter]")
    time.sleep(0.45)
    url = f"{ESEARCH}?db=pmc&retmode=json&sort=relevance&retmax={per_query * 2}&term={term}"
    with urllib.request.urlopen(url, timeout=60) as response:
        ids = json.loads(response.read())["esearchresult"]["idlist"]
    kept = [i for i in ids if i not in known and i not in found][:per_query]
    found.update((i, query) for i in kept)
    print(f"{len(kept):3} {query}")
out.write_text(json.dumps(found, indent=1) + "\n")
print(len(found), "papers")
