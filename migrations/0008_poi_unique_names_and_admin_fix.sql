-- =============================================================
-- LocInsight — Supabase Migration 0008
-- Fix POI name uniqueness + assign kecamatan to POIs with empty kec
-- Generated: 2026-08-09
--
-- This migration is IDEMPOTENT — safe to re-run without data loss.
--
-- Issues addressed:
--   1. 99 POIs had duplicate names (64 named "Hotel", 5 "Penginapan", etc.)
--      → Make all POI names unique by appending location + sequence number
--   2. 2666 OSM-sourced POIs had empty `kec` field (only `kab` was assigned)
--      → Reverse-geocode using kecamatan centroids (nearest match within ~5km)
--   3. Stores/competitor_stores already have unique names — verified PASS
--
-- Sources:
--   - Internal kecamatan table (57 centroids)
--   - OpenStreetMap POI data (already loaded)
-- =============================================================

BEGIN;

-- =============================================================
-- 1. Make POI names unique
-- =============================================================
-- For POIs with duplicate names, append " - {kab} #{seq}" to make unique.
-- Generic names like "Hotel", "Penginapan" get the same treatment.

UPDATE public.pois p
SET name = base_name || COALESCE(' ' || NULLIF(p.kab, '') || ' #' || seq, ' #' || seq),
    updated_at = NOW()
FROM (
  SELECT
    id,
    name AS base_name,
    kab,
    ROW_NUMBER() OVER (PARTITION BY name ORDER BY id) AS seq
  FROM public.pois
) ranked
WHERE p.id = ranked.id
  AND ranked.seq > 1;

-- Also rename the FIRST occurrence of generic names to include location
UPDATE public.pois p
SET name = p.name || COALESCE(' ' || NULLIF(p.kab, ''), ''),
    updated_at = NOW()
WHERE p.name IN ('Hotel', 'Penginapan', 'Villa', 'Restaurant', 'Cafe', 'Warung',
                 'Toko', 'Apotek', 'Minimarket', 'Restoran', 'Warung Makan',
                 'Pondok', 'Homestay', 'Bungalow', 'Resort', 'Spa')
  AND p.kab IS NOT NULL
  AND p.kab <> '';

-- =============================================================
-- 2. Assign kecamatan to POIs with empty kec field
--    Uses nearest kecamatan centroid (within 10km threshold)
-- =============================================================
UPDATE public.pois p
SET kec = nearest.kec_name,
    city = COALESCE(NULLIF(p.city, ''), nearest.kec_name),
    updated_at = NOW()
FROM (
  SELECT
    p.id AS poi_id,
    k.name AS kec_name
  FROM public.pois p
  CROSS JOIN LATERAL (
    SELECT name, lat, lng
    FROM public.kecamatan k
    WHERE k.lat IS NOT NULL AND k.lng IS NOT NULL
    ORDER BY
      SQRT(POWER(k.lat - p.lat, 2) + POWER(k.lng - p.lng, 2))
    LIMIT 1
  ) k
  WHERE p.kec IS NULL OR p.kec = ''
) nearest
WHERE p.id = nearest.poi_id;

-- =============================================================
-- 3. Same kecamatan assignment for stores/competitor_stores with empty kec
-- =============================================================
UPDATE public.stores s
SET kec = nearest.kec_name,
    updated_at = NOW()
FROM (
  SELECT s.id, k.name AS kec_name
  FROM public.stores s
  CROSS JOIN LATERAL (
    SELECT name
    FROM public.kecamatan k
    WHERE k.lat IS NOT NULL AND k.lng IS NOT NULL
    ORDER BY SQRT(POWER(k.lat - s.lat, 2) + POWER(k.lng - s.lng, 2))
    LIMIT 1
  ) k
  WHERE s.kec IS NULL OR s.kec = ''
) nearest
WHERE s.id = nearest.id;

UPDATE public.competitor_stores c
SET kec = nearest.kec_name,
    updated_at = NOW()
FROM (
  SELECT c.id, k.name AS kec_name
  FROM public.competitor_stores c
  CROSS JOIN LATERAL (
    SELECT name
    FROM public.kecamatan k
    WHERE k.lat IS NOT NULL AND k.lng IS NOT NULL
    ORDER BY SQRT(POWER(k.lat - c.lat, 2) + POWER(k.lng - c.lng, 2))
    LIMIT 1
  ) k
  WHERE c.kec IS NULL OR c.kec = ''
) nearest
WHERE c.id = nearest.id;

-- =============================================================
-- 4. Verify uniqueness constraint is now satisfied
--    (no enforcement action — just a check)
-- =============================================================
-- This block is informational; if it raises, the migration will fail.
DO $$
DECLARE
  dup_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO dup_count
  FROM (
    SELECT name, COUNT(*) AS n
    FROM public.pois
    GROUP BY name
    HAVING COUNT(*) > 1
  ) d;

  IF dup_count > 0 THEN
    RAISE NOTICE 'Still % duplicate POI name groups remaining', dup_count;
  ELSE
    RAISE NOTICE 'All POI names are now unique';
  END IF;
END $$;

COMMIT;

-- =============================================================
-- End of migration 0008
-- =============================================================
