#!/usr/bin/env python3
"""Copy the papers of an ablation sample into a fresh dataset under src/.

  python3 prepare_dataset.py SAMPLE.jsonl DATASET_DIR

DATASET_DIR must lie under dataset-builder-agent/src/, since DeepClause sees
no files outside its workspace (run_ablation.sh uses src/ablation/<name>/dataset,
which .gitignore covers). It is emptied first. Only tables.jsonl and
metadata.json are copied, from the dataset each sample line names: every arm
starts from the same built tables, and nothing from an earlier review or
type inference is carried over.
"""
import json
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
TA = HERE.parent / "type_abstraction"
SRC = HERE.parent.parent / "src"


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sample = [json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines() if line.strip()]
    dataset = Path(sys.argv[2]).resolve()
    if SRC.resolve() not in dataset.parents:
        sys.exit(f"error: {dataset} is not under {SRC}")
    if dataset.exists():
        shutil.rmtree(dataset)
    papers = dataset / "papers"
    papers.mkdir(parents=True)
    copied = set()
    for row in sample:
        if row["pmc_id"] in copied:
            continue
        source = TA / row["source"] / "papers" / row["pmc_id"]
        target = papers / row["pmc_id"]
        target.mkdir()
        for name in ("tables.jsonl", "metadata.json"):
            if (source / name).exists():
                shutil.copy2(source / name, target / name)
        if not (target / "tables.jsonl").exists():
            sys.exit(f"error: {source}/tables.jsonl is missing")
        uids = {json.loads(l)["table_uid"] for l in (target / "tables.jsonl").read_text().splitlines() if l.strip()}
        if row["table_uid"] not in uids:
            sys.exit(f"error: {row['table_uid']} is not in {source}/tables.jsonl")
        copied.add(row["pmc_id"])
    print(f"{len(copied)} paper(s) copied to {dataset}")


if __name__ == "__main__":
    main()
