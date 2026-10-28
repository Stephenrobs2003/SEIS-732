-- =====================================================================
-- P1 source profile and grain test: Minnesota Wildlife Survey Gap Finder
-- Source object: fiery-monitor-508317-a8.p0_scratch.mn_occurrences
--   (the bounded Minnesota extract of bigquery-public-data.gbif.occurrences
--    built in sql/00_feasibility.sql, Step 2). Nothing here rescans the
--    1.83 TB public table; every query reads the ~20.9M-row subset.
-- All outputs are aggregates. Run one statement at a time.
-- Project: fiery-monitor-508317-a8 (replace with your own to rerun).
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Grain test for the proposed fact: one row per GBIF occurrence (gbifid)
--    Expected: source_rows = 20,852,477 on the full extract (1,749,325 on
--              the current 2-ALT sample); rows_with_null_id = 0;
--              repeated_id_groups = 0   (P0 Q3: distinct gbifid = rows)
-- ---------------------------------------------------------------------
WITH grain_groups AS (
  SELECT gbifid, COUNT(*) AS rows_per_id
  FROM `fiery-monitor-508317-a8.p0_scratch.mn_occurrences`
  GROUP BY gbifid
)
SELECT
  COALESCE(SUM(rows_per_id), 0)                              AS source_rows,
  COALESCE(SUM(IF(gbifid IS NULL, rows_per_id, 0)), 0)       AS rows_with_null_id,
  COUNTIF(gbifid IS NOT NULL AND rows_per_id > 1)            AS repeated_id_groups
FROM grain_groups;


-- ---------------------------------------------------------------------
-- 2. Missing values in the fields that become dimension keys
--    These rows stay in the fact but need an "unknown" dimension member,
--    or they silently drop out of class, period, or month counts.
--    Expected (from P0 rates): ~404K null specieskey (1.94%),
--    ~42K null class (0.20%), 24,482 null year, ~298K null month (1.43%),
--    0 null coordinates (the Step 2 box filter required them).
-- ---------------------------------------------------------------------
SELECT
  COUNT(*)                                                    AS source_rows,
  COUNTIF(specieskey IS NULL)                                 AS null_specieskey,
  COUNTIF(class IS NULL)                                      AS null_class,
  COUNTIF(specieskey IS NULL AND class IS NOT NULL)           AS class_known_species_unknown,
  COUNTIF(year IS NULL)                                       AS null_year,
  COUNTIF(month IS NULL)                                      AS null_month,
  COUNTIF(decimallatitude IS NULL OR decimallongitude IS NULL) AS null_coordinates,
  COUNTIF(datasetkey IS NULL)                                 AS null_datasetkey
FROM `fiery-monitor-508317-a8.p0_scratch.mn_occurrences`;


-- ---------------------------------------------------------------------
-- 3. Does each specieskey map to exactly one class?
--    The taxon dimension assumes specieskey -> class is one-to-one.
--    Expected: 0 species keys with more than one class.
-- ---------------------------------------------------------------------
SELECT
  COUNT(*)                         AS distinct_species_keys,
  COUNTIF(classes_per_species > 1) AS species_with_multiple_classes
FROM (
  SELECT specieskey, COUNT(DISTINCT class) AS classes_per_species
  FROM `fiery-monitor-508317-a8.p0_scratch.mn_occurrences`
  WHERE specieskey IS NOT NULL
  GROUP BY specieskey
);


-- ---------------------------------------------------------------------
-- 4. Serving-grain preview: cell x class x period for the target classes
--    Shows how many cells currently have records, before the full grid
--    spine is built in P2 (cells with zero records are absent here, which
--    is why the model needs a complete cell dimension).
-- ---------------------------------------------------------------------
SELECT
  class,
  CASE WHEN year < 2015 THEN 'before 2015' ELSE '2015 onward' END AS period,
  COUNT(DISTINCT CONCAT(CAST(FLOOR(decimallatitude / 0.25) AS STRING), '_',
                        CAST(FLOOR(decimallongitude / 0.25) AS STRING)))   AS cells_with_records,
  COUNT(*)                                                                 AS records
FROM `fiery-monitor-508317-a8.p0_scratch.mn_occurrences`
WHERE class IN ('Aves', 'Amphibia', 'Reptilia')
  AND year IS NOT NULL
GROUP BY class, period
ORDER BY class, period;


