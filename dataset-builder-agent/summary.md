# Dataset Builder Agent

The dataset builder turns a search phrase into a set of scientific tables whose cells are labelled as **horizontal metadata (HMD)**, **vertical metadata (VMD)** or **data**. It is a DeepClause (DML) agent: a Prolog program in which a language model performs one narrow step and logic performs the rest.

## What it does

Given a phrase such as `"dementia with lewy bodies"`, the agent:

1. **Selects papers.** Claude searches PubMed Central through one tool, `search_pmc`, and picks up to 20 open-access papers. It sees only short result lines (id, date, journal, title).
2. **Downloads the full text** of each paper as XML from NCBI's public API, pausing and retrying when NCBI's rate limit is reached.
3. **Extracts every `<table>` element** and lays it out as a *raster*: a grid in which each slot holds the id of the cell covering it, so merged cells span several slots (`table_layout_generator.pl`).
4. **Finds the header boundaries.** Every candidate pair (HMD boundary row, VMD boundary column) is tested against the seven parse constraints; the pairs that satisfy all of them are kept (`parse_constraints.pl`).
5. **Annotates the table.** For each valid pair the original table is colored: HMD cells green, VMD cells blue, data cells gray (`table_annotator.pl`).
6. **Saves the result** as `dataset/papers/PMC<id>/annotated_tableN.html`, with `metadata.json` for the article title and table counts. Outputs are staged and replaced per PMC ID to avoid title collisions and stale tables.

Steps 2–6 run inside DeepClause's own Prolog engine and never involve the model.

## Workflow

```mermaid
flowchart TD
    A([Search phrase]) --> B["Select papers<br/><b>LLM</b> + search_pmc tool"]
    B -->|PMC ids| C["Download full text<br/>NCBI E-utilities, rate-limited"]
    C --> D["Extract &lt;table&gt; elements"]
    D --> E["Rasterize<br/>table_layout_generator.pl"]
    E --> F{"Parse constraints<br/>parse_constraints.pl<br/>any valid HMD/VMD boundary?"}
    F -->|yes| G["Color cells HMD / VMD / data<br/>table_annotator.pl"]
    F -->|no| H["Save table uncolored"]
    G --> I[("dataset/papers/PMC&lt;id&gt;/<br/>annotated_tableN.html")]
    H --> I

    classDef llm fill:#ffe9a8,stroke:#b8860b,color:#000
    classDef logic fill:#dbeafe,stroke:#1d4ed8,color:#000
    class B llm
    class C,D,E,F,G,H logic
```

Yellow is the only step that uses the language model; blue steps are deterministic Prolog.

## Advantages of the parse constraints in this workflow

- **No model cost for the hard part.** Deciding where a table's headers end is done by logic, so the model never reads a table. A 20-paper run that produced 38 tables used about 16,600 tokens (roughly $0.06), all of it spent choosing papers.
- **Deterministic and repeatable.** The same table always yields the same boundaries. Labels do not drift between runs, which matters when the output is training or evaluation data.
- **It declines rather than guesses.** A table with no boundary satisfying all seven constraints is saved uncolored instead of being given a plausible-looking but unsupported labelling. In the 20-paper run this happened for 1 of 38 tables.
- **Every decision is explainable.** A rejected boundary can be traced to the first constraint it violates (`omni_validate/4`), so a wrong or missing annotation can be diagnosed rather than merely observed.
- **Content-independent.** The constraints look only at the table's structure (which slots belong to the same merged cell), not at its text. They apply unchanged across subjects, languages and vocabularies.
- **Merged cells are evidence, not noise.** Row and column spans, which make tables hard for text-based methods, are exactly what the constraints reason about.
- **Exhaustive search is cheap.** Because a check is a few list lookups, every candidate boundary of every table is tested; a whole paper takes a fraction of a second.
- **Ambiguity is preserved.** When more than one boundary pair is valid, all are reported, leaving the choice to a later stage instead of hiding it.

## Limits observed

Tables published as images cannot be extracted, and the agent only reaches papers whose full text NCBI makes available as XML.
