-- =====================================================================
-- P3 Step S: Curated -> Serving  (Minnesota Wildlife Survey Gap Finder)
-- Project: fiery-monitor-508317-a8   Processing location: US
-- Input:  cur.fct_occurrence, cur.dim_taxon, cur.dim_month, cur.dim_grid_cell
-- Output: srv.cell_class_period_density (small table, 482 x 3 x 2 = 2,892 rows)
--
-- Users: survey coordinators in a state nongame wildlife program.
-- Question: for a chosen animal class and period, which 0.25-degree cells in
-- Minnesota have few or no occurrence records (possible survey gaps)?
-- One row = one grid cell x class x period, with its recording density and
-- possible-gap flag. Run one statement at a time.
-- =====================================================================

-- S0. Dataset for Serving (no cost)
CREATE SCHEMA IF NOT EXISTS `fiery-monitor-508317-a8.srv` OPTIONS (location = 'US');


-- S1. Serving table. Replaces srv.cell_class_period_density.
--     Rules (from P1/P2):
--       * every in-state cell appears for every class and period (zeros kept);
--       * records_per_100km2 = record_count / in-state area x 100 (area-adjusted);
--       * gap threshold = exact 25th percentile (PERCENTILE_DISC) of
--         records_per_100km2 among cells WITH records, per class and period;
--       * possible_gap = no records, or density <= threshold;
--       * is_edge_cell is shown so a coordinator can see edge gaps (P2 check A2).
CREATE OR REPLACE TABLE `fiery-monitor-508317-a8.srv.cell_class_period_density` AS
WITH occ AS (
  SELECT f.cell_key, t.class, m.period, f.taxon_key, t.is_species_resolved
  FROM `fiery-monitor-508317-a8.cur.fct_occurrence` AS f
  JOIN `fiery-monitor-508317-a8.cur.dim_taxon` AS t ON t.taxon_key       = f.taxon_key
  JOIN `fiery-monitor-508317-a8.cur.dim_month` AS m ON m.event_month_key = f.event_month_key
  WHERE t.class  IN ('Aves', 'Amphibia', 'Reptilia')
    AND m.period IN ('before 2015', '2015 onward')
),
agg AS (
  SELECT cell_key, class, period,
         COUNT(*)                                             AS record_count,
         COUNT(DISTINCT IF(is_species_resolved, taxon_key, NULL)) AS distinct_species
  FROM occ
  GROUP BY cell_key, class, period
),
spine AS (
  SELECT g.cell_key, g.min_lat, g.min_lon, g.in_state_area_km2, g.is_edge_cell, class, period
  FROM `fiery-monitor-508317-a8.cur.dim_grid_cell` AS g
  CROSS JOIN UNNEST(['Aves', 'Amphibia', 'Reptilia'])   AS class
  CROSS JOIN UNNEST(['before 2015', '2015 onward'])     AS period
),
dens AS (
  SELECT
    s.cell_key, s.class, s.period, s.min_lat, s.min_lon, s.in_state_area_km2, s.is_edge_cell,
    IFNULL(a.record_count, 0)                         AS record_count,
    IFNULL(a.distinct_species, 0)                     AS distinct_species,
    IFNULL(a.record_count, 0) * 100 / s.in_state_area_km2 AS records_per_100km2
  FROM spine AS s
  LEFT JOIN agg AS a
    ON a.cell_key = s.cell_key AND a.class = s.class AND a.period = s.period
),
thr AS (
  SELECT DISTINCT class, period,
         PERCENTILE_DISC(records_per_100km2, 0.25) OVER (PARTITION BY class, period) AS gap_threshold_per_100km2
  FROM dens
  WHERE record_count > 0
)
SELECT
  d.cell_key,
  d.class,
  d.period,
  d.min_lat,
  d.min_lon,
  d.in_state_area_km2,
  d.is_edge_cell,
  d.record_count,
  d.distinct_species,
  d.records_per_100km2,
  t.gap_threshold_per_100km2,
  (d.record_count = 0 OR d.records_per_100km2 <= t.gap_threshold_per_100km2) AS possible_gap,
  CASE
    WHEN d.record_count = 0                                THEN 'no records'
    WHEN d.records_per_100km2 <= t.gap_threshold_per_100km2 THEN 'lowest quartile of recorded cells'
  END AS gap_reason
FROM dens AS d
LEFT JOIN thr AS t ON t.class = d.class AND t.period = d.period;


-- S2. Serving summary for the build note (read-only). Save this result.
SELECT
  class,
  period,
  COUNT(*)                                   AS cells,
  COUNTIF(record_count > 0)                  AS cells_with_records,
  SUM(record_count)                          AS records,
  ANY_VALUE(gap_threshold_per_100km2)        AS gap_threshold_per_100km2,
  COUNTIF(possible_gap)                      AS possible_gap_cells,
  COUNTIF(gap_reason = 'no records')         AS gap_no_records,
  COUNTIF(possible_gap AND is_edge_cell)     AS gap_cells_on_edge
FROM `fiery-monitor-508317-a8.srv.cell_class_period_density`
GROUP BY class, period
ORDER BY class, period;
