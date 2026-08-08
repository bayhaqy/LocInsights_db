-- =============================================================
-- LocInsight — Supabase Migration 0004
-- Row Level Security (RLS) Policies
--
-- Architecture:
--   - Public read access to master tables (read-only via anon key)
--   - Write access only via service_role (server-side / Vercel API routes)
--   - Staging tables: only authenticated service_role can read/write
--   - ML predictions: public read (for dashboard rendering)
--   - Field surveys: insert allowed for anon (PWA submission), review needs service_role
-- =============================================================

-- Master tables: PUBLIC READ (anon), NO direct write from client
alter table public.countries          enable row level security;
alter table public.provinces          enable row level security;
alter table public.kabupaten          enable row level security;
alter table public.kecamatan          enable row level security;
alter table public.kelurahan          enable row level security;
alter table public.brands             enable row level security;
alter table public.malls              enable row level security;
alter table public.stores             enable row level security;
alter table public.pois               enable row level security;
alter table public.competitor_stores  enable row level security;
alter table public.mall_tenants       enable row level security;

-- Public read policies
create policy "public_read_countries"        on public.countries          for select using (true);
create policy "public_read_provinces"        on public.provinces          for select using (true);
create policy "public_read_kabupaten"        on public.kabupaten          for select using (true);
create policy "public_read_kecamatan"        on public.kecamatan          for select using (true);
create policy "public_read_kelurahan"        on public.kelurahan          for select using (true);
create policy "public_read_brands"           on public.brands             for select using (true);
create policy "public_read_malls"            on public.malls              for select using (true);
create policy "public_read_stores"           on public.stores             for select using (true);
create policy "public_read_pois"             on public.pois               for select using (true);
create policy "public_read_competitors"      on public.competitor_stores  for select using (true);
create policy "public_read_mall_tenants"     on public.mall_tenants       for select using (true);

-- All write operations on master tables are done via service_role (server-side)
-- No INSERT/UPDATE/DELETE policy for anon on these tables.
-- (Service role bypasses RLS by default, so no policy needed.)

-- Staging tables: NO anon access (only service_role can read/write)
alter table public.staging_stores       enable row level security;
alter table public.staging_competitors  enable row level security;
alter table public.staging_malls        enable row level security;
-- No policies = no anon access. Only service_role can access.

-- Scraper runs: NO anon access
alter table public.scraper_runs enable row level security;

-- ML tables: public read, write via service_role only
alter table public.ml_models       enable row level security;
alter table public.training_runs   enable row level security;
alter table public.predictions     enable row level security;
create policy "public_read_ml_models"     on public.ml_models     for select using (true);
create policy "public_read_training_runs" on public.training_runs for select using (true);
create policy "public_read_predictions"   on public.predictions   for select using (true);

-- Reports: public read
alter table public.reports enable row level security;
create policy "public_read_reports" on public.reports for select using (true);

-- Field surveys: anon CAN submit (PWA), but cannot read or modify
alter table public.field_surveys enable row level security;
create policy "anon_insert_surveys" on public.field_surveys
  for insert with check (true);
-- No SELECT/UPDATE policy for anon: review workflow happens server-side.

-- AB tests: public read
alter table public.ab_tests enable row level security;
create policy "public_read_ab_tests" on public.ab_tests for select using (true);

-- =============================================================
-- Helper function: merge staging -> master
-- Called by Vercel API route when Data Team approves a staging record
-- =============================================================
create or replace function public.merge_staging_store(p_staging_id text, p_reviewer text default 'system')
returns text
language pllgsql
security definer
as $$
declare
  v_staging record;
  v_store_id text;
