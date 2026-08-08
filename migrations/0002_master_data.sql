-- =============================================================
-- LocInsight — Supabase Migration 0002
-- Master data tables (administrative hierarchy + brands + malls + stores + POIs)
-- All tables include: city, country, source, created_at, updated_at
-- All tables use PostGIS geography for spatial queries
-- =============================================================

-- =============================================================
-- 1. COUNTRIES (lookup)
-- =============================================================
create table if not exists public.countries (
  id          text primary key,
  name        text not null,
  iso2        text,
  iso3        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
comment on table public.countries is 'Master list of countries (currently Indonesia only; future-proof for ASEAN rollout)';

-- =============================================================
-- 2. PROVINCES
-- =============================================================
create table if not exists public.provinces (
  code        text primary key,           -- BPS 2-digit code, e.g., 51
  name        text not null,
  country_id  text not null default 'ID' references public.countries(id),
  country     text not null default 'Indonesia',
  lat         double precision not null,
  lng         double precision not null,
  geom        geography(point, 4326)
    generated always as (st_makepoint(lng, lat)::geography) stored,
  area_km2    double precision,
  population  integer,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
comment on table public.provinces is 'Provinces (Bali = code 51)';

-- =============================================================
-- 3. KABUPATEN / KOTA
-- =============================================================
create table if not exists public.kabupaten (
  code                 text primary key,       -- BPS 4-digit
  name                 text not null,
  type                 admin_type_enum not null default 'Kabupaten',
  capital              text,
  province_code        text not null references public.provinces(code),
  province             text not null default 'Bali',
  country              text not null default 'Indonesia',
  city                 text not null default '',
  lat                  double precision not null,
  lng                  double precision not null,
  geom                 geography(point, 4326)
    generated always as (st_makepoint(lng, lat)::geography) stored,
  area_km2             double precision,
  population_2024      integer,
  population_density   integer,
  gdrp_per_capita_juta double precision,
  tier                 admin_tier_enum,
  hdmi_2024            double precision,
  tourist_hotels       integer default 0,
  notes                text default '',
  source               text default 'BPS Bali 2024',
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
create index if not exists kabupaten_geom_idx     on public.kabupaten using gist (geom);
create index if not exists kabupaten_province_idx  on public.kabupaten (province_code);
create index if not exists kabupaten_tier_idx      on public.kabupaten (tier);

-- =============================================================
-- 4. KECAMATAN
-- =============================================================
create table if not exists public.kecamatan (
  code            text primary key,           -- BPS 6-digit
  name            text not null,
  kabupaten_code  text not null references public.kabupaten(code),
  province        text not null default 'Bali',
  country         text not null default 'Indonesia',
  city            text not null default '',
  lat             double precision not null,
  lng             double precision not null,
  geom            geography(point, 4326)
    generated always as (st_makepoint(lng, lat)::geography) stored,
  population_2024 integer,
  area_km2        double precision,
  tier            admin_tier_enum,
  urban_score     integer,
  is_capital      boolean default false,
  source          text default 'BPS Bali 2024',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists kecamatan_geom_idx        on public.kecamatan using gist (geom);
create index if not exists kecamatan_kabupaten_idx    on public.kecamatan (kabupaten_code);

-- =============================================================
-- 5. KELURAHAN / DESA
-- =============================================================
create table if not exists public.kelurahan (
  id                  text primary key,
  code                text not null unique,
  name                text not null,
  kec_code            text not null references public.kecamatan(code),
  kec_name            text,
  kab_code            text not null references public.kabupaten(code),
  kab_name            text,
  province            text not null default 'Bali',
  country             text not null default 'Indonesia',
  city                text not null default '',
  tier                admin_tier_enum,
  lat                 double precision not null,
  lng                 double precision not null,
  geom                geography(point, 4326)
    generated always as (st_makepoint(lng, lat)::geography) stored,
  population          integer,
  area_km2            double precision,
  density             integer,
  urban_index         integer,
  income_index        integer,
  tourist_index       integer,
  transport_index     integer,
  poi_density_index   integer,
  is_coastal          boolean default false,
  source              text default 'BPS Bali 2024',
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index if not exists kelurahan_geom_idx     on public.kelurahan using gist (geom);
create index if not exists kelurahan_kec_idx      on public.kelurahan (kec_code);
create index if not exists kelurahan_kab_idx      on public.kelurahan (kab_code);
create index if not exists kelurahan_tier_idx     on public.kelurahan (tier);
create index if not exists kelurahan_name_trgm    on public.kelurahan using gin (name gin_trgm_ops);

-- =============================================================
-- 6. BRANDS
-- =============================================================
create table if not exists public.brands (
  id                  text primary key,
  name                text not null,
  parent              brand_parent_enum not null default 'MAA',
  category            brand_category_enum not null,
  origin_country      text default 'Indonesia',
  format              text,
  location_preference location_format_enum default 'both',
  typical_size_m2     integer default 0,
  target_audience     text default '',
  price_segment       brand_price_segment_enum default 'mid',
  brand_strength      double precision default 0.5 check (brand_strength between 0 and 1),
  notes               text default '',
  city                text default '',
  country             text default 'Indonesia',
  source              text default 'map.co.id/brands',
  is_active           boolean default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index if not exists brands_parent_idx     on public.brands (parent);
create index if not exists brands_category_idx   on public.brands (category);
create index if not exists brands_name_trgm      on public.brands using gin (name gin_trgm_ops);

-- =============================================================
-- 7. MALLS
-- =============================================================
create table if not exists public.malls (
  id                  text primary key,
  name                text not null,
  lat                 double precision not null,
  lng                 double precision not null,
  geom                geography(point, 4326)
    generated always as (st_makepoint(lng, lat)::geography) stored,
  kec                 text default '',
  kab                 text default '',
  city                text default '',
  country             text default 'Indonesia',
  gla_m2              integer default 0,
  opened_year         integer,
  class               mall_class_enum default 'regional',
  anchor_count        integer default 0,
  has_cinema          boolean default false,
  has_supermarket     boolean default false,
  has_department_store boolean default false,
  visitor_estimate_daily integer default 0,
  notes               text default '',
  source              text default 'nowbali.co.id',
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index if not exists malls_geom_idx       on public.malls using gist (geom);
create index if not exists malls_kab_idx        on public.malls (kab);
create index if not exists malls_name_trgm      on public.malls using gin (name gin_trgm_ops);

-- =============================================================
-- 8. STORES (MAP/MAA outlets)
-- Coordinate constraint: must be on Bali land (anti-ocean safeguard)
-- =============================================================
create table if not exists public.stores (
  id                  text primary key,
  brand_id            text not null references public.brands(id) on delete cascade,
  brand_name          text not null,
  brand_category      brand_category_enum,
  parent              brand_parent_enum not null default 'MAA',
  name                text not null,
  lat                 double precision not null,
  lng                 double precision not null,
  geom                geography(point, 4326)
    generated always as (st_makepoint(lng, lat)::geography) stored,
  kec                 text default '',
  kab                 text default '',
  city                text default '',
  country             text default 'Indonesia',
  is_in_mall          boolean default false,
  mall_id             text references public.malls(id),
  mall_name           text,
  address             text default '',
  opened_year         integer,
  estimated_size_m2   integer default 0,
  confirmed           boolean default false,
  source              text default 'map.co.id directory',
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  -- Anti-ocean constraint (Bali PoC):
  constraint stores_on_bali_land_chk check (public.is_on_bali_land(lat, lng))
);
create index if not exists stores_geom_idx       on public.stores using gist (geom);
create index if not exists stores_brand_idx      on public.stores (brand_id);
create index if not exists stores_kab_idx        on public.stores (kab);
create index if not exists stores_mall_idx       on public.stores (mall_id);
create index if not exists stores_name_trgm      on public.stores using gin (name gin_trgm_ops);

-- =============================================================
-- 9. POIs (Points of Interest)
-- =============================================================
create table if not exists public.pois (
  id          text primary key,
  name        text not null,
  type        poi_type_enum not null,
  lat         double precision not null,
  lng         double precision not null,
  geom        geography(point, 4326)
    generated always as (st_makepoint(lng, lat)::geography) stored,
  kec         text default '',
  kab         text default '',
  city        text default '',
  country     text default 'Indonesia',
  magnitude   double precision default 0,
  notes       text default '',
  source      text default 'Google Maps POI',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint pois_on_bali_land_chk check (public.is_on_bali_land(lat, lng))
);
create index if not exists pois_geom_idx        on public.pois using gist (geom);
create index if not exists pois_type_idx        on public.pois (type);
create index if not exists pois_kab_idx         on public.pois (kab);

-- =============================================================
-- 10. COMPETITOR STORES (Indomaret, Alfamart, Kawan Lama, Trans Group, Havaianas, etc.)
-- =============================================================
create table if not exists public.competitor_stores (
  id              text primary key default gen_random_uuid()::text,
  brand_name      text not null,
  brand_category  competitor_category_enum not null default 'other',
  name            text not null,
  lat             double precision not null,
  lng             double precision not null,
  geom            geography(point, 4326)
    generated always as (st_makepoint(lng, lat)::geography) stored,
  kec             text default '',
  kab             text default '',
  city            text default '',
  country         text default 'Indonesia',
  address         text default '',
  is_in_mall      boolean default false,
  mall_id         text references public.malls(id),
  mall_name       text,
  source          scraper_source_enum default 'osm',
  source_url      text default '',
  last_crawled_at timestamptz default now(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint competitor_on_bali_land_chk check (public.is_on_bali_land(lat, lng))
);
create index if not exists competitor_geom_idx     on public.competitor_stores using gist (geom);
create index if not exists competitor_brand_idx    on public.competitor_stores (brand_name);
create index if not exists competitor_category_idx on public.competitor_stores (brand_category);
create index if not exists competitor_kab_idx      on public.competitor_stores (kab);

-- =============================================================
-- 11. MALL TENANTS (live from scraper)
-- =============================================================
create table if not exists public.mall_tenants (
  id              text primary key default gen_random_uuid()::text,
  mall_id         text references public.malls(id),
  mall_name       text not null,
  brand_name      text not null,
  brand_category  brand_category_enum,
  is_map_brand    boolean default false,
  is_competitor   boolean default false,
  floor           text default '',
  category        text default '',
  source          scraper_source_enum default 'osm',
  source_url      text default '',
  last_crawled_at timestamptz default now(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists mall_tenants_mall_idx     on public.mall_tenants (mall_id);
create index if not exists mall_tenants_brand_idx    on public.mall_tenants (brand_name);
create index if not exists mall_tenants_map_brand_idx on public.mall_tenants (is_map_brand);

-- =============================================================
-- Updated_at triggers for all master tables
-- =============================================================
do $$
declare t text;
begin
  for t in select unnest(array[
    'countries','provinces','kabupaten','kecamatan','kelurahan',
    'brands','malls','stores','pois','competitor_stores','mall_tenants'
  ])
  loop
    execute format($f$
      create trigger set_updated_at before update on public.%I
      for each row execute function public.set_updated_at();
      drop trigger if exists %I_set_updated_at on public.%I;
      create trigger %I_set_updated_at before update on public.%I
      for each row execute function public.set_updated_at();
    $f$, t, t, t, t, t);
  end loop;
end $$;
