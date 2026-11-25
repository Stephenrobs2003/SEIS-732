# P2–P3 Build — Minnesota Wildlife Survey Gap Finder

> Code: [`sql/02_ingest.sql`](../sql/02_ingest.sql) (source → Raw) · [`sql/03_curate.sql`](../sql/03_curate.sql) (Raw → Curated) · [`sql/04_acceptance.sql`](../sql/04_acceptance.sql) (checks) · [`sql/05_serve.sql`](../sql/05_serve.sql) (Curated → Serving, P3) · [`sql/06_serving_check.sql`](../sql/06_serving_check.sql) (Serving number check, P3) · [`sql/07_rerun_and_change.sql`](../sql/07_rerun_and_change.sql) (rerun and change test, P3). Plan: [`docs/p1-plan.md`](p1-plan.md).
> Sections 1–4 are the P2 build; the [P3 section](#p3-serving-number-check-rerun-and-change) at the end adds Serving and the rerun and change evidence.
> Statement labels (R2, C5, A1, …) refer to the comment headings inside those files. All results below were observed on 2026-11-16.

## 1. Establish the input and run ingestion

**Audience and question (carried forward).** Survey coordinators in a state nongame wildlife program. Primary question: for a chosen animal class and period, which 0.25° grid cells in Minnesota have few or no occurrence records? Results describe recording density and possible survey gaps, not abundance.

**What this P2 path builds.** The source → Raw → Curated path for that question: the full Minnesota occurrence extract (Raw), and the Curated fact and dimensions the gap map needs: every in-state grid cell, taxon, month, and dataset. The Serving table and map are P3.

**Changes from P1.**

| Change | Reason |
|---|---|
| Raw is rebuilt from the **full** source, not the P0 working table | P1 found the working table was an ~8.4% sample. On the full data only **85** cells have no amphibian records since 2015; the sample showed **263**. The sample would have tripled the apparent gaps. |
| Newer source snapshot (2026-11-02, not 2026-10-02) | GBIF refreshed the public table. Minnesota rows rose from 20,852,477 (P0) to 22,425,432. Grain and rules are unchanged. |
| A missing **month** no longer sends a record to the "unknown" date member | A record with a year still belongs to its period, which is all the primary question needs. Only a missing **year** gives key 0. |
| The fact is a **view**; dimensions are small tables | The BigQuery sandbox has a 10 GiB storage limit; a second full-size copy of the occurrences is not needed. |

**Build location.**

| Item | Value |
|---|---|
| Google Cloud project | `fiery-monitor-508317-a8` (BigQuery sandbox, no billing) |
| Datasets | `raw`, `cur` |
| Processing location | US (same as the source) |

**Source objects.**

| Source | Identifier | Used for |
|---|---|---|
| GBIF occurrences | `bigquery-public-data.gbif.occurrences` (snapshot last modified **2026-11-02 00:01:35 UTC**) | All occurrence rows |
| US state boundaries | `bigquery-public-data.geo_us_boundaries.states` (`state_name = 'Minnesota'`) | Clipping to Minnesota; grid cells |

**How source → Raw works** ([`02_ingest.sql`](../sql/02_ingest.sql)).

1. **R0b** records the source snapshot (metadata only).
2. **R1** copies the Minnesota polygon to `raw.mn_boundary`.
3. **R2** makes **one** scan of the full GBIF table (no sample), reading 12 columns and keeping US records inside a latitude/longitude box around Minnesota → `raw.gbif_mn_box`. It adds `_loaded_at` and `_source_last_modified`. This is the only expensive step (~450 GB processed).
4. **R3** keeps only box rows whose point lies inside the Minnesota polygon → `raw.gbif_mn_occurrences`. Values are copied **unchanged**; only out-of-state rows are removed.
5. **R4** writes a one-row `raw.load_log`; **R5** verifies the result.

**What Raw preserves.** The source's own values for the 11 fields the model needs (`gbifid`, `datasetkey`, `basisofrecord`, `kingdom`, `class`, `specieskey`, coordinates, coordinate uncertainty, `year`, `month`), unchanged, plus load metadata. No cleaning happens in Raw.

**Raw result (R5).**

| Item | Value |
|---|---|
| Box rows (R2) | 32,305,853 |
| Raw rows (R3) | **22,425,432** |
| One Raw row represents | One GBIF occurrence record whose point lies in Minnesota |
| Distinct / null `gbifid` | 22,425,432 / 0 |
| Year range | 1800–2026 |
| Source snapshot / load time | 2026-11-02 00:01:35 UTC / 2026-11-16 14:56:50 UTC |

**Reproducibility limit.** GBIF replaces the public table on a monthly refresh and BigQuery keeps no older version, so rerunning R2 after the next refresh returns a different input. Comparison is possible through the recorded snapshot timestamp and the counts above, but the exact rows cannot be re-fetched later. Sandbox tables also expire after 60 days, so `raw` must be rebuilt for later phases if it lapses.

## 2. Build Curated at the intended grain

Code: [`03_curate.sql`](../sql/03_curate.sql).

**Grain.** One row of `cur.fct_occurrence` represents **one GBIF occurrence record located in Minnesota**, distinguished by `gbifid`.

| Object | Type | One row represents | Key | Rows |
|---|---|---|---|---|
| `cur.fct_occurrence` (C5) | View | One occurrence record | `gbifid` | 22,301,511 |
| `cur.dim_grid_cell` (C1) | Table | One 0.25° cell with area inside Minnesota | `cell_key` | 482 (125 edge cells) |
| `cur.dim_taxon` (C2) | Table | One species, class-only member, or `UNKNOWN` | `taxon_key` | 21,670 |
| `cur.dim_month` (C3) | Table | One year-month (month 0 = unknown month; key 0 = unknown year) | `event_month_key` | 2,048 |
| `cur.dim_dataset` (C4) | Table | One publishing dataset | `dataset_key` | 755 |

**Rules and why they fit the question.**

| Field or issue | Rule | Why |
|---|---|---|
| Grid cells | Built from the boundary, not from records; cells with zero in-state area dropped | Zero-record cells are the strongest "possible gap" answer and never appear in the occurrence data |
| Coordinates | Converted to `cell_key = FLOOR(lat/0.25) _ FLOOR(lon/0.25)`; coordinates not carried forward | The question is cell-level; dropping points also protects sensitive species locations |
| Coordinate uncertainty > 10 km | Excluded (123,921 rows, 0.55%) | Too coarse to place in a ~28 km cell |
| Uncertainty missing | Kept | 94% of records state no uncertainty; excluding them would remove most of the data |
| Missing species key | `taxon_key = 'CLASS:<class>'`; both missing → `'UNKNOWN'` | The record still counts for its class |
| Species key format | Used as is (no legacy-key mapping) | Check C0 below |
| Missing month | Year kept, month part 0 | Still counts toward its period |
| Repeated rows | None found (`gbifid` unique in Raw) | No selection rule needed |
| Types | Source types retained | Already suitable (numeric coordinates and years, string keys) |

**Investigated: the species-key scheme (C0).** GBIF switched in mid-2026 from integer backbone keys (6–8 digits, such as `1427067`) to Catalogue of Life keys of 4–5 characters (such as `66LTT`). A digits-only test flagged **100 of 21,380** keys as possible legacy keys, which would have meant adding a mapping step. Measuring key length showed all 100 are 4–5 characters, the same length as the letter-based keys, and **no key has 6 or more characters**. They are new-scheme keys that happen to contain no letters (the largest, `69669`, is a bird species with 159,687 records). Treatment: one key scheme, used directly.

**Raw → Curated counts.**

| | Rows |
|---|---|
| Raw | 22,425,432 |
| − coordinate uncertainty > 10 km | − 123,921 |
| **Curated fact** | **22,301,511** |

The only difference is the documented exclusion. Joins to the four dimensions do not change the count (check A1).

**Field trace (started).**

| Step | Field and rule | Observed |
|---|---|---|
| Source | `decimallatitude`, `decimallongitude` in `bigquery-public-data.gbif.occurrences` | — |
| Raw | Same values, unchanged, in `raw.gbif_mn_occurrences` (only out-of-state points removed, R3) | 22,425,432 rows |
| Curated | `cell_key = CONCAT(FLOOR(lat/0.25), '_', FLOOR(lon/0.25))` in `cur.fct_occurrence` (C5), joined to `cur.dim_grid_cell` | All 22,301,511 fact rows match one of 482 cells (A1); 15,005 amphibian records since 2015 fall in 397 of 482 cells (A2) |
| Serving (**planned, P3**) | Records per 100 km² of in-state area per cell, class and period in `srv.cell_class_period_density`, with a `possible_gap` flag and an edge-cell label | — |
| Audience output (**planned, P3**) | Grid map of possible survey gaps for the chosen class and period | — |

## 3. Run and interpret two acceptance checks

Code: [`04_acceptance.sql`](../sql/04_acceptance.sql).

| Risk and affected result | Check code | Expected result and why | Observed result | Interpretation or action |
|---|---|---|---|---|
| **Grain and relationships.** A fact row that fails to join a dimension drops out of gap counts; a repeated dimension key duplicates rows and inflates them. | `04_acceptance.sql` A1 | Fact rows = distinct `gbifid` = Raw − rows over 10 km; rows after joining all four dimensions = fact rows; 0 unmatched rows per dimension; 0 duplicate dimension keys; 0 species keys with more than one class. These follow from the declared grain and the one documented exclusion. | 22,425,432 − 123,921 = **22,301,511** = distinct `gbifid` = rows after joins. Unmatched cell / taxon / month / dataset: **0 / 0 / 0 / 0**. Duplicate keys: **0** in all four dimensions. Species keys with multiple classes: **0**. | **Pass.** The Curated fact keeps exactly one row per in-state occurrence, and every row reaches every dimension, so class, period and cell counts can be added without loss or inflation. |
| **Meaning of the gap result.** Edge cells cover less of Minnesota, so they collect fewer records and can be flagged as gaps for that reason alone. | `04_acceptance.sql` A2 (amphibians, 2015 onward) | Records in the cell spine = amphibian fact records (reconciliation); the edge-cell share of gaps is **lower** under the area-adjusted density rule than under a raw-count rule. | 15,005 = 15,005. 482 cells, 125 edge (26%), 85 with zero records. Count rule: 195 gaps, **36.9%** edge. Density rule: 184 gaps, **34.2%** edge. 11 cells change flag. | **Expectation met, but only partly corrected.** Area adjustment lowers the edge share, so the density rule is kept. Edge cells are still over-represented (34% of gaps against 26% of cells), mainly because small in-state slivers often have **zero** records, which no area adjustment changes. Treatment: keep the density rule **and** label edge cells in the P3 map so a coordinator can see that an edge gap may reflect a small area. |

### Additional source case: possible double counting across datasets (check A3)

The same sighting can be published by two datasets (for example, eBird and iNaturalist), which would make a cell look better recorded than it is. Raw has no observer or exact day, so duplicates cannot be proven. A3 brackets the true count: **upper** = records as published; **lower** = within each species × cell × year-month, only the largest single dataset (as if every other record were a copy). Species-identified records, 2015 onward.

| Class | Species × cell × month groups | Groups with 2+ datasets | Records: published → lower bound | Max possible copies | Possible gaps: published / lower bound | Cells whose flag changes |
|---|---|---|---|---|---|---|
| Amphibia | 8,134 | 1 | 14,279 → 14,278 | 0.0% | 185 / 185 | **0** |
| Aves | 1,675,484 | 64,959 | 17,315,256 → 17,186,443 | 0.7% | 135 / 135 | **0** |
| Reptilia | 6,795 | 4 | 12,475 → 12,470 | 0.0% | 213 / 213 | **0** |

**Effect and treatment.** Even in the worst case, the possible-gap map is identical for all three classes. Amphibian and reptile records come almost entirely from single sources, and bird overlap could remove at most 0.7% of records. Curated therefore keeps records **as published**, with no deduplication step; this decision now rests on measured evidence. (A3's amphibian total, 14,279, is below A2's 15,005 because A3 uses only species-identified records; A2 also counts 726 class-only amphibian records.)

## 4. Make the run reproducible and record the next step

**Run order.** Run each statement on its own in the BigQuery console, in this order.

| # | Step | Code | Needs | Effect on objects |
|---|---|---|---|---|
| 1 | Create datasets | [`02_ingest.sql`](../sql/02_ingest.sql) R0 | Access to the project | Creates `raw`, `cur` if missing |
| 2 | Record source snapshot | R0b | — | Read-only. **Save the result before step 4**: the source can change. |
| 3 | Minnesota boundary | R1 | Public boundary table | Replaces `raw.mn_boundary` |
| 4 | Full GBIF scan → box | R2 | ~450 GB of monthly free quota | Replaces `raw.gbif_mn_box`. **Run once.** |
| 5 | Clip to Minnesota → Raw | R3 | Steps 3–4 | Replaces `raw.gbif_mn_occurrences` |
| 6 | Load log | R4 | Step 5 | Replaces `raw.load_log` |
| 7 | Verify Raw | R5 | Step 5 | Read-only; compare with section 1 |
| 8 | Key-scheme profile | [`03_curate.sql`](../sql/03_curate.sql) C0 | Step 5 | Read-only |
| 9 | Input switch, then dimensions | C00 (added in P3) → C1 → C2 → C3 → C4 | Steps 3, 5 | C00 replaces view `cur.src_occurrences` (normally `SELECT * FROM raw.gbif_mn_occurrences`); then replace `cur.dim_grid_cell`, `dim_taxon`, `dim_month`, `dim_dataset` |
| 10 | Fact view | C5 | Step 5 | Replaces view `cur.fct_occurrence` |
| 11 | Curated counts | C6 | Steps 9–10 | Read-only; compare with section 2 |
| 12 | Acceptance checks | [`04_acceptance.sql`](../sql/04_acceptance.sql) A1, A2, A3 | Steps 9–10 | Read-only; compare with section 3 |
| 13 | Serving table (P3) | [`05_serve.sql`](../sql/05_serve.sql) S0, S1 | Steps 9–10 | Creates `srv` if missing; replaces `srv.cell_class_period_density` |
| 14 | Serving summary (P3) | S2 | Step 13 | Read-only; compare with the P3 section |
| 15 | Serving number check (P3) | [`06_serving_check.sql`](../sql/06_serving_check.sql) | Steps 5, 9, 13 | Read-only; expected = observed |
| 16 | Save Serving baseline (P3) | [`07_rerun_and_change.sql`](../sql/07_rerun_and_change.sql) B0, B1 | Step 13 | Creates `p3test`; replaces `p3test.serving_baseline`. **Run before any rerun or change test**, which overwrite Serving. |

Every build statement is `CREATE OR REPLACE` (the sandbox does not allow `INSERT`, `UPDATE`, `DELETE` or `MERGE`), so a rerun replaces objects rather than appending. Steps 5–15 read only tables in this project and can be rerun cheaply without repeating step 4. `raw.gbif_mn_box` is kept for that reason.

**Checked against this build.** The run order above is the sequence that produced the results in sections 1–3. Someone with access to the same project can rerun steps 5–12 and should get identical counts. A rerun of step 4 after a GBIF refresh will give a different snapshot, recorded by step 2 and `raw.load_log`.

**Main limitation.** The data measure **recording effort**, not wildlife: there is no survey-effort measure, so a possible gap cannot be separated into "few animals" or "few observers". Edge cells also remain over-represented among gaps after area adjustment (check A2).

**Next P3 step (written in P2; done in the P3 section below).** Build `srv.cell_class_period_density` from `cur.fct_occurrence` and `cur.dim_grid_cell`: records per 100 km² of in-state area for each cell, class and period, the possible-gap flag (no records, or lowest quartile of cells with records), and an `is_edge_cell` label. Then reconcile its total records with the Curated fact, as A2 does for amphibians.

**Model changes since P1.** The grain, fact type and dimensions are unchanged. Implementation changed three details: the fact is a view; a missing month keeps its year (`event_month_key = year*100 + 0`); and grid cells with zero in-state area are excluded. The P1 diagram's `specieskey` remains a string key, now confirmed to be a single key scheme (C0).

**AI and tool use.**

| What | How it was checked |
|---|---|
| Claude (Anthropic) wrote the cleaned-up `02_ingest.sql` from my first version (removing a duplicated block and a 0.1% `TABLESAMPLE` that had replaced Raw with 29,521 rows), wrote `03_curate.sql` and `04_acceptance.sql`, and drafted this note from my results. | I ran every statement in BigQuery and recorded the results shown. I checked that the counts reconcile (Raw − exclusion = fact; dimension sizes match C0 and A1; A2 and A3 totals agree after accounting for class-only records). The key-scheme conclusion was tested with the length query rather than assumed. I can explain each rule and check. |
| P3: Claude drafted `05_serve.sql`, `06_serving_check.sql`, `07_rerun_and_change.sql`, the input switch (C00) and the P3 section of this note. Its first change-test design avoided `UPDATE` because Google's sandbox documentation lists DML as unsupported; my probe (T0) showed `UPDATE` works in my project, so the test was redone with real `UPDATE` statements. | I ran every statement and recorded the results below. I confirmed the test copy matched Raw before changing it (T2c), predicted the after-change values before running the rebuild and compared them with the observed ones, and confirmed the restore with an exact row comparison (B3 = 0 / 0). The independent number check (06) recomputes from Raw by a different method rather than reusing Serving logic. |

---

## P3: Serving, number check, rerun and change

All P3 results were observed on 2026-11-25 against the P2 build (snapshot 2026-11-02).

### Part 1. Serving output

**Object.** `srv.cell_class_period_density` (table), built by [`05_serve.sql`](../sql/05_serve.sql) S1; run order steps 13–14 above.

**Who uses it.** Survey coordinators in a state nongame wildlife program, choosing where to send limited field-survey days.

**One row means.** One 0.25° grid cell × one animal class (Aves, Amphibia, Reptilia) × one period (before 2015, 2015 onward), with its recording density and whether it is a possible survey gap. 482 cells × 3 classes × 2 periods = **2,892 rows**; every in-state cell appears, including cells with no records.

| Column | Meaning |
|---|---|
| `record_count`, `distinct_species` | Curated occurrence records (and species) in the cell for that class and period |
| `records_per_100km2` | `record_count` ÷ in-state area × 100 |
| `gap_threshold_per_100km2` | Exact 25th percentile of `records_per_100km2` among cells that have records, for that class and period |
| `possible_gap`, `gap_reason` | True if the cell has no records, or its density is at or below the threshold |
| `is_edge_cell` | Cell is partly outside Minnesota; shown so an edge gap can be read with care (P2 check A2) |

**Result (S2).**

| Class | Period | Cells with records (of 482) | Records | Gap threshold (per 100 km²) | Possible-gap cells | of which no records | of which edge cells |
|---|---|---|---|---|---|---|---|
| Amphibia | 2015 onward | 397 | 15,005 | 0.7754 | **185** | 85 | 63 |
| Amphibia | before 2015 | 204 | 2,925 | 0.2186 | **329** | 278 | 94 |
| Aves | 2015 onward | 462 | 17,315,588 | 768.27 | **136** | 20 | 49 |
| Aves | before 2015 | 456 | 2,460,007 | 97.12 | **140** | 26 | 48 |
| Reptilia | 2015 onward | 358 | 12,487 | 0.7336 | **214** | 124 | 66 |
| Reptilia | before 2015 | 162 | 1,228 | 0.1902 | **361** | 320 | 97 |

The claim limit from P0/P1 still applies: these are places with few **records**, which may reflect few observers rather than few animals.

### Part 2. Check one number

**Number checked:** possible-gap cells for **Amphibia, 2015 onward**, the count a coordinator sees for the primary question.

**Check code:** [`06_serving_check.sql`](../sql/06_serving_check.sql). The expected value is computed from **Raw**, not from the Curated fact, taxon or month tables, and not from Serving: class and period come directly from Raw `class` and `year`, the >10 km exclusion is re-applied to Raw coordinate uncertainty, and the 25th-percentile threshold is found by ranking rows (`ROW_NUMBER`) instead of `PERCENTILE_DISC`. Only the boundary-derived cell areas come from `cur.dim_grid_cell`.

| | Expected (from Raw) | Observed (Serving) | Match |
|---|---|---|---|
| Possible-gap cells | 185 | 185 | ✅ |
| Amphibian records | 15,005 | 15,005 | ✅ |
| Gap threshold (per 100 km²) | 0.775448876159544 | 0.775448876159544 | ✅ |
| Raw records in cells outside the grid | 0 | — | ✅ |

**What the comparison checks:** that the Curated keys and joins (taxon → class, month → period, coordinates → cell), the uncertainty exclusion, the area adjustment and the Serving threshold rule together produce the same answer as a separate calculation straight from the input. **Note on 184 vs 185:** P2 check A2 found 184 density-rule gaps because it used `APPROX_QUANTILES`, an estimate. Serving uses the exact percentile, which the independent ranking method reproduces, and that moves one borderline cell.

**Extending the P2 field trace to Serving.** P2 traced `decimallatitude`, `decimallongitude` → Raw → Curated `cell_key = FLOOR(lat/0.25)_FLOOR(lon/0.25)`. In Serving, **`possible_gap`** is true when `record_count = 0` or `records_per_100km2 <= gap_threshold_per_100km2`, where `record_count` counts Curated `cur.fct_occurrence` rows grouped by **`cell_key`**, filtered by `cur.dim_taxon.class` and `cur.dim_month.period`, and `records_per_100km2` divides by `cur.dim_grid_cell.in_state_area_km2`.

### Part 3. Rerun with the same input, then change one number and trace it

Code: [`07_rerun_and_change.sql`](../sql/07_rerun_and_change.sql), plus the Curated and Serving steps it reruns.

**Same-input rerun.** After saving Serving as `p3test.serving_baseline` (B1), the pipeline was rerun from the Raw input: [`03_curate.sql`](../sql/03_curate.sql) C00–C6 → [`05_serve.sql`](../sql/05_serve.sql) S1. R2 and R3 were not rerun: R2 rescans ~450 GB of a source GBIF refreshes monthly, and R3 would rewrite ~3 GiB against the sandbox storage limit; the Raw input itself was unchanged.

| Comparison (B3) | Result |
|---|---|
| Curated counts (C6) | Identical to P2: 22,425,432 Raw, 123,921 excluded, 22,301,511 fact rows, 482 cells, 21,670 taxa, 2,048 months, 755 datasets |
| Serving rows, baseline / rerun | 2,892 / 2,892 |
| Rows only in baseline / only in rerun | **0 / 0**: every Serving row and value matches |

**How the test copy works.** The pipeline reads its input through one switch view, `cur.src_occurrences` (C00, added in P3), so pointing every downstream step at a test copy and back takes one statement. The test copy is the view `p3test.gbif_mn_occurrences_test` = Raw without the target row, `UNION ALL` a 1-row table `p3test.overlay_rows` holding that row (T2a–T2b). It behaves as a full copy of Raw but stores one row, which matters in the BigQuery sandbox (10 GiB storage limit, not refunded when data is deleted). The change and the restore are real `UPDATE` statements on that table. A probe (T0) confirmed this project accepts `UPDATE`, although Google's sandbox documentation lists DML as unsupported.

**Value changed.** `year` of occurrence `gbifid = 1143520712` (T1): an amphibian recorded in July 2015, the only amphibian record since 2015 in cell **`192_-380`** (48.00–48.25°N, 95.00–94.75°W). Change: **2015 → 2010**, which moves it from "2015 onward" to "before 2015". The test copy matched Raw before the change: 22,425,432 = 22,425,432 rows, target year 2015 (T2c).

| Step | Statement | Observed |
|---|---|---|
| Point pipeline at the test copy | T3 | Switch view replaced |
| Change | T5: `UPDATE p3test.overlay_rows SET year = 2010 WHERE gbifid = 1143520712` | "This statement modified 1 row in overlay_rows" |
| Rerun what reads the changed input | 03 C2, C3, C4, C5 → 05 S1 (C1 reads only the boundary) | — |
| Restore | T7: `UPDATE p3test.overlay_rows SET year = 2015 WHERE gbifid = 1143520712` | "This statement modified 1 row in overlay_rows" |
| Rerun the same steps | 03 C2–C5 → 05 S1 | — |
| Point pipeline back at Raw | T8 | Switch view replaced |

**What changed (T4, B3).** The values in the "Predicted" column were written down before the rebuild was run.

| Layer | Value | Before | Predicted | After change | After restore (B3 = 0 / 0, so Serving equals the baseline) |
|---|---|---|---|---|---|
| Curated | `event_month_key` of the record | 201507 | 201007 | **201007** | 201507 (observed in the dry run below) |
| Curated | Curated row counts (C6) | 22,301,511 fact rows, 2,048 months | unchanged | **unchanged** (observed in the dry run; 201007 already existed in `dim_month`) | — |
| Serving | Cell 192_-380, Amphibia, 2015 onward: records / density / reason | 1 / 0.1939 / lowest quartile | 0 / 0 / no records | **0 / 0.0 / no records** | 1 / 0.1939 / lowest quartile |
| Serving | Cell 192_-380, Amphibia, before 2015: records / density / reason | 0 / 0.0 / no records | 1 / 0.1939 / lowest quartile | **1 / 0.1939 / lowest quartile** | 0 / 0.0 / no records |
| Serving | Amphibian records, 2015 onward / before 2015 | 15,005 / 2,925 | 15,004 / 2,926 | **15,004 / 2,926** | 15,005 / 2,925 |
| Serving | Thresholds, 2015 onward / before 2015 | 0.7754 / 0.2186 | may shift slightly | **unchanged** | unchanged |
| Serving | Possible-gap cells, 2015 onward / before 2015 | 185 / 329 | may shift slightly | **unchanged** | unchanged |
| Serving | Rows differing from baseline, only in baseline / only in current (B3) | 0 / 0 | 2 / 2 | **2 / 2** | **0 / 0** |

**Interpretation.** One input value moved one record between periods, and exactly the two Serving rows for that cell changed; the other 2,890 rows stayed identical. The cell is a possible gap in both periods either way, but the **reason** changed ("lowest quartile" ↔ "no records"), which is what a coordinator would see. The thresholds did not move because one cell joining or leaving the recorded cells did not shift the 25th percentile. After the restore, Serving matched the baseline exactly (0 / 0).

**Run-order evidence.** Between the change and the Serving rebuild, an observation showed the Curated `event_month_key` already at 201007 while the Serving row still showed the old count. The fact is a view and reflects input changes immediately; the Serving table changes only when S1 is rerun. That is why the run order rebuilds C2–C5 **and then** S1.

**Earlier dry run.** Before the `UPDATE` probe, the same change was first made by redefining the test-copy view with an override (no DML). It produced identical results (201007; cell 1 → 0 records since 2015; 15,004 / 2,926; B3 2 / 2, then 0 / 0 after the restore).

### Part 4. History check

Not required: my C2 rating is not "Developing" (S1 Proficient, P1 Advanced), so my P3 C2 entry is N/A. For reference, the P3 test changed an event attribute (`year`), which the pipeline treats as a correction: every rebuild uses the current input value. The P1 history decision concerns a different attribute, taxonomic `class` (Type 1, current classification applied to all periods).

### Limitation and next step

**Main limitation.** The Serving output measures **recording**, not wildlife: a possible gap may reflect few observers rather than few animals, and edge cells remain over-represented among gaps (P2 check A2). Sandbox tables also expire 60 days after creation, so `raw`, `cur` and `srv` must be rebuilt from the run order if they lapse before P4.

**Next step (P4).** Build the audience output from `srv.cell_class_period_density`: a grid map of possible survey gaps for the chosen class and period, with edge cells marked and the claim limit stated on the map.
