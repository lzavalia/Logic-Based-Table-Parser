#!/bin/sh
# Offline Prolog regression suites; run from any working directory.
set -eu
cd "$(dirname "$0")"
for suite in boundary_regression_tests.pl paper_output_regression_tests.pl \
             raster_limits_regression_tests.pl paper_failure_regression_tests.pl; do
  printf '\n==> %s\n' "$suite"
  swipl -q -s "$suite" -g run_tests -t halt
done
