# Dataset Builder Agent

Turns a search phrase into a set of scientific tables whose cells are labelled as
horizontal metadata (HMD), vertical metadata (VMD) or data.

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
- The Prolog code uses only libraries bundled with SWI-Prolog (`sgml`,
  `sgml_write`, `json`, `assoc`, `apply`, `lists`, `readutil`, `filesex`). No
  packs are needed.
- No NCBI API key is needed. The agent stays under NCBI's keyless limit of 3
  requests per second.

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
agent was developed against.

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

Each run writes a `dataset/` directory inside `src/`:

| Path | Contents |
|---|---|
| `dataset/papers/PMC<id>/annotated_tableN.html` | One file per table. The table is repeated once for each valid header boundary, colored green (HMD), blue (VMD) and gray (data). A table with no valid boundary is saved uncolored. |
| `dataset/papers/PMC<id>/metadata.json` | Paper identity, original title, and counts of tables and validly partitioned tables. |
| `dataset/raw/PMC<id>.xml` | Full text of each paper as downloaded. |
| `dataset/cache/` | The last PubMed Central search responses. |

`dataset/` is retained between runs. Paper outputs are keyed by **canonical PMC ID**
(rather than article title), so papers with equal or truncated titles cannot
overwrite one another. Reprocessing an ID replaces its entire published paper
directory: old `annotated_tableN.html` files from larger previous runs do not
survive. The article title is available in `metadata.json` instead of the path.

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

**Migration:** directories produced by older versions at
`dataset/<sanitized article title>/` are left untouched to avoid accidental
delete/misattribution of files already affected by title collisions. Review
and archive or remove those legacy directories manually; new output is under
`dataset/papers/`.

### Settings

| Setting | Where | Default |
|---|---|---|
| Papers per run | `max_papers/1` in `dataset_builder.dml` | 20 |
| Delay between NCBI requests (s) | `ncbi_request_gap/1` in `dataset_builder.dml` | 0.4 |
| Waits before retrying a rate-limited request (s) | `ncbi_retry_waits/1` in `dataset_builder.dml` | 2, 5, 10, 20, 30 |
| Model | `deepclause set-model`, or `--model` for one run | chosen in step 5 |

## Running the table logic without the agent

These need SWI-Prolog (step 6) but no API key, no DeepClause and no network.
Run them from `src/`.

Annotate the tables of any HTML or XML file. This writes `table0.pl`,
`table1.pl`, ... next to the input file:

```bash
swipl -g 'consult(test_driver),
          test_table_parser("path/to/file.html", Files),
          writeln(Files)' -t halt
```

Process a paper the agent has already downloaded, exactly as the agent does.
Replace `7285984` with the id of a file in `dataset/raw/`:

```bash
swipl -g 'use_module(dataset_pipeline),
          process_paper("7285984", "dataset/raw/PMC7285984.xml", "dataset", Summary),
          writeln(Summary)' -t halt
```

### Boundary contract and regression tests

The table validator now returns boundaries only for rectangular rasters with at
least two rows and two columns. A boundary `(Hmd, Vmd)` must leave at least
one horizontal-metadata row, one vertical-metadata column **below** the
horizontal header, and a nonempty data region:

```text
0 <= Hmd < number_of_rows - 1
0 <= Vmd < number_of_columns - 1
```

Tables without such a partition are saved uncolored (the existing abstention
behavior). Both forms of `omni_validate` enforce the same domain. The
four-argument form reports `some(invalid_boundary)` for out-of-domain
coordinates or malformed/undersized rasters; structural failures continue
to report `some(0)` through `some(6)`.

Run the offline boundary regressions from `dataset-builder-agent/src`:

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
| `src/dataset_builder.dml` | The agent: paper selection (model), NCBI search and download, and the per-paper loop. |
| `src/dataset_pipeline.pl` | Prolog module the agent loads. Connects the three files below and writes the output. |
| `src/table_layout_generator.pl` | Parses HTML and turns each `<table>` into a raster of cell ids. |
| `src/parse_constraints.pl` | The seven parse constraints and the search for valid HMD/VMD boundaries. |
| `src/table_annotator.pl` | Colors a table's cells for a given boundary. |
| `src/boundary_regression_tests.pl` | Offline regression tests for boundary domain and structural validation. |
| `src/paper_output_regression_tests.pl` | Offline regression tests for stable PMC output identity, replacement, and failure rollback. |
| `src/test_driver.pl` | Runs the table logic on a local file, without the agent. |

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

Run the standalone offline regression suite from `dataset-builder-agent/src`:

```bash
swipl -q -s raster_limits_regression_tests.pl -g run_tests -t halt
```
