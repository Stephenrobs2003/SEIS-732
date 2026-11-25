-- =====================================================================
-- P3 Part 3: Same-input rerun, then change one input value and trace it
-- Project: fiery-monitor-508317-a8   Processing location: US
--
-- METHOD: the test copy of the input is the view
-- p3test.gbif_mn_occurrences_test = Raw WITHOUT the target row, UNION ALL a
-- 1-row editable table p3test.overlay_rows holding that row. This behaves as
-- a full copy of Raw but stores one row, which matters because the project
-- runs in the BigQuery sandbox (10 GiB storage limit, not refunded on delete).
-- The change and the restore are real UPDATE statements on that table.
-- Downstream steps read the copy through the switch view cur.src_occurrences
-- (03_curate C00). The target row (T1, observed 2026-11-25) is
-- gbifid 1143520712: an amphibian, July 2015, the only amphibian record
-- since 2015 in cell 192_-380.
--
-- Run ONE statement at a time, in the order of the steps below, and save
-- each result marked SAVE.
-- =====================================================================

-- B0. Dataset for test objects (no cost)
CREATE SCHEMA IF NOT EXISTS `fiery-monitor-508317-a8.p3test` OPTIONS (location = 'US');

-- B1. Save the first Serving result as the baseline (2,892 small rows).
--     Run once, right after the first build of 05_serve.sql S1.
CREATE OR REPLACE TABLE `fiery-monitor-508317-a8.p3test.serving_baseline` AS
SELECT * FROM `fiery-monitor-508317-a8.srv.cell_class_period_density`;

-- B2. SAME-INPUT RERUN: rerun the whole pipeline from the Raw input:
--       03_curate.sql C00, C1, C2, C3, C4, C5, C6  ->  05_serve.sql S1
--     (02_ingest R2/R3 are not rerun: R2 rescans ~450 GB of the public
--      source, which GBIF refreshes monthly, and R3 would rewrite ~3 GiB
--      against the sandbox storage limit. The Raw input is unchanged.)
--     Then run B3.

-- B3. Compare current Serving with the baseline. SAVE.
--     Same input -> expected 2,892 / 2,892 rows and 0 / 0 differing rows.
SELECT
  (SELECT COUNT(*) FROM `fiery-monitor-508317-a8.p3test.serving_baseline`)          AS baseline_rows,
  (SELECT COUNT(*) FROM `fiery-monitor-508317-a8.srv.cell_class_period_density`)    AS current_rows,
  (SELECT COUNT(*) FROM (
     SELECT * FROM `fiery-monitor-508317-a8.p3test.serving_baseline`
     EXCEPT DISTINCT
     SELECT * FROM `fiery-monitor-508317-a8.srv.cell_class_period_density`))         AS rows_only_in_baseline,
  (SELECT COUNT(*) FROM (
     SELECT * FROM `fiery-monitor-508317-a8.srv.cell_class_period_density`
     EXCEPT DISTINCT
     SELECT * FROM `fiery-monitor-508317-a8.p3test.serving_baseline`))               AS rows_only_in_current;


-- T0. Probe: does this project accept DML? (Observed 2026-11-25: yes,
--     "This statement modified 1 row in dml_probe".)
CREATE OR REPLACE TABLE `fiery-monitor-508317-a8.p3test.dml_probe` AS SELECT 1 AS x;
UPDATE `fiery-monitor-508317-a8.p3test.dml_probe` SET x = 2 WHERE TRUE;


-- T1. Choose the row to change. SAVE gbifid, cell_key, year, month.
--     An amphibian record from 2015 onward that is the ONLY such record in
--     its cell, so moving it to an earlier year visibly changes that cell.
WITH a AS (
  SELECT f.gbifid, f.cell_key, m.year, m.month
  FROM `fiery-monitor-508317-a8.cur.fct_occurrence` AS f
  JOIN `fiery-monitor-508317-a8.cur.dim_taxon` AS t ON t.taxon_key       = f.taxon_key
  JOIN `fiery-monitor-508317-a8.cur.dim_month` AS m ON m.event_month_key = f.event_month_key
  WHERE t.class = 'Amphibia' AND m.period = '2015 onward'
),
single AS (
  SELECT cell_key FROM a GROUP BY cell_key HAVING COUNT(*) = 1
)
SELECT a.gbifid, a.cell_key, a.year, a.month
FROM a JOIN single USING (cell_key)
ORDER BY a.gbifid
LIMIT 1;


