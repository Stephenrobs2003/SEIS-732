# P0 Feasibility — Minnesota Wildlife Survey Gap Finder

> Values marked **[Q#]** come from the numbered query in `sql/00_feasibility.sql`; the results are summarized in `evidence/p0-feasibility-results.md`.

## 1. Working title

**Minnesota Wildlife Survey Gap Finder** — where and when Minnesota's animal life is under-recorded.

## 2. Audience and need

**Audience.** Survey coordinators in a state nongame wildlife program (for example, the Minnesota DNR Nongame Wildlife Program) who plan each season's field surveys for amphibians, reptiles, and birds with a small staff and volunteer pool.

**Decision / recurring task.** Each spring, the coordinator decides which parts of the state to send survey crews and volunteers to, which taxonomic groups to prioritize, and in which months to schedule visits. Field days are the scarce resource.

**Why a data product helps.** Today the evidence about *where records already exist* is scattered across museum collections, agency surveys, and citizen-science apps (iNaturalist, eBird). GBIF aggregates these into one occurrence table. A product that summarizes recording density over space, time, and taxa makes survey gaps visible in minutes instead of being assembled by hand.

**What changes if it works.** The coordinator shifts crew-days from well-recorded areas (metro, popular parks) toward under-recorded grid cells, targets taxa whose records have thinned recently, and schedules visits in the months each group is most detectable.

## 3. Proposed analytical product and questions

**Artifact.** An interactive dashboard (Looker Studio on BigQuery) with a statewide grid map of recording density, a year-trend panel, and a month-by-taxon seasonality panel, filterable by taxonomic class and period.

**Questions**

1. **Q-A Gaps:** For a chosen taxonomic class and period (e.g., amphibians, 2015–present), which 0.25° grid cells in Minnesota have few or no records?
2. **Q-B Trend:** How have the number of records and the number of distinct species recorded per year changed since 2000 for each target class, and how much of that change comes from citizen-science sources versus specimens and formal surveys?
3. **Q-C Lapsed areas:** Which grid cells had records of a target class before 2010 but few or none since 2015 (possible decline *or* lapsed survey effort)?
4. **Q-D Timing:** In which months is each target class most often recorded, to guide when surveys are scheduled?

## 4. Source identification and access

| Item | Value |
|---|---|
| Dataset / provider | GBIF occurrence records (Global Biodiversity Information Facility), offered as a Google Cloud / BigQuery public dataset |
| Documentation | https://www.gbif.org/occurrence/search · BigQuery public datasets: https://cloud.google.com/bigquery/public-data |
| BigQuery identifiers | Project `bigquery-public-data`, dataset `gbif` |
| Candidate object | `occurrences` (table) **[Q1a]** |
| Location / region | ____ — from the dataset Details pane / `bq show` **[Q1d]** (region-level INFORMATION_SCHEMA is not accessible to outside users) |
| Access confirmed | Metadata query **[Q1a–1c]** ran from the course project on ____ (date). Working subset written to `<my_project>.p0_scratch.mn_occurrences`. |
| Use / attribution | Each record carries its own `license` (GBIF publishes under CC0, CC BY, or CC BY-NC). The product will show aggregates only, credit GBIF and contributing datasets, and is non-commercial coursework, so CC BY-NC records are usable. Distribution by license recorded **[Q6]**. |

## 5. Quick source profile

| Item | Finding |
|---|---|
| Meaning of one row | One occurrence: a record that a taxon was observed or collected at a place and time (a specimen, a human observation, a machine observation, etc.), as published by one source dataset. |
| Row count | Full table: ____ **[Q1c]**. Minnesota subset: ____ **[Q3]**. |
| Time coverage | Minnesota subset spans ____ to ____ **[Q3]**; dense coverage begins around ____ **[Q4]**. |
| Keys | `gbifid` — GBIF's record key; expected unique and non-null (null ____, distinct = rows? ____ **[Q3]**). `occurrenceid` — the publisher's ID; can be null or repeat across datasets (____ repeats **[Q3b]**). `specieskey`/`taxonkey` — taxon identifiers; `datasetkey` — source dataset. |
| Fields for questions | Space: `decimallatitude`, `decimallongitude`, `coordinateuncertaintyinmeters`. Time: `year`, `month`, `eventdate`. Taxon: `kingdom` → `species`, `specieskey`. Source type: `basisofrecord`, `datasetkey`. |
| Nulls / quality | No coordinates ____ %; uncertainty > 10 km ____ %; not resolved to species ____ %; null month ____ %; points outside MN box ____ **[Q5, Q5b]**. |
| Semi-structured | Full table has array columns (e.g., `issue`, `mediatype`) — excluded from the subset to limit scan cost **[Q1b]**. |
| Refresh | GBIF re-indexes continuously; the BigQuery copy is a periodic snapshot. Last modified ____ **[Q1c]**. Treated as static for the course. |
| Sensitivity / interpretation | (1) Records measure **observation effort, not abundance**; dense cells often mean more observers. (2) Locations of sensitive species may be generalized or withheld by publishers. (3) A few large citizen-science datasets dominate (top-5 share ____ % **[Q6]**). Product will not publish precise points for any species, only gridded counts. |

## 6. Need-to-source fit

| Proposed question | Needed fields or concepts | Candidate source object(s) | Why the source appears sufficient | Gap or assumption to test in P1 |
|---|---|---|---|---|
| Q-A Gaps | lat/long, coordinate precision, class, year | `occurrences` → MN subset | Point coordinates allow any grid; class is populated on resolved records; ____ occupied cells **[Q8]** | Choose cell size; how to treat records with large or missing uncertainty; "few records" threshold |
| Q-B Trend | year, specieskey, class, basisofrecord, datasetkey | same | Year field covers decades **[Q4]**; basisofrecord separates human observation from specimens **[Q6]** | Whether citizen-science growth swamps the trend; normalize by contributing datasets? |
| Q-C Lapsed areas | grid cell, class, year (two periods) | same | Same fields as Q-A, compared across periods | Enough pre-2010 records per cell to call an area "lapsed" rather than never-recorded |
| Q-D Timing | month, class | same | Month field low-null **[Q5]**; seasonal pattern visible **[Q9]** | Whether month reflects observation date or is defaulted (e.g., month = 1 spikes from date imprecision) |

## 7. Feasibility risks and response

**Risk 1 — Query cost on a very large table.** *Evidence:* full table is ____ TB / ____ rows **[Q1c]**; the subset build was estimated at ____ GB in the validator **[Q2]**. *Response:* scan the source once with only needed columns, then work from the small Minnesota subset; set a per-query byte cap in the BigQuery settings.

**Risk 2 — Records reflect observer effort, not wildlife.** *Evidence:* top contributing datasets supply ____ % of records **[Q6]**; records/year rise sharply after ____ **[Q4]**. *Response:* frame every metric as "recording density," never as abundance; break out counts by `basisofrecord`/dataset; label this clearly in the dashboard.

**Risk 3 — Coordinate quality and generalized locations.** *Evidence:* ____ % missing coordinates, ____ % with uncertainty > 10 km, ____ points outside the state box **[Q5, Q5b]**. *Response:* use a coarse grid (0.25°) and filter by uncertainty; report how many records each filter drops.

**Fallback.** If gridded gaps prove too noisy, narrow to one class (amphibians) and answer Q-B and Q-D at statewide level with Q-A at a coarser grid; the same source and subset still support that product.

## 8. First P1 decision

**Fact grain and spatial unit.** Decide whether the model's fact table stays at one row per occurrence (`gbifid`) with a derived grid-cell key, or is pre-aggregated to cell × class × year × month. This depends on the coordinate-uncertainty distribution and on whether `gbifid` is confirmed unique **[Q3]**.
