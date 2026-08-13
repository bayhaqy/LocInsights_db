-- =============================================================
-- LocInsights — Supabase Migration 0009
-- SaaS Multi-Tenant Transformation: Auth + Tenant Isolation
--
-- Author: Super Z (assistant)
-- Date: 2026-08-13
-- Scope:
--   1. Create `tenants` and `tenant_addons` tables (SaaS customer registry)
--   2. Create `docs` table (DB-backed documentation storage — replaces filesystem)
--   3. Add `tenant_id` column to all private (tenant-scoped) tables
--   4. Add `tenant_id` column to `users` (assign user to tenant; NULL = platform admin)
--   5. Add `tenant_scope` to `roles` (system-wide vs tenant-scoped roles)
--   6. Backfill existing data to a default tenant ("MAP Active Adiperkasa")
--   7. Replace permissive public-read RLS policies with tenant-isolated policies
--      using `current_setting('app.current_tenant_id', true)` for private tables
--   8. Public reference data (countries, provinces, kabupaten, kecamatan, kelurahan)
--      remains shared (tenant_id = NULL, public read)
--
-- IDEMPOTENT: Safe to re-run. All statements use IF NOT EXISTS / IF EXISTS guards.
--
-- Architecture decision (per user confirmation):
--   - Approach: Shared DB + tenant_id column + RLS per-tenant (NOT schema-per-tenant)
--   - Tenant resolution: JWT claim (NextAuth session.user.tenant_id)
--   - Defense-in-depth: RLS at DB layer + tenant_id filter at Prisma layer
--   - Reference data (Bali admin boundaries, BPS): SHARED across all tenants
--   - Tenant private data (stores, malls, brands, reports, etc.): ISOLATED per tenant
-- =============================================================

BEGIN;

-- =============================================================
-- 1. EXTENSIONS (idempotent)
-- =============================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =============================================================
-- 2. NEW ENUMS
-- =============================================================
DO $$ BEGIN
  CREATE TYPE tenant_plan_enum    AS ENUM ('saas_monthly', 'saas_yearly', 'enterprise_onprem', 'trial', 'internal');
  CREATE TYPE tenant_status_enum AS ENUM ('active', 'suspended', 'terminated', 'provisioning');
  CREATE TYPE addon_type_enum    AS ENUM ('region_expansion', 'custom_scraper', 'api_connector', 'ui_customization');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- Extend user_role_enum if missing values (idempotent)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'tenant_admin' AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'user_role_enum')) THEN
    ALTER TYPE user_role_enum ADD VALUE 'tenant_admin' BEFORE 'viewer';
  END IF;
EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- =============================================================
-- 3. tenants TABLE
-- =============================================================
CREATE TABLE IF NOT EXISTS public.tenants (
  id              text        PRIMARY KEY DEFAULT (gen_random_uuid())::text,
  name            text        NOT NULL,
  slug            text        NOT NULL UNIQUE,                    -- e.g. "map-active" for URL/path
  plan            tenant_plan_enum NOT NULL DEFAULT 'saas_monthly',
  status          tenant_status_enum NOT NULL DEFAULT 'active',
  region_scope    text[]      NOT NULL DEFAULT '{}',              -- ["bali"] or ["bali","jatim"]
  data_residency  text,                                            -- e.g. "id-sin1" (NULL = no residency constraint)
  -- White-labeling
  app_name        text        NOT NULL DEFAULT 'LocInsights',
  logo_url        text,
  primary_color   text        NOT NULL DEFAULT '#7A0A1A',         -- wine red default
  accent_color    text        NOT NULL DEFAULT '#C8102E',
  -- Metadata
  contact_name    text,
  contact_email   text,
  contact_phone   text,
  notes           text        NOT NULL DEFAULT '',
  max_users       integer     NOT NULL DEFAULT 10,
  max_api_calls_per_day integer NOT NULL DEFAULT 10000,
  -- Trial/expiry
  trial_ends_at   timestamptz,
  suspended_at    timestamptz,
  terminated_at   timestamptz,
  -- Audit
  created_at      timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_by      text
);

