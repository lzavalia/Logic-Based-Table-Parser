# Table Dataset Builder: the DeepClause agent plus everything needed to run
# the table logic and the offline tests without installing anything locally.
#
# Build (from dataset-builder-agent/):
#   docker build -t table-dataset-builder .
#
# Run the agent (the API key is supplied at run time, never stored in the image):
#   docker run --rm -e OPENAI_API_KEY \
#     -v "$PWD/dataset:/app/src/dataset" \
#     table-dataset-builder "dementia with lewy bodies"
#
# Run the offline tests:
#   docker run --rm --entrypoint /app/tests/run_regression_tests.sh table-dataset-builder

FROM node:24-bookworm-slim

# SWI-Prolog runs the table logic and the Prolog suites outside DeepClause;
# Python runs the remaining tests and the scripts under tools/. The agent
# itself needs neither: DeepClause ships its own Prolog engine.
RUN apt-get update \
 && apt-get install -y --no-install-recommends swi-prolog-nox python3 ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Pinned: DeepClause is pre-1.0 and this is the release the agent was written for.
ARG DEEPCLAUSE_VERSION=0.0.86
RUN npm install -g "deepclause-sdk@${DEEPCLAUSE_VERSION}" \
 && npm cache clean --force

WORKDIR /app
COPY README.md summary.md ./
COPY src/ src/
COPY tests/ tests/
COPY tools/ tools/

# The agent loads its .pl files from the workspace root, so it runs from src/.
# `deepclause init` creates the .deepclause/ configuration that is not kept in
# the repository; DEFAULT_MODEL is only a fallback, override it per run with
# `--model <provider>:<model>`.
WORKDIR /app/src
ARG DEFAULT_MODEL=openai:gpt-4o
RUN deepclause init --model "${DEFAULT_MODEL}"

# Papers, tables and run manifests are written here; mount a host directory
# to keep them after the container exits.
VOLUME /app/src/dataset

ENTRYPOINT ["deepclause", "run", "dataset_builder.dml", "--headless"]
