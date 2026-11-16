-- =====================================================================
-- P2 Step R: Source -> Raw  (Minnesota Wildlife Survey Gap Finder)
-- Project: fiery-monitor-508317-a8   Processing location: US
--
-- Every statement is CREATE ... AS SELECT (DDL); the BigQuery sandbox does
-- not allow DML (INSERT/UPDATE/DELETE/MERGE). Run ONE statement at a time,
-- in order. Each CREATE OR REPLACE overwrites its table.
--
-- COST: R2 is the only large scan of the public table (it processed about
-- 450 GB on 2026-11-16). Check the validator estimate and this month's
-- remaining free 1 TB before running it. Run it ONCE. Every later step
-- reads tables in my own project.
-- =====================================================================

-- R0. Datasets for this build (no cost)
CREATE SCHEMA IF NOT EXISTS `fiery-monitor-508317-a8.raw` OPTIONS (location = 'US');
CREATE SCHEMA IF NOT EXISTS `fiery-monitor-508317-a8.cur` OPTIONS (location = 'US');

-- R0b. Record the source snapshot BEFORE the scan (metadata only, ~0 bytes).
--      Save this result: it identifies the version of the source used.
SELECT table_id,
       row_count,
       ROUND(size_bytes / POW(1024, 4), 2)  AS size_tb,
       TIMESTAMP_MILLIS(last_modified_time) AS source_last_modified
FROM `bigquery-public-data.gbif.__TABLES__`
WHERE table_id = 'occurrences';

-- R1. Minnesota boundary from a small public table. Replaces raw.mn_boundary.
CREATE OR REPLACE TABLE `fiery-monitor-508317-a8.raw.mn_boundary` AS
SELECT state_name, state_fips_code, state_geom
FROM `bigquery-public-data.geo_us_boundaries.states`
WHERE state_name = 'Minnesota';

-- R2. ONE narrow scan of the FULL GBIF table (no sample) -> bounding box.
--     Reads only the 12 columns listed (incl. the filter column countrycode).
--     Adds two load-metadata columns. Replaces raw.gbif_mn_box.
--     Run 2026-11-16 14:46 UTC: 32,305,853 rows, 4.23 GiB.
CREATE OR REPLACE TABLE `fiery-monitor-508317-a8.raw.gbif_mn_box` AS
SELECT
  gbifid,
  datasetkey,
  basisofrecord,
  kingdom,
  class,
  specieskey,
  decimallatitude,
  decimallongitude,
  coordinateuncertaintyinmeters,
  year,
  month,
  CURRENT_TIMESTAMP() AS _loaded_at,
  (SELECT TIMESTAMP_MILLIS(last_modified_time)
   FROM `bigquery-public-data.gbif.__TABLES__`
   WHERE table_id = 'occurrences') AS _source_last_modified
FROM `bigquery-public-data.gbif.occurrences`
WHERE countrycode = 'US'
  AND decimallatitude  BETWEEN 43.4 AND 49.5
  AND decimallongitude BETWEEN -97.3 AND -89.4;

-- R3. Clip the box to the true Minnesota boundary -> the Raw input.
--     Values are copied unchanged; only rows outside Minnesota are removed.
--     Reads the box table (~4 GB), not the public table.
--     Replaces raw.gbif_mn_occurrences.
CREATE OR REPLACE TABLE `fiery-monitor-508317-a8.raw.gbif_mn_occurrences` AS
SELECT o.*
FROM `fiery-monitor-508317-a8.raw.gbif_mn_box` AS o
JOIN `fiery-monitor-508317-a8.raw.mn_boundary` AS s
  ON ST_CONTAINS(s.state_geom, ST_GEOGPOINT(o.decimallongitude, o.decimallatitude));

-- R4. One-row load log: snapshot, load time and row counts. Replaces raw.load_log.
CREATE OR REPLACE TABLE `fiery-monitor-508317-a8.raw.load_log` AS
SELECT
  'raw.gbif_mn_occurrences'                                                  AS loaded_table,
  CURRENT_TIMESTAMP()                                                        AS logged_at,
  (SELECT ANY_VALUE(_source_last_modified)
   FROM `fiery-monitor-508317-a8.raw.gbif_mn_occurrences`)                   AS source_last_modified,
  (SELECT MIN(_loaded_at)
   FROM `fiery-monitor-508317-a8.raw.gbif_mn_occurrences`)                   AS loaded_at,
  (SELECT COUNT(*) FROM `fiery-monitor-508317-a8.raw.gbif_mn_box`)           AS box_rows,
  (SELECT COUNT(*) FROM `fiery-monitor-508317-a8.raw.gbif_mn_occurrences`)   AS raw_rows;

-- R5. Verify the Raw input. Save this result for the build note.
--     P0 (snapshot 2026-10-02): box 30,232,036 -> Minnesota 20,852,477.
--     Expect a somewhat larger count from the newer snapshot, and
--     raw_rows = distinct_gbifid with 0 null gbifid.
SELECT
  COUNT(*)                     AS raw_rows,
  COUNT(DISTINCT gbifid)       AS distinct_gbifid,
  COUNTIF(gbifid IS NULL)      AS null_gbifid,
  MIN(year)                    AS earliest_year,
  MAX(year)                    AS latest_year,
  ANY_VALUE(_source_last_modified) AS source_last_modified,
  MIN(_loaded_at)              AS loaded_at
FROM `fiery-monitor-508317-a8.raw.gbif_mn_occurrences`;