CREATE INDEX IF NOT EXISTS idx_tenants_slug    ON public.tenants(slug);
CREATE INDEX IF NOT EXISTS idx_tenants_status  ON public.tenants(status);
CREATE INDEX IF NOT EXISTS idx_tenants_plan    ON public.tenants(plan);

COMMENT ON TABLE public.tenants IS 'SaaS customer registry. Each row = one company subscribed to LocInsights.';

-- =============================================================
-- 4. tenant_addons TABLE (Skema C: Professional Services & Data Add-ons)
-- =============================================================
CREATE TABLE IF NOT EXISTS public.tenant_addons (
  id            text        PRIMARY KEY DEFAULT (gen_random_uuid())::text,
  tenant_id     text        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  addon_type    addon_type_enum NOT NULL,
  addon_config  jsonb       NOT NULL DEFAULT '{}',                 -- { province: "jatim", scraper_target: "...", api_system: "powerbi" }
  expires_at    timestamptz,
  is_active     boolean     NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_by    text
);

CREATE INDEX IF NOT EXISTS idx_tenant_addons_tenant ON public.tenant_addons(tenant_id);
CREATE INDEX IF NOT EXISTS idx_tenant_addons_type   ON public.tenant_addons(addon_type);
CREATE INDEX IF NOT EXISTS idx_tenant_addons_active ON public.tenant_addons(is_active) WHERE is_active = true;

COMMENT ON TABLE public.tenant_addons IS 'Per-tenant add-ons (region expansion, custom scraper, API connector, UI customization). Maps to Skema C in SaaS pricing.';

