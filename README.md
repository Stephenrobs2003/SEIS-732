# Minnesota Wildlife Survey Gap Finder

An individual data-product project (P0–P4) built in BigQuery on the GBIF species occurrence public dataset.

**Purpose:** help Minnesota nongame wildlife survey coordinators decide **where and when to send limited field-survey effort**, by showing recording density: which 0.25° grid cells have few or no occurrence records for a chosen animal class and period (possible survey gaps), and in which months each class is typically recorded.

**Current phase (P3):** a working source → Raw → Curated → Serving build in BigQuery, with acceptance checks, an independent check of a Serving number, a same-input rerun and a traced change test. See [docs/p2-build.md](docs/p2-build.md) (one build note for P2 and P3).

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

## P2 files

| File | What it holds |
|---|---|
| [docs/p2-build.md](docs/p2-build.md) | Build note: input, Curated grain and rules, acceptance-check results, field trace, run order, next step |
| [sql/02_ingest.sql](sql/02_ingest.sql) | Source → Raw: full GBIF scan, Minnesota clip, load log |
| [sql/03_curate.sql](sql/03_curate.sql) | Raw → Curated: grid, taxon, month and dataset dimensions; occurrence fact view |
| [sql/04_acceptance.sql](sql/04_acceptance.sql) | Acceptance checks: grain and joins, edge cells, cross-dataset double counting |

## P3 files

| File | What it holds |
|---|---|
| [docs/p2-build.md](docs/p2-build.md#p3-serving-number-check-rerun-and-change) | P3 section of the build note: Serving output, number check, rerun and change results |
| [sql/05_serve.sql](sql/05_serve.sql) | Curated → Serving: `srv.cell_class_period_density` (cell × class × period, density, possible-gap flag) |
| [sql/06_serving_check.sql](sql/06_serving_check.sql) | Independent check of a Serving number, recomputed from Raw |
| [sql/07_rerun_and_change.sql](sql/07_rerun_and_change.sql) | Serving baseline, same-input comparison, test copy, `UPDATE` change and restore |
| [sql/03_curate.sql](sql/03_curate.sql) | Updated in P3: input switch view `cur.src_occurrences` (C00) |

## Source

`bigquery-public-data.gbif.occurrences` — Global Biodiversity Information Facility (GBIF) occurrence records, published as a BigQuery public dataset. Project scope: US records inside a lat/long box around Minnesota, clipped to the state boundary (see `sql/02_ingest.sql`). P2 build snapshot: 2026-11-02.

## Repository rules

- No source-data rows, extracts, or downloads are committed.
- No credentials, service-account keys, or `.env` files are committed (see `.gitignore`).
- Evidence is aggregate only.
- The Minnesota working tables live in BigQuery in my own project (`fiery-monitor-508317-a8`, datasets `raw` and `cur`), never in Git.
