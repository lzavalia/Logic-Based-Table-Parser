#!/usr/bin/env bash
# Refine the types of the cells in src/dataset/papers/ with the LLM: the rules
# of a type DSL program type every cell, then the cells only a model can
# refine are sent to it (see src/type_guidelines.pl).
#
#   ./guideline_agent.sh
#   ./guideline_agent.sh --papers PMC7293797,PMC5831205
#   ./guideline_agent.sh --model anthropic:claude-sonnet-4-6
#
#   --papers <ids>     only these papers (comma-separated PMC ids)
#   --run <name>       only the papers selected by the build run
#                      src/dataset/runs/<name> (run_agent.sh uses this)
#   --program <file>   the type DSL program, by default
#                      type_dsl_examples/sci.tdsl
# Anything else is passed on to `deepclause run`. The temperature defaults to
# 0; pass --temperature to change it.
#
# Answers are cached by (program, cell text, rule type), so a second run only
# sends what is still unanswered, and an interrupted run loses nothing:
# guided_types.jsonl is written from whatever answers there are, even after a
# failed model stage, and the exit status reports that failure.
#
# Writes, in src/:
#   src/guideline_log.txt            everything the stages printed
#   src/guideline_token_usage.json   tokens used, per model
#   src/dataset/papers/PMC<id>/types.jsonl, guided_types.jsonl
#   src/dataset/cache/guideline_answers.jsonl
# The two log files are overwritten by each run. With LOG_DIR set, they go
# instead to a new directory LOG_DIR/<UTC timestamp>-guidelines/ for every run;
# a relative LOG_DIR is taken from src/ (the Docker image sets
# LOG_DIR=/app/src/dataset/logs).
#
# Needs SWI-Prolog as well as DeepClause. A local src/budget_guard.mjs, if
# present, is preloaded as in run_agent.sh.

set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
papers=all
run=
program="$script_dir/type_dsl_examples/sci.tdsl"
passthrough=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --papers)
            [ "$#" -ge 2 ] || { echo "error: --papers needs a value" >&2; exit 2; }
            papers="$2"; shift 2 ;;
        --papers=*)
            papers="${1#--papers=}"; shift ;;
        --run)
            [ "$#" -ge 2 ] || { echo "error: --run needs a value" >&2; exit 2; }
            run="$2"; shift 2 ;;
        --program)
            [ "$#" -ge 2 ] || { echo "error: --program needs a value" >&2; exit 2; }
            program="$2"; shift 2 ;;
        --program=*)
            program="${1#--program=}"; shift ;;
        -h|--help)
            sed -n '2,34p' "$0"; exit 0 ;;
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
    echo "error: the guideline step needs SWI-Prolog ($swipl not found)." >&2
    exit 127
fi

if [ -n "$run" ]; then
    papers="$("$swipl" guideline_steps.pl run-papers "$run")" || exit 1
fi

if [ -n "${LOG_DIR:-}" ]; then
    log_dir="$LOG_DIR/$(date -u +%Y%m%dT%H%M%SZ)-guidelines"
    mkdir -p "$log_dir" || exit 1
    log_file="$log_dir/guideline_log.txt"
    usage_file="$log_dir/guideline_token_usage.json"
else
    log_dir=.
    log_file=guideline_log.txt
    usage_file=guideline_token_usage.json
    rm -f "$usage_file"
fi

if [ -f budget_guard.mjs ]; then
    export NODE_OPTIONS="--import $PWD/budget_guard.mjs${NODE_OPTIONS:+ $NODE_OPTIONS}"
    export BUDGET_USD="${BUDGET_USD:-5}"
    export BUDGET_LOG="$log_dir/budget_guard.log"
fi

# Stage 1 always runs first: it drops from the requests what the cache has
# answered since they were written, so nothing is paid for twice.
"$swipl" guideline_steps.pl prepare "$program" "$papers" 2>&1 | tee "$log_file"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "Preparing the guideline requests failed." >&2
    exit 1
fi

params=()
if [ "$papers" != all ]; then
    params+=(-P "papers=$papers")
fi

# --temperature 0 comes first so that a --temperature in the passed-on
# options overrides it.
deepclause run type_guidelines.dml --headless --temperature 0 \
    --usage "$usage_file" ${params[@]+"${params[@]}"} \
    ${passthrough[@]+"${passthrough[@]}"} \
    2> >(grep -v "AI SDK Warning" >&2) \
    | tee -a "$log_file"
status="${PIPESTATUS[0]}"

echo
if [ -f budget_guard.mjs ] && [ "$status" -eq 3 ]; then
    echo "Stopped by the budget guard (limit \$${BUDGET_USD:-5})." >&2
elif [ "$status" -ne 0 ]; then
    echo "deepclause exited with status $status." >&2
fi

"$swipl" guideline_steps.pl apply "$program" "$papers" 2>&1 | tee -a "$log_file"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "Writing guided_types.jsonl failed." >&2
    [ "$status" -ne 0 ] || status=1
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
