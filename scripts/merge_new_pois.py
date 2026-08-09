#!/usr/bin/env python3
"""
Merge NEW POIs from OSM scrape into Supabase DB — BATCHED version.
Uses execute_values for bulk insert + caches kec→kab mapping.
"""
import psycopg2
import psycopg2.extras
import json
import hashlib
from datetime import datetime, timezone
from collections import Counter

DB_URL = "postgresql://postgres.fcyhrzzfvdsghtummizv:Belajar%4011%21%21@aws-0-ap-southeast-2.pooler.supabase.com:5432/postgres"

print(f"Start: {datetime.now(timezone.utc).isoformat()}")

with open("/home/z/my-project/download/scraped_pois.json") as f:
    scraped_pois = json.load(f)
print(f"Loaded {len(scraped_pois)} scraped POIs from OSM")

conn = psycopg2.connect(DB_URL)
conn.autocommit = False
cur = conn.cursor()

# Get existing POI coordinates (rounded to 4 decimals = ~11m)
cur.execute("SELECT ROUND(lat::numeric, 4), ROUND(lng::numeric, 4) FROM public.pois")
existing_coords = {(float(r[0]), float(r[1])) for r in cur.fetchall()}
print(f"DB has {len(existing_coords)} existing POI coordinates")

# Get kecamatan → (lat, lng, kab_name) mapping in one query
cur.execute("""
    SELECT k.name AS kec_name, k.lat, k.lng, kb.name AS kab_name
    FROM public.kecamatan k
    JOIN public.kabupaten kb ON k.kabupaten_code = kb.code
    WHERE k.lat IS NOT NULL AND k.lng IS NOT NULL
""")
kec_data = cur.fetchall()
print(f"Loaded {len(kec_data)} kecamatan with kab mapping")


def nearest_kec_kab(lat, lng):
    """Find nearest kecamatan + kabupaten."""
    best_kec = None
    best_kab = None
    best_d = float('inf')
    for kec_name, klat, klng, kab_name in kec_data:
        d = (float(klat) - lat) ** 2 + (float(klng) - lng) ** 2
        if d < best_d:
            best_d = d
            best_kec = kec_name
            best_kab = kab_name
    return best_kec, best_kab


def map_poi_type(t, n):
    t, n = (t or "").lower(), (n or "").lower()
    if t in ["attraction", "museum"]:
        if "pantai" in n or "beach" in n:
            return "beach"
        if "pura" in n or "temple" in n:
            return "temple"
        return "tourist_attraction"
    if t in ["hotel", "resort", "guest_house", "hostel", "apartment", "motel"]:
        return "hotel_cluster"
    return "tourist_attraction"


# Build list of new POIs
new_rows = []
skipped_dup = 0
for p in scraped_pois:
    name = p.get('name', '').strip()
    if not name:
        continue
    lat = float(p['lat'])
    lng = float(p['lng'])
    coord_key = (round(lat, 4), round(lng, 4))
    if coord_key in existing_coords:
        skipped_dup += 1
        continue

    kec, kab = nearest_kec_kab(lat, lng)
    poi_type = map_poi_type(p.get('poi_type', ''), name)
    magnitude = 5.0 if poi_type == 'tourist_attraction' else 6.0
    h = hashlib.sha1(f"{p.get('osm_id', '')}".encode()).hexdigest()[:12]
    poi_id = f"POI_{h}"

    new_rows.append((
        poi_id, name, poi_type, lat, lng, kec or '', kab or '',
        kec or '', 'Indonesia', magnitude, f"OSM {p.get('osm_id', '')}",
        'OpenStreetMap',
    ))

print(f"Skipping {skipped_dup} duplicates (existing in DB)")
print(f"NEW POIs to insert: {len(new_rows)}")

if not new_rows:
    print("Nothing to insert.")
    cur.close()
    conn.close()
    exit(0)

# Bulk insert with execute_values
try:
    psycopg2.extras.execute_values(
        cur,
        """
        INSERT INTO public.pois
            (id, name, type, lat, lng, kec, kab, city, country, magnitude, notes, source)
        VALUES %s
        ON CONFLICT (id) DO NOTHING
        """,
        new_rows,
        page_size=200,
    )
    inserted = cur.rowcount
    conn.commit()
    print(f"\nInserted {inserted} new POIs (out of {len(new_rows)} candidates)")
except Exception as e:
    conn.rollback()
    print(f"Error during bulk insert: {e}")
    inserted = 0

# Final count
cur.execute("SELECT COUNT(*) FROM public.pois")
total = cur.fetchone()[0]
print(f"Final POI count in DB: {total}")

# Stats
cur.execute("""
    SELECT kab, COUNT(*) FROM public.pois GROUP BY kab ORDER BY COUNT(*) DESC LIMIT 10
""")
print("\nTop 10 kabupaten by POI count:")
for r in cur.fetchall():
    print(f"  {r[0] or '(none)':25s}  {r[1]}")

cur.close()
conn.close()
print(f"\nEnd: {datetime.now(timezone.utc).isoformat()}")