-- ---------------------------------------------------------------------
-- 5. Which build of the working tables is this? (metadata; free)
--    P0 evidence came from the full extract (box 30,232,036 -> MN 20,852,477).
--    Observed 2026-10-26: both tables recreated 2026-10-14 23:43 UTC with
--    2,614,310 and 1,749,325 rows (~8.5%), i.e. the Step 2-ALT 10% sample.
-- ---------------------------------------------------------------------
SELECT
  table_id,
  row_count,
  TIMESTAMP_MILLIS(creation_time)      AS created,
  TIMESTAMP_MILLIS(last_modified_time) AS last_modified
FROM `fiery-monitor-508317-a8.p0_scratch.__TABLES__`;


-- ---------------------------------------------------------------------
-- 6. Boundary case: how many 0.25-degree cells intersect Minnesota, and
--    how many are only partly inside? (Reads only the small boundary
--    table; no occurrence data.) Edge cells cover less of the state, so
--    they can look like "possible gaps" for that reason alone.
-- ---------------------------------------------------------------------
WITH mn AS (
  SELECT state_geom
  FROM `bigquery-public-data.geo_us_boundaries.states`
  WHERE state_name = 'Minnesota'
),
grid AS (
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
cells AS (
  SELECT ST_AREA(ST_INTERSECTION(g.cell, mn.state_geom)) / ST_AREA(g.cell) AS share_in_mn
  FROM grid AS g
  CROSS JOIN mn
  WHERE ST_INTERSECTS(g.cell, mn.state_geom)
)
SELECT
  COUNT(*)                     AS cells_intersecting_mn,
  COUNTIF(share_in_mn < 0.999) AS edge_cells,
  COUNTIF(share_in_mn < 0.5)   AS cells_mostly_outside_mn
FROM cells;


-- ---------------------------------------------------------------------
-- 7. Boundary case on the audience result: are "possible gaps" mostly
--    edge cells? Amphibians, 2015 onward, gap = fewer than 5 records.
--    Builds the full in-state cell spine so zero-record cells count.
--    NOTE: run on the current ~8.4% sample, so gap counts are inflated;
--    rerun on the full extract in P2.
-- ---------------------------------------------------------------------
WITH mn AS (
  SELECT state_geom
  FROM `bigquery-public-data.geo_us_boundaries.states`
  WHERE state_name = 'Minnesota'
),
grid AS (
  SELECT
    CONCAT(CAST(lat_i AS STRING), '_', CAST(lon_i AS STRING)) AS cell_key,
    ST_GEOGFROMTEXT(FORMAT('POLYGON((%f %f, %f %f, %f %f, %f %f, %f %f))',
      lon_i * 0.25,       lat_i * 0.25,
      (lon_i + 1) * 0.25, lat_i * 0.25,
      (lon_i + 1) * 0.25, (lat_i + 1) * 0.25,
      lon_i * 0.25,       (lat_i + 1) * 0.25,
      lon_i * 0.25,       lat_i * 0.25)) AS cell
  FROM UNNEST(GENERATE_ARRAY(173, 197)) AS lat_i,
       UNNEST(GENERATE_ARRAY(-390, -358)) AS lon_i
),
spine AS (
  SELECT g.cell_key,
         ST_AREA(ST_INTERSECTION(g.cell, mn.state_geom)) / ST_AREA(g.cell) AS share_in_mn
  FROM grid AS g
  CROSS JOIN mn
  WHERE ST_INTERSECTS(g.cell, mn.state_geom)
),
amph AS (
  SELECT
    CONCAT(CAST(CAST(FLOOR(decimallatitude / 0.25) AS INT64) AS STRING), '_',
           CAST(CAST(FLOOR(decimallongitude / 0.25) AS INT64) AS STRING)) AS cell_key,
    COUNT(*) AS records
  FROM `fiery-monitor-508317-a8.p0_scratch.mn_occurrences`
  WHERE class = 'Amphibia' AND year >= 2015
  GROUP BY cell_key
)
SELECT
  COUNT(*)                                                         AS in_state_cells,
  COUNTIF(a.cell_key IS NULL)                                      AS zero_record_cells,
  COUNTIF(IFNULL(a.records, 0) < 5)                                AS gap_cells,
  COUNTIF(IFNULL(a.records, 0) < 5 AND s.share_in_mn < 0.999)      AS gap_cells_on_edge,
  COUNTIF(IFNULL(a.records, 0) < 5 AND s.share_in_mn < 0.5)        AS gap_cells_mostly_outside,
  COUNTIF(s.share_in_mn < 0.999)                                   AS all_edge_cells
FROM spine AS s
LEFT JOIN amph AS a USING (cell_key);


-- ---------------------------------------------------------------------
-- 8. History consequence, measured (observed 2026-10-26: key 66LTT, 343 records;
--    2015 onward 442 -> 453 gap cells, before 2015 478 -> 480): if the most-recorded amphibian
--    species were reclassified out of Amphibia, how many cells would
--    become "possible gaps" in each period?
--      keep_class      = records keep their recorded class (Type 2 view
--                        of records already loaded)
--      after_reclass   = current taxonomy applied to all periods (Type 1)
--    Look up the species name at https://www.gbif.org/taxon/<top_species_key>
--    NOTE: run on the ~8.4% sample; rerun on the full extract in P2.
-- ---------------------------------------------------------------------
WITH mn AS (
  SELECT state_geom
  FROM `bigquery-public-data.geo_us_boundaries.states`
  WHERE state_name = 'Minnesota'
),
grid AS (
  SELECT
    CONCAT(CAST(lat_i AS STRING), '_', CAST(lon_i AS STRING)) AS cell_key,
    ST_GEOGFROMTEXT(FORMAT('POLYGON((%f %f, %f %f, %f %f, %f %f, %f %f))',
      lon_i * 0.25,       lat_i * 0.25,
      (lon_i + 1) * 0.25, lat_i * 0.25,
      (lon_i + 1) * 0.25, (lat_i + 1) * 0.25,
      lon_i * 0.25,       (lat_i + 1) * 0.25,
      lon_i * 0.25,       lat_i * 0.25)) AS cell
  FROM UNNEST(GENERATE_ARRAY(173, 197)) AS lat_i,
       UNNEST(GENERATE_ARRAY(-390, -358)) AS lon_i
),
spine AS (
  SELECT g.cell_key
  FROM grid AS g
  CROSS JOIN mn
  WHERE ST_INTERSECTS(g.cell, mn.state_geom)
),
top_species AS (
  SELECT specieskey AS top_key, COUNT(*) AS top_records
  FROM `fiery-monitor-508317-a8.p0_scratch.mn_occurrences`
  WHERE class = 'Amphibia' AND specieskey IS NOT NULL
  GROUP BY specieskey
  ORDER BY top_records DESC
  LIMIT 1
),
per_cell AS (
  SELECT
    CONCAT(CAST(CAST(FLOOR(o.decimallatitude / 0.25) AS INT64) AS STRING), '_',
           CAST(CAST(FLOOR(o.decimallongitude / 0.25) AS INT64) AS STRING)) AS cell_key,
    IF(o.year < 2015, 'before 2015', '2015 onward') AS period,
    COUNT(*) AS amph_records,
    COUNTIF(o.specieskey IS NULL OR o.specieskey != t.top_key) AS amph_records_after_reclass
  FROM `fiery-monitor-508317-a8.p0_scratch.mn_occurrences` AS o
  CROSS JOIN top_species AS t
  WHERE o.class = 'Amphibia' AND o.year IS NOT NULL
  GROUP BY cell_key, period
)
SELECT
  p                                                                        AS period,
  (SELECT top_key FROM top_species)                                        AS top_species_key,
  (SELECT top_records FROM top_species)                                    AS top_species_records,
  COUNTIF(IFNULL(c.amph_records, 0) < 5)                                   AS gap_cells_keep_class,
  COUNTIF(IFNULL(c.amph_records_after_reclass, 0) < 5)                     AS gap_cells_after_reclass,
  COUNTIF(IFNULL(c.amph_records, 0) >= 5
          AND IFNULL(c.amph_records_after_reclass, 0) < 5)                 AS cells_that_become_gaps
FROM spine AS s
CROSS JOIN UNNEST(['before 2015', '2015 onward']) AS p
LEFT JOIN per_cell AS c
  ON c.cell_key = s.cell_key AND c.period = p
GROUP BY p
ORDER BY p;


-- ---------------------------------------------------------------------
-- 9. Which taxon-key scheme does this snapshot use?
--    GBIF moved from integer backbone keys (e.g. 1427067) to alphanumeric
--    Catalogue of Life XR keys (e.g. Q2M4) in mid-2026. Expected: 0 legacy
--    integer keys if the 2026-10-02 snapshot is fully on the new scheme.
-- ---------------------------------------------------------------------
SELECT
  COUNT(DISTINCT specieskey)                                                         AS distinct_species_keys,
  COUNT(DISTINCT IF(REGEXP_CONTAINS(CAST(specieskey AS STRING), r'^[0-9]+$'), specieskey, NULL))  AS legacy_integer_keys,
  COUNT(DISTINCT IF(NOT REGEXP_CONTAINS(CAST(specieskey AS STRING), r'^[0-9]+$'), specieskey, NULL)) AS alphanumeric_keys
FROM `fiery-monitor-508317-a8.p0_scratch.mn_occurrences`
WHERE specieskey IS NOT NULL;
