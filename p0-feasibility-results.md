# P0 Feasibility Results (aggregate only)

Source: `bigquery-public-data.gbif.occurrences` · Subset: `fiery-monitor-508317-a8.p0_scratch.mn_occurrences` (countrycode = US, lat/long box, clipped to the Minnesota boundary)

Run date: 2026-10-14 · Run by: Stephen

No source rows appear in this file — only schema facts, counts, ranges, rates, and interpretation.

## Q1 — Objects, schema, size, location

| Fact | Result |
|---|---|
| Objects in `gbif` dataset | `occurrences` (TABLE) |
| Column count / partitioning / clustering | 50 / none / none |
| Array or nested columns | `identifiedby`, `recordedby`, `typestatus`, `mediatype`, `issue` — each `STRUCT<array ARRAY<STRUCT<array_element STRING>>>` |
| Full-table rows | 3,729,438,201 |
| Full-table size (TB) | 1.83 |
| Last modified | 2026-10-02 00:01:42 UTC |
| Dataset location | US |

## Q2 — Subset build cost

| Fact | Result |
|---|---|
| First attempt (~25 columns, `stateprovince` filter) | Refused: "Quota exceeded: free query bytes scanned" (2026-10-14) |
| Redesigned 2b (`mn_box_occurrences`) validator estimate (GB) | 453.19 |
| Ran 2b or 2-ALT (10% sample)? | 2b (full scan) |
| Bytes billed (GB, job details) | 453.19 |
| Box rows → Minnesota rows after clip (2d) | 30,232,036 → 20,852,477 |

## Q3 — Scale, time, keys (MN subset)

| Fact | Result |
|---|---|
| Rows | 20,852,477 |
| Distinct / null `gbifid` | 20,852,477 / 0 |
| Year range / null year | 1800–2026 / 24,482 |

**Interpretation:** `gbifid` can serve as the primary key: it has no null values and every value is distinct. Records span 1800–2026; 24,482 rows (0.12%) have no year and will be excluded from time-based questions.

## Q4 — Records per year (summary)

| Period | Records | Distinct species | Datasets |
|---|---|---|---|
| 1990–1999 | 312,157 | 5,060 | 246 |
| 2000–2009 | 903,622 | 5,588 | 216 |
| 2010–2014 | 1,368,536 | 5,146 | 139 |
| 2015–latest | 17,796,741 | 12,006 | 172 |

**Interpretation:** Recording effort in Minnesota has increased dramatically: 2015–present accounts for about 87% of all records since 1990 (17.8M of 20.4M), roughly 1.5M records per year compared with about 31K per year in the 1990s. Over the same period the number of contributing datasets fell from 246 to 172, so recent growth is concentrated in a few large sources, likely citizen-science platforms. This gives good coverage for recent-period gap analysis (Q-A, Q-D), but raw trends mainly reflect observer effort, so Q-B should compare records by source type and should not be read as change in abundance.

## Q5 — Quality rates

| Measure | % |
|---|---|
| Null uncertainty | 94.25 |
| Uncertainty > 10 km | 0.55 |
| Not resolved to species | 1.94 |
| Null class | 0.20 |
| Null month | 1.43 |

## Q6 — Record types, licenses, contributor concentration

| basisofrecord | % of records |
|---|---|
| HUMAN_OBSERVATION | 95.11 |
| PRESERVED_SPECIMEN | 2.49 |
| other | 2.39 |

| # | Dataset key (prefix) | Dataset name | % of records | Records | License |
|---|---|---|---|---|---|
| 1 | 4fa7b334-ce0d-4e88-aaae-2e0c13… | EOD – eBird Observation Dataset | 88.41 | 18,436,199 | CC BY 4.0 |
| 2 | 50c9509d-22c7-4a22-a47d-8c4842… | iNaturalist Research-grade Observations | 5.09 | 1,060,557 | Mixed per record: CC0, CC BY, CC BY-NC |
| 3 | 52827ade-d745-4d26-b45f-669… | ____ | 1.67 | 348,711 | ____ |
| 4 | e0ae862b-d456-4cb2-900b-c492… | ____ | 0.90 | 187,007 | ____ |
| 5 | a36438d0-bec7-4b7b-9bfa-2c31e… | ____ | 0.89 | 186,407 | ____ |

Top-5 datasets' combined share: 96.96%

## Q7 — Animal classes in scope

| Class | Records | Distinct species | Years |
|---|---|---|---|
| Aves | 18,805,331 | 574 | 166 |
| Amphibia | 18,458 | 30 | 119 |
| Reptilia | 961 | 26 | 133 |

Note: GBIF files reptiles under class Reptilia (not Squamata/Testudines).

## Q8 — Grid feasibility (0.25°, animals, 2015+)

| Fact | Result |
|---|---|
| Occupied cells | 463 |
| Records per cell (quartiles) | 161,987 |
| Cells with < 10 records | 15 |

## Q9 — Seasonality

Peak months — Amphibia: July · Reptilia: June · Aves: May

Any month-1 spike suggesting defaulted dates? No — January holds 3.7% of Aves records, consistent with genuine winter observations.

**Interpretation:** Since 2015, recording peaks in late spring and summer: birds in May (spring migration), reptiles in June, and amphibians in July. This gives survey coordinators a clear May–July window for planning fieldwork (Q-D). January's 3.7% share of bird records is in line with real winter birding activity, such as Christmas Bird Counts, rather than defaulted dates.

## Overall interpretation

The Minnesota subset (20.9M records, unique non-null `gbifid`) supports the proposed product, with clear limits. Recent coverage is dense and spatially broad (463 occupied 0.25° cells since 2015, only 15 with fewer than 10 records), which supports mapping recording density and possible gaps (Q-A) and seasonal timing (Q-D). Three issues shape P1: records are dominated by one citizen-science source (eBird supplies 88%), so trends (Q-B, Q-C) reflect observer effort rather than abundance; amphibians (18,458 records) and especially reptiles (961) are sparse, so they need coarser grids or statewide summaries; and 94% of records lack a coordinate-uncertainty value, so location precision cannot be filtered on reliably and the grid must stay coarse.
