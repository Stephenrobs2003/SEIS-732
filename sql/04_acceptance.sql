-- =====================================================================
-- P2 Step A: Acceptance checks on the implemented Curated path
-- Project: fiery-monitor-508317-a8   Processing location: US
-- Run after sql/03_curate.sql. Read-only. Run one at a time; save results.
-- =====================================================================


-- ---------------------------------------------------------------------
-- A1. Grain and relationships (P1 Risk 1)
--     Risk: a fact row fails to join a dimension (and drops out of counts),
--     or a repeated dimension key fans out the fact (and inflates counts).
--     Expected:
--       fact_rows = distinct_fact_gbifid             (one row per occurrence)
--       fact_rows = raw_rows - raw_rows_over_10km    (only the documented exclusion)
--       rows_after_joins = fact_rows                 (no fan-out)
--       unmatched_* = 0                              (every fact row joins)
--       dup_* = 0 and taxon_keys_with_multiple_classes = 0
-- ---------------------------------------------------------------------
WITH f AS (
  SELECT gbifid, cell_key, taxon_key, event_month_key, dataset_key
  FROM `fiery-monitor-508317-a8.cur.fct_occurrence`
),
joined AS (
  SELECT
    f.gbifid,
    c.cell_key        AS c_key,
    t.taxon_key       AS t_key,
    m.event_month_key AS m_key,
    d.dataset_key     AS d_key
  FROM f
  LEFT JOIN `fiery-monitor-508317-a8.cur.dim_grid_cell` AS c ON c.cell_key        = f.cell_key
  LEFT JOIN `fiery-monitor-508317-a8.cur.dim_taxon`     AS t ON t.taxon_key       = f.taxon_key
  LEFT JOIN `fiery-monitor-508317-a8.cur.dim_month`     AS m ON m.event_month_key = f.event_month_key
  LEFT JOIN `fiery-monitor-508317-a8.cur.dim_dataset`   AS d ON d.dataset_key     = f.dataset_key
)
SELECT
  (SELECT COUNT(*) FROM `fiery-monitor-508317-a8.raw.gbif_mn_occurrences`)            AS raw_rows,
  (SELECT COUNTIF(coordinateuncertaintyinmeters > 10000)
   FROM `fiery-monitor-508317-a8.raw.gbif_mn_occurrences`)                            AS raw_rows_over_10km,
  (SELECT COUNT(*) FROM f)                                                            AS fact_rows,
  (SELECT COUNT(DISTINCT gbifid) FROM f)                                              AS distinct_fact_gbifid,
  COUNT(*)                                                                            AS rows_after_joins,
  COUNTIF(c_key IS NULL)                                                              AS unmatched_cell,
  COUNTIF(t_key IS NULL)                                                              AS unmatched_taxon,
  COUNTIF(m_key IS NULL)                                                              AS unmatched_month,
  COUNTIF(d_key IS NULL)                                                              AS unmatched_dataset,
  (SELECT COUNT(*) - COUNT(DISTINCT cell_key)        FROM `fiery-monitor-508317-a8.cur.dim_grid_cell`) AS dup_cell_keys,
  (SELECT COUNT(*) - COUNT(DISTINCT taxon_key)       FROM `fiery-monitor-508317-a8.cur.dim_taxon`)     AS dup_taxon_keys,
  (SELECT COUNT(*) - COUNT(DISTINCT event_month_key) FROM `fiery-monitor-508317-a8.cur.dim_month`)     AS dup_month_keys,
  (SELECT COUNT(*) - COUNT(DISTINCT dataset_key)     FROM `fiery-monitor-508317-a8.cur.dim_dataset`)   AS dup_dataset_keys,
  (SELECT COUNTIF(n_class_values > 1)                FROM `fiery-monitor-508317-a8.cur.dim_taxon`)     AS taxon_keys_with_multiple_classes
FROM joined;


-- ---------------------------------------------------------------------
-- A2. Meaning of the audience result (P1 Risk 2): edge cells
--     Amphibians, 2015 onward. A cell is a "possible gap" if it has no
--     records or is in the lowest quartile of cells that have records.
--     Compares the count-based rule with the area-adjusted (density) rule.
--     Expected:
--       sum_records_in_spine = amphibian_fact_records  (no records outside the spine)
--       edge share of gap cells is LOWER under the density rule than the count rule
--       (P1 sample: 26.7% of count-rule gaps were edge cells)
-- ---------------------------------------------------------------------
WITH amph AS (
  SELECT f.cell_key, COUNT(*) AS records
  FROM `fiery-monitor-508317-a8.cur.fct_occurrence` AS f
  JOIN `fiery-monitor-508317-a8.cur.dim_taxon` AS t ON t.taxon_key       = f.taxon_key
  JOIN `fiery-monitor-508317-a8.cur.dim_month` AS m ON m.event_month_key = f.event_month_key
  WHERE t.class = 'Amphibia' AND m.period = '2015 onward'
  GROUP BY f.cell_key
),
cells AS (
  SELECT
    c.cell_key,
    c.is_edge_cell,
    IFNULL(a.records, 0)                                   AS records,
    SAFE_DIVIDE(IFNULL(a.records, 0), c.in_state_area_km2) AS density
  FROM `fiery-monitor-508317-a8.cur.dim_grid_cell` AS c
  LEFT JOIN amph AS a ON a.cell_key = c.cell_key
),
q AS (
  SELECT
    APPROX_QUANTILES(records, 4)[OFFSET(1)] AS q25_records,
    APPROX_QUANTILES(density, 4)[OFFSET(1)] AS q25_density
  FROM cells
  WHERE records > 0
),
flagged AS (
  SELECT
    cells.*,
    (records = 0 OR records <= q.q25_records) AS gap_count_rule,
    (records = 0 OR density <= q.q25_density) AS gap_density_rule
  FROM cells CROSS JOIN q
)
SELECT
  (SELECT SUM(records) FROM amph)                                            AS amphibian_fact_records,
  SUM(records)                                                               AS sum_records_in_spine,
  COUNT(*)                                                                   AS in_state_cells,
  COUNTIF(is_edge_cell)                                                      AS edge_cells,
  COUNTIF(records = 0)                                                       AS zero_record_cells,
  COUNTIF(gap_count_rule)                                                    AS gaps_count_rule,
  COUNTIF(gap_count_rule AND is_edge_cell)                                   AS gaps_count_rule_on_edge,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(gap_count_rule AND is_edge_cell),
                          COUNTIF(gap_count_rule)), 1)                       AS pct_edge_count_rule,
  COUNTIF(gap_density_rule)                                                  AS gaps_density_rule,
  COUNTIF(gap_density_rule AND is_edge_cell)                                 AS gaps_density_rule_on_edge,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(gap_density_rule AND is_edge_cell),
                          COUNTIF(gap_density_rule)), 1)                     AS pct_edge_density_rule,
  COUNTIF(gap_count_rule != gap_density_rule)                                AS cells_flag_changed
