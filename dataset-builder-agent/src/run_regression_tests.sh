#!/bin/sh
# Offline regression harness: each Prolog suite runs in its own SWI process
# so similarly named fixture predicates in different suites cannot collide.
# Run from any working directory; no API key, DeepClause, or network required.
set -eu

SRC_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SWIPL=${SWIPL:-swipl}
PYTHON=${PYTHON:-python3}

usage() {
    printf 'Usage: %s [--all|--prolog-only|--python-only|--list|--help]\n' "$0"
}

if [ "$#" -gt 1 ]; then
    usage >&2
    exit 2
fi

case "${1:---all}" in
    --all) run_prolog=1; run_python=1 ;;
    --prolog-only) run_prolog=1; run_python=0 ;;
    --python-only) run_prolog=0; run_python=1 ;;
    --list) run_prolog=0; run_python=0; list_only=1 ;;
    --help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac

# Expand in the source directory, not the invoking working directory.
# Without an explicit existence check, POSIX shells leave an unmatched glob
# literal and a suite-free CI run would be incorrectly reported as success.
set -- "$SRC_DIR"/*_regression_tests.pl
if [ ! -f "$1" ]; then
    echo 'ERROR: no Prolog regression suites found' >&2
    exit 1
fi
prolog_count=$#

set -- "$SRC_DIR"/*_regression_tests.py
if [ ! -f "$1" ]; then
    echo 'ERROR: no Python regression suites found' >&2
    exit 1
fi
python_count=$#

if [ "${list_only:-0}" -eq 1 ]; then
    printf 'Prolog suites (%s):\n' "$prolog_count"
    for suite in "$SRC_DIR"/*_regression_tests.pl; do printf '  %s\n' "${suite##*/}"; done
    printf 'Python suites (%s):\n' "$python_count"
    for suite in "$SRC_DIR"/*_regression_tests.py; do printf '  %s\n' "${suite##*/}"; done
    exit 0
fi

if [ "$run_prolog" -eq 1 ]; then
    if ! command -v "$SWIPL" >/dev/null 2>&1; then
        printf 'ERROR: SWI-Prolog executable not found: %s\n' "$SWIPL" >&2
        printf 'Install SWI-Prolog 9+ or run --python-only.\n' >&2
        exit 127
    fi
    printf 'Running %s offline Prolog regression suites\n' "$prolog_count"
    for suite in "$SRC_DIR"/*_regression_tests.pl; do
        printf '\n==> %s\n' "${suite##*/}"
        (cd "$SRC_DIR" && "$SWIPL" -q -f none -s "${suite##*/}" \
            -g '(run_tests -> halt(0) ; halt(1))' -t 'halt(2)')
    done
fi

if [ "$run_python" -eq 1 ]; then
    if ! command -v "$PYTHON" >/dev/null 2>&1; then
        printf 'ERROR: Python executable not found: %s\n' "$PYTHON" >&2
        exit 127
    fi
    printf '\nRunning %s offline Python regression suites\n' "$python_count"
    (cd "$SRC_DIR" && "$PYTHON" -m unittest discover -v -s . -p '*_regression_tests.py')
fi

printf '\nAll selected regression suites passed.\n'
