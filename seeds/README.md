# Seeds

This folder holds CSV exports of master data, useful for:
- Re-seeding a fresh Supabase project
- Bulk-loading data into a local Postgres instance
- Auditing what data was loaded at a given point in time

## Files

| File | Rows | Source |
|---|---|---|
| `brands.csv` | 27 | MAA/MAP portfolio (public brand directory) |
| `malls.csv` | 18 | nowbali.co.id + traveloka.com (Aug 2026) |
| `pois.csv` | 25 | Google Maps POI + OSM + Bali Tourism Board |
| `kabupaten.csv` | 9 | BPS Bali 2024 |
| `kecamatan.csv` | 48 | BPS Bali 2024 |
| `kelurahan.csv` | 172 | BPS Bali 2024 + Atlas Bali 2023 (centroids WGS84) |
| `stores.csv` | 80 | map.co.id directory + mall tenant lists |

## How to re-export

After making schema or data changes, re-export the seeds:

```bash
psql "$SUPABASE_DB_URL" -c "\copy (SELECT * FROM brands ORDER BY id) TO 'seeds/brands.csv' WITH CSV HEADER"
psql "$SUPABASE_DB_URL" -c "\copy (SELECT * FROM malls ORDER BY id) TO 'seeds/malls.csv' WITH CSV HEADER"
psql "$SUPABASE_DB_URL" -c "\copy (SELECT * FROM pois ORDER BY id) TO 'seeds/pois.csv' WITH CSV HEADER"
psql "$SUPABASE_DB_URL" -c "\copy (SELECT * FROM kabupaten ORDER BY code) TO 'seeds/kabupaten.csv' WITH CSV HEADER"
psql "$SUPABASE_DB_URL" -c "\copy (SELECT * FROM kecamatan ORDER BY code) TO 'seeds/kecamatan.csv' WITH CSV HEADER"
psql "$SUPABASE_DB_URL" -c "\copy (SELECT * FROM kelurahan ORDER BY code) TO 'seeds/kelurahan.csv' WITH CSV HEADER"
psql "$SUPABASE_DB_URL" -c "\copy (SELECT * FROM stores ORDER BY id) TO 'seeds/stores.csv' WITH CSV HEADER"
```

## How to load

If you have a fresh Supabase project and want to bulk-load (faster than running
`0005_seed_bali_data.sql` row-by-row):

```bash
psql "$SUPABASE_DB_URL" -c "\copy brands FROM 'seeds/brands.csv' WITH CSV HEADER"
psql "$SUPABASE_DB_URL" -c "\copy malls FROM 'seeds/malls.csv' WITH CSV HEADER"
# ... etc.
```

**Note**: `stores.csv` has FK constraints to `brands(id)` and `malls(id)` —
load brands and malls first.

## Scraper data NOT included

Scraped competitor data (Indomaret, Alfamart, McDonald's, etc.) is NOT
exported here because:
1. It changes frequently (re-scraped monthly)
2. It's not "seed" data — it's operational data
3. The scraper re-creates it on demand

To refresh competitor data in a fresh environment, run the unified scraper
in brand mode via the UI: Data Scraper → Brand Sweep → Save.
