# Table Dataset Builder: the DeepClause agent plus everything needed to run
# the table logic and the offline tests without installing anything locally.
#
# Build (from dataset-builder-agent/):
#   docker build -t table-dataset-builder .
#
# Run the agent (the API key is supplied at run time, never stored in the image).
# Tables, raw XML, run manifests and logs all land in the mounted directory:
#   docker run --rm -e OPENAI_API_KEY \
#     -v "$PWD/dataset:/app/src/dataset" \
#     table-dataset-builder "dementia with lewy bodies"
#
# Run the offline tests:
#   docker run --rm --entrypoint /app/tests/run_regression_tests.sh table-dataset-builder

FROM node:24-bookworm-slim

# Without a UTF-8 locale SWI-Prolog reads source and data files as ASCII,
# which breaks the non-ASCII test fixtures and article text.
ENV LANG=C.UTF-8

# SWI-Prolog runs the table logic and the Prolog suites outside DeepClause;
# Python runs the remaining tests and the scripts under tools/. The agent
# itself needs neither: DeepClause ships its own Prolog engine. patch applies
# the DeepClause fix below.
RUN apt-get update \
 && apt-get install -y --no-install-recommends swi-prolog-nox python3 ca-certificates patch \
 && rm -rf /var/lib/apt/lists/*

# Pinned: DeepClause is pre-1.0 and this is the release the agent was written for.
ARG DEEPCLAUSE_VERSION=0.0.86
RUN npm install -g "deepclause-sdk@${DEEPCLAUSE_VERSION}" \
 && npm cache clean --force

# Local fix to DeepClause, until it is released upstream: without it the model
# can lose the search_pmc results it chooses papers from. The patch is written
# against 0.0.86, so a different version fails here instead of silently
# shipping unpatched code; the grep confirms the fix is in place.
COPY docker/deepclause-0.0.86-compaction.patch /tmp/
RUN patch -p1 -d "$(npm root -g)/deepclause-sdk" < /tmp/deepclause-0.0.86-compaction.patch \
 && grep -q "compactedMessages !== normalizedForCompaction" \
      "$(npm root -g)/deepclause-sdk/dist/agent.js" \
 && rm /tmp/deepclause-0.0.86-compaction.patch

WORKDIR /app
COPY README.md summary.md run_agent.sh ./
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
# to keep them after the container exits. run_agent.sh puts each run's logs
# in dataset/logs/<UTC timestamp>/ so the same mount captures them.
VOLUME /app/src/dataset
ENV LOG_DIR=/app/src/dataset/logs

# run_agent.sh adds the per-run logs. Arguments after the search phrase are
# passed on to `deepclause run`.
ENTRYPOINT ["/app/run_agent.sh"]
