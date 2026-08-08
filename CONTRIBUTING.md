# Contributing to LocInsights_db

Thanks for helping maintain the LocInsight database layer! This guide covers
the workflow for adding migrations, updating seed data, and reviewing changes.

## Repository layout

```
Locinsights_db/
├── migrations/         # SQL migration files (apply in numerical order)
│   ├── 0001_init_extensions_and_enums.sql
│   ├── 0002_master_data.sql
│   ├── 0003_staging_and_ml.sql
│   ├── 0004_rls_and_merge_functions.sql
│   ├── 0005_seed_bali_data.sql
│   └── 0006_fix_staging_malls_and_functions.sql
├── policies/           # RLS policy documentation
├── seeds/              # CSV exports for bulk re-seeding
├── scripts/
│   ├── apply_migrations.sh
│   └── backup.sh
└── README.md
```

## Adding a new migration

1. **Pick the next number.** Look at `migrations/` — the next file is
   `0007_<short_description>.sql`.
2. **Use idempotent SQL.** Wrap DDL in `IF NOT EXISTS` / `IF EXISTS`:
   ```sql
   CREATE TABLE IF NOT EXISTS my_new_table (...);
   ALTER TABLE my_new_table ADD COLUMN IF NOT EXISTS my_col text;
   DROP TABLE IF EXISTS old_table;
   ```
3. **Test locally first**. Apply to a local Postgres+PostGIS instance
   (see ` LocInsights/docs/DEPLOYMENT.md` for Docker setup).
4. **Document the migration**. Add a comment block at the top:
   ```sql
   -- 0007_add_desa_table.sql
   -- Adds the `desa` table for rural villages (outside Bali, where the
   -- kelurahan/desa distinction matters). Mirrors the kelurahan pattern.
   -- Depends on: 0002_master_data.sql (kecamatan table must exist)
   -- Author: <your name>, <date>
   ```
5. **Update `policies/README.md`** if you add a new table or change RLS.
6. **Update `seeds/README.md`** if you add a new seedable table.
7. **Commit + push** with a clear message:
   `feat(migrations): 0007 add desa table for rural villages`

## Migration numbering convention

- `0001-0099` — Schema setup (extensions, enums, master tables)
- `0100-0199` — Seed data
- `0200-0299` — Bugfixes and small adjustments
- `0300-0399` — Feature additions (new tables, columns, functions)
- `0400-0499` — Performance optimizations (indexes, partitions)
- `0500+` — Deprecations and removals

## Testing migrations

```bash
# Spin up a fresh local Postgres+PostGIS
docker run -d --name loc-test -e POSTGRES_PASSWORD=postgres -p 5432:5432 postgis/postgis:15-3.4

# Apply all migrations in order
for f in migrations/*.sql; do
  echo "Applying $f ..."
  PGPASSWORD=postgres psql -h localhost -U postgres -d postgres -f "$f"
done

# Verify
PGPASSWORD=postgres psql -h localhost -U postgres -d postgres -c "
  SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname='public';
"
```

## Code review checklist

Before approving a migration PR:

- [ ] File name follows `NNNN_description.sql` convention
- [ ] Top-of-file comment block explains purpose, dependencies, author
- [ ] All DDL is idempotent (`IF NOT EXISTS` / `IF EXISTS`)
- [ ] No hard-coded Supabase project URL or secrets
- [ ] RLS policies documented in `policies/README.md` if a new table
- [ ] Tested locally against a fresh Postgres+PostGIS instance
- [ ] Forward-only (no `DROP COLUMN` without a deprecation period —
      prefer adding a new column and migrating app code first)

## Anti-patterns to avoid

- **Don't use `CASCADE` on `DROP TABLE`** — it can wipe dependent tables
  silently. Drop FK constraints explicitly first.
- **Don't change ENUM values** in-place — Postgres ENUMs are immutable
  for removals. Create a new ENUM, migrate the column, drop the old one.
- **Don't add `NOT NULL` columns without a default** to large tables —
  it rewrites the whole table. Add as nullable first, backfill, then
  add the NOT NULL constraint.
- **Don't use `SELECT *` in functions or views** — schema changes will
  break them. Always list columns explicitly.

## Commit message format

We use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat(migrations): 0007 add desa table`
- `fix(migrations): 0006 correct staging_malls FK reference`
- `docs: update RLS policy documentation`
- `chore(scripts): add backup.sh retention flag`
