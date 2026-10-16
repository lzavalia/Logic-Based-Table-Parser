#!/usr/bin/env bash
# Ask the LLM to review the parser's candidate boundaries for every table in
# src/dataset/papers/ (see src/review_dataset.dml).
#
#   ./review_agent.sh
#   ./review_agent.sh --papers PMC7293797,PMC5831205
#   ./review_agent.sh --force --model anthropic:claude-sonnet-4-6
#
#   --papers <ids>   review only these papers (comma-separated PMC ids)
#   --run <name>     review only the papers selected by the build run
#                    src/dataset/runs/<name> (run_agent.sh uses this)
#   --force          review again even when a paper's review.jsonl is current
# Anything else is passed on to `deepclause run`. The temperature defaults to
# 0 so that repeated reviews agree as far as the model allows; pass
# --temperature to change it. --model is also recorded in every review.
#
# Writes, in src/:
#   src/review_log.txt            everything the agent printed
#   src/review_token_usage.json   tokens used, per model
#   src/dataset/papers/PMC<id>/review.jsonl, src/dataset/reviews/review-*/
# The two log files are overwritten by each run. With LOG_DIR set, they go
# instead to a new directory LOG_DIR/<UTC timestamp>-review/ for every run; a
# relative LOG_DIR is taken from src/ (the Docker image sets
# LOG_DIR=/app/src/dataset/logs).
#
# A local src/budget_guard.mjs, if present, is preloaded as in run_agent.sh.

set -uo pipefail

params=()
passthrough=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --papers)
            [ "$#" -ge 2 ] || { echo "error: --papers needs a value" >&2; exit 2; }
            params+=(-P "papers=$2"); shift 2 ;;
        --papers=*)
            params+=(-P "papers=${1#--papers=}"); shift ;;
        --run)
            [ "$#" -ge 2 ] || { echo "error: --run needs a value" >&2; exit 2; }
            params+=(-P "run=$2"); shift 2 ;;
        --force)
            params+=(-P "force=true"); shift ;;
        --model)
            [ "$#" -ge 2 ] || { echo "error: --model needs a value" >&2; exit 2; }
            passthrough+=(--model "$2"); params+=(-P "model=$2"); shift 2 ;;
        --model=*)
            passthrough+=("$1"); params+=(-P "model=${1#--model=}"); shift ;;
        -h|--help)
            sed -n '2,27p' "$0"; exit 0 ;;
        *)
            passthrough+=("$1"); shift ;;
    esac
done

# DeepClause reads its config and the workspace from the current directory.
cd "$(dirname "$0")/src" || exit 1

if [ ! -d dataset/papers ]; then
    echo "error: $PWD/dataset/papers does not exist; build a dataset first." >&2
    exit 1
fi
if [ ! -w dataset/papers ]; then
    echo "error: $PWD/dataset/papers is not writable by user $(id -u):$(id -g)." >&2
    echo "With Docker, make the host directory yours:" >&2
    echo "  sudo chown -R \"\$(id -u):\$(id -g)\" <host directory>" >&2
    exit 1
fi

if [ -n "${LOG_DIR:-}" ]; then
    log_dir="$LOG_DIR/$(date -u +%Y%m%dT%H%M%SZ)-review"
    mkdir -p "$log_dir" || exit 1
    log_file="$log_dir/review_log.txt"
    usage_file="$log_dir/review_token_usage.json"
else
    log_dir=.
    log_file=review_log.txt
    usage_file=review_token_usage.json
    rm -f "$usage_file"
fi

if [ -f budget_guard.mjs ]; then
    export NODE_OPTIONS="--import $PWD/budget_guard.mjs${NODE_OPTIONS:+ $NODE_OPTIONS}"
    export BUDGET_USD="${BUDGET_USD:-5}"
    export BUDGET_LOG="$log_dir/budget_guard.log"
fi

# --temperature 0 comes first so that a --temperature in the passed-on
# options overrides it.
deepclause run review_dataset.dml --headless --temperature 0 \
    --usage "$usage_file" ${params[@]+"${params[@]}"} \
    ${passthrough[@]+"${passthrough[@]}"} \
    2> >(grep -v "AI SDK Warning" >&2) \
    | tee "$log_file"
status="${PIPESTATUS[0]}"

echo
if [ -f budget_guard.mjs ] && [ "$status" -eq 3 ]; then
    echo "Stopped by the budget guard (limit \$${BUDGET_USD:-5})." >&2
elif [ "$status" -ne 0 ]; then
    echo "deepclause exited with status $status." >&2
fi
if [ -f "$usage_file" ]; then
    echo "Token usage:"
    cat "$usage_file"
    echo
fi
if [ "$log_dir" != . ]; then
    echo "Logs: $log_dir" >&2
fi
exit "$status"
