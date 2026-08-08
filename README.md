# LocInsights_db — Supabase Database Layer

> PostgreSQL schema, RLS policies, and seed data for the
> [LocInsight](https://github.com/bayhaqy/LocInsights) location intelligence system.
> Used by **MAP Active Adiperkasa (MAA)** for retail store expansion decisions.

[![Supabase](https://img.shields.io/badge/Supabase-PostgreSQL+PostGIS-3ECF8E?style=flat-square)](https://supabase.com)
[![License](https://img.shields.io/badge/License-Apache--2.0-blue?style=flat-square)](LICENSE)
[![Status](https://img.shields.io/badge/Status-Production-C8102E?style=flat-square)](https://locinsights.bayhaqy.my.id)

---

## Architecture

- **Platform**: Supabase (PostgreSQL 15 + PostGIS 3.4 + pg_trgm)
- **Scope (PoC)**: Bali — 8 kabupaten + 1 kota = 9 records, 48 kecamatan, 172 kelurahan
- **Future scope**: National rollout (Microsoft Fabric integration ready)
- **Production URL**: https://fcyhrzzfvdsghtummizv.supabase.co
- **App URL**: https://locinsights.bayhaqy.my.id

## Repository structure

```
Locinsights_db/
├── migrations/
│   ├── 0001_init_extensions_and_enums.sql     # Extensions, enums, is_on_bali_land() function
│   ├── 0002_master_data.sql                   # Admin hierarchy + brands + malls + stores + POIs
│   ├── 0003_staging_and_ml.sql                # Staging tables + ML model/prediction tables
│   ├── 0004_rls_and_merge_functions.sql       # Row Level Security + merge_staging_*() functions
│   ├── 0005_seed_bali_data.sql                # Seed: Bali admin + MAP brands + malls + POIs
│   └── 0006_fix_staging_malls_and_functions.sql  # Bugfixes for staging_malls FK + merge functions
├── policies/
│   └── README.md                              # RLS policy documentation
├── seeds/
│   └── README.md                              # CSV export/import instructions
├── scripts/
│   ├── apply_migrations.sh                    # Apply all migrations via Supabase REST
│   └── backup.sh                              # pg_dump backup with retention
├── CONTRIBUTING.md                            # How to add new migrations
├── LICENSE                                    # Apache-2.0
└── README.md                                  # This file
```

## Migration order (CRITICAL)

Migrations **MUST** be applied in numerical order:

| # | File | Purpose |
|---|---|---|
| 1 | `0001_init_extensions_and_enums.sql` | Installs extensions (PostGIS, pg_trgm) and creates all ENUM types |
| 2 | `0002_master_data.sql` | Creates master tables (uses enums + PostGIS geometry columns) |
| 3 | `0003_staging_and_ml.sql` | Creates staging tables (scraper output) + ML tables (predictions, training runs) |
| 4 | `0004_rls_and_merge_functions.sql` | Enables RLS on all tables + creates `merge_staging_*()` functions |
| 5 | `0005_seed_bali_data.sql` | Seeds Bali administrative data + 27 MAP brands + 18 malls + 25 POIs |
| 6 | `0006_fix_staging_malls_and_functions.sql` | Bugfixes for staging_malls FK + merge functions |

## Key design decisions

### 1. PostGIS geography columns

Every spatial table has a `geom geography(point, 4326)` column generated from
`lat`+`lng`. This enables efficient spatial queries:

```sql
-- All stores within 5 km of a candidate site
SELECT * FROM stores
WHERE ST_DWithin(geom, ST_MakePoint(115.2126, -8.6705)::geography, 5000);
```

### 2. Anti-ocean coordinate validation

All `stores`, `pois`, and `competitor_stores` tables have a `CHECK` constraint
using `is_on_bali_land(lat, lng)` to **reject coordinates that fall in the
ocean**. This was a critical bug in v1 where some store pins appeared in the
Bali Sea.

### 3. Staging workflow (Scraper → Review → Master)

The scraper module writes to `staging_stores`, `staging_competitors`, and
`staging_malls` tables (NOT directly to master tables). The Data Team reviews
staging records in the web UI, then approves/rejects. Approval triggers the
`merge_staging_*()` function which atomically moves the record to the master
table.

See [`policies/README.md`](policies/README.md) for the full RLS policy
catalog and [`LocInsights/docs/SCRAPER.md`](https://github.com/bayhaqy/LocInsights/blob/main/docs/SCRAPER.md)
for the scraper workflow.

### 4. Row Level Security (RLS)

- **Master tables**: Public read (anon key), writes only via service_role
- **Staging tables**: No anon access (only service_role)
- **ML predictions**: Public read (for dashboard rendering)
- **Field surveys**: Anon can INSERT (PWA submission), cannot SELECT/UPDATE

See [`policies/README.md`](policies/README.md) for the full policy reference.

### 5. Source provenance

Every master record includes `source` (e.g., `'BPS Bali 2024'`,
`'map.co.id/brands'`, `'OpenStreetMap'`) and `last_crawled_at` for
scraper-sourced data. This supports audit trails.

### 6. Stores vs competitor_stores — never mixed

The master `stores` table contains **only MAA/MAP portfolio brands** (Starbucks,
Ace Hardware, Sports Station, etc.). All competitor brands (Indomaret, Alfamart,
McDonald's, etc.) live in a **separate** `competitor_stores` table.

This fixes the v1 design flaw where competitors were stored in `stores` with
`parent='COMPETITOR'`, causing schema drift, query confusion, and scraper
pollution.

## How to apply

### Option A: Apply via Supabase SQL Editor (recommended for first-time setup)

1. Go to https://supabase.com/dashboard/project/fcyhrzzfvdsghtummizv/sql/new
2. Paste each migration file IN ORDER (0001 → 0006) and click Run
3. Verify with:
   ```sql
   SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname='public';
   ```
   All 16 tables should show `rowsecurity = true`.

### Option B: Apply via psql

```bash
# Get your database connection string from Supabase dashboard > Settings > Database
DB_URL="postgresql://postgres.[ref]:[password]@aws-0-ap-southeast-1.pooler.supabase.com:6543/postgres"

for f in migrations/0001_*.sql migrations/0002_*.sql migrations/0003_*.sql \
         migrations/0004_*.sql migrations/0005_*.sql migrations/0006_*.sql; do
  echo "Applying $f ..."
  psql "$DB_URL" -f "$f"
done
```

### Option C: Apply via REST API (automated)

```bash
bash scripts/apply_migrations.sh
```

See the script header for required environment variables.

## Backup

Daily automatic backups are included with Supabase (7-day retention on free
tier). For additional safety, run `scripts/backup.sh` on a cron:

```bash
# crontab -e
0 2 * * * SUPABASE_DB_URL="postgresql://..." /path/to/Locinsights_db/scripts/backup.sh
```

Backups are stored as gzip-compressed SQL dumps with 30-day retention
(configurable via `RETENTION_DAYS` env var).

## Connection details

| Parameter | Value |
|-----------|-------|
| Project URL | https://fcyhrzzfvdsghtummizv.supabase.co |
| Region | ap-southeast-1 (Singapore) |
| Database | PostgreSQL 15 with PostGIS 3.4 |
| Schema | `public` |
| Pooler (transactions) | `aws-0-ap-southeast-1.pooler.supabase.com:6543` (use as `DATABASE_URL`) |
| Pooler (session) | `aws-0-ap-southeast-1.pooler.supabase.com:5432` (use as `DIRECT_URL` for Prisma migrations) |
| Anon Key | Set as `NEXT_PUBLIC_SUPABASE_ANON_KEY` in Vercel env vars |
| Service Role Key | Set as `SUPABASE_SERVICE_ROLE_KEY` in Vercel env vars (NEVER expose to client) |

## Related repositories

| Repo | Purpose |
|---|---|
| [`bayhaqy/LocInsights`](https://github.com/bayhaqy/LocInsights) | Next.js frontend + API (consumes this DB) |
| [`bayhaqy/Locinsights_db`](https://github.com/bayhaqy/Locinsights_db) | **This repo** — SQL migrations + RLS |
| [`Bayhaqy/LocInsights_ml`](https://huggingface.co/spaces/Bayhaqy/LocInsights_ml) | HF Space — PyScript ML explorer (reads from this DB) |

## Maintained by

**Achmad Bayhaqy** — Data Team, MAP Active Adiperkasa (MAA)
Last updated: 2026-08-09

## License

Apache-2.0 — see [`LICENSE`](LICENSE).
