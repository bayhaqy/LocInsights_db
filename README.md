# LocInsights_db — Supabase Database Layer

This repository contains the **PostgreSQL schema, RLS policies, and seed data** for the LocInsight Location Intelligence system used by **MAP Active Adiperkasa (MAA)**.

## Architecture

- **Platform**: Supabase (PostgreSQL 15 + PostGIS + pg_trgm)
- **Scope (PoC)**: Bali (8 kabupaten + 1 kota)
- **Future scope**: National rollout (Microsoft Fabric integration ready)
- **Project URL**: https://fcyhrzzfvdsghtummizv.supabase.co

## Repository Structure

```
migrations/
├── 0001_init_extensions_and_enums.sql    # Extensions, enums, geo-validation helpers
├── 0002_master_data.sql                  # Administrative hierarchy + brands + malls + stores + POIs
├── 0003_staging_and_ml.sql               # Staging tables + ML model/prediction tables + reports + surveys
├── 0004_rls_and_merge_functions.sql      # Row Level Security + merge_staging_*() functions
└── 0005_seed_bali_data.sql               # Seed: Bali admin hierarchy + 27 MAP brands + 18 malls + 25 POIs

policies/
└── README.md                             # RLS policy documentation

seeds/
└── (export CSVs here for bulk re-seeding)

scripts/
├── apply_migrations.sh                   # Apply all migrations via Supabase REST
└── backup.sh                             # pg_dump backup script
```

## Migration Order (CRITICAL)

Migrations **MUST** be applied in numerical order:

1. `0001_init_extensions_and_enums.sql` — Installs extensions (PostGIS!) and creates all ENUM types
2. `0002_master_data.sql` — Creates master tables (uses enums + PostGIS geometry columns)
3. `0003_staging_and_ml.sql` — Creates staging tables (scraper output) + ML tables (predictions, training runs)
4. `0004_rls_and_merge_functions.sql` — Enables RLS on all tables + creates `merge_staging_*()` functions
5. `0005_seed_bali_data.sql` — Seeds Bali administrative data + MAP brands + Bali malls + Bali POIs

## Key Design Decisions

### 1. PostGIS Geography Columns
Every spatial table has a `geom geography(point, 4326)` column generated from `lat`+`lng`. This enables efficient spatial queries:
```sql
SELECT * FROM stores
WHERE ST_DWithin(geom, ST_MakePoint(115.2126, -8.6705)::geography, 5000);  -- within 5km of Denpasar
```

### 2. Anti-Ocean Coordinate Validation
All `stores`, `pois`, and `competitor_stores` tables have a `CHECK` constraint using `is_on_bali_land(lat, lng)` to **reject coordinates that fall in the ocean**. This was a critical bug in the previous version where some store pins appeared in the Bali Sea.

### 3. Staging Workflow (Scraper → Review → Master)
The scraper module on Hugging Face writes to `staging_stores`, `staging_competitors`, and `staging_malls` tables (NOT directly to master tables). The Data Team reviews staging records in the web UI, then approves/rejects. Approval triggers the `merge_staging_*()` function which atomically moves the record to the master table.

### 4. Row Level Security (RLS)
- **Master tables**: Public read (anon key), writes only via service_role
- **Staging tables**: No anon access (only service_role)
- **ML predictions**: Public read (for dashboard rendering)
- **Field surveys**: Anon can INSERT (PWA submission), cannot SELECT/UPDATE

### 5. Source Provenance
Every master record includes `source` (e.g., 'BPS Bali 2024', 'map.co.id/brands', 'OpenStreetMap') and `last_crawled_at` for scraper-sourced data. This supports audit trails.

## How to Apply

### Option A: Apply via Supabase SQL Editor
1. Go to https://supabase.com/dashboard/project/fcyhrzzfvdsghtummizv/sql/new
2. Paste each migration file IN ORDER (0001 → 0005) and click Run

### Option B: Apply via psql
```bash
# Get your database connection string from Supabase dashboard > Settings > Database
psql "postgresql://postgres.[project-ref]:[password]@aws-0-[region].pooler.supabase.com:6543/postgres" \
  -f migrations/0001_init_extensions_and_enums.sql
psql "..." -f migrations/0002_master_data.sql
# ... continue for 0003, 0004, 0005
```

### Option C: Apply via REST API (automated)
See `scripts/apply_migrations.sh`.

## Connection Details

| Parameter | Value |
|-----------|-------|
| Project URL | https://fcyhrzzfvdsghtummizv.supabase.co |
| Database | PostgreSQL 15 with PostGIS |
| Schema | `public` |
| Anon Key | Set as `NEXT_PUBLIC_SUPABASE_ANON_KEY` in Vercel env vars |
| Service Role Key | Set as `SUPABASE_SERVICE_ROLE_KEY` in Vercel env vars (NEVER expose to client) |

## Maintained By
**Achmad Bayhaqy** — Data Team, MAP Active Adiperkasa (MAA)
Last updated: 2026-08-08
