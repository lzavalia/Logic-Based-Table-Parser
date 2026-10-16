#!/usr/bin/env bash
# Build a dataset for one search prompt, then have the LLM review it.
#
#   ./run_agent.sh "dementia with lewy bodies"
#   ./run_agent.sh "dementia with lewy bodies" --model anthropic:claude-sonnet-4-6
#   ./run_agent.sh "dementia with lewy bodies" --no-review
#
# One run does two steps:
#   1. the dataset builder (src/dataset_builder.dml) selects, downloads and
#      parses the papers;
#   2. the review (review_agent.sh, src/review_dataset.dml) checks the
#      candidate parses of exactly the papers this run selected, and writes
#      src/dataset/papers/PMC<id>/review.jsonl.
# --no-review stops after step 1. Step 2 is skipped as well when the build
# fails or selects no papers. Anything else after the search prompt is passed
# on to `deepclause run` in both steps, so --model applies to both.
#
# The agents run in src/, where DeepClause finds its configuration and the .pl
# files, so all output goes there too:
#   src/runtime_log.txt    everything the agent printed (also shown on screen)
#   src/token_usage.json   tokens used, per model
#   src/dataset/           the annotated tables
#   src/review_log.txt, src/review_token_usage.json   the same for step 2
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
build_args=()
for arg in "$@"; do
    if [ "$arg" = "--no-review" ]; then
        review=0
    else
        build_args+=("$arg")
    fi
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
if [ "$status" -ne 0 ] || [ "$review" -eq 0 ]; then
    exit "$status"
fi

# Step 2. The build prints "Run manifest: /workspace/dataset/runs/<name>/
# manifest.json"; the review reads that run's selected papers from it.
run_name="$(sed -n 's|^Run manifest: .*/runs/\([^/]*\)/manifest\.json$|\1|p' \
    "$log_dir/runtime_log.txt" | tail -n 1)"
if [ -z "$run_name" ]; then
    echo "No run manifest was written (no papers selected?); skipping the review." >&2
    exit 0
fi
echo
echo "Reviewing the candidate parses of this run's papers..."
"$script_dir/review_agent.sh" --run "$run_name" ${build_args[@]+"${build_args[@]}"}
exit $?
