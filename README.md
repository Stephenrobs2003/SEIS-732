# Minnesota Wildlife Survey Gap Finder

An individual data-product project (P0–P4) built in BigQuery on the GBIF species occurrence public dataset.

**Current purpose (P0):** test whether GBIF occurrence records can support a data product that helps Minnesota nongame wildlife survey coordinators decide **where and when to send limited field-survey effort**, by showing which parts of the state and which taxa are under-recorded, how recording has changed over time, and when in the year each group is typically observed.

## P0 files

| File | What it holds |
|---|---|
| [docs/p0-feasibility.md](docs/p0-feasibility.md) | Audience, questions, source, fit, risks, first P1 decision |
| [sql/00_feasibility.sql](sql/00_feasibility.sql) | Reproducible schema and aggregate profiling queries |
| [evidence/p0-feasibility-results.md](evidence/p0-feasibility-results.md) | Summarized results (counts, ranges, rates) — no source rows |

## Source

`bigquery-public-data.gbif.occurrences` — Global Biodiversity Information Facility (GBIF) occurrence records, published as a BigQuery public dataset. Project scope: records with `countrycode = 'US'` and `stateprovince = 'Minnesota'`.

## Repository rules

- No source-data rows, extracts, or downloads are committed.
- No credentials, service-account keys, or `.env` files are committed (see `.gitignore`).
- Evidence is aggregate only.
- The Minnesota working subset lives in BigQuery in my own project, never in Git.
