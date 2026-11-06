#!/usr/bin/env bash
# Type the cells of every table in src/dataset/papers/ by rule and by the
# LLM following the type program's guidelines (guideline_agent.sh), select a
# candidate for every table by its cell types (src/type_inference.pl), ask
# the LLM to check it (see src/review_dataset.dml), and write each selected
# table's certificate with its typing (src/certify_reviews.pl).
#
#   ./review_agent.sh
#   ./review_agent.sh --scorer purity
#   ./review_agent.sh --papers PMC7293797,PMC5831205
#   ./review_agent.sh --force --model anthropic:claude-sonnet-4-6
#   ./review_agent.sh --arm llm-only --tables PMC7293797/t0
#
#   --papers <ids>   review only these papers (comma-separated PMC ids)
#   --run <name>     review only the papers selected by the build run
#                    src/dataset/runs/<name> (run_agent.sh uses this)
#   --force          review again even when a paper's review.jsonl is current
#   --scorer <name>  how type inference selects a candidate: bit-cost (the default)
#                    or purity; changing it makes the review run again
#   --program <file> the type DSL program, by default
#                    type_dsl_examples/sci.tdsl
#   --level <level>  how type inference compares cell types: family (the
#                    default) or group (see src/type_inference.pl)
#   --no-guidelines  (full arm) skip the guideline step: type inference then
#                    uses whatever guided_types.jsonl is there, else the rule
#                    types (run_agent.sh passes it, as it runs that step itself)
#   --arm <arm>      the ablation arm (see experiments/ablation/README.md):
#                    full (the default): guideline typing, type inference,
#                      LLM review, repair, typed certificates
#                    constraints: the LLM segments each table blind and must
#                      match a parser candidate; no types, no repair
#                    llm-only: the LLM segments each table, nothing else
#                    constraints and llm-only run src/ablation_review.dml and
#                    write review.<arm>.jsonl and final_tables.<arm>.json
#   --dataset <dir>  the dataset, a directory under src/ (default
#                    src/dataset), since DeepClause sees nothing outside src/
#   --tables <uids>  send only these tables (PMC<id>/t<index>, comma-separated);
#                    their papers are reviewed, unless --papers is given, and
#                    their other tables are recorded as not_selected
#   --log-dir <dir>  write review_log.txt and review_token_usage.json there,
#                    and the guideline step's guideline_log.txt and
#                    guideline_token_usage.json
# Anything else is passed on to `deepclause run`. The temperature defaults to
# 0 so that repeated reviews agree as far as the model allows; pass
# --temperature to change it. --model is also recorded in every review.
#
# Writes, in src/:
#   src/review_log.txt            everything the agent printed
#   src/review_token_usage.json   tokens used, per model
#   src/dataset/papers/PMC<id>/types.jsonl, guided_types.jsonl and
#   src/dataset/cache/guideline_answers.jsonl (the guideline step)
#   src/dataset/papers/PMC<id>/type_inference.jsonl
#   src/dataset/papers/PMC<id>/review.jsonl, src/dataset/reviews/review-*/
#   src/dataset/papers/PMC<id>/certificateN_*.pl, each with its checking
#   kernel and the typing of the table's cells
#   (with --arm constraints or llm-only: review.<arm>.jsonl and
#   final_tables.<arm>.json instead, no typing and no type inference; the
#   constraints arm also writes certificates.constraints/, without typing)
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
papers_given=false
run=
arm=full
dataset=
tables=
log_dir_opt=
guidelines=1
scorer=bit-cost
level=family
program="$script_dir/type_dsl_examples/sci.tdsl"
params=()
passthrough=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --papers)
            [ "$#" -ge 2 ] || { echo "error: --papers needs a value" >&2; exit 2; }
            papers="$2"; papers_given=true; params+=(-P "papers=$2"); shift 2 ;;
        --papers=*)
            papers="${1#--papers=}"; papers_given=true; params+=(-P "papers=$papers"); shift ;;
        --arm)
            [ "$#" -ge 2 ] || { echo "error: --arm needs a value" >&2; exit 2; }
            arm="$2"; shift 2 ;;
        --arm=*)
            arm="${1#--arm=}"; shift ;;
        --dataset)
            [ "$#" -ge 2 ] || { echo "error: --dataset needs a value" >&2; exit 2; }
            dataset="$2"; shift 2 ;;
        --dataset=*)
            dataset="${1#--dataset=}"; shift ;;
        --tables)
            [ "$#" -ge 2 ] || { echo "error: --tables needs a value" >&2; exit 2; }
            tables="$2"; shift 2 ;;
        --tables=*)
            tables="${1#--tables=}"; shift ;;
        --log-dir)
            [ "$#" -ge 2 ] || { echo "error: --log-dir needs a value" >&2; exit 2; }
            log_dir_opt="$2"; shift 2 ;;
        --log-dir=*)
            log_dir_opt="${1#--log-dir=}"; shift ;;
        --run)
            [ "$#" -ge 2 ] || { echo "error: --run needs a value" >&2; exit 2; }
            run="$2"; params+=(-P "run=$2"); shift 2 ;;
        --force)
            params+=(-P "force=true"); shift ;;
        --no-guidelines)
            guidelines=0; shift ;;
        --scorer)
            [ "$#" -ge 2 ] || { echo "error: --scorer needs a value" >&2; exit 2; }
            scorer="$2"; shift 2 ;;
        --scorer=*)
            scorer="${1#--scorer=}"; shift ;;
        --level)
            [ "$#" -ge 2 ] || { echo "error: --level needs a value" >&2; exit 2; }
            level="$2"; shift 2 ;;
        --level=*)
            level="${1#--level=}"; shift ;;
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
            sed -n '2,65p' "$0"; exit 0 ;;
        *)
            passthrough+=("$1"); shift ;;
    esac
