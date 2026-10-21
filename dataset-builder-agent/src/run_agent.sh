#!/usr/bin/env bash
# Run the dataset builder agent on one search prompt.
#
#   ./run_agent.sh "dementia with lewy bodies"
#
# Writes, next to this script:
#   runtime_log.txt    everything the agent printed (also shown on screen)
#   token_usage.json   tokens used, per model
#   budget_guard.log   one line per model call, with running cost
#   dataset/           the annotated tables
# runtime_log.txt, token_usage.json and budget_guard.log are overwritten by
# each run.
#
# The run is stopped once it has spent BUDGET_USD dollars (default 5):
#   BUDGET_USD=1 ./run_agent.sh "some topic"

set -uo pipefail

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
    echo "usage: $0 \"<search prompt>\"" >&2
    exit 2
fi
prompt="$1"

# DeepClause reads its config and the workspace from the current directory.
cd "$(dirname "$0")" || exit 1

rm -f budget_guard.log token_usage.json

# The guard reports its totals on stderr; the AI SDK's repeated warning about
# system messages is dropped so those totals stay visible.
NODE_OPTIONS="--import $PWD/budget_guard.mjs" \
BUDGET_USD="${BUDGET_USD:-5}" \
deepclause run dataset_builder.dml "$prompt" --headless --usage token_usage.json \
    2> >(grep -v "AI SDK Warning" >&2) \
    | tee runtime_log.txt
status="${PIPESTATUS[0]}"

echo
if [ "$status" -eq 3 ]; then
    echo "Stopped by the budget guard (limit \$${BUDGET_USD:-5})." >&2
elif [ "$status" -ne 0 ]; then
    echo "deepclause exited with status $status." >&2
fi
if [ -f token_usage.json ]; then
    echo "Token usage:"
    cat token_usage.json
    echo
fi
exit "$status"
