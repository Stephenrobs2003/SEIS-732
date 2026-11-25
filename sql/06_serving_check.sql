-- =====================================================================
-- P3 Part 2: Check one Serving number against an independent calculation
-- Number checked: possible_gap_cells for Amphibia, '2015 onward'
--   (how many cells a coordinator would see flagged as possible gaps).
--
-- The EXPECTED value is calculated from RAW, not from the Curated fact,
-- taxon or month tables, and not from Serving. It re-applies the published
-- rules by a different method:
--   * class and period taken directly from raw `class` and `year`;
--   * the >10 km exclusion re-applied to raw coordinate uncertainty;
--   * the 25th-percentile threshold found by ranking rows (ROW_NUMBER),
--     not with PERCENTILE_DISC.
-- Only the boundary-derived cell areas come from cur.dim_grid_cell.
-- The OBSERVED value is read from srv.cell_class_period_density.
-- Read-only. Reads ~1-2 GB of raw.
-- =====================================================================
WITH r AS (
  SELECT
    CONCAT(CAST(CAST(FLOOR(decimallatitude  / 0.25) AS INT64) AS STRING), '_',
           CAST(CAST(FLOOR(decimallongitude / 0.25) AS INT64) AS STRING)) AS cell_key
  FROM `fiery-monitor-508317-a8.raw.gbif_mn_occurrences`
  WHERE class = 'Amphibia'
    AND year >= 2015
    AND (coordinateuncertaintyinmeters IS NULL OR coordinateuncertaintyinmeters <= 10000)
),
per_cell AS (
  SELECT cell_key, COUNT(*) AS n FROM r GROUP BY cell_key
),
cells AS (
  SELECT g.cell_key,
         IFNULL(p.n, 0)                          AS n,
         IFNULL(p.n, 0) * 100 / g.in_state_area_km2 AS density
  FROM `fiery-monitor-508317-a8.cur.dim_grid_cell` AS g
  LEFT JOIN per_cell AS p ON p.cell_key = g.cell_key
),
ranked AS (
  SELECT density,
         ROW_NUMBER() OVER (ORDER BY density) AS rn,
         COUNT(*) OVER ()                     AS cnt
  FROM cells
  WHERE n > 0
),
thr AS (
  SELECT density AS q25 FROM ranked WHERE rn = CAST(CEIL(0.25 * cnt) AS INT64)
),
expected AS (
  SELECT
    (SELECT SUM(n) FROM per_cell)                                              AS records,
    (SELECT COUNT(*) FROM per_cell
     WHERE cell_key NOT IN (SELECT cell_key FROM `fiery-monitor-508317-a8.cur.dim_grid_cell`)) AS raw_cells_outside_spine,
    ANY_VALUE(thr.q25)                                                         AS threshold,
    COUNTIF(cells.n = 0 OR cells.density <= thr.q25)                           AS gap_cells
  FROM cells CROSS JOIN thr
),
observed AS (
  SELECT
    SUM(record_count)                   AS records,
    ANY_VALUE(gap_threshold_per_100km2) AS threshold,
    COUNTIF(possible_gap)               AS gap_cells
  FROM `fiery-monitor-508317-a8.srv.cell_class_period_density`
  WHERE class = 'Amphibia' AND period = '2015 onward'
)
SELECT
  e.gap_cells   AS expected_gap_cells,
  o.gap_cells   AS observed_gap_cells,
  e.gap_cells = o.gap_cells AS gap_cells_match,
  e.records     AS expected_records,
  o.records     AS observed_records,
  e.threshold   AS expected_threshold,
  o.threshold   AS observed_threshold,
  e.raw_cells_outside_spine
FROM expected AS e CROSS JOIN observed AS o;
