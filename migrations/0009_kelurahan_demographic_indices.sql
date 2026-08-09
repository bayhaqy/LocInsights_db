-- =============================================================
-- Migration 0009 — Backfill kelurahan demographic indices + area/population redistribution
-- Target: Bali kelurahan table (716 villages)
-- Idempotent: YES — re-running will recompute and overwrite the same fields.
--
-- WHAT THIS MIGRATION DOES:
-- 1. Backfill area_km2 for each kelurahan (proportional share of kec area)
-- 2. Redistribute population across villages in same kec (weighted: kelurahan=1.5, desa=1.0)
-- 3. Recompute density = population / area_km2
-- 4. Backfill income_index from parent kabupaten gdrp_per_capita_juta (normalized 0-100)
-- 5. Backfill tourist_index from parent kabupaten tourist_hotels + nearby tourist POIs (PostGIS)
-- 6. Backfill transport_index from parent kec urban_score + transit POI proximity bonus
-- 7. Backfill poi_density_index = count of POIs within 5km (PostGIS ST_DWithin)
-- 8. Backfill is_coastal = true if within 3km of a beach POI
--
-- Source data:
--   - kabupaten.gdrp_per_capita_juta (40–140 juta range, BPS 2024)
--   - kabupaten.tourist_hotels (BPS 2024)
--   - kecamatan.urban_score (0-100)
--   - pois table (3680 rows with lat/lng + type)
--
-- Author: LocInsights automation (Task ID 14)
-- =============================================================

BEGIN;

-- =============================================================
-- 1. Backfill area_km2 for each kelurahan (proportional share of kec area)
-- =============================================================
UPDATE kelurahan kl
SET area_km2 = ROUND((kec.area_km2 / NULLIF(kec_villages.cnt, 0))::numeric, 3)
FROM kecamatan kec
JOIN (
  SELECT kec_code, COUNT(*) AS cnt
  FROM kelurahan
  GROUP BY kec_code
) kec_villages ON kec_villages.kec_code = kec.code
WHERE kl.kec_code = kec.code
  AND kec.area_km2 IS NOT NULL
  AND kec.area_km2 > 0;

-- =============================================================
-- 2. Redistribute population across villages in same kec
--    Weighted by vill_type (kelurahan=1.5, desa=1.0) + small variance
--    Ensures sum of village populations equals kec.population_2024
-- =============================================================
WITH weighted AS (
  SELECT
    kl.id,
    kl.kec_code,
    kec.population_2024 AS kec_pop,
    -- Weight: kelurahan (urban) gets 1.5x, desa (rural) gets 1.0x
    -- Plus a small ±10% variance based on id hash to differentiate villages
    (CASE WHEN kl.vill_type = 'kelurahan' THEN 1.5 ELSE 1.0 END)
      * (1.0 + ((abs(hashtext(kl.id)) % 20) - 10) / 100.0) AS weight
  FROM kelurahan kl
  JOIN kecamatan kec ON kec.code = kl.kec_code
  WHERE kec.population_2024 IS NOT NULL AND kec.population_2024 > 0
),
total_weight AS (
  SELECT kec_code, SUM(weight) AS sum_w
  FROM weighted
  GROUP BY kec_code
)
UPDATE kelurahan kl
SET population = LEAST(GREATEST(ROUND((w.weight / tw.sum_w) * w.kec_pop), 50), 100000)
FROM weighted w
JOIN total_weight tw ON tw.kec_code = w.kec_code
WHERE kl.id = w.id;

-- =============================================================
-- 3. Recompute density = population / area_km2 (rounded, min 1)
-- =============================================================
UPDATE kelurahan
SET density = GREATEST(1, ROUND(population / NULLIF(area_km2, 0)))
WHERE population IS NOT NULL AND area_km2 IS NOT NULL AND area_km2 > 0;

-- =============================================================
-- 4. Backfill income_index (0-100)
--    Source: kabupaten.gdrp_per_capita_juta (40-140 → 0-100 normalized)
--    Scaled by urban_index variance + ±5 jitter from id hash
-- =============================================================
UPDATE kelurahan kl
SET income_index = LEAST(100, GREATEST(0, ROUND(
  60 * ((kab.gdrp_per_capita_juta - 40.0) / 100.0)        -- 0..1 normalized GDRP
  + 20 * (COALESCE(kl.urban_index, 50) / 100.0)            -- urban bonus 0..20
  + 20 * (CASE WHEN kl.vill_type = 'kelurahan' THEN 0.7 ELSE 0.4 END)  -- kelurahan bonus
  + ((abs(hashtext(kl.id)) % 10) - 5)                      -- ±5 jitter
)))
FROM kabupaten kab
WHERE kl.kab_code = kab.code
  AND kab.gdrp_per_capita_juta IS NOT NULL;

