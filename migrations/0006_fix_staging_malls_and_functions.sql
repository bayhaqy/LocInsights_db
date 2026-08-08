-- =============================================================
-- LocInsight — Fix Script: Re-apply corrected functions + staging_malls
-- =============================================================

-- 1. Drop the old (broken) staging_malls table if it exists
drop table if exists public.staging_malls cascade;

-- 2. Recreate is_on_bali_land with permissive bounding-box check
create or replace function public.is_on_bali_land(p_lat double precision, p_lng double precision)
returns boolean
language plpgsql
immutable
as $$
begin
  return p_lat between -8.84 and -8.05
     and p_lng between 114.42 and 115.72;
end;
$$;

-- 3. Recreate staging_malls with correct default
create table if not exists public.staging_malls (
  id              text primary key default gen_random_uuid()::text,
  batch_id        text not null,
  source          scraper_source_enum not null default 'osm',
  source_url      text default 'https://www.nowbali.co.id',
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

-- 4. Recreate merge_staging_store (fixed: plpgsql not pllgsql)
create or replace function public.merge_staging_store(p_staging_id text, p_reviewer text default 'system')
returns text
language plpgsql
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

  v_store_id := coalesce(v_staging.merged_to, gen_random_uuid()::text);

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

  update public.staging_stores
  set review_status = 'merged',
      reviewer = p_reviewer,
      reviewed_at = now(),
      merged_to = v_store_id
  where id = p_staging_id;

  return v_store_id;
end;
$$;

-- 5. Recreate merge_staging_competitor
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

-- 6. Recreate merge_staging_mall
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

-- 7. Add RLS to staging_malls (was missed)
alter table public.staging_malls enable row level security;

-- 8. Re-insert POIs that previously failed (with corrected is_on_bali_land function)
insert into public.pois (id, name, type, lat, lng, kec, kab, city, country, magnitude, notes, source)
values
  ('poi-airport',      'Ngurah Rai International Airport', 'airport',          -8.7481, 115.1672, 'Kuta Selatan', 'Badung',   'Kuta',     'Indonesia', 95, 'Main gateway to Bali',                     'Google Maps POI'),
  ('poi-tanahlot',     'Tanah Lot Temple',                'temple',           -8.6211, 115.0867, 'Kediri',        'Tabanan',  'Tanah Lot','Indonesia', 80, 'Iconic sea temple, major tourist draw',     'Google Maps POI'),
  ('poi-uluwatu',      'Uluwatu Temple',                  'temple',           -8.8291, 115.0847, 'Kuta Selatan',  'Badung',   'Uluwatu',  'Indonesia', 78, 'Cliff-top temple, sunset attraction',       'Google Maps POI'),
  ('poi-ulundanu',     'Ulun Danu Beratan Temple',        'temple',           -8.2744, 115.1667, 'Sukasada',      'Buleleng', 'Bedugul',  'Indonesia', 65, 'Lake temple, mountain destination',         'Google Maps POI'),
  ('poi-besakih',      'Besakih Mother Temple',           'temple',           -8.3783, 115.4483, 'Rendang',       'Karangasem','Besakih', 'Indonesia', 70, 'Bali''s largest and holiest temple',        'Google Maps POI'),
  ('poi-kuta-beach',   'Kuta Beach',                      'beach',            -8.7189, 115.1689, 'Kuta',          'Badung',   'Kuta',     'Indonesia', 95, 'Most visited beach in Bali',                'Google Maps POI'),
  ('poi-seminyak-bch', 'Seminyak Beach',                  'beach',            -8.6717, 115.1583, 'Kuta Utara',    'Badung',   'Seminyak', 'Indonesia', 78, 'Upscale beach, beach clubs',                'Google Maps POI'),
  ('poi-sanur-beach',  'Sanur Beach',                     'beach',            -8.6736, 115.2642, 'Denpasar Selatan','Denpasar','Sanur',   'Indonesia', 70, 'Sunrise beach, family-friendly',            'Google Maps POI'),
  ('poi-nusadua-bch',  'Nusa Dua Beach',                  'beach',            -8.8039, 115.2281, 'Kuta Selatan',  'Badung',   'Nusa Dua', 'Indonesia', 82, 'Resort enclave beach',                      'Google Maps POI'),
  ('poi-canggu-bch',   'Canggu Beach',                    'beach',            -8.6500, 115.1383, 'Kuta Utara',    'Badung',   'Canggu',   'Indonesia', 85, 'Surfing hotspot, expat hub',                'Google Maps POI'),
  ('poi-ubud-monkey',  'Ubud Monkey Forest',              'tourist_attraction',-8.5197, 115.2608, 'Ubud',          'Gianyar',  'Ubud',     'Indonesia', 80, 'Sacred monkey sanctuary',                   'Google Maps POI'),
  ('poi-ubud-palace',  'Puri Saren Agung Ubud Palace',    'tourist_attraction',-8.5069, 115.2625, 'Ubud',          'Gianyar',  'Ubud',     'Indonesia', 60, 'Royal palace, cultural events',             'Google Maps POI'),
  ('poi-ubud-market',  'Ubud Traditional Art Market',     'market',           -8.5078, 115.2619, 'Ubud',          'Gianyar',  'Ubud',     'Indonesia', 75, 'Souvenir and craft market',                 'Google Maps POI'),
  ('poi-mount-agung',  'Mount Agung',                     'tourist_attraction',-8.3428, 115.5083, 'Selat',         'Karangasem','Mount Agung','Indonesia', 55, 'Highest peak in Bali, trekking',            'Google Maps POI'),
  ('poi-mount-batur',  'Mount Batur Caldera',             'tourist_attraction',-8.2417, 115.3744, 'Kintamani',     'Bangli',   'Kintamani','Indonesia', 65, 'Sunrise trekking destination',              'Google Maps POI'),
  ('poi-penida',       'Nusa Penida Island',              'tourist_attraction',-8.7533, 115.4881, 'Nusa Penida',    'Klungkung','Nusa Penida','Indonesia', 75, 'Day-trip island, cliff diving',             'Google Maps POI'),
  ('poi-gwk',          'Garuda Wisnu Kencana Cultural Park','tourist_attraction',-8.8106, 115.1664, 'Kuta Selatan',  'Badung',   'Uluwatu',  'Indonesia', 65, 'GWK statue, cultural park',                 'Google Maps POI'),
  ('poi-benoa-port',   'Benoa Harbour',                   'port',             -8.7625, 115.2103, 'Kuta Selatan',  'Badung',   'Benoa',    'Indonesia', 60, 'Cruise and yacht port',                     'Google Maps POI'),
  ('poi-bedugul-mkt',  'Bedugul Botanical Garden',        'tourist_attraction',-8.2778, 115.1503, 'Sukasada',      'Buleleng', 'Bedugul',  'Indonesia', 50, 'Botanical garden, mountain resort',         'Google Maps POI'),
  ('poi-tirta-empul',  'Tirta Empul Holy Spring',         'temple',           -8.4172, 115.3311, 'Tampaksiring',  'Gianyar',  'Tampaksiring','Indonesia', 55, 'Purification water temple',                 'Google Maps POI'),
  ('poi-gilimanuk',    'Gilimanuk Port',                  'port',             -8.3389, 114.6550, 'Melaya',        'Jembrana', 'Gilimanuk','Indonesia', 45, 'Java-Bali ferry terminal',                  'Google Maps POI'),
  ('poi-padangbai',    'Padangbai Port',                  'port',             -8.5308, 115.5008, 'Manggis',       'Karangasem','Padangbai','Indonesia', 50, 'Lombok ferry terminal',                     'Google Maps POI'),
  ('poi-unud',         'Udayana University',              'university',       -8.7936, 115.1881, 'Kuta Selatan',  'Badung',   'Jimbaran', 'Indonesia', 70, 'Largest university in Bali',                'Google Maps POI'),
  ('poi-undiksha',     'Undiksha University',             'university',       -8.1144, 115.0922, 'Buleleng',      'Buleleng', 'Singaraja','Indonesia', 45, 'Northern Bali main university',             'Google Maps POI'),
  ('poi-sanglah',      'Sanglah General Hospital',        'hospital',         -8.6697, 115.2097, 'Denpasar Selatan','Denpasar','Denpasar','Indonesia', 85, 'Bali''s largest referral hospital',         'Google Maps POI'),
  ('poi-bali-mandara', 'Bali Mandara Toll Road',          'transit_hub',      -8.7300, 115.1950, 'Denpasar Selatan','Denpasar','Denpasar','Indonesia', 60, 'Benoa-Nusa Dua-Ngurah Rai toll road',       'Google Maps POI')
on conflict (id) do nothing;
