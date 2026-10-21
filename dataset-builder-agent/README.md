# Dataset Builder Agent

Turns a search phrase into a set of scientific tables with **candidate
structural** horizontal metadata (HMD), vertical metadata (VMD) and data
regions. The segmentation is **not** verified semantic ground truth.

A language model picks open-access papers from PubMed Central; everything after
that (download, table extraction, rasterization, constraint checking, coloring)
is deterministic Prolog. The agent is written in DML and runs on
[DeepClause](https://github.com/deepclause/deepclause-sdk).

## Dependencies

| Dependency | Version | Needed for | Notes |
|---|---|---|---|
| [Node.js](https://nodejs.org) | 18 or newer | running the agent | Tested with 26.10.0. `npm` comes with it. |
| [`deepclause-sdk`](https://www.npmjs.com/package/deepclause-sdk) | 0.0.86 | running the agent | npm package that provides the `deepclause` command. |
| An API key for a model provider | | running the agent | Any provider DeepClause supports. See [step 4](#4-choose-a-model-provider). |
| Internet access | | running the agent | The model provider's API and `eutils.ncbi.nlm.nih.gov`. |
| [SWI-Prolog](https://www.swi-prolog.org) | 9 or newer | **optional**: running the table logic without the agent | Tested with 10.0.2. |

There is nothing else to install. In particular:

- **SWI-Prolog is not required to run the agent.** DeepClause ships its own
  Prolog engine (SWI-Prolog compiled to WebAssembly) and the `.pl` files are
  loaded into it. A local `swipl` is only needed for the offline commands in
  [Running the table logic without the agent](#running-the-table-logic-without-the-agent).
- The Prolog code uses SWI-Prolog libraries (`sgml`, `sgml_write`, `json`,
  `assoc`, `apply`, `lists`, `readutil`, `filesex`). SHA-256 provenance
  additionally needs `library(crypto)` or `library(sha)` from the SWI runtime;
  if neither is available, paper publication fails with an explicit error.
  DeepClause's WebAssembly distribution must provide one of them.
- No NCBI API key is needed. Workers sharing a filesystem workspace coordinate
  their request reservations with a 0.4-second minimum gap. This does not
  coordinate requests from other workspaces or machines sharing an IP.

Developed and tested on macOS (Apple Silicon).

## Installation

These steps start from a machine that has never had DeepClause on it.

### 1. Install Node.js

macOS, with [Homebrew](https://brew.sh):

```bash
brew install node
```

Other systems: use the installer from <https://nodejs.org>, or your package
manager. Then check the version:

```bash
node --version    # v18.0.0 or newer
```

### 2. Install DeepClause

DeepClause is an npm package. Installing it globally adds the `deepclause`
command:

```bash
npm install -g deepclause-sdk@0.0.86
deepclause --version    # 0.0.86
```

The version is pinned because DeepClause is pre-1.0 and this is the release the
agent was developed against. The agent itself is Prolog only: it needs no
Python and does not use DeepClause's `bash` tool. Python 3.10+ is needed only
for some of the offline tests and the scripts under `tools/`.

Then apply the project's fix to DeepClause, from `dataset-builder-agent/`:

```bash
patch -p1 -b -d "$(npm root -g)/deepclause-sdk" < docker/deepclause-0.0.86-compaction.patch
```

Without it, DeepClause 0.0.86 can drop the `search_pmc` results from the
model's conversation before it chooses papers; the patch file explains the
change. `-b` keeps the original as `dist/agent.js.orig`. The Docker image
applies the same patch. It is needed until the fix is released upstream.

### 3. Get the code

```bash
git clone https://github.com/lzavalia/Logic-Based-Table-Parser.git
cd Logic-Based-Table-Parser/dataset-builder-agent/src
```

All commands below are run from `src/`, the directory that holds
`dataset_builder.dml` and the `.pl` files.

### 4. Choose a model provider

The agent uses the model for one step only: choosing papers with a search tool.
Any provider DeepClause supports will do, as long as the model supports tool
calling.

| Provider | Model id format | API key variable |
|---|---|---|
| OpenAI | `openai:<model>` | `OPENAI_API_KEY` |
| Anthropic | `anthropic:<model>` | `ANTHROPIC_API_KEY` |
| Google | `google:<model>` | `GOOGLE_GENERATIVE_AI_API_KEY` |
| OpenRouter | `openrouter:<vendor>/<model>` | `OPENROUTER_API_KEY` |
| Any OpenAI-compatible endpoint | `custom:<name>:<model>` | `LLM_PROVIDER_<NAME>_API_KEY` and `LLM_PROVIDER_<NAME>_BASE_URL` |

Export the key for the provider you picked in the shell that will run the
agent. For example:

```bash
export OPENAI_API_KEY="sk-..."
```

A local model server such as Ollama goes through the last row:

```bash
export LLM_PROVIDER_LOCAL_BASE_URL="http://localhost:11434/v1"
export LLM_PROVIDER_LOCAL_API_KEY="dummy"
```

### 5. Initialize DeepClause in `src/`

DeepClause keeps its configuration in a `.deepclause/` directory next to the
agent. It is not part of the repository, so create it once, naming the model
from step 4:

```bash
deepclause init --model openai:gpt-4o
deepclause show-model
```

`deepclause list-models` lists the model ids DeepClause knows about. To switch
later, run `deepclause set-model <provider>:<model>`.

`.deepclause/` is local to your machine. Do not commit it, especially if you
store an API key in its `config.json` instead of using an environment variable.

### 6. Optional: install SWI-Prolog

Only needed to run the table logic directly, without DeepClause.

```bash
brew install swi-prolog          # macOS
sudo apt install swi-prolog      # Debian / Ubuntu
swipl --version
```

### 7. Check the installation

```bash
deepclause run dataset_builder.dml "dementia with lewy bodies" --headless
```

A working installation prints `Phase 1: Selecting papers...`, then one line per
paper, and ends with `Dataset build complete`. As a guide to cost, this prompt
with `anthropic:claude-sonnet-4-6` took 5 model calls and about $0.06 for the
full 20 papers.

## Docker

The `Dockerfile` in this directory builds an image with Node.js, DeepClause
0.0.86 with the project's patch applied, SWI-Prolog and Python 3, with
DeepClause already initialized for `openai:gpt-4o`. It replaces installation
steps 1 to 6. Build it from `dataset-builder-agent/`:

```bash
docker build -t table-dataset-builder .
```

Run the agent. The API key is passed in at run time and is not stored in the
image. The container runs `run_agent.sh`, which builds the dataset and then
has the LLM review it, and keeps a log of each run (see
[Running the agent](#running-the-agent); add `--no-review` after the search
phrase to skip the review):

```bash
mkdir -p dataset
docker run --rm --user "$(id -u):$(id -g)" -e OPENAI_API_KEY \
  -v "$PWD/dataset:/app/src/dataset" \
  table-dataset-builder "dementia with lewy bodies"
```

Create the host directory first, as above. If it does not exist, Docker creates
it owned by root and, on Linux, the run stops with `.../dataset is not
writable`; fix an existing one with `sudo chown "$(id -u):$(id -g)" dataset`.

Options from [Running the agent](#running-the-agent) go after the search
phrase. For another provider, pass its key variable and a model, for example
`-e ANTHROPIC_API_KEY` with `--model anthropic:claude-sonnet-4-6`.

**Getting the dataset out.** The container writes straight into the mounted
host directory, so there is nothing to extract: after the run, `./dataset/`
holds the `papers/`, `raw/`, `runs/` and `attempts/` output described below,
plus `logs/<UTC timestamp>/` with that run's `runtime_log.txt` and
`token_usage.json`. Mount the same directory on every
run: results accumulate per PMC ID, and `dataset/cache/` holds the NCBI rate
limiter's state. `--user` makes the files yours; without it they are owned by
root on a Linux host. Where mounting is not possible, run without `--rm` and
copy the output out afterwards:

```bash
docker run --name tdb-run -e OPENAI_API_KEY table-dataset-builder "dementia with lewy bodies"
docker cp tdb-run:/app/src/dataset ./dataset
docker rm tdb-run
```

Run the offline tests, or open a shell to use `swipl` directly:

```bash
docker run --rm --entrypoint /app/tests/run_regression_tests.sh table-dataset-builder
docker run --rm -it --entrypoint bash table-dataset-builder
```

`.github/workflows/docker.yml` rebuilds the image on every push to `main` that
touches this directory and publishes it to the GitHub Container Registry as
`ghcr.io/lzavalia/logic-based-table-parser:latest`, for x86-64 and ARM64
machines, so the published image tracks the repository. Other branches and
pull requests only build and smoke-test it. On another computer, pull it
instead of building:

```bash
docker pull ghcr.io/lzavalia/logic-based-table-parser:latest
mkdir -p dataset
docker run --rm --user "$(id -u):$(id -g)" -e OPENAI_API_KEY \
  -v "$PWD/dataset:/app/src/dataset" \
  ghcr.io/lzavalia/logic-based-table-parser:latest "dementia with lewy bodies"
```

The package is private until it is made public in its GitHub package
settings; until then, run `docker login ghcr.io` first, with a GitHub token
that has the `read:packages` scope.

To run only the [LLM review](#reviewing-candidates-with-the-llm), on a mounted
dataset that already exists, use the review script as the entrypoint; its
options go after the image name:

```bash
docker run --rm --user "$(id -u):$(id -g)" -e OPENAI_API_KEY \
  -v "$PWD/dataset:/app/src/dataset" \
  --entrypoint /app/review_agent.sh \
  ghcr.io/lzavalia/logic-based-table-parser:latest --papers PMC7293797
```

## Running the agent

From `src/`:

```bash
deepclause run dataset_builder.dml "<search prompt>" --headless
```

Useful options:

| Option | Effect |
|---|---|
| `--model <provider>:<model>` | Use a different model for this run only. |
| `--usage <file>` | Save the tokens used, per model, to a JSON file. |
| `--verbose` | Also print each tool call. |

`run_agent.sh`, in `dataset-builder-agent/`, is the normal way to run it. One
run does two steps: it builds the dataset with that command, then runs the
[LLM review](#reviewing-candidates-with-the-llm) on exactly the papers this
run selected, so every new table gets a verdict in its paper's
`review.jsonl`. The review is skipped when the build fails or selects no
papers, or with `--no-review`. Run it from any directory; it changes into
`src/` itself:

```bash
./run_agent.sh "<search prompt>"
./run_agent.sh "<search prompt>" --model anthropic:claude-sonnet-4-6
./run_agent.sh "<search prompt>" --no-review      # build only
```

Other arguments after the search prompt are passed on to `deepclause run` in
both steps, so `--model` selects the model for both. The build step writes `runtime_log.txt` (everything the agent printed) and `token_usage.json`
(tokens per model) to `src/`, beside `dataset/`, replacing those of the
previous run. With `LOG_DIR` set, they go instead to a new
`LOG_DIR/<UTC timestamp>/` directory for each run; the Docker image uses
`dataset/logs`. The review step's logs are described in
[Reviewing candidates with the LLM](#reviewing-candidates-with-the-llm).

Each run writes a `dataset/` directory inside `src/`:

| Path | Contents |
|---|---|
| `dataset/papers/PMC<id>/candidatesN.html` | Optional inspection view for table `N`. Each candidate has an explicit heading and boundary coordinates; a table with no valid boundary has an explicit abstention heading. Cells are colored green (HMD), blue (VMD), and gray (data). |
| `dataset/papers/PMC<id>/input_tableN.html` | The input counterpart of `candidatesN.html`, for side-by-side comparison: the same sanitized table and JATS label, caption and notes, shown once and uncolored. Written for every table that has an annotated view, so a quarantined table has neither. |
| `dataset/papers/PMC<id>/metadata.json` | Paper identity, title, counts, and source context, plus JSONL record linkage, candidate counts and status per table. |
| `dataset/papers/PMC<id>/certificateN_hH_vV.pl` | Geometric labelability certificate for candidate `(H, V)` of table `N`, written only when the candidate is labelable. A Prolog program that checks itself; see [Geometric labelability certificates](#geometric-labelability-certificates). |
| `dataset/papers/PMC<id>/tables.jsonl` | Canonical machine-readable export: one JSON object per source table, including raster, cell-to-XPath mapping, each structural candidate and its labels, and explicit abstention state. Empty for papers containing no tables. |
| `dataset/papers/PMC<id>/final_tables.json` | Written by the last stage of the [LLM review](#reviewing-candidates-with-the-llm): every `valid` table as `subtables` with nested horizontal and vertical metadata, unmerged data, and the residual corner. |
| `dataset/papers/PMC<id>/review.jsonl` | Written by the [LLM review](#reviewing-candidates-with-the-llm), not by the build: one verdict per line of `tables.jsonl`. Absent until the paper has been reviewed; a rebuilt paper loses it. |
| `dataset/papers/PMC<id>/final_tableN.html` | Also written by the review: the outcome for table `N`. "Parse Succeeded", the LLM's reason and the table colored for the boundary the parser and the LLM agree on; "Error: Misalignment Between LLM And Formal Table Parser" with the LLM's reason; or "Nothing To Do." when the parser found no candidate. |
| `dataset/reviews/review-<timestamp>-<n>/manifest.json` | One per review run: model, prompt version, papers requested and one status line per paper. |
| `dataset/attempts/PMC<id>.<timestamp>.<sequence>.json` | Best-effort per-paper `complete` or `failed` attempt status, timestamp, and diagnostic. |
| `dataset/raw/PMC<id>.xml` | Full text of each paper as downloaded. |
| `dataset/cache/requests/` | Private, temporary ESearch/ESummary pairs; removed after each search. |
| `dataset/cache/.ncbi-last-request` | Persistent timestamp for workspace-wide request throttling. |

`dataset/` is retained between runs. Paper outputs are keyed by **canonical PMC ID**
(rather than article title), so papers with equal or truncated titles cannot
overwrite one another. Reprocessing an ID replaces its entire published paper
directory: old `candidatesN.html` files from larger previous runs do not
survive. The article title is available in `metadata.json` instead of the path.

### JATS table context and provenance

In JATS, `<table-wrap>` generally contains the `<label>`, `<caption>`, and
`<table-wrap-foot>` as **siblings** of `<table>`. They are not cells and must
not affect row/column inference. The exported HTML renders them around each
annotated table, while `metadata.json` stores an entry for every table in the
same document order as `candidates0.html`, `candidates1.html`, etc.
Each `tables` entry has `source_path` (1-based element-child indexes through
the normalized JATS DOM), `table_id`, `wrap_path`, `wrap_id`, `label`,
`caption`, `caption_external` (whether the caption is outside the table),
`notes` (individual plain-text footnotes), and
`source_table_html` (uncolored serialized table), plus `label_markup`,
`caption_markup`, and `foot_markup` (serialized source elements, retaining
inline scientific notation). Empty strings and `[]`
represent unavailable context for tables without a wrapping element.

The displayed HTML uses normalized context text, while the structured
metadata retains the original context-element markup. This does not claim
that table headers are semantically correct. Source markup is preserved only
in the structured JSON/JSONL records, not inserted verbatim into inspection HTML.

### HTML inspection safety (original audit F17)

Before serializing browser-facing tables, `table_html_sanitizer.pl` recursively
removes active elements and their subtrees (scripts, embeds, media, forms, SVG,
MathML, styles, images). Harmless unsupported inline tags are replaced by inert
`span` elements so the scientific text remains visible. A fixed table/inline
allowlist preserves table structure and harmless formatting; source attributes
(including styles, classes, event handlers, URLs, `srcdoc` and XML namespaces)
are discarded. Only validated `rowspan`/`colspan`/`scope` values survive. The
label colors are applied **after** sanitization, so source CSS cannot override
them. This also addresses the original audit F18 CSS-precedence issue for the
inspection views.

`candidatesN.html` is for review, not a byte-for-byte reproduction of
the source. `metadata.json` and `tables.jsonl` intentionally retain the raw
serialized table and context fields for research; keep these JSON files under
`application/json` if serving them and NEVER insert their raw markup into a
web page without sanitizing again. If deploying a viewer, use an appropriate
Content Security Policy and test it independently.

The offline security suite is `tests/html_sanitization_regression_tests.pl`.

**PMC query encoding (F15).** Search terms are encoded in
`src/pmc_query_encoding.pl`, which converts each Unicode scalar value to
UTF-8 bytes and percent-encodes all bytes except ASCII letters and digits.
Accents, non-Latin scripts, and emoji therefore survive the trip to NCBI
instead of being removed. PubMed operators such as `[`/`]` are percent-encoded
in transit and interpreted as part of the `term` query parameter rather than
as URL delimiters. Unsupported scalar values fail explicitly. Run
`swipl -q -s pmc_query_encoding_regression_tests.pl -g run_tests -t halt`
from `tests/` for the targeted offline regression suite.

**Search provenance (F06).** Paper selection is fail-closed. At the start of each
`agent_main` run, the in-memory PMC-ID allowlist is cleared. Each successful
`search_pmc` call records only canonical IDs present in **both** its NCBI
ESearch ID list and the ESummary entries actually shown to the model. The
model's final list is deduplicated and intersected with this allowlist **before**
the paper limit is applied or downloads begin. Unverified IDs are reported and
ignored; a run with no verified selection downloads nothing. IDs from multiple
successful searches in the same run remain eligible, but prior runs do not.
This prevents fabricated or unobserved IDs; it does **not** independently
prove that a returned paper is scientifically relevant to the topic.

Paper output is first written in a hidden staging directory under
`dataset/papers/`. The old complete version remains untouched on normal
processing failures; a successful rerun moves it to a temporary backup and
publishes the new directory, then removes the backup. **Directory replacement
is not crash-atomic**: if the process or host stops in the short interval
between the two renames, a hidden `.PMC<id>.stage.*.backup` directory may hold
the previous complete version while `papers/PMC<id>/` is absent. Recover it
manually only after confirming no other run is active, and inspect any stale
`.PMC<id>.stage.*` directories before removing them. An exclusive
`.PMC<id>.lock` directory protects against two processes publishing the same
paper concurrently. A hard crash can leave that lock behind: manually remove
it only after verifying the earlier process is no longer running.

**Concurrent runs (F13).** Search responses are allocated in private
`dataset/cache/requests/.search.stage.*` directories, cleaned up after each
`search_pmc` call. Both ESearch and ESummary are read from the same pair, so
one worker cannot overwrite another's selection evidence. Before each NCBI
request, workers using the **same `/workspace` filesystem** acquire
`dataset/cache/.ncbi-request.lock`, honor a 0.4-second gap since the previous
reservation, and update `.ncbi-last-request`. The atomic directory lock also
serializes concurrent writers to the shared timestamp. A normal exception
releases the rate lock; a hard crash may leave it behind. The limiter gates
request *reservations* immediately preceding `url_fetch`, not guaranteed
HTTP arrival times. It cannot enforce an IP-wide limit across unrelated
workspaces or servers; use one shared workspace/host limiter for those runs.

**Waits (F14).** Request spacing and retry backoff are done in Prolog, by
`reserve_ncbi_request/1` and `pause/1` in `src/dataset_pipeline.pl`; there is no
host helper. In standalone SWI-Prolog `pause/1` blocks in `sleep/1` and uses no
CPU. DeepClause's WebAssembly engine has no blocking wait (`sleep/1` raises a
JavaScript error, and `shell/1` and threads are absent), so there `pause/1`
falls back to polling the clock. That keeps one CPU core busy while waiting:
0.4 seconds per NCBI request, and 2 to 30 seconds per retry when NCBI
rate-limits. The lock directory and timestamp file are the same in both
engines, so native and DeepClause workers sharing a workspace stay coordinated.
An invalid timestamp or a busy lock **aborts the request** rather than
bypassing throttling. `tests/pause_regression_tests.pl` and
`tests/concurrency_regression_tests.pl` cover the waits and the limiter.

An exclusive `dataset/raw/.PMC<id>.ingest.lock` covers an individual paper's
raw XML download **and subsequent processing**; a competing ingest for the
same ID fails explicitly instead of overwriting XML still being parsed. Other
paper IDs can proceed. A crash may leave ingest or request lock directories;
inspect running workers before removing them. Do not delete these locks just
because they appear old. Retrying failed same-ID papers after the other run
finishes is safe. These changes do not make two-rename paper publication fully
crash-atomic (see above), or make a dynamic allowlist thread-local within a
single shared Prolog engine; the DeepClause CLI runs in separate processes.

**Migration:** directories produced by older versions at
`dataset/<sanitized article title>/` are left untouched to avoid accidental
delete/misattribution of files already affected by title collisions. Review
and archive or remove those legacy directories manually; new output is under
`dataset/papers/`.

### Optional table-level recovery (post-F16)

**Default behavior is unchanged.** The DeepClause agent calls
`process_paper/4`, which fails the entire paper on any invalid table; an
existing published snapshot is retained. Native SWI-Prolog callers may
*explicitly* opt into quarantine for known table-local geometry errors:

```prolog
?- use_module(dataset_pipeline).
?- process_paper("123", "dataset/raw/PMC123.xml", "dataset",
                 [on_table_error(quarantine)], Summary).
```

For each source table, `tables.jsonl` still has an entry with the **original
zero-based table index**. A quarantined table has `status: "quarantined"`,
`raster: null`, no cell/candidate labels, and an `error` object with a stable
code and reason. Its `candidatesN.html` **does not exist**, rather than
containing a misleading annotation. All successful tables keep their original
numbered HTML files. The `metadata.json` file includes `status: "partial"`,
`table_count` (total), `parsed_table_count` (usable tables with a valid
boundary), and `quarantined_table_count`. Partial snapshots use schema `3.1`;
fully successful snapshots retain schema `3.0` (with an extra zero count in
the opt-in path). Summaries and attempt records explicitly say `partial`.

Quarantine applies only to known invalid spans/overlaps, table raster limits,
missing raster-cell mappings, and per-table candidate-output budgets. XML
parsing, PMC identity, per-paper resource limits, disk/permission errors,
serialization errors, and unexpected exceptions **abort** and preserve the
previous snapshot. If *all* source tables are quarantined, no replacement is
published. Quarantine is not enabled automatically in DeepClause, because
consumers must explicitly understand that a `partial` dataset contains
rejected tables. Use `[on_table_error(fail)]` for the strict /5 equivalent.

The offline suite `paper_recovery_regression_tests.pl` checks partial
snapshot consistency, retained indices, strict-by-default semantics,
whole-paper failure and corruption detection. Run it through the existing
`run_regression_tests.sh --all` CI harness.

**Security note:** The original audit's F17 refers to browser sanitization
of annotated HTML. That issue is distinct from this follow-up recovery task
and remains unresolved.

### Settings

| Setting | Where | Default |
|---|---|---|
| Papers per run | `max_papers/1` in `dataset_builder.dml` | 20 |
| Shared minimum gap between NCBI request reservations (s) | `ncbi_request_gap/1` in `dataset_builder.dml` | 0.4 |
| Waits before retrying a rate-limited request (s) | `ncbi_retry_waits/1` in `dataset_builder.dml` | 2, 5, 10, 20, 30 |
| Model | `deepclause set-model`, or `--model` for one run | chosen in step 5 |

## Offline testing and CI (F16)

The repository runs its **network-free regression tests on each push and pull
request** using `.github/workflows/regression.yml`. CI installs SWI-Prolog and
Python 3.12 and requires all Prolog and Python suites to pass; the job fails on
missing interpreters, missing test suites, load errors, assertions, or other
nonzero test exits. No API key, NCBI access, or DeepClause installation is
needed. Different Prolog suites run in separate interpreters to avoid shared
fixture-predicate name collisions.

From **any directory**, run the portable harness:

```sh
/path/to/Logic-Based-Table-Parser-main/dataset-builder-agent/tests/run_regression_tests.sh --all
# Alternatives:
./dataset-builder-agent/tests/run_regression_tests.sh --list
./dataset-builder-agent/tests/run_regression_tests.sh --prolog-only
./dataset-builder-agent/tests/run_regression_tests.sh --python-only
```

`--all` is also the default. Prolog suite files matching
`tests/*_regression_tests.pl` and Python suite files matching
`tests/*_regression_tests.py` are discovered automatically. The selected
interpreter must be installed: `swipl` (SWI-Prolog 9+) or `python3` (Python
3.10+). Set `SWIPL=/path/to/swipl` or `PYTHON=/path/to/python3` to select
alternatives. **No suites are silently skipped.** The `--python-only` option
is useful on hosts without SWI-Prolog but is not a substitute for the complete
CI run.

To test the harness itself without SWI-Prolog, run:

```sh
python3 -m unittest discover -v -s dataset-builder-agent/tests -p 'test_*.py'
```

These harness tests use mock executables to verify discovery, working-directory
independence, and failure propagation. CI does **not** run the live DeepClause
agent or NCBI network integration; those still require separate integration
validation. The independent Python geometry and boundary-model scripts under
`tools/` are supplementary checks, not native Prolog coverage.

## Reviewing candidates with the LLM

The parser only finds *structurally* admissible header boundaries. A second
agent, `src/review_dataset.dml`, asks the LLM whether it agrees. `run_agent.sh`
runs it automatically after each build, on that run's papers (see
[Running the agent](#running-the-agent)). To review an existing dataset
without building, run it on its own with `review_agent.sh`:

```bash
./review_agent.sh                                  # every paper not yet reviewed
./review_agent.sh --papers PMC7293797,PMC5831205   # only these papers
./review_agent.sh --run <name>                     # the papers of build run dataset/runs/<name>
./review_agent.sh --force --model anthropic:claude-sonnet-4-6
```

**How a table is judged.** The review is blind: for each table the model is
shown the cell texts row by row (with merged cells, `<th>` header cells,
label, caption and notes) but *not* the parser's candidates, so it cannot
simply agree with them. It answers with its own boundary: the number of
column-header rows and the number of row-header columns, either of which may
be 0 (`0` and `0` when the table has no headers at all). `src/table_review.pl` then compares that answer with the
candidates:

| Parser | Model's answer | `final_status` | `decided_by` |
|---|---|---|---|
| one candidate (`unique`) | the same boundary | `valid` | `llm` |
| several candidates (`ambiguous`) | one of them | `valid`, with `selected_candidate_id` | `llm` |
| `unique` or `ambiguous` | any other counts, including `0` and `0` | `unparseable` | `llm` |
| no candidate (`abstained`) | not asked | `unparseable` | `parser` |
| `quarantined`, or more than 2,500 slots | not asked | `unreviewed` | none |
| any | no usable answer after one retry | `unreviewed` (`review_status: "review_failed"`) | none |

An API failure or an answer that cannot be read is never counted as
`unparseable`. Each table gets a fresh call with no earlier conversation and
no tools, so verdicts cannot influence one another, and the temperature is 0
unless `--temperature` is passed. Text inside the table is presented as data;
only the typed answer is used.

**Output.** `dataset/papers/PMC<id>/review.jsonl` has one record per line of
the paper's `tables.jsonl`, which itself is left unchanged. Each record has the
statuses above, the candidate ids, the model's boundary and one-sentence
reason, its raw answer, the number of attempts, the model and prompt version,
and the SHA-256 of the `tables.jsonl` it reviewed. A paper whose review is
current (same `tables.jsonl`, prompt version and model, and no failed
reviews) is skipped on the next run; `--force` reviews it again. Each run also
writes `dataset/reviews/review-*/manifest.json`. The script's own log goes to
`src/review_log.txt` and `src/review_token_usage.json` (or under `LOG_DIR`).

Next to `review.jsonl` the review writes `final_tableN.html` for every table,
rendered by `final_table_html/3` in `src/dataset_pipeline.pl` from the table's
`tables.jsonl` record and its verdict. It starts with one of these headings:

| Verdict | Heading | Then |
|---|---|---|
| `valid` | Parse Succeeded | the LLM's reason, then the table with its label, caption and notes, colored for the agreed candidate (green HMD, blue VMD, gray data) |
| `unparseable`, decided by the LLM | Error: Misalignment Between LLM And Formal Table Parser | the LLM's reason, then the LLM's boundary and the parser's candidate ids |
| no candidates (parser abstained, or the table was quarantined) | Nothing To Do. | one line saying why |
| `unreviewed` (too large, or no usable answer) | Not Reviewed | one line saying why |

The table in a "Parse Succeeded" page is re-parsed from `tables.jsonl` and
must rasterize to the recorded raster, so its colors are exactly those of the
reviewed boundary. The pages are written before `review.jsonl` under the
paper's lock, each through a temporary file, so a failure leaves the previous
review and pages in place. A paper whose review is current but has no pages
(reviewed before they existed) gets them on the next run, from `review.jsonl`
and without new model calls.

`valid` means that the parser and the model agree, nothing more:
`semantic_validation` is `"llm_reviewed_not_human_verified"`. The model can
be wrong, and its agreement rate should be checked against human labels
before it is relied on.

**Structured export.** As its last stage, without the LLM, the review agent
runs `src/table_export.pl`, which writes `dataset/papers/PMC<id>/final_tables.json`
for every paper in scope whose `review.jsonl` matches its current
`tables.jsonl` (including papers skipped because their review is current).
Papers still in schema 1.x are skipped. The file has one entry per table, in
`tables.jsonl` order, with `table_uid`, `table_index`, `label`, `caption`,
`final_status`, and for a `valid` table the agreed `candidate_id`, its
`boundary` (`{hmd, vmd}` counts), its `geometric_certificate`, and
`subtables`. For now a table has exactly one subtable:

```json
{"subtables": [
  {"horizontal metadata": [{"HMD 0": [{"HMD 1": []}, {"HMD 1": []}, {"HMD 1": []}]}],
   "vertical metadata":   [{"VMD 0": [{"VMD 1": []}, {"VMD 1": []}]},
                           {"VMD 0": [{"VMD 1": []}, {"VMD 1": []}]}],
   "data": [["DATA", "DATA", "DATA"], ["DATA", "DATA", "DATA"],
            ["DATA", "DATA", "DATA"], ["DATA", "DATA", "DATA"]],
   "residual_corner": [{"Corner": []}]}]}
```

That is the export of a table with a two-row header (`HMD 0` over three
`HMD 1` cells), two two-level row headers, and a `Corner` cell spanning the
two header rows and two row-header columns.

- Each metadata cell is an object with one key, the cell's text, whose value
  is the list of its children, in reading order. A padding cell's key is `""`.
- `horizontal metadata`: the header rows over the data columns. Roots are the
  cells of the first row; a cell's children are the cells directly below it.
  The leaves, left to right, head the data columns.
- `vertical metadata`: the row-header columns over the data rows, read left to
  right. The leaves, top to bottom, head the data rows.
- `data`: the data region as a list of rows of cell texts. Merged cells are
  **unmerged**: a cell's text is repeated in every slot it covers. Slots that
  pad short rows are `null`.
- `residual_corner`: the cells above the row headers, as a forest read top to
  bottom; `[]` without header rows or row-header columns. A cell over both
  the corner and the data columns (a title row) appears in both
  `residual_corner` and `horizontal metadata`.

Other tables keep their entry with `"subtables": null`. If a metadata cell
sits under (or right of) more than one cell, so the metadata is not a forest,
the table gets an `export_error` instead; the ten constraints rule this out
for every candidate. Tables with central metadata (several subtables) are not
supported yet; they have no candidate, so they are never `valid`. The file is
written under the paper's lock through a temporary file. Tests:
`tests/table_export_regression_tests.pl`.

**Cost.** One model call per table with candidates, which DeepClause turns
into two API requests (the answer and a short follow-up), each carrying the
whole table. In a trial with `anthropic:claude-sonnet-4-6` that was 6,000 to
61,000 input tokens per table, depending on its size: roughly $0.02 to $0.20
per table, about $0.06 on average.

The model recorded in each review is the `--model` passed to `review_agent.sh`,
or else the `run` model in `src/.deepclause/config.json`. When running
`deepclause run review_dataset.dml` directly with `--model`, also pass
`-P model=<the same id>` so the record names the right model.

## Running the table logic without the agent

These need SWI-Prolog (step 6) but no API key, no DeepClause and no network.
Run them from `src/`.

Annotate the tables of any HTML or XML file with `test_driver.pl`. Files with
the extension `.xml` or `.nxml` are parsed as strict JATS XML; anything else is
parsed as loose HTML:

```bash
swipl -g 'consult(test_driver),
          test_table_parser("path/to/file.html", Files),
          writeln(Files)' -t halt
```

For every `<table>` (numbered from 0 in document order) the driver writes one
sanitized, colored view per structural candidate boundary to
`path/to/file.html.tables/`:

- `table<N>_hmd<H>_vmd<V>.html`: table `N` colored for `H` HMD rows and `V`
  VMD columns.
- `table<N>_unannotated.html`: table `N` has no admissible boundary, so it is
  written uncolored instead of being omitted.

Choose another directory with `test_table_parser(File, OutDir, Files)`. Earlier
`table*.html` files in that directory are replaced; other files are untouched.
The driver is strict like `process_paper/4`: oversized or malformed spans raise
the same typed errors, and a file with no `<table>` raises
`no_tables_found(File)`. Candidates are structural hypotheses, not verified
semantic labels. `tests/test_driver_regression_tests.pl` covers this driver.

Process a paper the agent has already downloaded, exactly as the agent does.
Replace `7285984` with the id of a file in `dataset/raw/`:

```bash
swipl -g 'use_module(dataset_pipeline),
          process_paper("7285984", "dataset/raw/PMC7285984.xml", "dataset", Summary),
          writeln(Summary)' -t halt
```

### Boundary contract and regression tests

A boundary `(Hmd, Vmd)` gives the **number** of horizontal-metadata rows and
the number of vertical-metadata columns:

```text
rows 0 .. Hmd-1                     horizontal metadata (HMD)
rows Hmd.., columns 0 .. Vmd-1      vertical metadata (VMD)
rows Hmd.., columns Vmd..           data
```

`Hmd = 0` means the table has no HMD rows (row headers only), and `Vmd = 0`
that it has no VMD columns (column headers only). Three constraints on top of
the seven original ones rule out the degenerate partitions and bias the
search towards HMD:

| # | Constraint | Rejects |
|---|---|---|
| 7 | not entirely data | `(0, 0)` |
| 8 | not entirely metadata | `Hmd = number_of_rows` or `Vmd = number_of_columns` |
| 9 | no HMD rows only for a plain grid | `Hmd = 0` in any table with a merged cell |

A *plain grid* is a table without merged cells: no two raster slots belong to
the same cell (padding slots for short rows are cells of their own). A merged
cell anywhere is taken as evidence of a header hierarchy, so such a table is
always read with at least one HMD row. `Vmd = 0` is not limited this way, so
a table can have column headers without row headers whatever its shape, but
row headers without column headers only if it is a plain grid.

So every candidate satisfies `0 <= Hmd < number_of_rows`,
`0 <= Vmd < number_of_columns` and `Hmd + Vmd > 0`. Rasters of any rectangular
shape are accepted, including one-row and one-column tables; a single cell has
no admissible boundary. Tables without one are saved uncolored (the existing
abstention behavior).

Constraints 0 to 6 are those of the original `ConstraintValidators.scala`,
which named the last HMD row and the last VMD column. For `Hmd >= 1` and
`Vmd >= 1` each tests exactly the cells the original tested at
`(Hmd-1, Vmd-1)`; `tests/legacy_index_constraints.pl` keeps the original
rules so a regression test can check this. A rule that compares a region with
an empty one has nothing to compare and holds.

Both forms of `omni_validate` enforce the same domain (`0..number_of_rows`,
`0..number_of_columns`). The four-argument form reports
`some(invalid_boundary)` for counts outside it or malformed rasters,
`some(7)` or `some(8)` for a degenerate partition, `some(9)` for no HMD rows in
a table with merged cells, and otherwise the first failed structural
constraint, `some(0)` through `some(6)`.

A plain grid of at least 2x2 admits exactly three boundaries, `(0,1)`, `(1,0)`
and `(1,1)`: the structure alone cannot tell a header row from a header column,
so such tables are `ambiguous` and the LLM review chooses. Tables with merged
cells can also be ambiguous between `Vmd = 0` and `Vmd >= 1`.

Run the offline boundary regressions from `dataset-builder-agent/tests`:

```bash
swipl -q -s boundary_regression_tests.pl -g run_tests -t halt
```

This check needs SWI-Prolog but no network access or LLM.

Paper-output regressions (duplicate titles, stale files, rollback, and PMC
identity validation) are run separately:

```bash
swipl -q -s paper_output_regression_tests.pl -g run_tests -t halt
``` A valid structural
partition is still only a *candidate interpretation*, not a verified semantic
label for a scientific table.

## Files

| File | Purpose |
|---|---|
| `src/pmc_query_encoding.pl` | Unicode-safe UTF-8 query-component encoder used by the agent. |
| `tests/pmc_query_encoding_regression_tests.pl` | Offline tests for Unicode, reserved URL characters, and edge cases. |
| `src/dataset_builder.dml` | The agent: paper selection (model), NCBI search and download, and the per-paper loop. |
| `src/dataset_pipeline.pl` | Prolog module the agent loads. Connects parsers, constraints, annotations, and staged JSONL/HTML output. |
| `src/table_machine_records.pl` | Canonical JSONL schema, deterministic cell provenance and candidate labels. |
| `tests/machine_annotations_regression_tests.pl` | Offline tests for JSONL schema, ambiguous boundaries, merged cells, synthetic slots, abstention, IDs, and reruns. |
| `src/table_layout_generator.pl` | Parses HTML and turns each `<table>` into a raster of cell ids. |
| `src/table_html_sanitizer.pl` | Removes executable markup from browser-facing table views while keeping source records unchanged. |
| `src/parse_constraints.pl` | The ten reference constraints (HMD and VMD as counts), the public boundary validator (`valid_boundaries/2`), and the search for candidate layouts with metadata in the middle of the table (`table_layouts/2`, not yet used by the pipeline). |
| `tests/table_layouts_regression_tests.pl` | Offline tests for `valid_boundaries/2` and `table_layouts/2` on hand-built rasters: separator rows, central HMD and VMD, nested and mixed cuts. |
| `tests/legacy_index_constraints.pl` | The original last-index constraints, kept as a test reference only. |
| `src/fast_boundaries.pl` | Indexed adjacency summaries for efficient exhaustive-equivalent boundary enumeration. |
| `src/table_annotator.pl` | Colors a table's cells for a given boundary. |
| `src/certificate_kernel.pl` | Trusted checker for geometric labelability certificates (see [Geometric labelability certificates](#geometric-labelability-certificates)). |
| `src/table_certify.pl` | Builds and writes geometric labelability certificates; not trusted, every certificate is checked by the kernel. |
| `tests/certificate_regression_tests.pl` | Offline tests for the certificate kernel and generator: both claims, the strong reading, boundary lines, tampering, and agreement with the constraints. |
| `src/review_dataset.dml` | The review agent: asks the LLM to check every table's candidates (see [Reviewing candidates with the LLM](#reviewing-candidates-with-the-llm)). |
| `src/table_review.pl` | Builds the review prompts, checks the answers against the candidates, and writes `review.jsonl`. |
| `src/table_export.pl` | Last stage: writes `final_tables.json` from `tables.jsonl` and `review.jsonl`. |
| `tests/table_export_regression_tests.pl` | Offline tests for the export: the reference example, trees, unmerged data, stale reviews, locking, paper filter. |
| `tests/table_review_regression_tests.pl` | Offline tests for the review: blind prompts, answer checking, statuses, skipping current reviews, file safety. |
| `tests/boundary_regression_tests.pl` | Offline regression tests for boundary domain and structural validation. |
| `tests/boundary_scaling_regression_tests.pl` | Differential tests for indexed boundary search and streamed renderer. |
| `tests/paper_output_regression_tests.pl` | Offline regression tests for stable PMC output identity, replacement, and failure rollback. |
| `src/test_driver.pl` | Runs the table logic on a local file, without the agent. |
| `tests/test_driver_regression_tests.pl` | Offline tests for the local driver: output naming, sanitization, stale-file replacement, strict errors. |

## Troubleshooting

- **`deepclause: command not found`**: npm's global `bin` directory is not on
  `PATH`. `npm prefix -g` prints the prefix; add its `bin` subdirectory to
  `PATH`.
- **`No .deepclause directory found in this workspace`**: step 5 was skipped,
  or the command was not run from `src/`.
- **`... API key is missing`**, followed by `Could not build a dataset`: the API
  key variable for the configured provider is not set in the shell running the
  command. `deepclause show-model` prints which provider that is.
- **`Could not build a dataset ... no usable PMC ids were selected`** with no
  error before it: the model did not return any PMC ids. Try a more specific
  prompt, or a model with reliable tool calling.
- **`ncbi_invalid_rate_state(...)` / `ncbi_rate_clock_skew(...)`**: the shared
  limiter file `dataset/cache/.ncbi-last-request` is unreadable or holds a time
  in the future. Check ownership of `dataset/cache/`; once no run is active,
  delete that file. Do not bypass the limiter to make the run proceed.
- **`concurrent_lock_busy(...)` / `pmc_ingest_busy(...)`, or an error naming a
  `.PMC<n>.lock` path under `dataset/papers/`**: another run owns a lock, or a
  crashed run left one behind. Locks are plain directories and are never removed
  automatically, because a slow live run must not lose its lock. To recover:
  1. Confirm nothing is using this workspace:
     `pgrep -fa 'deepclause|swipl'` should show no run for it.
  2. List the lock directories:
     `find dataset -maxdepth 3 -type d -name '.*lock'`.
     The three kinds are `dataset/cache/.ncbi-request.lock` (request limiter),
     `dataset/raw/.PMC<n>.ingest.lock` (download and processing of one paper)
     and `dataset/papers/.PMC<n>.lock` (publication of one paper).
  3. Remove only the stale one with `rmdir <path>` (it is empty).
  Leftover `dataset/papers/.PMC<n>.stage.*` or `*.backup` directories are
  harmless debris from a crash and may be deleted once no run is active; a
  `*.backup` directory beside a missing `PMC<n>` directory holds the previous
  published copy, so rename it back to `PMC<n>` instead of deleting it.
- **`NCBI rate limit reached; pausing ...`**: expected now and then. The request
  is retried up to five times before that paper is reported as failed.
- **A paper reports `0 table(s)`**: its tables are published as images, or NCBI
  does not provide its full text as XML.

### Table raster resource limits (F04)

Untrusted table spans are validated **before** grid slots are allocated. The
rasterizer raises a structured `table_raster_limit_exceeded(Name, Limit, Actual)`
exception (wrapped in `error/2`) rather than accepting oversized input or
silently truncating column spans. Such a failure aborts the paper and, thanks
to staged paper publication, leaves any previously published results unchanged.

| Budget | Default | Configured in |
|---|---:|---|
| Rows per table | 1,000 | `table_layout_generator.pl:table_raster_limit/2` |
| Columns / colspan per table | 256 | same |
| Real cells per table | 10,000 | same |
| Total cell-slot claim attempts per table | 100,000 | same |
| Total dense slots (`rows * columns`) per table | 100,000 | same |
| Span attribute characters | 32 | same |
| Tables extracted per paper | 256 | `dataset_pipeline.pl:paper_raster_limit/2` |
| Combined dense raster slots per paper | 250,000 | same |

The rasterizer writes claimed slots incrementally instead of allocating a
second `findall/3` list for each merged-cell rectangle. Its existing rules for
`rowspan="0"` and clipping rowspans to the table section remain unchanged.
Change budgets only for **trusted** oversized tables with adequate memory.
These checks protect the rasterization stage; they do not cap XML download
sizes, DOM parsing allocations or the later number of annotations generated.

Run the standalone offline regression suite from `dataset-builder-agent/tests`:

```bash
swipl -q -s raster_limits_regression_tests.pl -g run_tests -t halt
```

### Failure reporting and complete-output validation (F05)

A successful paper publication is now tagged `"status":"complete"` in its
`metadata.json` and is preceded by a check that **exactly** the numbered
`candidatesN.html` files, matching metadata and the certificate files the
records name exist in the staging directory; empty table files, missing or unexpected files, and inconsistent
counts abort publication. Annotation rendering now requires an output for
**each** valid boundary (instead of silently dropping failed candidates).

Failed builds appear as `PMC<id>: failed (<reason>); <previous snapshot status>`
with an indexed table error or raster-limit description where applicable.
Failures do **not** publish partial table sets; previously published completed
snapshots remain untouched. Download failures may still leave a raw response
under `dataset/raw/`; these are not published table annotations. Status files
under `dataset/attempts/` record successful and failed build attempts
separately; they are **best-effort**, not a transactional database. A hard
crash can still leave an incomplete staging directory or prevent a status
record from being written; there is no automatic crash recovery yet.

Run the new offline tests alongside the prior three suites (from `tests/`):

```bash
./run_regression_tests.sh
# or run just F05:
swipl -q -s paper_failure_regression_tests.pl -g run_tests -t halt
```

### PMC download and XML integrity (F07/F08)

PMC eFetch payloads are parsed as **JATS XML**, using SWI's XML dialect with
parser diagnostics treated as errors. Standalone HTML helpers remain tolerant
of loose HTML. The parser normalizes qualified JATS element names before
extracting and rasterizing `<table>` elements; it does not change the
semantics of the seven boundary constraints. Before publishing a paper,
`process_paper/4` requires exactly one JATS article and a matching `pmc` or
`pmcid` `article-id` inside `<front><article-meta>` (current eFetch responses use
`pmcid`; versioned and internal ids such as `pmcid-ver` and `pmcaid` are ignored). A genuine, well-formed paper
with no tables may still produce a complete zero-table result.

`download_status/3` distinguishes accepted ESearch/ESummary JSON, accepted
JATS XML, rate-limited/transient error bodies, and invalid/empty/nonarticle
responses. A body that parses as exactly one JATS article is accepted as such
*before* any error-text matching, so an article whose title mentions "rate limit
exceeded" or "too many requests" is not mistaken for a throttling reply; bodies
that fail that check (JSON errors, XML `<ERROR>` documents, HTML pages) are
still matched against the transient-error phrases. `ncbi_fetch` retries only
known transient bodies, with bounded retries. Invalid responses cannot publish
a paper. The DeepClause
`url_fetch` API in use does **not** expose HTTP headers/status to this DML
code; status/content-type checks at the transport layer remain a follow-up
for the fetch adapter. The local, network-free regression suite is
`tests/download_xml_regression_tests.pl` (also included in
`tests/run_regression_tests.sh`).


### Canonical machine-readable annotations (F10)

Each complete paper snapshot includes `papers/PMC<id>/tables.jsonl`, with
**exactly one compact JSON object per extracted table** (newline-delimited JSON).
Do not derive labels from the inspection HTML/CSS. The JSONL records include:

- `schema_version: "3.0"` (`"3.1"` for a quarantined table; 3.x adds
  `geometric_certificate` to each candidate, otherwise it is 2.x), `pmc_id` (e.g.
  `PMC123`), zero-based `table_index`, and
  stable `table_uid` (`PMC123/t0`); JATS `source_table_id` is descriptive and
  **not** used for identity because source IDs may be missing or duplicate.
- `source_path` and `context`, including unannotated `source_table_html`, JATS
  label/caption/footnotes and their original markup (preserved since F09).
- `rows`, `columns`, `raster` (rectangular array of zero-based cell IDs), and
  `cells`: each distinct cell ID with its top-left `row`/`column`, text, tag,
  and `source_xpath` using 1-based element-sibling XPath steps. Cells added
  to pad short rows have `kind: "synthetic_gap"` and `source_xpath: null`.
- `candidates`: **all** structurally valid boundaries, in deterministic search
  order. Each candidate has `candidate_id` such as `PMC123/t0/h1_v0`, `hmd`
  and `vmd` as **counts** (the number of HMD rows and VMD columns; schema 1.x
  files stored the last HMD row and VMD column instead), and one
  `{cell_id, region}` label per distinct raster cell, with region `"hmd"`,
  `"vmd"`, or `"data"`. `failed_constraints: []` signifies that all ten
  constraints passed. **Rejected candidates are not exported**;
  `omni_validate/4` can diagnose an individual rejected boundary. Each
  candidate also has `geometric_certificate`: `{status: "certified", claim:
  "columns"|"rows", file, rejections: null}` naming the certificate file, or
  `{status: "not_labelable", claim: null, file: null, rejections: {columns,
  rows}}` with the kernel's reason for rejecting each claim.
- `status`: `"unique"` (one candidate), `"ambiguous"` (multiple), or
  `"abstained"` (none), plus nullable `abstention_reason`. Structural validity
  does **not** establish that a human would assign the same header semantics.

`metadata.json` retains its existing per-table scientific context and now also
supplies `table_uid`, `candidate_count`, `annotation_status`, and `jsonl_file`.
Publication validates the JSONL record count, identities, statuses, and
candidate counts against this metadata and the HTML file count before replacing
an existing paper snapshot. A zero-table paper publishes an empty `tables.jsonl`.

### Geometric labelability certificates

A boundary `(Hmd, Vmd)` makes a table **geometrically labelable** if its data
columns correspond one to one with the root-to-sink paths of the HMD graph,
or its data rows with those of the VMD graph. The HMD graph has an edge
`A -> B` when, in a data column, cell `A` is directly above cell `B` and
`A` differs from `B`; a column's path is its HMD cell ids, top to bottom,
without repeats. So no two columns share a path, and no path in the graph
belongs to no column (which excludes inverted hierarchies). The VMD graph
is the same, read left to right over the data rows. In addition, no cell may
cross the HMD line (in any column) or, below the HMD, the VMD line.

- `src/certificate_kernel.pl` is the trusted checker; it depends only on
  SWI-Prolog's standard libraries and states the definition precisely.
- `src/table_certify.pl` (not trusted) builds certificates with `certify/4,5`
  and writes them with `write_certificate/2`. Every certificate it returns
  has been accepted by the kernel.

For each candidate the build writes `certificateN_hH_vV.pl` if it is
labelable. Before publishing, the stage validator reads every certificate
back **as data** (its directives are never run), compares it with a freshly
generated one, and has the kernel check it. Check a published certificate
yourself with only the kernel:

```bash
swipl -p certificate_kernel=src dataset/papers/PMC123/certificate0_h1_v1.pl
```

It prints `certificate accepted` and exits with status 0, or prints the
reason and exits with status 1. The certificate locates the kernel through
the `certificate_kernel` search path, so whoever checks it decides which
kernel to trust. In the Docker image the kernel is in `/app/src`.

Labelability is checked independently of the ten constraints. On random
tables the two agree on every candidate except one known case: constraint 1
checks the HMD line only from column `Vmd-1` rightwards, so a VMD cell further
left may cross it; such a candidate is kept with status `"not_labelable"`.
Tests: `tests/certificate_regression_tests.pl`.

All coordinates, table indices, and cell IDs start at **zero**. XPath element
sibling indices start at **one** (as required by XPath). Cell labels follow
**the top-left occupied raster slot** for merged cells. If a malformed source
cell is absent from the raster, JSONL generation fails instead of silently
assigning that source cell a label; detailed collision diagnostics remain F12.

Run the offline regression suite with `tests/run_regression_tests.sh`; the new
F10-specific suite is `tests/machine_annotations_regression_tests.pl`.

### Indexed boundary search and streamed rendering (F11)

`src/parse_constraints.pl` keeps the ten public constraint predicates and
`omni_validate/3-4` as the reference, for precise explanations.
`valid_boundaries/2` now calls `src/fast_boundaries.pl` after validating the
raster's shape **once**. The new evaluator makes a single pass through cell
adjacencies and builds ordered-association summaries for merged-cell
crossings, hierarchy witnesses, and inversions. Per-header-row bounds reduce
the candidate-column search range before further checks. It returns exactly
the same candidate list, in the same `(hmd,vmd)` order, as the reference
predicates. Its summaries are indexed by the last HMD row and VMD column; the
cases with no HMD or no VMD are checked separately.

In contrast to the old repeated `nth0/3` scans, the indexed construction uses
`O(R*C*log(R+C))` time and `O(R+C)` auxiliary summary space for an `R x C`
raster. Testing candidate positions costs up to `O(R*C*log(R+C))`; candidate
materialization still takes `O(K)` positions for `K` accepted pairs. The
writer now **streams one HTML candidate at a time** and reuses the input
raster without rerasterizing merged cells for each candidate. Canonical
JSONL records still intentionally contain all candidate label lists, so their
size can grow as `O(K*R*C)` in the worst case. To avoid huge allocations,
the output layer rejects a table before opening its HTML file if the number
of candidate × distinct-cell labels exceeds **500,000**. This raises
`table_output_limit_exceeded(candidate_labels, Limit, Actual)` and preserves
previously published results via the existing staging/rollback path. It does
not silently truncate candidates or pretend the table was successfully parsed.
This is a resource limit on F10's explicit-label schema, not a restriction
of the logical boundary solver itself.

Run the new offline differential tests as part of the full suite:

```sh
cd dataset-builder-agent/tests
./run_regression_tests.sh
# Or just F11:
swipl -q -s boundary_scaling_regression_tests.pl -g run_tests -t halt
# Repeatable standalone (no external services) benchmark:
swipl -q -s ../tools/benchmark_boundaries.pl -g run_benchmark -t halt
# Independent Python formula replay (does not execute Prolog):
python3 ../tools/verify_fast_boundary_logic.py
```

The differential suite includes exhaustive binary-valued small rasters,
400 seeded randomized rectangular rasters, real merged-cell arrangements,
malformed/degenerate inputs, and byte-for-byte comparison with the legacy
HTML renderer. The Python formula check is a separate verification aid; it
must **not** be represented as native SWI-Prolog test coverage or a Prolog
runtime benchmark.


### Strict raster integrity (F12)

Rasterization now **fails closed** on malformed source-cell geometry instead
of silently discarding part of a cell. If two merged cell rectangles attempt
to claim the same `(row, column)` slot, it raises
`error(table_layout_error(overlapping_cell_spans(NewId, Row, Col, OldId)), Context)`.
The per-paper pipeline attaches the failing table index and keeps any prior
published snapshot unchanged. Source cells are required to occur in the
finished grid, and annotators reject source cells lacking a raster position.

Missing `rowspan`/`colspan` attributes still mean `1`; `rowspan="0"` is valid
and rowspans are clipped to their section as before. **Explicit malformed
span values** (nonnumeric, negative, or `colspan="0"`) now cause a typed
`table_layout_error(invalid_span(Attribute, Value))` rather than being
silently normalized. This stricter behavior intentionally rejects some
malformed HTML that a browser might repair. Oversized spans continue to
use F04's resource-limit errors. An empty source table fails with
`table_layout_error(empty_table)`.

Legitimate sparse rows are still supported: uncovered slots receive distinct
synthetic IDs, identifiable by `kind: "synthetic_gap"` and `source_xpath: null`
in `tables.jsonl`. No silent overlap correction or permissive rasterization
mode is offered; a malformed table is quarantined with a diagnostic. Run:

```bash
cd dataset-builder-agent/tests
swipl -q -s raster_integrity_regression_tests.pl -g run_tests -t halt
./run_regression_tests.sh
```


## Final audit closure: F19, F20 and semantic limitations

**PMC ID selection (F19).** `src/pmc_id_parser.pl` accepts case-insensitive
`PMC` + 1–12 ASCII digits as a *complete token*, with optional enclosing
brackets/quotes and trailing sentence punctuation. It splits tabs, newlines,
commas, semicolons and spaces; collapses leading-zero aliases and preserves
first-seen order. Standalone numbers, embedded punctuation and non-ASCII digits
are rejected. Grounding against this run's observed NCBI IDs remains mandatory.
Offline tests: `tests/pmc_id_parser_regression_tests.pl`.

**Per-paper evidence (F20).** Every normally published `metadata.json` now
contains `source_provenance` with the **raw-input-file SHA-256**, file byte count,
input filename, canonical PMC identity, processing timestamp, article reference
URL, and any JATS license evidence. `retrieval_timestamp` (ISO 8601 UTC, with
`retrieval_timestamp_unix`) is the raw file's modification time, and
`retrieval_timestamp_basis` is always `"raw_file_mtime"`. In an agent run the
file is re-downloaded each time, so this is when NCBI's response was written; for
a pre-existing local file passed to `process_paper/4` it is only when that file
was last written, not an observed NCBI request time. The license state
`requires_manual_review` is *not* an authorization to redistribute source
material. The raw input file is not automatically embedded in the paper
snapshot; retain `dataset/raw/` with a controlled storage policy for later
hash verification. Both strict and opt-in quarantine modes attach provenance
inside the staged paper snapshot before publication. Missing SHA-256 support is
fatal, not silently replaced with a weaker checksum.

**Run manifest (F20).** DML runs additionally write
`dataset/runs/run-<unique-id>/manifest.json`, containing the topic,
successful search query strings, authorized IDs, raw model selection, parsed
IDs, chosen IDs, rejected IDs and per-paper status lines. Individual local
`process_paper/4` calls have no upstream search query and create no run-level
manifest; only the source manifest embedded in `metadata.json` is available.
Run-manifest persistence failures are explicitly reported by the DML agent and
do not roll back papers that have already been published. If you require
end-to-end complete run manifests, treat the warning as an unsuccessful run.

**Semantic correctness (F02).** All candidates are **structural boundary
hypotheses**. Even a single valid boundary does not imply the data cells are
semantically correct. JSONL table records and paper metadata explicitly mark
`semantic_validation: "unverified"`; gold labels must come from independent
human annotation. Tables with HMD only are represented by `Vmd = 0`, and
plain grids with VMD only by `Hmd = 0`; a table with merged cells is always
read with HMD rows (constraint 9), and tables without any headers have no
admissible boundary.

To measure semantic usefulness, prepare a **human-labeled** JSONL file, one
record per source table, of the shape:

```json
{"pmc_id":"PMC123456", "table_index":0, "gold_boundary":{"hmd":1,"vmd":1}}
```

`hmd` and `vmd` are counts, as in `tables.jsonl`. For a table that genuinely
has no header segmentation at all, use
`"gold_boundary":null`. Then run:

```sh
python3 tools/evaluate_structural_candidates.py \
  --predictions dataset/papers/PMC123456/tables.jsonl \
  --gold path/to/independently_annotated_gold.jsonl \
  --output evaluation.json
```

Metrics include candidate-set recall, unique-hypothesis precision/coverage,
no-header false-positive rate and abstention/ambiguity rates, with explicit
denominators. **No human-labeled reference corpus was supplied, so no semantic
accuracy claim can yet be made.** The included evaluator tests use synthetic
examples, not gold data.

Security: `.gitignore` excludes `.deepclause/`, local datasets and `.env`
files. This guards accidental `git add .` but does not revoke previously
committed secrets or establish article redistribution rights.
