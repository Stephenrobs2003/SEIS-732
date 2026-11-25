-- =====================================================================
-- P2 Step C: Raw -> Curated  (Minnesota Wildlife Survey Gap Finder)
-- Project: fiery-monitor-508317-a8   Processing location: US
-- Input:  raw.gbif_mn_occurrences (built by sql/02_ingest.sql), read through the
--         switch view cur.src_occurrences (C00), and raw.mn_boundary
-- Output: four small dimension TABLES and one fact VIEW in dataset `cur`.
--
-- Storage: the sandbox has a 10 GiB storage limit, so the fact is a VIEW
-- (no storage); the dimensions are small tables. Every statement is
-- CREATE OR REPLACE (DDL) and overwrites its object. Run one at a time.
-- =====================================================================

-- C0. Input profile for the taxon rule: which key scheme does Raw use?
--     GBIF moved from integer backbone keys (6-8 digits, e.g. 1427067) to
--     Catalogue of Life keys of 4-5 characters (e.g. Q2M4, 66LTT) in mid-2026.
--     A digits-only test alone is misleading: some new 4-5 character keys
--     contain no letters. Key length separates the schemes.
--     Observed 2026-11-16: 21,380 keys; 100 digits-only, all 4-5 characters;
--     0 keys of 6+ characters -> one (new) key scheme, no mapping step needed.
SELECT
  REGEXP_CONTAINS(CAST(specieskey AS STRING), r'^[0-9]+$') AS all_digits,
  LENGTH(CAST(specieskey AS STRING))                       AS key_length,
  COUNT(DISTINCT specieskey)                               AS keys,
  COUNT(*)                                                 AS records,
  COUNTIF(class IN ('Aves', 'Amphibia', 'Reptilia'))       AS target_class_records
FROM `fiery-monitor-508317-a8.raw.gbif_mn_occurrences`
WHERE specieskey IS NOT NULL
GROUP BY all_digits, key_length
ORDER BY all_digits, key_length;


-- C00. Input switch (added in P3). Every Curated step that reads occurrences
--      reads this view, so the whole downstream pipeline can be pointed at a
--      test copy of the input (P3 Part 3) and back by changing ONE statement.
--      Normal setting: the Raw table. No storage (it is a view).
CREATE OR REPLACE VIEW `fiery-monitor-508317-a8.cur.src_occurrences` AS
SELECT * FROM `fiery-monitor-508317-a8.raw.gbif_mn_occurrences`;


-- C1. dim_grid_cell: every 0.25-degree cell with a positive area inside Minnesota.
--     Built from the boundary, NOT from occurrences, so cells with zero
--     records exist (needed to show possible gaps).
CREATE OR REPLACE TABLE `fiery-monitor-508317-a8.cur.dim_grid_cell` AS
WITH grid AS (
  SELECT
    lat_i,
    lon_i,
    ST_GEOGFROMTEXT(FORMAT('POLYGON((%f %f, %f %f, %f %f, %f %f, %f %f))',
      lon_i * 0.25,       lat_i * 0.25,
      (lon_i + 1) * 0.25, lat_i * 0.25,
      (lon_i + 1) * 0.25, (lat_i + 1) * 0.25,
      lon_i * 0.25,       (lat_i + 1) * 0.25,
      lon_i * 0.25,       lat_i * 0.25)) AS cell
  FROM UNNEST(GENERATE_ARRAY(173, 197)) AS lat_i,     -- 43.25 to 49.50 N
       UNNEST(GENERATE_ARRAY(-390, -358)) AS lon_i    -- 97.50 to 89.25 W
),
measured AS (
  SELECT
    g.lat_i,
    g.lon_i,
    ST_AREA(g.cell) / 1e6                                            AS cell_area_km2,
    ST_AREA(ST_INTERSECTION(g.cell, b.state_geom)) / ST_AREA(g.cell) AS share_in_mn
  FROM grid AS g
  CROSS JOIN `fiery-monitor-508317-a8.raw.mn_boundary` AS b
  WHERE ST_INTERSECTS(g.cell, b.state_geom)
)
SELECT
  CONCAT(CAST(lat_i AS STRING), '_', CAST(lon_i AS STRING)) AS cell_key,
  lat_i,
  lon_i,
  lat_i * 0.25                       AS min_lat,
  lon_i * 0.25                       AS min_lon,
  cell_area_km2,
  share_in_mn,
  cell_area_km2 * share_in_mn        AS in_state_area_km2,
  share_in_mn < 0.999                AS is_edge_cell
FROM measured
WHERE share_in_mn > 0;               -- drop cells that only touch the border


