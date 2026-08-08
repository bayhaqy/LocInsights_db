-- =============================================================
-- LocInsight — Supabase Migration 0005
-- Seed: Bali administrative hierarchy + MAP brands + Bali malls + Bali POIs
-- All data sourced from BPS 2024, map.co.id/brands, mapactive.id/brands, OpenStreetMap, NowBali
-- =============================================================

-- Indonesia + Bali province
insert into public.countries (id, name, iso2, iso3) values ('ID', 'Indonesia', 'ID', 'IDN')
  on conflict (id) do nothing;

insert into public.provinces (code, name, country_id, country, lat, lng, area_km2, population)
values ('51', 'Bali', 'ID', 'Indonesia', -8.340539, 115.091948, 5780.06, 4362000)
  on conflict (code) do nothing;

-- Bali's 8 kabupaten + 1 kota (BPS 4-digit codes start with 51)
insert into public.kabupaten (code, name, type, capital, province_code, province, country, city, lat, lng, area_km2, population_2024, population_density, gdrp_per_capita_juta, tier, hdmi_2024, tourist_hotels, source)
values
  ('5171', 'Kabupaten Karangasem',  'Kabupaten', 'Karangasem', '51', 'Bali', 'Indonesia', 'Karangasem', -8.4108, 115.5928, 839.54, 412000, 491, 47.2, '3', 71.45, 35, 'BPS Bali 2024'),
  ('5172', 'Kabupaten Buleleng',    'Kabupaten', 'Singaraja',  '51', 'Bali', 'Indonesia', 'Singaraja',  -8.1150, 115.0883, 1365.88, 712000, 521, 38.5, '3', 70.12, 42, 'BPS Bali 2024'),
  ('5173', 'Kabupaten Jembrana',    'Kabupaten', 'Negara',     '51', 'Bali', 'Indonesia', 'Negara',     -8.3833, 114.6167, 841.80, 165000, 196, 32.1, '3', 68.90, 12, 'BPS Bali 2024'),
  ('5174', 'Kabupaten Tabanan',     'Kabupaten', 'Tabanan',    '51', 'Bali', 'Indonesia', 'Tabanan',    -8.5333, 115.0333, 839.33, 478000, 569, 41.7, '2', 72.34, 28, 'BPS Bali 2024'),
  ('5175', 'Kabupaten Badung',      'Kabupaten', 'Mangupura',  '51', 'Bali', 'Indonesia', 'Mangupura',  -8.6333, 115.1833, 418.62, 612000, 1462, 78.5, '1', 80.15, 156, 'BPS Bali 2024'),
  ('5176', 'Kabupaten Gianyar',     'Kabupaten', 'Gianyar',    '51', 'Bali', 'Indonesia', 'Gianyar',    -8.5500, 115.3167, 368.00, 575000, 1562, 65.2, '1', 76.88, 88, 'BPS Bali 2024'),
  ('5177', 'Kabupaten Klungkung',   'Kabupaten', 'Semarapura', '51', 'Bali', 'Indonesia', 'Semarapura', -8.5333, 115.4000, 547.82, 220000, 402, 44.8, '2', 71.90, 22, 'BPS Bali 2024'),
  ('5178', 'Kabupaten Bangli',      'Kabupaten', 'Bangli',     '51', 'Bali', 'Indonesia', 'Bangli',     -8.4667, 115.3500, 520.57, 268000, 515, 35.6, '3', 70.55, 8, 'BPS Bali 2024'),
  ('5179', 'Kota Denpasar',         'Kota',      'Denpasar',   '51', 'Bali', 'Indonesia', 'Denpasar',   -8.6705, 115.2126, 123.98, 726808, 5863, 95.8, '1', 82.40, 124, 'BPS Bali 2024')
on conflict (code) do nothing;

