# P0 Feasibility — Minnesota Wildlife Survey Gap Finder

> Values marked **[Q#]** come from the numbered query in `sql/00_feasibility.sql`; the results are summarized in `evidence/p0-feasibility-results.md`.

## 1. Working title

**Minnesota Wildlife Survey Gap Finder** — where and when Minnesota's animal life has been recorded least.

**Scope of claims.** The product reports **recording density** (how many occurrence records exist for a place, time, and taxon) and flags **possible survey gaps** (cells with few or no records). Occurrence counts reflect where people looked and reported, so they cannot establish wildlife abundance, population change, or that a survey is needed. Whether a flagged gap warrants fieldwork remains the coordinator's judgment, informed by habitat and program priorities.

## 2. Audience and need

**Audience.** Survey coordinators in a state nongame wildlife program (for example, the Minnesota DNR Nongame Wildlife Program) who plan each season's field surveys for amphibians, reptiles, and birds with a small staff and volunteer pool.

**Decision / recurring task.** Each spring, the coordinator decides which parts of the state to send survey crews and volunteers to, which taxonomic groups to prioritize, and in which months to schedule visits. Field days are the scarce resource.

**Why a data product helps.** Today the evidence about *where records already exist* is scattered across museum collections, agency surveys, and citizen-science apps (iNaturalist, eBird). GBIF aggregates these into one occurrence table. A product that summarizes recording density over space, time, and taxa makes possible survey gaps — places, taxa, and times with few records — visible in minutes instead of being assembled by hand.

**What changes if it works.** The coordinator has a shortlist of low-recording cells and taxa to weigh against habitat knowledge and program priorities when assigning crew-days, rather than defaulting to well-recorded areas (metro, popular parks), and schedules visits in the months each group is most often recorded.

## 3. Proposed analytical product and questions

**Artifact.** An interactive dashboard (Looker Studio on BigQuery) with a statewide grid map of recording density, a year-trend panel, and a month-by-taxon seasonality panel, filterable by taxonomic class and period.

**Questions**

1. **Q-A Possible gaps:** For a chosen taxonomic class and period (e.g., amphibians, 2015–present), which 0.25° grid cells in Minnesota have few or no records?
2. **Q-B Trend:** How have the number of records and the number of distinct species recorded per year changed since 2000 for each target class, and how much of that change comes from citizen-science sources versus specimens and formal surveys?
3. **Q-C Lapsed areas:** Which grid cells had records of a target class before 2010 but few or none since 2015 (a possible lapse in recording; the data cannot distinguish reduced survey effort from a real change in the animals)?
4. **Q-D Timing:** In which months is each target class most often recorded, to guide when surveys are scheduled?

## 4. Source identification and access

| Item | Value |
|---|---|
| Dataset / provider | GBIF occurrence records (Global Biodiversity Information Facility), offered as a Google Cloud / BigQuery public dataset |
| Documentation | https://www.gbif.org/occurrence/search · BigQuery public datasets: https://cloud.google.com/bigquery/public-data |
| BigQuery identifiers | Project `bigquery-public-data`, dataset `gbif` |
| Candidate object | `occurrences` (TABLE) — the only object in the dataset **[Q1a]** |
| Location / region | US multi-region, from the dataset Details pane **[Q1d]** (region-level INFORMATION_SCHEMA is not accessible to outside users) |
| Access confirmed | Metadata queries **[Q1a–1c]** ran from the course project `fiery-monitor-508317-a8` on 2026-10-14. Working subset written to `fiery-monitor-508317-a8.p0_scratch.mn_occurrences`; the first subset attempt was refused by the free-tier scan quota and redesigned (see Risk 1). |
| Use / attribution | Each record carries its own license (CC0, CC BY, or CC BY-NC). The largest source, the eBird Observation Dataset (88% of Minnesota records), is CC BY 4.0; iNaturalist Research-grade Observations (5%) mixes CC0, CC BY, and CC BY-NC **[Q6]**. The product shows aggregates only, credits GBIF and contributing datasets, and is non-commercial coursework, so CC BY-NC records are usable. |

## 5. Quick source profile

| Item | Finding |
|---|---|
| Meaning of one row | One occurrence: a record that a taxon was observed or collected at a place and time (a specimen, a human observation, a machine observation, etc.), as published by one source dataset. |
| Row count | Full table: 3,729,438,201 rows, 1.83 TB **[Q1c]**. Minnesota subset: 20,852,477 rows **[Q3]**. |
| Time coverage | Minnesota subset spans 1800–2026 **[Q3]**; coverage becomes dense from 2015, which holds about 87% of records since 1990 **[Q4]**. |
| Keys | `gbifid` — GBIF's record key; unique and never null (20,852,477 distinct of 20,852,477 rows, 0 null) **[Q3]**. `specieskey` — species identifier; `datasetkey` — source dataset. The publisher's `occurrenceid` was left out of the subset to save scan cost. |
| Fields for questions | Space: `decimallatitude`, `decimallongitude`, `coordinateuncertaintyinmeters`. Time: `year`, `month`. Taxon: `kingdom`, `class`, `specieskey`. Source type: `basisofrecord`, `datasetkey`. |
| Nulls / quality | Null uncertainty 94.25%; uncertainty > 10 km 0.55%; not resolved to species 1.94%; null class 0.20%; null month 1.43%; null year 0.12% (24,482 rows) **[Q3, Q5]**. Box rows 30,232,036 → Minnesota rows 20,852,477 after boundary clip **[Q2d]**. Records with no coordinates are excluded by design and not yet counted. |
| Semi-structured | Five nested array columns (`identifiedby`, `recordedby`, `typestatus`, `mediatype`, `issue`, each `STRUCT<array ARRAY<…>>`) — excluded from the subset to limit scan cost **[Q1b]**. |
| Refresh | GBIF re-indexes continuously; the BigQuery copy is a periodic snapshot, last modified 2026-10-02 **[Q1c]**. Treated as static for the course. |
| Sensitivity / interpretation | (1) Records measure **observation effort, not abundance**; dense cells often mean more observers. (2) Locations of sensitive species may be generalized or withheld by publishers. (3) A few large citizen-science datasets dominate: the top 5 supply 96.96% of records and eBird alone 88.41% **[Q6]**. Reptiles are filed under class Reptilia **[Q7]**. Product will not publish precise points for any species, only gridded counts. |

## 6. Need-to-source fit

| Proposed question | Needed fields or concepts | Candidate source object(s) | Why the source appears sufficient | Gap or assumption to test in P1 |
|---|---|---|---|---|
| Q-A Possible gaps | lat/long, coordinate precision, class, year | `occurrences` → MN subset | Point coordinates allow any grid; 463 occupied 0.25° cells since 2015, only 15 with < 10 records **[Q8]** | Cell size per class; 94% of records lack an uncertainty value, so precision cannot be filtered reliably; "few records" threshold |
| Q-B Trend | year, specieskey, class, basisofrecord, datasetkey | same | Year field covers decades with 0.12% null **[Q3, Q4]**; basisofrecord separates human observation (95%) from specimens (2.5%) **[Q6]** | Citizen-science growth swamps the trend (eBird 88%); normalize by contributing datasets or source type |
| Q-C Lapsed areas | grid cell, class, year (two periods) | same | Same fields as Q-A, compared across periods | Enough pre-2010 records per cell to call an area "lapsed" rather than never-recorded, especially for amphibians (18,458 records) and reptiles (961) **[Q7]** |
| Q-D Timing | month, class | same | Month field 1.43% null **[Q5]**; clear peaks: birds May, reptiles June, amphibians July **[Q9]** | January holds 3.7% of bird records, consistent with real winter birding; confirm January shares for amphibians and reptiles are near zero |

## 7. Feasibility risks and response

**Risk 1 — Query cost on a very large table (already observed).** *Evidence:* the full table is 1.83 TB / 3.73 billion rows **[Q1c]**. My first subset query, which read about 25 columns and filtered on the `stateprovince` text field, was refused with "Quota exceeded: free query bytes scanned." The redesigned query reads 11 mostly numeric columns and filters on country code plus a lat/long box; it processed 453.19 GB, within the free 1 TB monthly allowance **[Q2]**. *Response:* all later work runs on the 20.9M-row Minnesota subset, which costs little to query; set a per-query byte cap in BigQuery settings and avoid re-scanning the source. Any future change case will need the same narrow-scan approach.

**Risk 2 — Records reflect observer effort, not wildlife.** *Evidence:* eBird supplies 88.41% of records and the top 5 datasets 96.96% **[Q6]**; 95% of records are human observations; records per year rose from about 31K in the 1990s to about 1.5M since 2015 **[Q4]**. *Response:* frame every metric as "recording density," never as abundance; break out counts by `basisofrecord` and dataset; label this clearly in the dashboard.

**Risk 3 — Coordinate quality and generalized locations.** *Evidence:* 94.25% of records have no coordinate-uncertainty value, and only 0.55% are known to exceed 10 km **[Q5]**; the boundary clip removed 9.4M records from neighboring states **[Q2d]**. *Response:* because uncertainty is mostly missing, a precision filter would remove almost nothing useful; instead keep the grid coarse (0.25°, ~28 km), drop only records known to exceed 10 km, and state in the dashboard that point precision is largely undocumented.

**Fallback.** Birds have the density for fine-grained grid analysis, but amphibians (18,458 records) and reptiles (961) are sparse **[Q7]**. If their gridded gaps prove too noisy, answer Q-A for birds at 0.25° and for amphibians and reptiles at a coarser grid or by region, with Q-B and Q-D at statewide level; the same source and subset still support that product.

## 8. First P1 decision

**Fact grain and spatial unit.** `gbifid` is confirmed unique and non-null **[Q3]**, so a per-record fact table is possible. The decision is whether the model keeps one row per occurrence with a derived grid-cell key, or pre-aggregates to cell × class × year × month for dashboard speed. This also requires deciding how to treat the 94% of records with no coordinate-uncertainty value when assigning grid cells.
