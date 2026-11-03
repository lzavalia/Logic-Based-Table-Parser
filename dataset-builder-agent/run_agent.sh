#!/usr/bin/env bash
# Build a dataset for one search prompt, then have the LLM type its cells and
# review it.
#
#   ./run_agent.sh "dementia with lewy bodies"
#   ./run_agent.sh "dementia with lewy bodies" --model anthropic:claude-sonnet-4-6
#   ./run_agent.sh "dementia with lewy bodies" --no-review --no-guidelines
#   ./run_agent.sh "dementia with lewy bodies" --scorer purity
#
# One run does three steps:
#   1. the dataset builder (src/dataset_builder.dml) selects, downloads and
#      parses the papers;
#   2. the guideline step (guideline_agent.sh, src/type_guidelines.dml) types
#      the cells of exactly the papers this run selected, by rule and then by
#      LLM, and writes src/dataset/papers/PMC<id>/guided_types.jsonl;
#   3. the review (review_agent.sh, src/review_dataset.dml) selects a candidate
#      for each table by its types (--scorer bit-cost, the default, or
#      --scorer purity), has the LLM check that candidate, and writes
#      src/dataset/papers/PMC<id>/review.jsonl.
# --no-guidelines skips step 2 and --no-review skips step 3. Both are skipped
# when the build fails or selects no papers. A failed or skipped step 2 does
# not stop step 3: type inference then uses the rule types. The exit status is
# the first failure's. Anything else after the search prompt is passed on to
# `deepclause run` in all steps, so --model applies to all of them.
#
# The agents run in src/, where DeepClause finds its configuration and the .pl
# files, so all output goes there too:
#   src/runtime_log.txt    everything the agent printed (also shown on screen)
#   src/token_usage.json   tokens used, per model
#   src/dataset/           the annotated tables
#   src/guideline_log.txt, src/guideline_token_usage.json   the same for step 2
#   src/review_log.txt, src/review_token_usage.json   the same for step 3
# runtime_log.txt and token_usage.json are overwritten by each run. With
# LOG_DIR set, they go instead to a new directory LOG_DIR/<UTC timestamp>/ for
# every run, so earlier runs' logs are kept; a relative LOG_DIR is taken from
# src/ (the Docker image sets LOG_DIR=/app/src/dataset/logs).
#
# A local src/budget_guard.mjs, if present, is preloaded into
# deepclause (with BUDGET_USD, default 5). It is a debugging aid kept out of
# the repository and the Docker image.

set -uo pipefail

if [ "$#" -lt 1 ] || [ -z "$1" ]; then
    echo "usage: $0 \"<search prompt>\" [deepclause run options]" >&2
    exit 2
fi
prompt="$1"
shift

review=1
guidelines=1
scorer=bit-cost
build_args=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-review)
            review=0; shift ;;
        --no-guidelines)
            guidelines=0; shift ;;
        --scorer)
            [ "$#" -ge 2 ] || { echo "error: --scorer needs a value" >&2; exit 2; }
            scorer="$2"; shift 2 ;;
        --scorer=*)
            scorer="${1#--scorer=}"; shift ;;
        *)
            build_args+=("$1"); shift ;;
    esac
done
script_dir="$(cd "$(dirname "$0")" && pwd)"

# DeepClause reads its config and the workspace from the current directory.
cd "$(dirname "$0")/src" || exit 1

# Fail early, with the fix, when the output directory is not writable. The
# usual cause is a Docker bind mount of a host directory that did not exist:
# Docker then creates it owned by root, and a run with --user cannot write.
mkdir -p dataset 2>/dev/null
if [ ! -w dataset ]; then
    echo "error: $PWD/dataset is not writable by user $(id -u):$(id -g)." >&2
    echo "With Docker, create the host directory before mounting it, or make" >&2
    echo "it yours: sudo chown \"\$(id -u):\$(id -g)\" <host directory>" >&2
    exit 1
fi

if [ -n "${LOG_DIR:-}" ]; then
    log_dir="$LOG_DIR/$(date -u +%Y%m%dT%H%M%SZ)"
    mkdir -p "$log_dir" || exit 1
else
    log_dir=.
    rm -f budget_guard.log token_usage.json
fi

if [ -f budget_guard.mjs ]; then
    export NODE_OPTIONS="--import $PWD/budget_guard.mjs${NODE_OPTIONS:+ $NODE_OPTIONS}"
    export BUDGET_USD="${BUDGET_USD:-5}"
    export BUDGET_LOG="$log_dir/budget_guard.log"
fi

# The AI SDK's repeated warning about system messages is dropped from stderr.
deepclause run dataset_builder.dml "$prompt" --headless \
    --usage "$log_dir/token_usage.json" ${build_args[@]+"${build_args[@]}"} \
    2> >(grep -v "AI SDK Warning" >&2) \
    | tee "$log_dir/runtime_log.txt"
status="${PIPESTATUS[0]}"

echo
if [ -f budget_guard.mjs ] && [ "$status" -eq 3 ]; then
    echo "Stopped by the budget guard (limit \$${BUDGET_USD:-5})." >&2
elif [ "$status" -ne 0 ]; then
    echo "deepclause exited with status $status." >&2
fi
if [ -f "$log_dir/token_usage.json" ]; then
    echo "Token usage:"
    cat "$log_dir/token_usage.json"
    echo
fi
if [ "$log_dir" != . ]; then
    echo "Logs: $log_dir" >&2
fi
if [ "$status" -ne 0 ] || { [ "$review" -eq 0 ] && [ "$guidelines" -eq 0 ]; }; then
    exit "$status"
fi

# The build prints "Run manifest: /workspace/dataset/runs/<name>/
# manifest.json"; the later steps read that run's selected papers from it.
run_name="$(sed -n 's|^Run manifest: .*/runs/\([^/]*\)/manifest\.json$|\1|p' \
    "$log_dir/runtime_log.txt" | tail -n 1)"
if [ -z "$run_name" ]; then
    echo "No run manifest was written (no papers selected?); skipping the later steps." >&2
    exit 0
fi

# Step 2.
if [ "$guidelines" -eq 1 ]; then
    echo
    echo "Typing the cells of this run's papers..."
    "$script_dir/guideline_agent.sh" --run "$run_name" ${build_args[@]+"${build_args[@]}"}
    status=$?
    if [ "$status" -ne 0 ]; then
        echo "The guideline step failed (status $status)." >&2
    fi
fi

# Step 3.
if [ "$review" -eq 1 ]; then
    echo
    echo "Reviewing the selected candidates of this run's papers..."
    "$script_dir/review_agent.sh" --run "$run_name" --scorer "$scorer" ${build_args[@]+"${build_args[@]}"}
    review_status=$?
    [ "$status" -ne 0 ] || status="$review_status"
fi
exit "$status"