done

case "$level" in
    family|group) ;;
    *) echo "error: --level must be family or group, not '$level'." >&2; exit 2 ;;
esac
case "$arm" in
    full|constraints|llm-only) ;;
    *) echo "error: --arm must be full, constraints or llm-only, not '$arm'." >&2; exit 2 ;;
esac
if [ -n "$dataset" ]; then
    case "$dataset" in
        /*|..|../*|*/..|*/../*)
            echo "error: --dataset must be a directory under src/, given relative to it." >&2
            exit 2 ;;
    esac
    dataset="${dataset%/}"
    params+=(-P "dataset=$dataset")
fi
if [ -n "$tables" ]; then
    params+=(-P "tables=$tables")
    if [ "$papers_given" = false ] && [ -z "$run" ]; then
        # The papers of the tables: PMC123/t0,PMC123/t2 -> PMC123.
        papers="$(printf '%s\n' "$tables" | tr ',; ' '\n\n\n' | sed -n 's|^\(PMC[0-9]*\)/t[0-9]*$|\1|p' | sort -u | paste -sd, -)"
        if [ -z "$papers" ]; then
            echo "error: --tables must be table uids such as PMC123/t0." >&2
            exit 2
        fi
        params+=(-P "papers=$papers")
    fi
fi

if [ ! -r "$program" ]; then
    echo "error: cannot read the type DSL program $program." >&2
    exit 1
fi
program="$(cd "$(dirname "$program")" && pwd)/$(basename "$program")"

# DeepClause reads its config and the workspace from the current directory.
cd "$script_dir/src" || exit 1

dataset_dir="${dataset:-dataset}"
if [ ! -d "$dataset_dir/papers" ]; then
    echo "error: $PWD/$dataset_dir/papers does not exist; build a dataset first." >&2
    exit 1
fi
if [ ! -w "$dataset_dir/papers" ]; then
    echo "error: $PWD/$dataset_dir/papers is not writable by user $(id -u):$(id -g)." >&2
    echo "With Docker, make the host directory yours:" >&2
    echo "  sudo chown -R \"\$(id -u):\$(id -g)\" <host directory>" >&2
    exit 1
fi

swipl="${SWIPL:-swipl}"
if ! command -v "$swipl" >/dev/null 2>&1; then
    echo "error: type inference needs SWI-Prolog ($swipl not found)." >&2
    exit 127
fi

# The full review works from the output of type inference, so without it
# there is nothing to review; the types come from the rules and the guideline
# step. The other arms use no types.
# < /dev/null: swipl must never wait at its toplevel.
guideline_status=0
if [ "$arm" = full ]; then
    if [ -n "$run" ]; then
        papers="$("$swipl" guideline_steps.pl run-papers "$run" < /dev/null)" || exit 1
    fi
    if [ "$guidelines" -eq 1 ]; then
        # A failed guideline step does not stop the review: guided_types.jsonl
        # is written from whatever answers there are (guideline_agent.sh).
        "$script_dir/guideline_agent.sh" --papers "$papers" --program "$program" \
            --dataset "$dataset_dir" ${log_dir_opt:+--log-dir "$log_dir_opt"} \
            ${passthrough[@]+"${passthrough[@]}"} < /dev/null
        guideline_status=$?
        if [ "$guideline_status" -ne 0 ]; then
            echo "The guideline step failed (status $guideline_status); reviewing with the types there are." >&2
        fi
    fi
    "$swipl" type_inference.pl --scorer="$scorer" --level="$level" --papers="$papers" \
        --program="$program" --dataset="$dataset_dir" < /dev/null
    if [ "$?" -ne 0 ]; then
        echo "Type inference failed; the review was not started." >&2
        exit 1
    fi
    agent=review_dataset.dml
else
    if [ -n "$run" ]; then
        echo "error: --run is only supported with --arm full." >&2
        exit 2
    fi
    agent=ablation_review.dml
    params+=(-P "arm=$arm")
fi

if [ -n "$log_dir_opt" ]; then
    mkdir -p "$log_dir_opt" || exit 1
    log_dir="$(cd "$log_dir_opt" && pwd)"
    log_file="$log_dir/review_log.txt"
    usage_file="$log_dir/review_token_usage.json"
    rm -f "$usage_file"
elif [ -n "${LOG_DIR:-}" ]; then
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
deepclause run "$agent" --headless --temperature 0 \
    --usage "$usage_file" ${params[@]+"${params[@]}"} \
    ${passthrough[@]+"${passthrough[@]}"} \
    2> >(grep -v "AI SDK Warning" >&2) \
    | tee "$log_file"
status="${PIPESTATUS[0]}"

# The certificates of the full review, with the typing of every cell: the
# review has written them without it, since DeepClause has no PCRE.
if [ "$arm" = full ] && [ "$status" -eq 0 ]; then
    echo
    echo "Writing the typed certificates..."
    "$swipl" certify_reviews.pl --dataset="$dataset_dir" --arm=full \
        --program="$program" --papers="$papers" < /dev/null 2>&1 | tee -a "$log_file"
    certify_status="${PIPESTATUS[0]}"
    if [ "$certify_status" -ne 0 ]; then
        echo "Writing the typed certificates failed (status $certify_status)." >&2
        status="$certify_status"
    fi
fi
if [ "$status" -eq 0 ] && [ "$guideline_status" -ne 0 ]; then
    status="$guideline_status"
fi

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