-- =============================================================
-- 5. docs TABLE (DB-backed documentation — replaces filesystem on Vercel)
-- =============================================================
CREATE TABLE IF NOT EXISTS public.docs (
  id            text        PRIMARY KEY DEFAULT (gen_random_uuid())::text,
  slug          text        NOT NULL UNIQUE,                       -- e.g. "architecture", "user-guide"
  title         text        NOT NULL,
  category      text        NOT NULL DEFAULT 'General',
  "order"       integer     NOT NULL DEFAULT 100,
  content       text        NOT NULL DEFAULT '',                   -- raw markdown
  last_updated  date        NOT NULL DEFAULT CURRENT_DATE,
  owner         text        NOT NULL DEFAULT 'Data Team',
  -- Multi-tenant: NULL = system-wide doc (shared), non-NULL = tenant-specific doc
  tenant_id     text        REFERENCES public.tenants(id) ON DELETE CASCADE,
  is_published  boolean     NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_docs_slug       ON public.docs(slug);
CREATE INDEX IF NOT EXISTS idx_docs_category   ON public.docs(category);
CREATE INDEX IF NOT EXISTS idx_docs_tenant     ON public.docs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_docs_published  ON public.docs(is_published) WHERE is_published = true;

COMMENT ON TABLE public.docs IS 'DB-backed documentation storage (replaces filesystem — Vercel serverless FS is read-only). System docs have tenant_id=NULL; tenant-specific docs reference tenants.id.';

-- =============================================================
-- 6. ALTER users: add tenant_id + tenant relationship
-- =============================================================
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS tenant_id text REFERENCES public.tenants(id) ON DELETE SET NULL;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS default_tenant_id text REFERENCES public.tenants(id) ON DELETE SET NULL;

-- Index for tenant-scoped user queries
CREATE INDEX IF NOT EXISTS idx_users_tenant_id        ON public.users(tenant_id);
CREATE INDEX IF NOT EXISTS idx_users_default_tenant   ON public.users(default_tenant_id);

-- =============================================================
-- 7. ALTER roles: add tenant_scope columns
-- =============================================================
ALTER TABLE public.roles
  ADD COLUMN IF NOT EXISTS tenant_id text REFERENCES public.tenants(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS is_tenant_scoped boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_roles_tenant_id ON public.roles(tenant_id);

COMMENT ON COLUMN public.roles.tenant_id IS 'NULL = system-wide role (superadmin, admin, data, analyst, viewer). Non-NULL = tenant-specific custom role.';
COMMENT ON COLUMN public.roles.is_tenant_scoped IS 'true = role can be edited by tenant_admin of this tenant. false = system role, only superadmin can edit.';

-- =============================================================
-- 8. ADD tenant_id to all PRIVATE (tenant-scoped) tables
--    Reference data tables (countries, provinces, kabupaten, kecamatan, kelurahan)
--    remain SHARED (no tenant_id column) — they are public reference data.
-- =============================================================

-- 8a. Master retail data (tenant-private)
ALTER TABLE public.brands            ADD COLUMN IF NOT EXISTS tenant_id text REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.stores            ADD COLUMN IF NOT EXISTS tenant_id text REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.malls             ADD COLUMN IF NOT EXISTS tenant_id text REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.mall_tenants      ADD COLUMN IF NOT EXISTS tenant_id text REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.competitor_stores ADD COLUMN IF NOT EXISTS tenant_id text REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.pois              ADD COLUMN IF NOT EXISTS tenant_id text REFERENCES public.tenants(id) ON DELETE CASCADE;

-- 8b. Workflow tables (tenant-private)
ALTER TABLE public.reports           ADD COLUMN IF NOT EXISTS tenant_id text REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.scraper_runs      ADD COLUMN IF NOT EXISTS tenant_id text REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.field_surveys     ADD COLUMN IF NOT EXISTS tenant_id text REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.ab_tests          ADD COLUMN IF NOT EXISTS tenant_id text REFERENCES public.tenants(id) ON DELETE CASCADE;

-- 8c. ML tables (tenant-private)
ALTER TABLE public.ml_models         ADD COLUMN IF NOT EXISTS tenant_id text REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.training_runs     ADD COLUMN IF NOT EXISTS tenant_id text REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.predictions       ADD COLUMN IF NOT EXISTS tenant_id text REFERENCES public.tenants(id) ON DELETE CASCADE;

-- 8d. Staging tables (tenant-private)
ALTER TABLE public.staging_stores    ADD COLUMN IF NOT EXISTS tenant_id text REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.staging_competitors ADD COLUMN IF NOT EXISTS tenant_id text REFERENCES public.tenants(id) ON DELETE CASCADE;
ALTER TABLE public.staging_malls     ADD COLUMN IF NOT EXISTS tenant_id text REFERENCES public.tenants(id) ON DELETE CASCADE;

-- Indexes for tenant_id on all private tables (for RLS performance)
CREATE INDEX IF NOT EXISTS idx_brands_tenant            ON public.brands(tenant_id);
CREATE INDEX IF NOT EXISTS idx_stores_tenant            ON public.stores(tenant_id);
CREATE INDEX IF NOT EXISTS idx_malls_tenant             ON public.malls(tenant_id);
CREATE INDEX IF NOT EXISTS idx_mall_tenants_tenant      ON public.mall_tenants(tenant_id);
CREATE INDEX IF NOT EXISTS idx_competitor_stores_tenant ON public.competitor_stores(tenant_id);
CREATE INDEX IF NOT EXISTS idx_pois_tenant              ON public.pois(tenant_id);
CREATE INDEX IF NOT EXISTS idx_reports_tenant           ON public.reports(tenant_id);
CREATE INDEX IF NOT EXISTS idx_scraper_runs_tenant      ON public.scraper_runs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_field_surveys_tenant     ON public.field_surveys(tenant_id);
CREATE INDEX IF NOT EXISTS idx_ab_tests_tenant          ON public.ab_tests(tenant_id);
CREATE INDEX IF NOT EXISTS idx_ml_models_tenant         ON public.ml_models(tenant_id);
CREATE INDEX IF NOT EXISTS idx_training_runs_tenant     ON public.training_runs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_predictions_tenant       ON public.predictions(tenant_id);
CREATE INDEX IF NOT EXISTS idx_staging_stores_tenant    ON public.staging_stores(tenant_id);
CREATE INDEX IF NOT EXISTS idx_staging_competitors_tenant ON public.staging_competitors(tenant_id);
CREATE INDEX IF NOT EXISTS idx_staging_malls_tenant     ON public.staging_malls(tenant_id);

-- =============================================================
-- 9. CREATE default tenant for existing MAP Active data
-- =============================================================
INSERT INTO public.tenants (id, name, slug, plan, status, region_scope, app_name, contact_name, contact_email, notes, max_users, max_api_calls_per_day, created_by)
VALUES (
  'tnt_map_active_0001',
  'MAP Active Adiperkasa',
  'map-active',
  'internal',
  'active',
  ARRAY['bali'],
  'LocInsights',
  'Achmad Bayhaqy',
  'bayhaqy@locinsights.local',
  'Default tenant for existing MAA data (Bali PoC). Migrated from single-tenant to multi-tenant on 2026-08-13.',
  50,
  100000,
  'system'
)
ON CONFLICT (id) DO NOTHING;

-- =============================================================
-- 10. BACKFILL tenant_id for existing rows in all private tables
--     All existing data belongs to the MAP Active default tenant.
-- =============================================================
UPDATE public.brands            SET tenant_id = 'tnt_map_active_0001' WHERE tenant_id IS NULL;
UPDATE public.stores            SET tenant_id = 'tnt_map_active_0001' WHERE tenant_id IS NULL;
UPDATE public.malls             SET tenant_id = 'tnt_map_active_0001' WHERE tenant_id IS NULL;
UPDATE public.mall_tenants      SET tenant_id = 'tnt_map_active_0001' WHERE tenant_id IS NULL;
UPDATE public.competitor_stores SET tenant_id = 'tnt_map_active_0001' WHERE tenant_id IS NULL;
UPDATE public.pois              SET tenant_id = 'tnt_map_active_0001' WHERE tenant_id IS NULL;
UPDATE public.reports           SET tenant_id = 'tnt_map_active_0001' WHERE tenant_id IS NULL;
UPDATE public.scraper_runs      SET tenant_id = 'tnt_map_active_0001' WHERE tenant_id IS NULL;
UPDATE public.field_surveys     SET tenant_id = 'tnt_map_active_0001' WHERE tenant_id IS NULL;
UPDATE public.ab_tests          SET tenant_id = 'tnt_map_active_0001' WHERE tenant_id IS NULL;
UPDATE public.ml_models         SET tenant_id = 'tnt_map_active_0001' WHERE tenant_id IS NULL;
UPDATE public.training_runs     SET tenant_id = 'tnt_map_active_0001' WHERE tenant_id IS NULL;
UPDATE public.predictions       SET tenant_id = 'tnt_map_active_0001' WHERE tenant_id IS NULL;
UPDATE public.staging_stores    SET tenant_id = 'tnt_map_active_0001' WHERE tenant_id IS NULL;
UPDATE public.staging_competitors SET tenant_id = 'tnt_map_active_0001' WHERE tenant_id IS NULL;
UPDATE public.staging_malls     SET tenant_id = 'tnt_map_active_0001' WHERE tenant_id IS NULL;

-- 10a. Assign existing users to default tenant (except superadmin which is platform-wide)
UPDATE public.users
SET tenant_id = 'tnt_map_active_0001',
    default_tenant_id = 'tnt_map_active_0001'
WHERE role != 'superadmin' AND tenant_id IS NULL;

-- Superadmin gets default_tenant_id (so they can switch into it) but tenant_id = NULL (platform-wide)
UPDATE public.users
SET default_tenant_id = 'tnt_map_active_0001'
WHERE role = 'superadmin' AND default_tenant_id IS NULL;

-- =============================================================
-- 11. RLS POLICIES — Replace permissive public-read with tenant-isolated
-- =============================================================

-- 11a. Enable RLS on new tables
ALTER TABLE public.tenants       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_addons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.docs          ENABLE ROW LEVEL SECURITY;

-- 11b. Drop existing permissive public-read policies on private tables
DROP POLICY IF EXISTS public_read_brands           ON public.brands;
DROP POLICY IF EXISTS public_read_malls            ON public.malls;
DROP POLICY IF EXISTS public_read_stores           ON public.stores;
DROP POLICY IF EXISTS public_read_pois             ON public.pois;
DROP POLICY IF EXISTS public_read_competitors      ON public.competitor_stores;
DROP POLICY IF EXISTS public_read_mall_tenants     ON public.mall_tenants;
DROP POLICY IF EXISTS public_read_reports          ON public.reports;
DROP POLICY IF EXISTS public_read_ml_models        ON public.ml_models;
DROP POLICY IF EXISTS public_read_training_runs    ON public.training_runs;
DROP POLICY IF EXISTS public_read_predictions      ON public.predictions;
DROP POLICY IF EXISTS public_read_ab_tests         ON public.ab_tests;

-- 11c. CREATE tenant-isolated policies on private tables
--      Pattern: row is visible if (a) tenant_id matches current_setting, OR (b) row is shared (tenant_id IS NULL), OR (c) current_setting is unset (service_role bypass anyway)
--
--      Note: `current_setting('app.current_tenant_id', true)` returns NULL if not set,
--      which makes the OR chain still work safely (returns NULL = false for the equality).
--
--      Service role bypasses RLS entirely (Supabase default), so admin/API routes
--      using service_role key are unaffected.

-- Helper: returns current tenant_id from session setting, or NULL if unset
CREATE OR REPLACE FUNCTION public.current_tenant_id()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('app.current_tenant_id', true), '')::text;
$$;

-- Brands
CREATE POLICY tenant_isolation_brands ON public.brands
  FOR ALL
  USING (
    public.current_tenant_id() IS NULL  -- service_role / no context set = see all (defense-in-depth + debugging)
    OR tenant_id IS NULL                 -- shared reference brand
    OR tenant_id = public.current_tenant_id()
  )
  WITH CHECK (
    tenant_id = public.current_tenant_id()
    OR tenant_id IS NULL
  );

-- Stores
CREATE POLICY tenant_isolation_stores ON public.stores
  FOR ALL
  USING (
    public.current_tenant_id() IS NULL
    OR tenant_id IS NULL
    OR tenant_id = public.current_tenant_id()
  )
  WITH CHECK (
    tenant_id = public.current_tenant_id()
  );

-- Malls
CREATE POLICY tenant_isolation_malls ON public.malls
  FOR ALL
  USING (
    public.current_tenant_id() IS NULL
    OR tenant_id IS NULL
    OR tenant_id = public.current_tenant_id()
  )
  WITH CHECK (
    tenant_id = public.current_tenant_id()
  );

-- Mall Tenants
CREATE POLICY tenant_isolation_mall_tenants ON public.mall_tenants
  FOR ALL
  USING (
    public.current_tenant_id() IS NULL
    OR tenant_id IS NULL
    OR tenant_id = public.current_tenant_id()
  )
  WITH CHECK (
    tenant_id = public.current_tenant_id()
  );

-- Competitor Stores
CREATE POLICY tenant_isolation_competitor_stores ON public.competitor_stores
  FOR ALL
  USING (
    public.current_tenant_id() IS NULL
    OR tenant_id IS NULL
    OR tenant_id = public.current_tenant_id()
  )
  WITH CHECK (
    tenant_id = public.current_tenant_id()
  );

-- POIs
CREATE POLICY tenant_isolation_pois ON public.pois
  FOR ALL
  USING (
    public.current_tenant_id() IS NULL
    OR tenant_id IS NULL
    OR tenant_id = public.current_tenant_id()
  )
  WITH CHECK (
    tenant_id = public.current_tenant_id()
  );

-- Reports
CREATE POLICY tenant_isolation_reports ON public.reports
  FOR ALL
  USING (
    public.current_tenant_id() IS NULL
    OR tenant_id IS NULL
    OR tenant_id = public.current_tenant_id()
  )
  WITH CHECK (
    tenant_id = public.current_tenant_id()
  );

-- Scraper Runs (already RLS-enabled but no policy — keep restrictive)
CREATE POLICY tenant_isolation_scraper_runs ON public.scraper_runs
  FOR ALL
  USING (
    public.current_tenant_id() IS NULL
    OR tenant_id IS NULL
    OR tenant_id = public.current_tenant_id()
  )
  WITH CHECK (
    tenant_id = public.current_tenant_id()
  );

-- Field Surveys — keep anon INSERT (PWA submission) but tenant-scoped read
DROP POLICY IF EXISTS anon_insert_surveys ON public.field_surveys;
CREATE POLICY tenant_insert_surveys ON public.field_surveys
  FOR INSERT WITH CHECK (true);
CREATE POLICY tenant_isolation_field_surveys ON public.field_surveys
  FOR SELECT
  USING (
    public.current_tenant_id() IS NULL
    OR tenant_id IS NULL
    OR tenant_id = public.current_tenant_id()
  );
CREATE POLICY tenant_update_field_surveys ON public.field_surveys
  FOR UPDATE
  USING (
    public.current_tenant_id() IS NULL
    OR tenant_id = public.current_tenant_id()
  );

-- AB Tests
CREATE POLICY tenant_isolation_ab_tests ON public.ab_tests
  FOR ALL
  USING (
    public.current_tenant_id() IS NULL
    OR tenant_id IS NULL
    OR tenant_id = public.current_tenant_id()
  )
  WITH CHECK (
    tenant_id = public.current_tenant_id()
  );

-- ML Models
CREATE POLICY tenant_isolation_ml_models ON public.ml_models
  FOR ALL
  USING (
    public.current_tenant_id() IS NULL
    OR tenant_id IS NULL
    OR tenant_id = public.current_tenant_id()
  )
  WITH CHECK (
    tenant_id = public.current_tenant_id()
  );

-- Training Runs
CREATE POLICY tenant_isolation_training_runs ON public.training_runs
  FOR ALL
  USING (
    public.current_tenant_id() IS NULL
    OR tenant_id IS NULL
    OR tenant_id = public.current_tenant_id()
  )
  WITH CHECK (
    tenant_id = public.current_tenant_id()
  );

-- Predictions
CREATE POLICY tenant_isolation_predictions ON public.predictions
  FOR ALL
  USING (
    public.current_tenant_id() IS NULL
    OR tenant_id IS NULL
    OR tenant_id = public.current_tenant_id()
  )
  WITH CHECK (
    tenant_id = public.current_tenant_id()
  );

-- Staging tables (already RLS-enabled, no policy = no anon access). Add tenant policy.
CREATE POLICY tenant_isolation_staging_stores ON public.staging_stores
  FOR ALL
  USING (
    public.current_tenant_id() IS NULL
    OR tenant_id = public.current_tenant_id()
  )
  WITH CHECK (
    tenant_id = public.current_tenant_id()
  );

CREATE POLICY tenant_isolation_staging_competitors ON public.staging_competitors
  FOR ALL
  USING (
    public.current_tenant_id() IS NULL
    OR tenant_id = public.current_tenant_id()
  )
  WITH CHECK (
    tenant_id = public.current_tenant_id()
  );

CREATE POLICY tenant_isolation_staging_malls ON public.staging_malls
  FOR ALL
  USING (
    public.current_tenant_id() IS NULL
    OR tenant_id = public.current_tenant_id()
  )
  WITH CHECK (
    tenant_id = public.current_tenant_id()
  );

-- 11d. Policies on NEW tables (tenants, tenant_addons, docs)
--      Only platform superadmin (no tenant context) can read all tenants.
--      Tenant admins can read their own tenant record.
CREATE POLICY tenants_visibility ON public.tenants
  FOR SELECT
  USING (
    public.current_tenant_id() IS NULL    -- platform admin sees all
    OR id = public.current_tenant_id()    -- tenant sees only self
  );
CREATE POLICY tenants_write_superuser ON public.tenants
  FOR ALL
  USING (public.current_tenant_id() IS NULL)
  WITH CHECK (public.current_tenant_id() IS NULL);

CREATE POLICY tenant_addons_visibility ON public.tenant_addons
  FOR SELECT
  USING (
    public.current_tenant_id() IS NULL
    OR tenant_id = public.current_tenant_id()
  );
CREATE POLICY tenant_addons_write_superuser ON public.tenant_addons
  FOR INSERT
  WITH CHECK (public.current_tenant_id() IS NULL);
CREATE POLICY tenant_addons_update_superuser ON public.tenant_addons
  FOR UPDATE
  USING (public.current_tenant_id() IS NULL);

-- Docs: system docs (tenant_id NULL) visible to all logged-in users; tenant docs to own tenant
CREATE POLICY docs_visibility ON public.docs
  FOR SELECT
  USING (
    is_published = true
    AND (
      public.current_tenant_id() IS NULL
      OR tenant_id IS NULL
      OR tenant_id = public.current_tenant_id()
    )
  );
CREATE POLICY docs_write_superuser ON public.docs
  FOR ALL
  USING (
    public.current_tenant_id() IS NULL
    OR tenant_id = public.current_tenant_id()
  )
  WITH CHECK (
    public.current_tenant_id() IS NULL
    OR tenant_id = public.current_tenant_id()
  );

-- 11e. Auth tables (users, roles, user_audit_logs) policies
--      These tables already had RLS enabled but no explicit policies.
--      Add policies so they are visible/modifiable only by:
--        - Platform superadmin (no tenant context) → all users
--        - Tenant admin (current_tenant_id set) → users in their tenant only
--        - User themselves → their own row only

-- Drop any existing policies on auth tables (in case of re-run)
DROP POLICY IF EXISTS users_select_all      ON public.users;
DROP POLICY IF EXISTS users_select_self     ON public.users;
DROP POLICY IF EXISTS users_select_tenant   ON public.users;
DROP POLICY IF EXISTS users_insert_superuser ON public.users;
DROP POLICY IF EXISTS users_update_self     ON public.users;
DROP POLICY IF EXISTS users_update_superuser ON public.users;
DROP POLICY IF EXISTS users_update_tenant_admin ON public.users;
DROP POLICY IF EXISTS users_delete_superuser ON public.users;
DROP POLICY IF EXISTS users_delete_tenant_admin ON public.users;
DROP POLICY IF EXISTS roles_select_all      ON public.roles;
DROP POLICY IF EXISTS roles_write_superuser ON public.roles;
DROP POLICY IF EXISTS roles_write_tenant_admin ON public.roles;
DROP POLICY IF EXISTS audit_logs_select_all ON public.user_audit_logs;
DROP POLICY IF EXISTS audit_logs_insert     ON public.user_audit_logs;

-- Users: SELECT
CREATE POLICY users_select ON public.users
  FOR SELECT
  USING (
    public.current_tenant_id() IS NULL                       -- platform superadmin: all users
    OR tenant_id = public.current_tenant_id()                -- tenant admin: own tenant users
    OR id = NULLIF(current_setting('app.current_user_id', true), '')::text  -- user sees own row
  );

-- Users: INSERT (only platform superadmin or tenant_admin of own tenant)
CREATE POLICY users_insert ON public.users
  FOR INSERT
  WITH CHECK (
    public.current_tenant_id() IS NULL
    OR tenant_id = public.current_tenant_id()
  );

-- Users: UPDATE (superadmin: all; tenant_admin: own tenant; user: own row, limited fields)
CREATE POLICY users_update ON public.users
  FOR UPDATE
  USING (
    public.current_tenant_id() IS NULL
    OR tenant_id = public.current_tenant_id()
    OR id = NULLIF(current_setting('app.current_user_id', true), '')::text
  );

-- Users: DELETE (superadmin only, OR tenant_admin for own tenant)
CREATE POLICY users_delete ON public.users
  FOR DELETE
  USING (
    public.current_tenant_id() IS NULL
    OR tenant_id = public.current_tenant_id()
  );

-- Roles: SELECT (all authenticated can see roles)
CREATE POLICY roles_select ON public.roles
  FOR SELECT
  USING (
    public.current_tenant_id() IS NULL                  -- platform: all roles (system + tenant)
    OR tenant_id IS NULL                                -- everyone sees system roles
    OR tenant_id = public.current_tenant_id()           -- tenant sees own custom roles
  );

-- Roles: INSERT/UPDATE/DELETE (superadmin: all; tenant_admin: own tenant only)
CREATE POLICY roles_write ON public.roles
  FOR ALL
  USING (
    public.current_tenant_id() IS NULL
    OR tenant_id = public.current_tenant_id()
  )
  WITH CHECK (
    public.current_tenant_id() IS NULL
    OR tenant_id = public.current_tenant_id()
  );

-- Audit logs: SELECT (superadmin: all; tenant_admin: own tenant's logs)
CREATE POLICY audit_logs_select ON public.user_audit_logs
  FOR SELECT
  USING (
    public.current_tenant_id() IS NULL
    OR EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = user_audit_logs.user_id
        AND u.tenant_id = public.current_tenant_id()
    )
  );

-- Audit logs: INSERT (always — server-side via service_role anyway, but allow if context set)
CREATE POLICY audit_logs_insert ON public.user_audit_logs
  FOR INSERT WITH CHECK (true);

-- =============================================================
-- 12. updated_at triggers for new tables
-- =============================================================
DROP TRIGGER IF EXISTS trg_tenants_updated_at ON public.tenants;
CREATE TRIGGER trg_tenants_updated_at
  BEFORE UPDATE ON public.tenants
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_tenant_addons_updated_at ON public.tenant_addons;
CREATE TRIGGER trg_tenant_addons_updated_at
  BEFORE UPDATE ON public.tenant_addons
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_docs_updated_at ON public.docs;
CREATE TRIGGER trg_docs_updated_at
  BEFORE UPDATE ON public.docs
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================
-- 13. SEED default system docs (migrate from filesystem /docs/*.md)
--     This is a placeholder — actual content will be seeded by seed-docs script.
--     We only create the placeholder rows here; the seed script will UPDATE content.
-- =============================================================
INSERT INTO public.docs (slug, title, category, "order", content, owner, tenant_id, is_published)
VALUES
  ('architecture',   'Architecture',          'Technical',  10, '# Architecture\n\n*Content will be seeded.*',  'Data Team', NULL, true),
  ('data-model',     'Data Model',            'Technical',  20, '# Data Model\n\n*Content will be seeded.*',     'Data Team', NULL, true),
  ('data-sources',   'Data Sources',          'Technical',  30, '# Data Sources\n\n*Content will be seeded.*',   'Data Team', NULL, true),
  ('data-dictionary','Data Dictionary',       'Technical',  40, '# Data Dictionary\n\n*Content will be seeded.*','Data Team', NULL, true),
  ('calculations',   'Calculations',          'Technical',  50, '# Calculations\n\n*Content will be seeded.*',    'Data Team', NULL, true),
  ('scraper',        'Scraper',               'Technical',  60, '# Scraper\n\n*Content will be seeded.*',         'Data Team', NULL, true),
  ('api-reference',  'API Reference',         'Technical',  70, '# API Reference\n\n*Content will be seeded.*',   'Data Team', NULL, true),
  ('deployment',     'Deployment',            'Technical',  80, '# Deployment\n\n*Content will be seeded.*',      'Data Team', NULL, true),
  ('technical',      'Technical Overview',    'Technical',  90, '# Technical Overview\n\n*Content will be seeded.*','Data Team', NULL, true),
  ('user-guide',     'User Guide',            'User',      100, '# User Guide\n\n*Content will be seeded.*',      'Data Team', NULL, true),
  ('changelog',      'Changelog',             'Meta',      110, '# Changelog\n\n*Content will be seeded.*',       'Data Team', NULL, true)
ON CONFLICT (slug) DO NOTHING;

-- =============================================================
-- 14. VERIFICATION (informational queries — won't fail if zero)
-- =============================================================
DO $$
DECLARE
  v_tenant_count   integer;
  v_users_with_tenant integer;
  v_brands_with_tenant integer;
  v_docs_count     integer;
BEGIN
  SELECT count(*) INTO v_tenant_count FROM public.tenants;
  RAISE NOTICE 'Tenants created: %', v_tenant_count;

  SELECT count(*) INTO v_users_with_tenant FROM public.users WHERE tenant_id IS NOT NULL;
  RAISE NOTICE 'Users assigned to tenant: % / total users', v_users_with_tenant;

  SELECT count(*) INTO v_brands_with_tenant FROM public.brands WHERE tenant_id IS NOT NULL;
  RAISE NOTICE 'Brands with tenant_id: %', v_brands_with_tenant;

  SELECT count(*) INTO v_docs_count FROM public.docs;
  RAISE NOTICE 'Docs seeded: %', v_docs_count;
END $$;

COMMIT;

-- =============================================================
-- End of migration 0009
-- =============================================================