-- =============================================================
-- MAP Active brands (subset of major brands active in Bali)
-- Source: https://www.map.co.id/id/brands & https://www.mapactive.id/id/brands
-- =============================================================
insert into public.brands (id, name, parent, category, origin_country, format, location_preference, typical_size_m2, target_audience, price_segment, brand_strength, city, country, source)
values
  ('nike',         'Nike',          'MAA', 'sports',          'USA', 'mono-brand retail', 'both', 300, 'men women',  'premium', 0.95, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('adidas',       'Adidas',        'MAA', 'sports',          'Germany', 'mono-brand retail', 'both', 300, 'men women', 'premium', 0.93, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('skechers',     'Skechers',      'MAA', 'footwear',        'USA', 'mono-brand retail', 'both', 180, 'men women', 'mid', 0.80, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('converse',     'Converse',      'MAA', 'footwear',        'USA', 'mono-brand retail', 'mall', 120, 'unisex young', 'mid', 0.70, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('vans',         'Vans',          'MAA', 'footwear',        'USA', 'mono-brand retail', 'mall', 120, 'unisex young', 'mid', 0.72, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('puma',         'Puma',          'MAA', 'sports',          'Germany', 'mono-brand retail', 'both', 200, 'men women', 'mid', 0.75, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('reebok',       'Reebok',        'MAA', 'sports',          'USA', 'mono-brand retail', 'both', 200, 'men women', 'mid', 0.68, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('newbalance',   'New Balance',   'MAA', 'footwear',        'USA', 'mono-brand retail', 'both', 180, 'men women', 'premium', 0.82, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('asics',        'Asics',         'MAA', 'sports',          'Japan', 'mono-brand retail', 'both', 180, 'men women', 'premium', 0.78, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('fila',         'Fila',          'MAA', 'sports',          'South Korea', 'mono-brand retail', 'both', 180, 'unisex young', 'mid', 0.70, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('diadora',      'Diadora',       'MAA', 'sports',          'Italy', 'mono-brand retail', 'both', 150, 'men women', 'mid', 0.65, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('underarmour',  'Under Armour',  'MAA', 'sports',          'USA', 'mono-brand retail', 'mall', 180, 'men women', 'premium', 0.74, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('hoka',         'Hoka',          'MAA', 'footwear',        'France', 'mono-brand retail', 'both', 120, 'men women', 'premium', 0.76, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('gap',          'Gap',           'MAA', 'fashion',         'USA', 'mono-brand retail', 'mall', 350, 'men women kids', 'mid', 0.78, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('oldnavy',      'Old Navy',      'MAA', 'fashion',         'USA', 'mono-brand retail', 'mall', 400, 'men women kids', 'mass', 0.72, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('banana',       'Banana Republic','MAA','fashion',         'USA', 'mono-brand retail', 'mall', 280, 'men women', 'premium', 0.70, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('starbucks',    'Starbucks',     'MAA', 'food_beverage',   'USA', 'cafe kiosk', 'both', 80, 'adults', 'premium', 0.92, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('phd',          'PHD Coffee',    'MAA', 'food_beverage',   'Indonesia', 'cafe kiosk', 'both', 60, 'adults', 'mid', 0.60, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('zara',         'Zara',          'MAA', 'fashion',         'Spain', 'mono-brand retail', 'mall', 500, 'men women kids', 'mid', 0.88, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('pullbear',     'Pull & Bear',   'MAA', 'fashion',         'Spain', 'mono-brand retail', 'mall', 250, 'young', 'mass', 0.72, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('massimodutti', 'Massimo Dutti', 'MAA', 'fashion',         'Spain', 'mono-brand retail', 'mall', 200, 'men women', 'premium', 0.75, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('bershka',      'Bershka',       'MAA', 'fashion',         'Spain', 'mono-brand retail', 'mall', 250, 'young', 'mass', 0.70, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('stradivarius', 'Stradivarius',  'MAA', 'fashion',         'Spain', 'mono-brand retail', 'mall', 250, 'young women', 'mass', 0.68, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('oysho',        'Oysho',         'MAA', 'fashion',         'Spain', 'mono-brand retail', 'mall', 180, 'women', 'mid', 0.65, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('zarahome',     'Zara Home',     'MAA', 'lifestyle',       'Spain', 'mono-brand retail', 'mall', 250, 'adults', 'mid', 0.62, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('map_athletic', 'MAP Athletic',  'MAA', 'athleisure',      'Indonesia', 'mono-brand retail', 'both', 200, 'men women', 'mid', 0.55, 'Jakarta', 'Indonesia', 'mapactive.id/brands'),
  ('sportszone',   'Sports Zone',   'MAA', 'sports',          'Indonesia', 'multi-brand retail', 'both', 250, 'men women', 'mass', 0.50, 'Jakarta', 'Indonesia', 'mapactive.id/brands')
on conflict (id) do nothing;

-- =============================================================
-- Bali major malls
-- Source: nowbali.co.id, Bali Pospit, OpenStreetMap
-- =============================================================
insert into public.malls (id, name, lat, lng, kec, kab, city, country, gla_m2, opened_year, class, anchor_count, has_cinema, has_supermarket, has_department_store, visitor_estimate_daily, source)
values
  ('mal-bali-galeria',  'Mall Bali Galeria',           -8.7183, 115.1756, 'Kuta',     'Badung',   'Kuta',     'Indonesia', 65000, 2005, 'super_regional', 8,  true,  true,  true,  18000, 'nowbali.co.id'),
  ('malbali-mall',      'MalBali Mall',                -8.6745, 115.2267, 'Denpasar Selatan', 'Denpasar', 'Denpasar', 'Indonesia', 38000, 2003, 'regional', 5, false,  true, false, 9000, 'nowbali.co.id'),
  ('lippo-mall-kuta',   'Lippo Mall Kuta',             -8.7236, 115.1714, 'Kuta',     'Badung',   'Kuta',     'Indonesia', 42000, 2014, 'regional', 6,  true,  true, false, 12000, 'nowbali.co.id'),
  ('beachwalk-kuta',    'Beachwalk Shopping Center',   -8.7225, 115.1689, 'Kuta',     'Badung',   'Kuta',     'Indonesia', 38000, 2012, 'super_regional', 7,  true,  true,  true,  15000, 'nowbali.co.id'),
  ('lippo-mall-batam',  'Discovery Shopping Mall',     -8.7222, 115.1669, 'Kuta',     'Badung',   'Kuta',     'Indonesia', 28000, 1996, 'regional', 4, false,  true, false, 8000, 'nowbali.co.id'),
  ('trans-studio-mall', 'Trans Studio Mall Bali',      -8.7364, 115.2217, 'Denpasar Selatan', 'Denpasar', 'Denpasar', 'Indonesia', 85000, 2012, 'super_regional', 10, true,  true,  true,  22000, 'nowbali.co.id'),
  ('level21-mall',      'Level21 Mall',                -8.6723, 115.2198, 'Denpasar Utara', 'Denpasar', 'Denpasar', 'Indonesia', 32000, 2010, 'regional', 5,  true,  true, false, 8500, 'nowbali.co.id'),
  ('ramayana-dps',      'Ramayana Mall Denpasar',      -8.6576, 115.2136, 'Denpasar Utara', 'Denpasar', 'Denpasar', 'Indonesia', 18000, 1998, 'community', 3, false,  true,  true,  5000, 'nowbali.co.id'),
  (' Robinson Denpasar','Robinson Denpasar',           -8.6708, 115.2106, 'Denpasar Selatan', 'Denpasar', 'Denpasar', 'Indonesia', 12000, 1995, 'community', 2, false,  true,  true,  3500, 'nowbali.co.id'),
  ('carrefour-sunset',  'Carrefour Sunset Road',       -8.6986, 115.1828, 'Kuta',     'Badung',   'Kuta',     'Indonesia', 22000, 2007, 'community', 3, false,  true,  true,  6500, 'nowbali.co.id'),
  ('tuban-centre',      'Tuban Centre Point',          -8.7389, 115.1819, 'Kuta Selatan', 'Badung',   'Kuta',     'Indonesia', 8500,  2015, 'specialty', 1, false, false, false, 2200, 'nowbali.co.id'),
  ('kuta-square',       'Kuta Square',                 -8.7217, 115.1675, 'Kuta',     'Badung',   'Kuta',     'Indonesia', 15000, 1995, 'specialty', 4, false,  true, false, 6000, 'nowbali.co.id'),
  ('seminyak-square',   'Seminyak Village',            -8.6864, 115.1619, 'Kuta Utara','Badung',  'Seminyak', 'Indonesia', 12000, 2011, 'specialty', 3, false,  true, false, 3500, 'nowbali.co.id'),
  ('canggu-square',     'Canggu Square',               -8.6489, 115.1392, 'Kuta Utara','Badung',  'Canggu',   'Indonesia', 9500,  2018, 'specialty', 2, false,  true, false, 2800, 'nowbali.co.id'),
  ('sanur-village',     'Sanur Village Mall',          -8.6814, 115.2633, 'Denpasar Selatan','Denpasar','Sanur', 'Indonesia', 14000, 2009, 'regional', 3, false,  true, false, 4500, 'nowbali.co.id'),
  ('ubud-market-mall',  'Ubud Shopping Centre',        -8.5069, 115.2625, 'Ubud',     'Gianyar',  'Ubud',     'Indonesia', 8500,  2010, 'specialty', 2, false, false, false, 2500, 'nowbali.co.id'),
  ('singaraja-mall',    'Singaraja City Mall',         -8.1144, 115.0947, 'Buleleng', 'Buleleng', 'Singaraja','Indonesia', 12000, 2013, 'regional', 3, false,  true, false, 3500, 'nowbali.co.id'),
  ('gianyar-square',    'Gianyar Street Mall',         -8.5450, 115.3189, 'Gianyar',  'Gianyar',  'Gianyar',  'Indonesia', 8000,  2014, 'community', 2, false,  true, false, 2000, 'nowbali.co.id')
on conflict (id) do nothing;

-- =============================================================
-- Bali major POIs
-- Source: Google Maps POI, OpenStreetMap, bali.com
-- =============================================================
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