-- C2. dim_taxon: one row per taxon_key.
--     Rule: taxon_key = specieskey; if null, 'CLASS:<class>' (class-only
--     member); if both null, 'UNKNOWN'. Type 1: one current class per key.
--     n_class_values is kept so check A1 can prove the key has one class.
CREATE OR REPLACE TABLE `fiery-monitor-508317-a8.cur.dim_taxon` AS
WITH t AS (
  SELECT
    COALESCE(CAST(specieskey AS STRING), CONCAT('CLASS:', class), 'UNKNOWN') AS taxon_key,
    CAST(specieskey AS STRING) AS specieskey,
    class,
    kingdom
  FROM `fiery-monitor-508317-a8.cur.src_occurrences`
)
SELECT
  taxon_key,
  ANY_VALUE(specieskey)            AS specieskey,
  MAX(class)                       AS class,
  MAX(kingdom)                     AS kingdom,
  ANY_VALUE(specieskey) IS NOT NULL AS is_species_resolved,
  COUNT(DISTINCT class)            AS n_class_values
FROM t
GROUP BY taxon_key;


-- C3. dim_month: one row per event_month_key = year*100 + month.
--     Rule: a missing month keeps its year (month part 0), so the record
--     still counts toward its period; a missing year gives key 0 ('unknown').
CREATE OR REPLACE TABLE `fiery-monitor-508317-a8.cur.dim_month` AS
SELECT DISTINCT
  IF(year IS NULL, 0, year * 100 + IFNULL(month, 0))         AS event_month_key,
  year,
  IF(year IS NULL, NULL, month)                              AS month,
  CASE
    WHEN year IS NULL THEN 'unknown'
    WHEN year < 2015  THEN 'before 2015'
    ELSE '2015 onward'
  END                                                        AS period
FROM `fiery-monitor-508317-a8.cur.src_occurrences`;


-- C4. dim_dataset: one row per publishing dataset (names and licenses for
--     the top datasets are added from GBIF metadata in P3).
CREATE OR REPLACE TABLE `fiery-monitor-508317-a8.cur.dim_dataset` AS
SELECT
  datasetkey AS dataset_key,
  COUNT(*)   AS raw_records
FROM `fiery-monitor-508317-a8.cur.src_occurrences`
GROUP BY datasetkey;


-- C5. fct_occurrence (VIEW): one row per GBIF occurrence record in Minnesota.
--     Rules: exclude records whose stated coordinate uncertainty exceeds
--     10 km (too coarse for 0.25-degree cells); keep records with no stated
--     uncertainty (94% of records; see P0). Coordinates become cell_key and
--     are not carried forward. record_count = 1 (additive measure).
CREATE OR REPLACE VIEW `fiery-monitor-508317-a8.cur.fct_occurrence` AS
SELECT
  gbifid,
  CONCAT(CAST(CAST(FLOOR(decimallatitude  / 0.25) AS INT64) AS STRING), '_',
         CAST(CAST(FLOOR(decimallongitude / 0.25) AS INT64) AS STRING))    AS cell_key,
  COALESCE(CAST(specieskey AS STRING), CONCAT('CLASS:', class), 'UNKNOWN') AS taxon_key,
  IF(year IS NULL, 0, year * 100 + IFNULL(month, 0))                       AS event_month_key,
  datasetkey                                                               AS dataset_key,
  basisofrecord                                                            AS basis_of_record,
  coordinateuncertaintyinmeters                                            AS coord_uncertainty_m,
  1                                                                        AS record_count
FROM `fiery-monitor-508317-a8.cur.src_occurrences`
WHERE coordinateuncertaintyinmeters IS NULL
   OR coordinateuncertaintyinmeters <= 10000;


-- C6. Curated counts for the build note. Save this result.
SELECT
  (SELECT COUNT(*) FROM `fiery-monitor-508317-a8.raw.gbif_mn_occurrences`)                       AS raw_rows,
  (SELECT COUNTIF(coordinateuncertaintyinmeters > 10000)
   FROM `fiery-monitor-508317-a8.raw.gbif_mn_occurrences`)                                       AS raw_rows_over_10km,
  (SELECT COUNT(*) FROM `fiery-monitor-508317-a8.cur.fct_occurrence`)                            AS fact_rows,
  (SELECT COUNT(*) FROM `fiery-monitor-508317-a8.cur.dim_grid_cell`)                             AS grid_cells,
  (SELECT COUNTIF(is_edge_cell) FROM `fiery-monitor-508317-a8.cur.dim_grid_cell`)                AS edge_cells,
  (SELECT COUNT(*) FROM `fiery-monitor-508317-a8.cur.dim_taxon`)                                 AS taxon_rows,
  (SELECT COUNT(*) FROM `fiery-monitor-508317-a8.cur.dim_month`)                                 AS month_rows,
  (SELECT COUNT(*) FROM `fiery-monitor-508317-a8.cur.dim_dataset`)                               AS dataset_rows;