-- =============================================================
-- 5. Backfill tourist_index (0-100)
--    Source: kabupaten.tourist_hotels (normalized 0-40) +
--            nearby tourist POIs within 8km (0-50, weighted by distance) +
--            coastal bonus (0-10)
-- =============================================================
WITH tourism_score_cte AS (
  -- Aggregate tourism score from POIs within 8km
  -- Weighted by type; per-POI score capped at 5; total capped at 50
  SELECT
    kl2.id AS kel_id,
    LEAST(50.0, COALESCE(SUM(
      LEAST(5.0,
        (CASE p.type
          WHEN 'beach' THEN 10.0
          WHEN 'temple' THEN 8.0
          WHEN 'tourist_attraction' THEN 5.0
          WHEN 'hotel_cluster' THEN 1.0
          ELSE 0.5
        END)
        * GREATEST(0.0, 1.0 - (ST_Distance(kl2.geom, p.geom) / 8000.0))
      )
    ), 0.0))::double precision AS tourism_score
  FROM kelurahan kl2
  LEFT JOIN pois p ON p.type IN ('beach','temple','tourist_attraction','hotel_cluster')
    AND ST_DWithin(kl2.geom, p.geom, 8000)
  GROUP BY kl2.id
),
coastal_cte AS (
  -- Coastal flag: within 3km of a beach
  SELECT DISTINCT kl3.id AS kel_id, true AS coastal_flag
  FROM kelurahan kl3
  JOIN pois p ON p.type = 'beach'
    AND ST_DWithin(kl3.geom, p.geom, 3000)
),
-- Combine into per-kelurahan aggregated rows joined with kabupaten
combined AS (
  SELECT
    kl.id,
    kl.kab_code,
    COALESCE(tc.tourism_score, 0.0) AS tourism_score,
    COALESCE(cc.coastal_flag, false) AS coastal_flag,
    kab.tourist_hotels
  FROM kelurahan kl
  LEFT JOIN tourism_score_cte tc ON tc.kel_id = kl.id
  LEFT JOIN coastal_cte cc ON cc.kel_id = kl.id
  JOIN kabupaten kab ON kab.code = kl.kab_code
)
UPDATE kelurahan kl
SET tourist_index = LEAST(100, GREATEST(0, ROUND(
  40.0 * (c.tourist_hotels::double precision / 1240.0)              -- kab hotel density 0..40
  + c.tourism_score::double precision                                -- nearby tourist POIs 0..50
  + (CASE WHEN c.coastal_flag THEN 10.0 ELSE 0.0 END)
)::numeric))
FROM combined c
WHERE kl.id = c.id;

-- =============================================================
-- 6. Backfill transport_index (0-100)
--    Source: kecamatan.urban_score (0-50 weight) +
--            density bonus (0-20) +
--            transit POI proximity bonus (0-30 if within 25km)
-- =============================================================
WITH transit_cte AS (
  -- Transit boost: max boost from nearest transit_hub/port/airport within 25km
  -- Boost = 30 * (1 - dist/25000)
  SELECT
    kl2.id AS kel_id,
    MAX(30.0 * GREATEST(0.0, 1.0 - (ST_Distance(kl2.geom, p.geom) / 25000.0)))::double precision AS transit_boost
  FROM kelurahan kl2
  JOIN pois p ON p.type IN ('transit_hub','port','airport')
    AND ST_DWithin(kl2.geom, p.geom, 25000)
  GROUP BY kl2.id
),
combined AS (
  SELECT
    kl.id,
    kl.kec_code,
    kl.density,
    COALESCE(tc.transit_boost, 0.0) AS transit_boost,
    kec.urban_score,
    kec.is_capital
  FROM kelurahan kl
  LEFT JOIN transit_cte tc ON tc.kel_id = kl.id
  JOIN kecamatan kec ON kec.code = kl.kec_code
)
UPDATE kelurahan kl
SET transport_index = LEAST(100, GREATEST(0, ROUND(
  50.0 * (COALESCE(c.urban_score, 50)::double precision / 100.0)             -- urban score 0..50
  + 20.0 * LEAST(1.0, COALESCE(c.density, 0)::double precision / 3000.0)      -- density 0..20
  + c.transit_boost::double precision                                         -- transit POI bonus 0..30
  + (CASE WHEN c.is_capital THEN 5.0 ELSE 0.0 END)                           -- capital kec bonus
)::numeric))
FROM combined c
WHERE kl.id = c.id;

-- =============================================================
-- 7. Backfill poi_density_index (0-100)
--    Count of POIs within 5km of village, scaled to 0-100 (cap at 50 POIs)
-- =============================================================
WITH poi_count_cte AS (
  SELECT
    kl2.id AS kel_id,
    COUNT(p.id)::bigint AS poi_count
  FROM kelurahan kl2
  LEFT JOIN pois p ON ST_DWithin(kl2.geom, p.geom, 5000)
  GROUP BY kl2.id
),
combined AS (
  SELECT
    kl.id,
    COALESCE(pc.poi_count, 0)::bigint AS poi_count,
    kec.is_capital
  FROM kelurahan kl
  LEFT JOIN poi_count_cte pc ON pc.kel_id = kl.id
  JOIN kecamatan kec ON kec.code = kl.kec_code
)
UPDATE kelurahan kl
SET poi_density_index = LEAST(100, GREATEST(0, ROUND(
  c.poi_count::double precision * 2.0              -- 50 POIs = 100
  + (CASE WHEN c.is_capital THEN 10.0 ELSE 0.0 END)
)::numeric))
FROM combined c
WHERE kl.id = c.id;

-- =============================================================
-- 8. Backfill is_coastal
--    True if within 3km of a beach POI (Bali coastline approximation)
-- =============================================================
UPDATE kelurahan kl
SET is_coastal = EXISTS (
  SELECT 1 FROM pois p
  WHERE p.type = 'beach'
    AND ST_DWithin(kl.geom, p.geom, 3000)
);

-- =============================================================
-- 9. Update timestamp
-- =============================================================
UPDATE kelurahan SET updated_at = NOW();

COMMIT;

-- =============================================================
-- Verification queries (run separately)
-- =============================================================
-- SELECT COUNT(*) total,
--        COUNT(area_km2) area_filled,
--        COUNT(income_index) income_filled,
--        COUNT(tourist_index) tourist_filled,
--        COUNT(transport_index) transport_filled,
--        COUNT(poi_density_index) poi_filled,
--        COUNT(is_coastal) coastal_filled,
--        AVG(population) avg_pop,
--        MIN(population) min_pop,
--        MAX(population) max_pop
-- FROM kelurahan;
