#!/usr/bin/env bash
# Run every human-labelled table no earlier batch has run, as one last batch.
#
#   experiments/ablation/run_remaining.sh <name> <seed> [--yes]
#
# A run may hold only one table per paper: review_agent.sh --tables marks a
# paper's other tables not_selected in its review file, which the collector
# reads. So the batch runs in rounds <name>a, <name>b, ..., each drawing at
# most one table per paper, until no table is left. Pool the rounds with
# pool_ablation.py. Seeds are <seed>, <seed>+1, ... per round.

set -euo pipefail

yes=()
args=()
for a in "$@"; do
    case "$a" in
        --yes) yes=(--yes) ;;
        *) args+=("$a") ;;
    esac
done
[ "${#args[@]}" -eq 2 ] || { sed -n '2,10p' "$0"; exit 2; }
name="${args[0]}"; seed="${args[1]}"
here="$(cd "$(dirname "$0")" && pwd)"

left() {
    (cd "$here" && python3 make_sample.py /dev/null --batch 1000 --gold-out /dev/null \
        --exclude "$(ls smoke_sample.jsonl batch*_sample.jsonl | paste -sd, -)" 2>&1 | tail -1 || true)
}

for round in a b c d e f g h i j k l m n o p q r s t u v w x y z; do
    case "$(left)" in *"no human-labelled"*) echo "No human-labelled table is left."; exit 0 ;; esac
    echo "=== round ${name}${round}"
    "$here/run_batch.sh" "${name}${round}" "$seed" 1000 ${yes[@]+"${yes[@]}"}
    seed=$((seed + 1))
done
echo "error: tables are still left after 26 rounds" >&2
exit 1
