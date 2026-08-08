-- =============================================================
-- LocInsight — Supabase Migration 0003
-- Staging tables (scraper output pending approval) + ML tables
-- =============================================================

-- =============================================================
-- 1. STAGING_STORES — raw scraped stores awaiting review
-- =============================================================
create table if not exists public.staging_stores (
  id              text primary key default gen_random_uuid()::text,
  batch_id        text not null,
  source          scraper_source_enum not null default 'osm',
  source_url      text default '',
  last_crawled_at timestamptz default now(),
  -- Raw payload (untyped, mirrors target schema)
  brand_name      text not null,
  brand_category  text,
  parent          text default 'MAA',
  name            text not null,
  lat             double precision,
  lng             double precision,
  kec             text default '',
  kab             text default '',
  city            text default '',
  country         text default 'Indonesia',
  address         text default '',
  is_in_mall      boolean default false,
  mall_name       text,
  estimated_size_m2 integer,
  -- Review workflow
  review_status   approval_status_enum not null default 'pending',
  reviewer        text,
  reviewer_notes  text default '',
  reviewed_at     timestamptz,
  -- Merge target (NULL until merged)
  merged_to       text,                  -- references stores(id) once approved
  -- Quality checks
  quality_issues  text default '[]'::jsonb::text,
  is_duplicate    boolean default false,
  -- Audit
  created_at      timestamptz not null default now()
);
create index if not exists staging_stores_batch_idx     on public.staging_stores (batch_id);
create index if not exists staging_stores_status_idx    on public.staging_stores (review_status);
create index if not exists staging_stores_lat_lng_idx   on public.staging_stores (lat, lng);
comment on table public.staging_stores is 'Raw scraped store data pending Data Team review before merging into stores table';

-- =============================================================
-- 2. STAGING_COMPETITORS — raw scraped competitor stores
-- =============================================================
create table if not exists public.staging_competitors (
  id              text primary key default gen_random_uuid()::text,
  batch_id        text not null,
  source          scraper_source_enum not null default 'osm',
  source_url      text default '',
  last_crawled_at timestamptz default now(),
  brand_name      text not null,
  brand_category  text,
  name            text not null,
  lat             double precision,
  lng             double precision,
  kec             text default '',
  kab             text default '',
  city            text default '',
  country         text default 'Indonesia',
  address         text default '',
  is_in_mall      boolean default false,
  mall_name       text,
  review_status   approval_status_enum not null default 'pending',
  reviewer        text,
  reviewer_notes  text default '',
  reviewed_at     timestamptz,
  merged_to       text,
  quality_issues  text default '[]'::jsonb::text,
  is_duplicate    boolean default false,
  created_at      timestamptz not null default now()
);
create index if not exists staging_comp_batch_idx     on public.staging_competitors (batch_id);
create index if not exists staging_comp_status_idx    on public.staging_competitors (review_status);

-- =============================================================
-- 3. STAGING_MALLS — raw scraped malls
-- =============================================================
create table if not exists public.staging_malls (
  id              text primary key default gen_random_uuid()::text,
  batch_id        text not null,
  source          scraper_source_enum not null default 'nowbali.co.id',
  source_url      text default '',
  last_crawled_at timestamptz default now(),
  name            text not null,
  lat             double precision,
  lng             double precision,
  kec             text default '',
  kab             text default '',
  city            text default '',
  address         text default '',
  gla_m2          integer,
  opened_year     integer,
  class           text,
  review_status   approval_status_enum not null default 'pending',
  reviewer        text,
  reviewer_notes  text default '',
  reviewed_at     timestamptz,
  merged_to       text,
  quality_issues  text default '[]'::jsonb::text,
  is_duplicate    boolean default false,
  created_at      timestamptz not null default now()
);
create index if not exists staging_malls_batch_idx    on public.staging_malls (batch_id);
create index if not exists staging_malls_status_idx   on public.staging_malls (review_status);

-- =============================================================
-- 4. SCRAPER_RUNS — execution log
-- =============================================================
create table if not exists public.scraper_runs (
  id            text primary key default gen_random_uuid()::text,
  query         text not null,
  source        scraper_source_enum not null default 'osm',
  status        scraper_status_enum not null default 'pending',
  found_count   integer default 0,
  saved_count   integer default 0,
  error         text,
  result_json   jsonb default '[]'::jsonb,
  started_at    timestamptz not null default now(),
  finished_at   timestamptz
);
create index if not exists scraper_runs_status_idx  on public.scraper_runs (status);
create index if not exists scraper_runs_source_idx  on public.scraper_runs (source);