-- T2. Make the test copy of the input.
-- T2a. Editable 1-row table holding the target row, copied unchanged.
CREATE OR REPLACE TABLE `fiery-monitor-508317-a8.p3test.overlay_rows` AS
SELECT * FROM `fiery-monitor-508317-a8.raw.gbif_mn_occurrences`
WHERE CAST(gbifid AS STRING) = '1143520712';

-- T2b. Test copy = Raw without that row + the editable row.
CREATE OR REPLACE VIEW `fiery-monitor-508317-a8.p3test.gbif_mn_occurrences_test` AS
SELECT * FROM `fiery-monitor-508317-a8.raw.gbif_mn_occurrences`
WHERE gbifid NOT IN (SELECT gbifid FROM `fiery-monitor-508317-a8.p3test.overlay_rows`)
UNION ALL
SELECT * FROM `fiery-monitor-508317-a8.p3test.overlay_rows`;

-- T2c. Confirm the copy equals Raw: same row count, target year 2015. SAVE.
SELECT
  (SELECT COUNT(*) FROM `fiery-monitor-508317-a8.raw.gbif_mn_occurrences`)       AS raw_rows,
  (SELECT COUNT(*) FROM `fiery-monitor-508317-a8.p3test.gbif_mn_occurrences_test`) AS test_copy_rows,
  (SELECT year FROM `fiery-monitor-508317-a8.p3test.gbif_mn_occurrences_test`
   WHERE CAST(gbifid AS STRING) = '1143520712')                                  AS target_year;

-- T3. Point the downstream pipeline at the test copy.
CREATE OR REPLACE VIEW `fiery-monitor-508317-a8.cur.src_occurrences` AS
SELECT * FROM `fiery-monitor-508317-a8.p3test.gbif_mn_occurrences_test`;


-- T4. Observe the traced row and its Serving rows. Run it at three points:
--     BEFORE the change, AFTER the change, AFTER the restore. SAVE each.
WITH target AS (
  SELECT f.cell_key, f.event_month_key
  FROM `fiery-monitor-508317-a8.cur.fct_occurrence` AS f
  WHERE CAST(f.gbifid AS STRING) = '1143520712'
),
period_summary AS (
  SELECT period,
         SUM(record_count)                   AS period_records,
         ANY_VALUE(gap_threshold_per_100km2) AS period_threshold,
         COUNTIF(possible_gap)               AS period_gap_cells
  FROM `fiery-monitor-508317-a8.srv.cell_class_period_density`
  WHERE class = 'Amphibia'
  GROUP BY period
)
SELECT
  s.period,
  t.cell_key                     AS target_cell,
  t.event_month_key              AS curated_event_month_key,
  c.record_count                 AS cell_records,
  ROUND(c.records_per_100km2, 4) AS cell_density,
  c.possible_gap                 AS cell_possible_gap,
  c.gap_reason                   AS cell_gap_reason,
  s.period_records,
  ROUND(s.period_threshold, 4)   AS period_threshold,
  s.period_gap_cells
FROM period_summary AS s
CROSS JOIN target AS t
LEFT JOIN `fiery-monitor-508317-a8.srv.cell_class_period_density` AS c
  ON c.class = 'Amphibia' AND c.period = s.period AND c.cell_key = t.cell_key
ORDER BY s.period;


-- T5. CHANGE one value in one row of the test copy.
UPDATE `fiery-monitor-508317-a8.p3test.overlay_rows`
SET year = 2010
WHERE CAST(gbifid AS STRING) = '1143520712';

-- T6. Rerun the steps that read the changed input (C1 reads only the
--     boundary, so it is not rerun):
--       03_curate.sql C2, C3, C4, C5, C6  ->  05_serve.sql S1
--     Then run T4 (AFTER) and B3 (expect 2 / 2 changed rows: the target
--     cell's two amphibian rows).


-- T7. RESTORE the original value in the test copy.
UPDATE `fiery-monitor-508317-a8.p3test.overlay_rows`
SET year = 2015
WHERE CAST(gbifid AS STRING) = '1143520712';
--     Then rerun 03_curate.sql C2, C3, C4, C5, C6 -> 05_serve.sql S1,
--     run T4 (RESTORED) and B3 (expect 0 / 0 differing rows).


-- T8. Point the pipeline back at Raw (same as 03_curate.sql C00).
--     No rerun needed: the restored copy is identical to Raw (B3 = 0 / 0).
CREATE OR REPLACE VIEW `fiery-monitor-508317-a8.cur.src_occurrences` AS
SELECT * FROM `fiery-monitor-508317-a8.raw.gbif_mn_occurrences`;