FROM flagged;


-- ---------------------------------------------------------------------
-- A3. Additional source case (P1 Risk 4): the same sighting published by
--     more than one dataset (e.g., eBird and iNaturalist).
--     Raw has no day or observer, so exact duplicates cannot be proven.
--     Bounds: within each species x cell x year-month group,
--       upper = all records as published
--       lower = the largest single-dataset count (as if every record from
--               other datasets were a copy)
--     The true count lies between them. If the gap flags agree under both,
--     double counting does not change the audience result.
-- ---------------------------------------------------------------------
WITH g AS (
  SELECT t.class, f.cell_key, f.taxon_key, f.event_month_key, f.dataset_key, COUNT(*) AS n
  FROM `fiery-monitor-508317-a8.cur.fct_occurrence` AS f
  JOIN `fiery-monitor-508317-a8.cur.dim_taxon` AS t ON t.taxon_key       = f.taxon_key
  JOIN `fiery-monitor-508317-a8.cur.dim_month` AS m ON m.event_month_key = f.event_month_key
  WHERE t.class IN ('Aves', 'Amphibia', 'Reptilia')
    AND t.is_species_resolved
    AND m.period = '2015 onward'
  GROUP BY t.class, f.cell_key, f.taxon_key, f.event_month_key, f.dataset_key
),
grp AS (
  SELECT class, cell_key, taxon_key, event_month_key,
         SUM(n) AS upper_n, MAX(n) AS lower_n, COUNT(*) AS datasets
  FROM g
  GROUP BY class, cell_key, taxon_key, event_month_key
),
per_cell AS (
  SELECT class, cell_key, SUM(upper_n) AS upper_n, SUM(lower_n) AS lower_n
  FROM grp
  GROUP BY class, cell_key
),
cells AS (
  SELECT k.class, c.cell_key, c.in_state_area_km2 AS area,
         IFNULL(p.upper_n, 0) AS upper_n,
         IFNULL(p.lower_n, 0) AS lower_n
  FROM `fiery-monitor-508317-a8.cur.dim_grid_cell` AS c
  CROSS JOIN (SELECT class FROM UNNEST(['Aves', 'Amphibia', 'Reptilia']) AS class) AS k
  LEFT JOIN per_cell AS p ON p.class = k.class AND p.cell_key = c.cell_key
),
q AS (
  SELECT class,
         APPROX_QUANTILES(SAFE_DIVIDE(upper_n, area), 4)[OFFSET(1)] AS q_upper,
         APPROX_QUANTILES(SAFE_DIVIDE(lower_n, area), 4)[OFFSET(1)] AS q_lower
  FROM cells
  WHERE upper_n > 0
  GROUP BY class
),
multi AS (
  SELECT class,
         COUNT(*)                                AS groups,
         COUNTIF(datasets > 1)                   AS multi_dataset_groups,
         SUM(IF(datasets > 1, upper_n, 0))       AS records_in_multi_dataset_groups
  FROM grp
  GROUP BY class
),
flagged AS (
  SELECT cells.class, upper_n, lower_n,
         (upper_n = 0 OR SAFE_DIVIDE(upper_n, area) <= q.q_upper) AS gap_upper,
         (lower_n = 0 OR SAFE_DIVIDE(lower_n, area) <= q.q_lower) AS gap_lower
  FROM cells JOIN q ON q.class = cells.class
)
SELECT
  flagged.class,
  ANY_VALUE(multi.groups)                                        AS species_cell_month_groups,
  ANY_VALUE(multi.multi_dataset_groups)                          AS multi_dataset_groups,
  SUM(upper_n)                                                   AS records_as_published,
  SUM(lower_n)                                                   AS records_lower_bound,
  ROUND(100 * (1 - SAFE_DIVIDE(SUM(lower_n), SUM(upper_n))), 1)  AS max_pct_possible_copies,
  COUNTIF(gap_upper)                                             AS gaps_as_published,
  COUNTIF(gap_lower)                                             AS gaps_lower_bound,
  COUNTIF(gap_upper != gap_lower)                                AS cells_flag_changed
FROM flagged
JOIN multi ON multi.class = flagged.class
GROUP BY flagged.class
ORDER BY flagged.class;
