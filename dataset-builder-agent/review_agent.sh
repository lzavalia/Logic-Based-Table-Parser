#!/usr/bin/env bash
# Select a candidate for every table in src/dataset/papers/ by its cell types
# (src/type_inference.pl), then ask the LLM to check it (see
# src/review_dataset.dml).
#
#   ./review_agent.sh
#   ./review_agent.sh --scorer purity
#   ./review_agent.sh --papers PMC7293797,PMC5831205
#   ./review_agent.sh --force --model anthropic:claude-sonnet-4-6
#
#   --papers <ids>   review only these papers (comma-separated PMC ids)
#   --run <name>     review only the papers selected by the build run
#                    src/dataset/runs/<name> (run_agent.sh uses this)
#   --force          review again even when a paper's review.jsonl is current
#   --scorer <name>  how type inference selects a candidate: bit-cost (the default)
#                    or purity; changing it makes the review run again
#   --program <file> the type DSL program, by default
#                    type_dsl_examples/sci.tdsl
# Anything else is passed on to `deepclause run`. The temperature defaults to
# 0 so that repeated reviews agree as far as the model allows; pass
# --temperature to change it. --model is also recorded in every review.
#
# Writes, in src/:
#   src/review_log.txt            everything the agent printed
#   src/review_token_usage.json   tokens used, per model
#   src/dataset/papers/PMC<id>/type_inference.jsonl
#   src/dataset/papers/PMC<id>/review.jsonl, src/dataset/reviews/review-*/
# The two log files are overwritten by each run. With LOG_DIR set, they go
# instead to a new directory LOG_DIR/<UTC timestamp>-review/ for every run; a
# relative LOG_DIR is taken from src/ (the Docker image sets
# LOG_DIR=/app/src/dataset/logs).
#
# Needs SWI-Prolog as well as DeepClause. A local src/budget_guard.mjs, if
# present, is preloaded as in run_agent.sh.

set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
papers=all
run=
scorer=bit-cost
program="$script_dir/type_dsl_examples/sci.tdsl"
params=()
passthrough=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --papers)
            [ "$#" -ge 2 ] || { echo "error: --papers needs a value" >&2; exit 2; }
            papers="$2"; params+=(-P "papers=$2"); shift 2 ;;
        --papers=*)
            papers="${1#--papers=}"; params+=(-P "papers=$papers"); shift ;;
        --run)
            [ "$#" -ge 2 ] || { echo "error: --run needs a value" >&2; exit 2; }
            run="$2"; params+=(-P "run=$2"); shift 2 ;;
        --force)
            params+=(-P "force=true"); shift ;;
        --scorer)
            [ "$#" -ge 2 ] || { echo "error: --scorer needs a value" >&2; exit 2; }
            scorer="$2"; shift 2 ;;
        --scorer=*)
            scorer="${1#--scorer=}"; shift ;;
        --program)
            [ "$#" -ge 2 ] || { echo "error: --program needs a value" >&2; exit 2; }
            program="$2"; shift 2 ;;
        --program=*)
            program="${1#--program=}"; shift ;;
        --model)
            [ "$#" -ge 2 ] || { echo "error: --model needs a value" >&2; exit 2; }
            passthrough+=(--model "$2"); params+=(-P "model=$2"); shift 2 ;;
        --model=*)
            passthrough+=("$1"); params+=(-P "model=${1#--model=}"); shift ;;
        -h|--help)
            sed -n '2,35p' "$0"; exit 0 ;;
        *)
            passthrough+=("$1"); shift ;;
    esac
done

if [ ! -r "$program" ]; then
    echo "error: cannot read the type DSL program $program." >&2
    exit 1
fi
program="$(cd "$(dirname "$program")" && pwd)/$(basename "$program")"

# DeepClause reads its config and the workspace from the current directory.
cd "$script_dir/src" || exit 1

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

swipl="${SWIPL:-swipl}"
if ! command -v "$swipl" >/dev/null 2>&1; then
    echo "error: type inference needs SWI-Prolog ($swipl not found)." >&2
    exit 127
fi

# The review works from the output of type inference, so without it there is
# nothing to review. < /dev/null: swipl must never wait at its toplevel.
if [ -n "$run" ]; then
    papers="$("$swipl" guideline_steps.pl run-papers "$run" < /dev/null)" || exit 1
fi
"$swipl" type_inference.pl --scorer="$scorer" --papers="$papers" \
    --program="$program" < /dev/null
if [ "$?" -ne 0 ]; then
    echo "Type inference failed; the review was not started." >&2
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
