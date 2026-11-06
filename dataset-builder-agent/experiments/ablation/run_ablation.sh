#!/usr/bin/env bash
# Run the ablation study on a table sample: every arm on every table, one
# DeepClause run per table so that tokens are counted per table, then collect
# and score the results (see README.md).
#
#   experiments/ablation/run_ablation.sh
#   experiments/ablation/run_ablation.sh --arms llm-only --yes
#   experiments/ablation/run_ablation.sh --sample my_sample.jsonl --gold my_gold.jsonl
#
#   --name <name>       the run's name (default smoke); the dataset is
#                       src/ablation/<name>/dataset, rebuilt fresh, and the
#                       results go to experiments/ablation/results/<name>-<UTC time>/
#   --sample <file>     the tables (default smoke_sample.jsonl, from make_sample.py)
#   --gold <file>       their gold labels (default smoke_gold.jsonl)
#   --arms <list>       comma-separated, from llm-only, constraints, full
#                       (default all three, in that order)
#   --model <id>        default anthropic:claude-haiku-5-5
#   --program <file>    the full arm's type DSL program (default
#                       type_dsl_examples/sci.tdsl, as in review_agent.sh)
#   --level <level>     the full arm's type comparison, family (default) or group
#   --input-price <x>   USD per million input tokens, to report a cost
#   --output-price <x>  USD per million output tokens
#   --yes               do not ask for confirmation before the model calls
#
# Every arm runs at temperature 0 (review_agent.sh) and with --force, so the
# run never reuses an earlier review. A table whose call fails is recorded and
# the run goes on. The collector reads each call's own copy of the paper's
# review and export, so a sample may hold several tables of one paper. A
# local src/budget_guard.mjs, if present, caps each call's
# spending as in review_agent.sh (BUDGET_USD, default 5).

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
name=smoke
sample="$here/smoke_sample.jsonl"
gold="$here/smoke_gold.jsonl"
arms="llm-only,constraints,full"
model="anthropic:claude-haiku-5-5"
program="$root/type_dsl_examples/sci.tdsl"
level=family
prices=()
yes=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --name) name="$2"; shift 2 ;;
        --sample) sample="$2"; shift 2 ;;
        --gold) gold="$2"; shift 2 ;;
        --arms) arms="$2"; shift 2 ;;
        --model) model="$2"; shift 2 ;;
        --program) program="$2"; shift 2 ;;
        --level) level="$2"; shift 2 ;;
        --input-price) prices+=(--input-price "$2"); shift 2 ;;
        --output-price) prices+=(--output-price "$2"); shift 2 ;;
        --yes) yes=true; shift ;;
        -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
        *) echo "error: unknown option $1" >&2; exit 2 ;;
    esac
done

case "$name" in
    *[!A-Za-z0-9_-]*|"") echo "error: --name may only use letters, digits, - and _." >&2; exit 2 ;;
esac
for f in "$sample" "$gold" "$program"; do
    [ -r "$f" ] || { echo "error: cannot read $f" >&2; exit 1; }
done
sample="$(cd "$(dirname "$sample")" && pwd)/$(basename "$sample")"
gold="$(cd "$(dirname "$gold")" && pwd)/$(basename "$gold")"
program="$(cd "$(dirname "$program")" && pwd)/$(basename "$program")"
case "$level" in
    family|group) ;;
    *) echo "error: --level must be family or group" >&2; exit 2 ;;
esac
IFS=',' read -r -a arm_list <<< "$arms"
for arm in "${arm_list[@]}"; do
    case "$arm" in
        llm-only|constraints|full) ;;
        *) echo "error: unknown arm '$arm'" >&2; exit 2 ;;
    esac
done
command -v deepclause >/dev/null || { echo "error: deepclause not found" >&2; exit 127; }
command -v swipl >/dev/null || { echo "error: swipl not found" >&2; exit 127; }

