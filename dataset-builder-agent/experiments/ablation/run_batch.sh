#!/usr/bin/env bash
# Draw, prepare, check and run one batch of the ablation study (see README.md).
#
#   experiments/ablation/run_batch.sh <name> <seed> [size] [--yes]
#
#   <name>   the batch's name, e.g. 18; the files are batch<name>_sample.jsonl
#            and batch<name>_gold.jsonl here, the results results/batch<name>-<UTC>/
#   <seed>   the sampling seed
#   [size]   tables to draw (default 10); fewer when fewer papers are left
#   --yes    do not ask before the paid model calls
#
# The batch is drawn with make_sample.py --batch from the human-labelled
# tables that no earlier sample (smoke_sample.jsonl, batch*_sample.jsonl)
# holds, so no table is paid for twice. Its papers are copied into data/
# here, and before any model call the collector is run on the fresh dataset
# to check that every gold candidate resolves to a segmentation.

set -euo pipefail

yes=()
args=()
for a in "$@"; do
    case "$a" in
        --yes) yes=(--yes) ;;
        *) args+=("$a") ;;
    esac
done
[ "${#args[@]}" -ge 2 ] || { sed -n '2,17p' "$0"; exit 2; }
name="${args[0]}"; seed="${args[1]}"; size="${args[2]:-10}"

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
cd "$here"
sample="batch${name}_sample.jsonl"
gold="batch${name}_gold.jsonl"
[ -e "$sample" ] && { echo "error: batch $name is already drawn ($sample)" >&2; exit 1; }

exclude=$(ls smoke_sample.jsonl batch*_sample.jsonl | paste -sd, -)
python3 make_sample.py "$sample" --batch "$size" --gold-out "$gold" --exclude "$exclude" --seed "$seed"

# Keep the batch's papers in the repository, as for the smoke sample.
python3 - "$sample" <<'EOF'
import json, shutil, sys
from pathlib import Path
TA = Path("../type_abstraction")
for line in open(sys.argv[1]):
    row = json.loads(line)
    src = TA / row["source"] / "papers" / row["pmc_id"]
    dst = Path(row["source"]) / "papers" / row["pmc_id"]
    if dst.exists():
        if (dst / "tables.jsonl").read_bytes() != (src / "tables.jsonl").read_bytes():
            sys.exit(f"error: {dst}/tables.jsonl differs from {src}")
        continue
    dst.mkdir(parents=True)
    for f in ("tables.jsonl", "metadata.json"):
        if (src / f).exists():
            shutil.copy2(src / f, dst / f)
EOF

dataset_rel="ablation/batch${name}/dataset"
python3 prepare_dataset.py "$sample" "$root/src/$dataset_rel"
check="$(mktemp)"
trap 'rm -f "$check"' EXIT
(cd "$root/src" && swipl ablation_collect.pl --dataset="$dataset_rel" \
    --sample="$here/$sample" --gold="$here/$gold" --arms=full --output="$check" < /dev/null)
python3 -c '
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
ok = sum(bool(r["gold_segmentation"]) for r in rows)
print(f"{ok} of {len(rows)} gold labels resolve")
sys.exit(ok != len(rows))' "$check"

"$here/run_ablation.sh" --name "batch${name}" --sample "$here/$sample" --gold "$here/$gold" ${yes[@]+"${yes[@]}"}