-- =============================================================
-- 5. ML_MODELS — model registry
-- =============================================================
create table if not exists public.ml_models (
  id              text primary key,
  name            text not null,
  version         text not null,
  type            ml_model_type_enum not null,
  algorithm       ml_algorithm_enum not null,
  description     text default '',
  features        jsonb default '[]'::jsonb,
  hyperparameters jsonb default '{}'::jsonb,
  metrics         jsonb default '{}'::jsonb,
  status          ml_model_status_enum default 'active',
  trained_at      timestamptz default now(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- =============================================================
-- 6. TRAINING_RUNS — auto-retrain pipeline log
-- =============================================================
create table if not exists public.training_runs (
  id                  text primary key default gen_random_uuid()::text,
  model_id            text not null references public.ml_models(id) on delete cascade,
  model_name          text not null,
  algorithm           ml_algorithm_enum not null,
  status              training_status_enum default 'pending',
  dataset_size        integer default 0,
  features            jsonb default '[]'::jsonb,
  hyperparameters     jsonb default '{}'::jsonb,
  metrics             jsonb default '{}'::jsonb,
  feature_importance  jsonb default '[]'::jsonb,
  model_artifact_url  text,    -- URL to HF Space model artifact
  train_duration_ms   integer,
  error               text,
  started_at          timestamptz not null default now(),
  finished_at         timestamptz
);
create index if not exists training_runs_model_idx    on public.training_runs (model_id);
create index if not exists training_runs_status_idx   on public.training_runs (status);

-- =============================================================
-- 7. PREDICTIONS — model outputs (site scores, blank spots)
-- =============================================================
create table if not exists public.predictions (
  id              text primary key default gen_random_uuid()::text,
  model_id        text not null references public.ml_models(id) on delete cascade,
  target_type     prediction_target_enum not null,
  target_id       text not null,
  target_name     text default '',
  lat             double precision,
  lng             double precision,
  geom            geography(point, 4326)
    generated always as (st_makepoint(lng, lat)::geography) stored,
  prediction      double precision not null,    -- 0..1 probability or score
  score_pct       double precision generated always as (prediction * 100.0) stored,
  confidence      double precision default 0,
  explanation     jsonb default '{}'::jsonb,
  is_blank_spot   boolean default false,
  created_at      timestamptz not null default now()
);
create index if not exists predictions_model_idx       on public.predictions (model_id);
create index if not exists predictions_target_idx      on public.predictions (target_type, target_id);
create index if not exists predictions_blank_spot_idx  on public.predictions (is_blank_spot) where is_blank_spot = true;
create index if not exists predictions_geom_idx        on public.predictions using gist (geom);

-- =============================================================
-- 8. REPORTS — generated report metadata
-- =============================================================
create table if not exists public.reports (
  id            text primary key default gen_random_uuid()::text,
  title         text not null,
  type          text not null,
  format        report_format_enum not null,
  filters       jsonb default '{}'::jsonb,
  status        report_status_enum default 'pending',
  file_path     text,
  file_url      text,
  file_size_kb  integer,
  generated_by  text default 'system',
  created_at    timestamptz not null default now()
);

-- =============================================================
-- 9. FIELD_SURVEYS — surveyor PWA submissions
-- =============================================================
create table if not exists public.field_surveys (
  id                      text primary key default gen_random_uuid()::text,
  kelurahan_id            text,
  kelurahan_name          text default '',
  lat                     double precision not null,
  lng                     double precision not null,
  geom                    geography(point, 4326)
    generated always as (st_makepoint(lng, lat)::geography) stored,
  accuracy_m              double precision,
  surveyor_name           text not null,
  survey_type             survey_type_enum not null,
  brand_name              text,
  brand_category          text,
  outlet_name             text default '',
  address                 text default '',
  is_in_mall              boolean default false,
  mall_name               text default '',
  condition               outlet_condition_enum,
  estimated_size_m2       integer,
  foot_traffic_observation traffic_enum,
  notes                   text default '',
  photo_urls              jsonb default '[]'::jsonb,
  review_status           review_status_enum default 'pending',
  reviewer_notes          text default '',
  submitted_at            timestamptz not null default now(),
  reviewed_at             timestamptz
);
create index if not exists field_surveys_geom_idx     on public.field_surveys using gist (geom);
create index if not exists field_surveys_status_idx   on public.field_surveys (review_status);
create index if not exists field_surveys_surveyor_idx on public.field_surveys (surveyor_name);

-- =============================================================
-- 10. AB_TESTS — A/B simulation runs
-- =============================================================
create table if not exists public.ab_tests (
  id            text primary key default gen_random_uuid()::text,
  name          text not null,
  scenario_a    jsonb not null,
  scenario_b    jsonb not null,
  metrics       jsonb default '{}'::jsonb,
  winner        text,
  created_by    text default 'system',
  created_at    timestamptz not null default now()
);

-- Triggers
do $$
declare t text;
begin
  for t in select unnest(array[
    'staging_stores','staging_competitors','staging_malls',
    'scraper_runs','ml_models','training_runs','reports','field_surveys','ab_tests'
  ])
  loop
    execute format($f$
      drop trigger if exists %I_set_updated_at on public.%I;
      create trigger %I_set_updated_at before update on public.%I
      for each row execute function public.set_updated_at();
    $f$, t, t, t, t);
  end loop;
end $$;
