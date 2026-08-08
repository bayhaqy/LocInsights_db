-- =============================================================
-- LocInsight — Supabase Migration 0001
-- Extensions, enums, and shared utilities
-- Author: MAP Active Data Team (Achmad Bayhaqy)
-- Date: 2026-08-08
-- Scope: Bali PoC (future-proof for national rollout)
-- =============================================================

-- Required extensions
create extension if not exists "uuid-ossp";
create extension if not exists "postgis";
create extension if not exists "pgcrypto";
create extension if not exists "pg_trgm";     -- fuzzy search on store/brand names
create extension if not exists "btree_gist";  -- composite constraints

-- =============================================================
-- Enums
-- =============================================================
do $$ begin
  create type brand_parent_enum        as enum ('MAP','MAA','OTHER');
  create type brand_category_enum      as enum (
    'sports','fashion','food_beverage','department_store','kids','lifestyle','beauty','athleisure','footwear'
  );
  create type brand_price_segment_enum as enum ('mass','mid','premium','luxury');
  create type location_format_enum     as enum ('mall','street','both');
  create type mall_class_enum          as enum ('super_regional','regional','community','specialty');
  create type poi_type_enum            as enum (
    'tourist_attraction','beach','temple','hotel_cluster','transit_hub','university','hospital',
    'office_cluster','port','market','school','government','stadium','airport'
  );
  create type admin_tier_enum          as enum ('1','2','3');
  create type admin_type_enum          as enum ('Kabupaten','Kota');
  create type scraper_status_enum      as enum ('pending','running','success','failed','partial');
  create type scraper_source_enum      as enum ('nominatim','overpass','bps','map_co_id','mapactive_id','manual','google_places','osm');
  create type report_status_enum       as enum ('pending','generated','failed');
  create type report_format_enum       as enum ('pdf','xlsx','csv','json');
  create type competitor_category_enum as enum (
    'convenience_store','fast_food','coffee','fashion','beauty','supermarket','pharmacy','department_store','sports','other'
  );
  create type ml_model_type_enum       as enum ('site_scoring','revenue_forecast','cannibalization','cluster','blank_spot');
  create type ml_algorithm_enum        as enum ('huff_gravity','gradient_boosting','random_forest','xgboost','kmeans','dbscan','gbr_regressor');
  create type ml_model_status_enum     as enum ('active','archived','experimental');
  create type training_status_enum     as enum ('pending','running','completed','failed');
  create type prediction_target_enum   as enum ('kelurahan','store','mall','candidate_site');
  create type survey_type_enum         as enum ('site_visit','competitor_audit','mall_audit','market_observations');
  create type review_status_enum       as enum ('pending','approved','rejected','imported');
  create type outlet_condition_enum    as enum ('excellent','good','fair','poor','under_construction');
  create type traffic_enum             as enum ('low','medium','high','very_high');
  create type approval_status_enum     as enum ('pending','approved','rejected','merged');
exception
  when duplicate_object then null;
end $$;

-- =============================================================
-- updated_at trigger helper
-- =============================================================
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- =============================================================
-- Geo-validation helper:
-- Returns TRUE if a (lat,lng) point is within Bali's bounding box (not in ocean)
-- Bali bounding box: lat  -8.84 to -8.05, lng 114.42 to 115.72
-- This is a coarse check — for production, replace with actual PostGIS
-- landmass polygon from GADM or BPS shapefile.
-- =============================================================
create or replace function public.is_on_bali_land(p_lat double precision, p_lng double precision)
returns boolean
language plpgsql
immutable
as $$
begin
  -- Coarse bounding box check (covers main Bali + Nusa Penida + Nusa Lembongan)
  -- Excludes obvious ocean points (e.g., coordinates in Java, Lombok, or open sea)
  return p_lat between -8.84 and -8.05
     and p_lng between 114.42 and 115.72;
end;
$$;

-- =============================================================
-- Coordinate sanitization function:
-- If a coordinate falls in the ocean, snaps it to nearest Bali land bbox centroid
-- =============================================================
create or replace function public.sanitize_bali_coord(p_lat double precision, p_lng double precision)
returns table(lat double precision, lng double precision)
language plpgsql
immutable
as $$
begin
  if public.is_on_bali_land(p_lat, p_lng) then
    return query select p_lat, p_lng;
  else
    -- Snap to Denpasar centroid as fallback (capital of Bali)
    return query select -8.670458::double precision, 115.212629::double precision;
  end if;
end;
$$;
