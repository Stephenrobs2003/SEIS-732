# Minnesota Wildlife Survey Gap Finder

An individual data-product project (P0–P4) built in BigQuery on the GBIF species occurrence public dataset.

**Current purpose (P0):** test whether GBIF occurrence records can support a data product that helps Minnesota nongame wildlife survey coordinators decide **where and when to send limited field-survey effort**, by showing recording density: which parts of the state and which taxa have few occurrence records (possible survey gaps), how recording has changed over time, and when in the year each group is typically recorded.

**Scope of claims:** the product reports recording density and flags possible survey gaps. Occurrence counts reflect where and when people recorded wildlife; they do not measure wildlife abundance and do not by themselves establish where surveys are needed.

## P0 files

| File | What it holds |
|---|---|
| [p0-feasibility.md](p0-feasibility.md) | Audience, questions, source, fit, risks, first P1 decision |
| [00_feasibility.sql](00_feasibility.sql) | Reproducible schema and aggregate profiling queries |
| [p0-feasibility-results.md](p0-feasibility-results.md) | Summarized results (counts, ranges, rates) — no source rows |

## P1 files

| File | What it holds |
|---|---|
| [docs/p1-plan.md](docs/p1-plan.md) | Question, grain test, dimensional model and diagram, history decision, layer plan, checks, change memo |
| [sql/01_source_profile.sql](sql/01_source_profile.sql) | Reproducible grain and key-coverage checks on the Minnesota extract |

## Source

`bigquery-public-data.gbif.occurrences` — Global Biodiversity Information Facility (GBIF) occurrence records, published as a BigQuery public dataset. Project scope: US records inside a lat/long box around Minnesota, clipped to the state boundary (see `00_feasibility.sql`, Step 2).

## Repository rules

- No source-data rows, extracts, or downloads are committed.
- No credentials, service-account keys, or `.env` files are committed (see `.gitignore`).
- Evidence is aggregate only.
- The Minnesota working subset lives in BigQuery in my own project, never in Git.