begin
  select * into v_staging from public.staging_stores where id = p_staging_id and review_status = 'pending';
  if not found then
    raise exception 'Staging record % not found or already reviewed', p_staging_id;
  end if;

  -- Generate store ID
  v_store_id := coalesce(v_staging.merged_to, gen_random_uuid()::text);

  -- Insert into stores (upsert by id)
  insert into public.stores (
    id, brand_id, brand_name, brand_category, parent, name, lat, lng,
    kec, kab, city, country, is_in_mall, mall_id, mall_name, address,
    opened_year, estimated_size_m2, confirmed, source
  ) values (
    v_store_id, v_staging.brand_name, v_staging.brand_name, v_staging.brand_category::brand_category_enum,
    v_staging.parent::brand_parent_enum, v_staging.name, v_staging.lat, v_staging.lng,
    v_staging.kec, v_staging.kab, v_staging.city, v_staging.country,
    v_staging.is_in_mall, null, v_staging.mall_name, v_staging.address,
    null, v_staging.estimated_size_m2, true, v_staging.source::text
  )
  on conflict (id) do update set
    name = excluded.name,
    lat = excluded.lat,
    lng = excluded.lng,
    kec = excluded.kec,
    kab = excluded.kab,
    address = excluded.address,
    confirmed = true,
    source = excluded.source,
    updated_at = now();

  -- Mark staging record as merged
  update public.staging_stores
  set review_status = 'merged',
      reviewer = p_reviewer,
      reviewed_at = now(),
      merged_to = v_store_id
  where id = p_staging_id;

  return v_store_id;
end;
$$;
comment on function public.merge_staging_store is 'Move an approved staging store record into the master stores table. Called by Vercel API route when Data Team approves.';

-- Same pattern for competitors
create or replace function public.merge_staging_competitor(p_staging_id text, p_reviewer text default 'system')
returns text
language plpgsql
security definer
as $$
declare
  v_staging record;
  v_id text;
begin
  select * into v_staging from public.staging_competitors where id = p_staging_id and review_status = 'pending';
  if not found then
    raise exception 'Staging record % not found or already reviewed', p_staging_id;
  end if;

  v_id := coalesce(v_staging.merged_to, gen_random_uuid()::text);

  insert into public.competitor_stores (
    id, brand_name, brand_category, name, lat, lng,
    kec, kab, city, country, address, is_in_mall, mall_name,
    source, source_url, last_crawled_at
  ) values (
    v_id, v_staging.brand_name, v_staging.brand_category::competitor_category_enum,
    v_staging.name, v_staging.lat, v_staging.lng,
    v_staging.kec, v_staging.kab, v_staging.city, v_staging.country,
    v_staging.address, v_staging.is_in_mall, v_staging.mall_name,
    v_staging.source::scraper_source_enum, v_staging.source_url, v_staging.last_crawled_at
  )
  on conflict (id) do update set
    name = excluded.name,
    lat = excluded.lat,
    lng = excluded.lng,
    address = excluded.address,
    source = excluded.source,
    updated_at = now();

  update public.staging_competitors
  set review_status = 'merged',
      reviewer = p_reviewer,
      reviewed_at = now(),
      merged_to = v_id
  where id = p_staging_id;

  return v_id;
end;
$$;

-- Same pattern for malls
create or replace function public.merge_staging_mall(p_staging_id text, p_reviewer text default 'system')
returns text
language plpgsql
security definer
as $$
declare
  v_staging record;
  v_id text;
begin
  select * into v_staging from public.staging_malls where id = p_staging_id and review_status = 'pending';
  if not found then
    raise exception 'Staging record % not found or already reviewed', p_staging_id;
  end if;

  v_id := coalesce(v_staging.merged_to, gen_random_uuid()::text);

  insert into public.malls (
    id, name, lat, lng, kec, kab, city, country,
    gla_m2, opened_year, class, source
  ) values (
    v_id, v_staging.name, v_staging.lat, v_staging.lng,
    v_staging.kec, v_staging.kab, v_staging.city, v_staging.country,
    v_staging.gla_m2, v_staging.opened_year, v_staging.class::mall_class_enum,
    v_staging.source::text
  )
  on conflict (id) do update set
    name = excluded.name,
    lat = excluded.lat,
    lng = excluded.lng,
    gla_m2 = excluded.gla_m2,
    updated_at = now();

  update public.staging_malls
  set review_status = 'merged',
      reviewer = p_reviewer,
      reviewed_at = now(),
      merged_to = v_id
  where id = p_staging_id;

  return v_id;
end;
$$;

-- =============================================================
-- Reject staging record (no merge)
-- =============================================================
create or replace function public.reject_staging(p_table text, p_staging_id text, p_reviewer text, p_notes text)
returns void
language plpgsql
security definer
as $$
begin
  execute format(
    'update public.%I set review_status = ''rejected'', reviewer = $1, reviewer_notes = $2, reviewed_at = now() where id = $3',
    p_table
  ) using p_reviewer, p_notes, p_staging_id;
end;
$$;
