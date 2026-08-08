# Row-Level Security (RLS) Policies

> Documentation of all RLS policies applied to LocInsight tables.
> The actual SQL is in `migrations/0004_rls_and_merge_functions.sql`.

## Overview

RLS is enabled on **all 16 tables** in the LocInsight schema. Policies are
grouped by access pattern:

| Pattern | Tables | Anon can | Service role can |
|---|---|---|---|
| **Public read** | countries, provinces, kabupaten, kecamatan, kelurahan, brands, stores, competitor_stores, malls, mall_tenants, pois, ml_models, predictions, ab_tests, reports | SELECT | SELECT, INSERT, UPDATE, DELETE |
| **PWA submission only** | field_surveys | INSERT | SELECT, INSERT, UPDATE, DELETE |
| **Service-only** | staging_stores, staging_competitors, staging_malls, training_runs, scraper_runs | (nothing) | SELECT, INSERT, UPDATE, DELETE |

## Why these patterns?

### Public read (anon SELECT)

These tables contain data that the dashboard needs to render. The anon key
is embedded client-side in the Next.js app and the HF Space; it's safe to
expose because RLS prevents any writes via anon.

### PWA submission only (anon INSERT but no SELECT)

Field surveyors use the `/survey` PWA on their phones to submit observations
(competitor outlets, site conditions, etc.). They need INSERT permission to
push new rows. They must NOT be able to SELECT (to prevent scraping of
competitor survey data), nor UPDATE/DELETE (to prevent tampering after
submission).

All reads and reviews happen server-side via the Next.js API using the
service_role key.

### Service-only (no anon access)

Staging tables contain raw scraper output that hasn't been reviewed yet.
Exposing them client-side would leak unverified data (often with errors —
ocean coordinates, misspelled brands, etc.). All access goes through the
Next.js API.

## Policy reference

### `stores`

```sql
-- Enable RLS
ALTER TABLE stores ENABLE ROW LEVEL SECURITY;

-- Anon can read all MAA/MAP stores
CREATE POLICY "stores_select_anon" ON stores
  FOR SELECT TO anon USING (true);

-- Only service_role can write
CREATE POLICY "stores_insert_service" ON stores
  FOR INSERT TO service_role WITH CHECK (true);
CREATE POLICY "stores_update_service" ON stores
  FOR UPDATE TO service_role USING (true);
CREATE POLICY "stores_delete_service" ON stores
  FOR DELETE TO service_role USING (true);
```

(Same pattern applies to all "Public read" tables.)

### `field_surveys`

```sql
ALTER TABLE field_surveys ENABLE ROW LEVEL SECURITY;

-- Anon can submit new surveys (PWA flow) — but NOT read them back
CREATE POLICY "field_surveys_insert_anon" ON field_surveys
  FOR INSERT TO anon WITH CHECK (true);
-- No SELECT/UPDATE/DELETE policy for anon → denied by default

-- Service role has full access
CREATE POLICY "field_surveys_all_service" ON field_surveys
  FOR ALL TO service_role USING (true) WITH CHECK (true);
```

### `staging_stores`, `staging_competitors`, `staging_malls`

```sql
ALTER TABLE staging_stores ENABLE ROW LEVEL SECURITY;
-- No policies for anon → all access denied by default
-- Only service_role (which bypasses RLS) can read/write
```

## Service role bypass

The `service_role` key bypasses RLS entirely — it can read and write any
row in any table. This is why it MUST NEVER be exposed to the client.

In LocInsight, the `service_role` key is used only by:
- The Next.js API routes (server-side, via Prisma)
- The `apply_migrations.sh` script (one-time setup)
- The `backup.sh` script (pg_dump)

## Verifying policies

After applying migrations, verify RLS is enabled:

```sql
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;
```

All 16 tables should show `rowsecurity = true`.

To list all policies:

```sql
SELECT tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;
```

## Adding a new table

When you add a new table in a future migration:

1. Decide which access pattern it follows (public read / PWA / service-only).
2. Add `ALTER TABLE ... ENABLE ROW LEVEL SECURITY;` in the migration.
3. Add the appropriate policies (copy from a similar existing table).
4. Update this document.

## Common pitfalls

- **Forgetting `ENABLE ROW LEVEL SECURITY`**: Just creating policies isn't
  enough — you must explicitly enable RLS on the table.
- **Using `FORCE` unnecessarily**: `FORCE ROW LEVEL SECURITY` makes RLS
  apply even to table owners. We don't use it — the table owner (postgres)
  can always bypass RLS, which is fine for admin operations.
- **Over-permissive `USING (true)`**: Be careful — `USING (true)` on a SELECT
  policy means "all rows visible". This is correct for public-read tables
  but wrong for restricted ones. Use column-based conditions instead
  (e.g., `USING (owner = current_user)`).