uids=()
while IFS= read -r uid; do uids+=("$uid"); done < <(
    python3 -c 'import json,sys
for l in open(sys.argv[1]):
    if l.strip(): print(json.loads(l)["table_uid"])' "$sample")
calls=$(( ${#uids[@]} * ${#arm_list[@]} ))

dataset_rel="ablation/$name/dataset"
run_dir="$here/results/$name-$(date -u +%Y%m%dT%H%M%SZ)"

echo "Ablation run '$name'"
echo "  tables:  ${#uids[@]} (from $sample)"
echo "  arms:    ${arm_list[*]}"
echo "  model:   $model"
echo "  full:    program $(basename "$program"), level $level"
echo "  runs:    $calls DeepClause runs (one per table and arm)"
echo "  dataset: src/$dataset_rel (rebuilt)"
echo "  results: $run_dir"
if [ "$yes" != true ]; then
    read -r -p "This makes paid model calls. Continue? [y/N] " reply
    case "$reply" in y|Y|yes) ;; *) echo "Stopped."; exit 1 ;; esac
fi

python3 "$here/prepare_dataset.py" "$sample" "$root/src/$dataset_rel" || exit 1
mkdir -p "$run_dir" || exit 1
cp "$sample" "$run_dir/sample.jsonl"
cp "$gold" "$run_dir/gold.jsonl"
python3 - "$run_dir/manifest.json" "$name" "$model" "$arms" "$dataset_rel" "$program" "$level" <<'EOF'
import hashlib, json, os, subprocess, sys, time
out, name, model, arms, dataset, program, level = sys.argv[1:]
commit = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
dirty = bool(subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True).stdout.strip())
json.dump({"name": name, "model": model, "arms": arms.split(","), "dataset": "src/" + dataset,
           "started_unix": time.time(), "git_commit": commit, "git_dirty": dirty,
           "full_program": os.path.basename(program),
           "full_program_sha256": hashlib.sha256(open(program, "rb").read()).hexdigest(),
           "full_level": level},
          open(out, "w"), indent=1)
EOF

failures=0
for arm in "${arm_list[@]}"; do
    for uid in "${uids[@]}"; do
        dir="$run_dir/$arm/${uid//\//_}"
        mkdir -p "$dir"
        echo
        echo "== $arm  $uid"
        full_opts=()
        [ "$arm" = full ] && full_opts=(--program "$program" --level "$level")
        "$root/review_agent.sh" --arm "$arm" --dataset "$dataset_rel" \
            --tables "$uid" --force --model "$model" --log-dir "$dir" \
            ${full_opts[@]+"${full_opts[@]}"} > "$dir/stdout.txt" 2>&1
        status=$?
        echo "$status" > "$dir/exit_status"
        tail -n 12 "$dir/stdout.txt"
        if [ "$status" -ne 0 ]; then
            echo "!! $arm $uid exited with status $status (see $dir/stdout.txt)" >&2
            failures=$((failures + 1))
        fi
        # Keep the paper's files as this call left them.
        paper="$root/src/$dataset_rel/papers/${uid%%/*}"
        if [ "$arm" = full ]; then
            files="review.jsonl final_tables.json type_inference.jsonl types.jsonl guided_types.jsonl"
        else
            files="review.$arm.jsonl final_tables.$arm.json"
        fi
        for f in $files; do
            [ -f "$paper/$f" ] && cp "$paper/$f" "$dir/"
        done
        # Arm C's certificate of this table, with its typing.
        if [ "$arm" = full ]; then
            index="${uid##*/t}"
            for cert in "$paper"/certificate"$index"_*.pl; do
                [ -f "$cert" ] && cp "$cert" "$dir/"
            done
        fi
        # Arm B's certificates (each carries its checking kernel).
        if [ "$arm" = constraints ] && [ -d "$paper/certificates.constraints" ]; then
            rm -rf "$dir/certificates.constraints"
            cp -R "$paper/certificates.constraints" "$dir/"
        fi
    done
done

echo
echo "Collecting and scoring..."
(cd "$root/src" && swipl ablation_collect.pl --dataset="$dataset_rel" \
    --sample="$sample" --gold="$gold" --arms="$arms" --calls="$run_dir" \
    --output="$run_dir/collected.jsonl" < /dev/null) || exit 1
python3 "$here/score_ablation.py" "$run_dir/collected.jsonl" \
    "$root/src/$dataset_rel" "$run_dir" ${prices[@]+"${prices[@]}"} || exit 1

echo "Results: $run_dir ($failures failed run(s))"
[ "$failures" -eq 0 ]
