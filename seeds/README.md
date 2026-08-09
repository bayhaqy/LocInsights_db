# LocInsights DB — Seed Data

This directory contains the **authoritative source-of-truth data** for the LocInsights database. Each JSON file maps 1:1 to a Postgres table and is loaded by migration `0007_real_data_replace.sql`.

## Files

| File | Table | Rows | Source | Last Updated |
|---|---|---:|---|---|
| `01_countries.json` | `countries` | 1 | ISO 3166 | 2026-08-09 |
| `02_provinces.json` | `provinces` | 1 | BPS Bali 2025 | 2026-08-09 |
| `03_kabupaten.json` | `kabupaten` | 9 | BPS Bali Dalam Angka 2025 | 2026-08-09 |
| `04_kecamatan.json` | `kecamatan` | 57 | BPS Provinsi Bali 2024 | 2026-08-09 |
| `05_villages.json` | `kelurahan` | 716 | OSM Overpass + Wikipedia + BPS cross-check | 2026-08-09 |
| `06_brands.json` | `brands` | 94 | map.co.id + mapactive.id | 2026-08-09 |
| `07_malls.json` | `malls` | 20 | nowbali.co.id + traveloka.com | 2026-08-09 |
| `08_stores.json` | `stores` | 136 | OpenStreetMap + map.co.id | 2026-08-09 |
| `09_pois.json` | `pois` | 2,708 | OpenStreetMap + Google Maps POI | 2026-08-09 |
| `10_competitors.json` | `competitor_stores` | 887 | OpenStreetMap | 2026-08-09 |

## Migration

Apply with:

```bash
psql "$DATABASE_URL" -f migrations/0007_real_data_replace.sql
```

**The migration is IDEMPOTENT** — safe to re-run unlimited times. It uses:

- `INSERT ... ON CONFLICT (id) DO UPDATE SET ...` (UPSERT) for all tables except `kelurahan`
- `TRUNCATE TABLE public.kelurahan RESTART IDENTITY CASCADE` followed by fresh `INSERT` (no FKs reference `kelurahan`, so this is safe)
- `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` for new columns

Re-running preserves all data because UPSERT updates existing rows in place rather than deleting them.

## Village Data (Special Case)

The `kelurahan` table was renamed conceptually to hold **both** kelurahan (urban villages, 80) and desa (rural villages, 636) — totaling **716 villages** matching BPS Bali 2025 exactly.

Each village record has:

- `id` / `code`: 10-digit KEMENDAGRI code (e.g., `5101011006` from `51.01.01.1006`)
- `vill_type`: `'kelurahan'` or `'desa'`
- `osm_id`: OpenStreetMap relation ID
- `ref_kemendagri`: Original KEMENDAGRI code with dots (e.g., `51.01.01.1006`)
- `kec_code`: 7-digit kecamatan code (FK to `kecamatan.code`)
- `kab_code`: 4-digit kabupaten code (FK to `kabupaten.code`)

**Disambiguation note:** Two KEMENDAGRI codes were duplicated in the OSM source data (likely OSM mapping errors). These are disambiguated by appending `_osm_id` to the village ID:

- `51.01.04.2004` (2 villages in Melaya, Jembrana) → IDs `5101042004` + `5101042004_20447602`
- `51.02.09.2002` (3 villages in Baturiti, Tabanan) → IDs `5102092002` + `5102092002_20447369` + `5102092002_20447374`

## Store / Competitor Unique Names

Every store and competitor has a **unique outlet name** following the pattern:

- Mall stores: `{brand} {mall_name}` (e.g., `Starbucks Living World Denpasar`)
- Standalone stores with address: `{brand} {street_area}` (e.g., `Subway Seminyak`)
- Other stores: `{brand} {kecamatan}` (e.g., `Adidas Kuta`)
- Competitors: `{brand} {kecamatan} {kabupaten}` (e.g., `Indomaret Kuta Badung`)

When multiple stores of the same brand exist in the same area, a `#N` suffix is appended (e.g., `Starbucks Denpasar Barat #2`, `Alfamart Kuta Badung #38`).

All 136 store names are unique. All 887 competitor names are unique.

## Regenerating the Migration

If you update any JSON file, regenerate the SQL migration:

```bash
python3 /home/z/my-project/scripts/generate_migration_sql.py
```

This script reads all 10 JSON files and emits `migrations/0007_real_data_replace.sql` (≈940 KB, 4,722 lines).

## Synchronization Status (Aug 2026)

| Layer | Synthetic (Before) | Real (After) | Source |
|---|---:|---:|---|
| Countries | 0 | 1 | ✓ ISO 3166 |
| Provinces | 1 (Bali) | 1 (Bali, BPS 2025 pop) | ✓ BPS Bali Dalam Angka 2025 |
| Kabupaten | 9 (codes 5101-5109) | 9 (codes 5101-5108, 5171) | ✓ BPS 2025 with correct KEMENDAGRI codes |
| Kecamatan | 48 | 57 | ✓ BPS 2024 |
| Kelurahan/Desa | 161 synthetic | 716 real (80 kel + 636 desa) | ✓ OSM + Wikipedia + BPS cross-check |
| Brands | 94 | 94 | ✓ map.co.id + mapactive.id |
| Malls | 20 | 20 | ✓ nowbali.co.id + traveloka.com |
| Stores | 136 (generic names) | 136 (unique outlet names) | ✓ OpenStreetMap + map.co.id |
| POIs | 2,708 | 2,708 | ✓ OpenStreetMap + Google Maps POI |
| Competitors | 887 (generic names) | 887 (unique outlet names) | ✓ OpenStreetMap |

**Bali total population (sum of 9 kabupaten):** 4,375,763 ✓ matches BPS 2025
