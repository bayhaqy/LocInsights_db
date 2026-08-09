"""
Task 4: Apply freshly scraped Bali data to DB.

Strategy:
  - For COMPETITORS: REPLACE competitor_stores with fresh OSM scrape (963 records, all clean)
  - For STORES (MAP/MAA): MERGE — keep existing DB records + add new ones from OSM scrape
    (existing DB has manually-verified records from MAP store directory that OSM doesn't have)

The competitor_stores.source is scraper_source_enum, so we use 'osm' for new records.
"""
import json
import psycopg2
from psycopg2.extras import execute_values
from datetime import datetime, timezone
from pathlib import Path
from collections import defaultdict

CONN = "postgresql://postgres.fcyhrzzfvdsghtummizv:Belajar%4011%21%21@aws-0-ap-southeast-2.pooler.supabase.com:5432/postgres"

CHUNKS_DIR = Path("/home/z/my-project/download/scrape_chunks")

# ============================================================================
# Kecamatan polygon loader for reverse geocoding
# ============================================================================
import os

KEC_POLYGONS = None

def load_kec_polygons():
    global KEC_POLYGONS
    if KEC_POLYGONS is not None:
        return KEC_POLYGONS
    paths = [
        "/home/z/my-project/audit/LocInsights/public/geojson/bali-kecamatan.geojson",
    ]
    for p in paths:
        if os.path.exists(p):
            print(f"  Loading kecamatan polygons from {p}", flush=True)
            with open(p) as f:
                data = json.load(f)
            KEC_POLYGONS = []
            for feat in data.get("features", []):
                props = feat.get("properties", {})
                KEC_POLYGONS.append({
                    "name": props.get("NAME_3", ""),
                    "kab": props.get("NAME_2", ""),
                    "geometry": feat.get("geometry", {}),
                })
            print(f"  Loaded {len(KEC_POLYGONS)} kecamatan polygons", flush=True)
            return KEC_POLYGONS
    KEC_POLYGONS = []
    return KEC_POLYGONS

def point_in_polygon(lat, lng, geometry):
    if not geometry:
        return False
    gtype = geometry.get("type")
    coords = geometry.get("coordinates", [])
    if gtype == "Polygon":
        rings = coords
    elif gtype == "MultiPolygon":
        rings = [ring for poly in coords for ring in poly]
    else:
        return False
    for ring in rings:
        if not ring:
            continue
        n = len(ring)
        inside = False
        j = n - 1
        for i in range(n):
            yi, xi = ring[i][1], ring[i][0]
            yj, xj = ring[j][1], ring[j][0]
            if ((yi > lat) != (yj > lat)) and \
               (lng < (xj - xi) * (lat - yi) / (yj - yi + 1e-12) + xi):
                inside = not inside
            j = i
        if inside:
            return True
    return False

def reverse_geocode(lat, lng):
    polys = load_kec_polygons()
    for p in polys:
        if point_in_polygon(lat, lng, p["geometry"]):
            return {"kec": p["name"], "kab": p["kab"]}
    return {"kec": "", "kab": ""}

# ============================================================================
def main():
    print("=" * 70)
    print("Task 4: Apply scraped Bali data to DB")
    print("=" * 70)

    # Load all chunk records
    print("\n[1/5] Loading scraped chunks...")
    all_records = []
    for f in sorted(CHUNKS_DIR.glob("*.json")):
        recs = json.loads(f.read_text())
        all_records.extend(recs)
    print(f"  Loaded {len(all_records)} records from {len(list(CHUNKS_DIR.glob('*.json')))} chunk files")

    # Split
    stores_scraped = [r for r in all_records if r.get("parent") in ("MAP", "MAA")]
    competitors_scraped = [r for r in all_records if r.get("parent") == "COMPETITOR"]
    print(f"  MAP/MAA stores: {len(stores_scraped)}")
    print(f"  Competitors: {len(competitors_scraped)}")

    # Reverse geocode all
    print("\n[2/5] Reverse geocoding all records via kecamatan polygons...")
    load_kec_polygons()
    for i, r in enumerate(all_records):
        if i % 200 == 0:
            print(f"  [{i}/{len(all_records)}]...", flush=True)
        geo = reverse_geocode(r["lat"], r["lng"])
        r["kec"] = geo.get("kec", "")
        r["kab"] = geo.get("kab", "")
        r["city"] = geo.get("kab", "")
        r["country"] = "Indonesia"
    print(f"  Geocoded: {sum(1 for r in all_records if r.get('kec'))}/{len(all_records)}")

    # ============================================================================
    # DB Operations
    # ============================================================================
    conn = psycopg2.connect(CONN)
    conn.autocommit = False
    cur = conn.cursor()

    # ============================================================================
    # 3. REPLACE competitor_stores with fresh OSM data
    # ============================================================================
    print(f"\n[3/5] Replacing competitor_stores with {len(competitors_scraped)} fresh OSM records...")
    cur.execute("DELETE FROM competitor_stores")
    print(f"  Deleted {cur.rowcount} old records")

    # Map our generic categories to competitor_category_enum values
    CATEGORY_MAP = {
        "food_beverage": "fast_food",
        "retail": "convenience_store",
        "beauty": "beauty",
        "department_store": "department_store",
        "lifestyle": "other",
        "sports": "sports",
        "footwear": "fashion",
        "kids": "other",
        "fashion": "fashion",
    }
    COFFEE_BRANDS = {"Starbucks", "Janji Jiwa", "Kopi Kenangan", "Excelso",
                     "Tomoro Coffee", "Kopi Tuku", "Tom Toms Coffee",
                     "Olesay Coffee", "Nordic Tea", "J.CO"}
    CONVENIENCE_BRANDS = {"Indomaret", "Alfamart", "Alfamidi", "Circle K", "7-Eleven"}
    PHARMACY_BRANDS = {"Apotek K24", "Kimia Farma", "Apotek Century", "Guardian", "Watsons"}
    SUPERMARKET_BRANDS = {"Transmart", "Lotte Mart", "Ranch Market", "Hypermart",
                          "Carrefour", "The FoodHall", "Daily FoodHall"}
    RESTAURANT_BRANDS = {"KFC", "McDonald's", "Burger King", "Wendy's", "A&W",
                         "Domino's Pizza", "Pizza Hut", "Carl's Jr", "Texas Chicken",
                         "Popeyes", "Sushi Tei", "Matahari Department Store"}

    def map_category(brand_name, original_category):
        if brand_name in COFFEE_BRANDS:
            return "coffee"
        if brand_name in CONVENIENCE_BRANDS:
            return "convenience_store"
        if brand_name in PHARMACY_BRANDS:
            return "pharmacy"
        if brand_name in SUPERMARKET_BRANDS:
            return "supermarket"
        if brand_name in RESTAURANT_BRANDS:
            return "fast_food"
        return CATEGORY_MAP.get(original_category, "other")

    # Insert new competitors in batches
    comp_rows = []
    for r in competitors_scraped:
        comp_rows.append((
            r.get("name", ""),
            r.get("brand_name", ""),
            map_category(r.get("brand_name", ""), r.get("brand_category", "retail")),
            float(r["lat"]),
            float(r["lng"]),
            r.get("kec", ""),
            r.get("kab", ""),
            r.get("city", ""),
            r.get("country", "Indonesia"),
            r.get("address", ""),
            False,  # is_in_mall (unknown from OSM)
            None,   # mall_id
            None,   # mall_name
            "osm",  # source (scraper_source_enum)
            r.get("source_url", ""),
            None,   # last_crawled_at
        ))

    # Use execute_values for batch insert
    insert_sql = """
        INSERT INTO competitor_stores (
            id, name, brand_name, brand_category,
            lat, lng, kec, kab, city, country,
            address, is_in_mall, mall_id, mall_name,
            source, source_url, last_crawled_at,
            created_at, updated_at
        ) VALUES (
            %s, %s, %s, %s,
            %s, %s, %s, %s, %s, %s,
            %s, %s, %s, %s,
            %s::scraper_source_enum, %s, %s,
            NOW(), NOW()
        )
    """

    # Generate IDs based on name+lat+lng
    def comp_id(r, i):
        import hashlib
        h = hashlib.md5(f"{r[0]}_{r[3]}_{r[4]}".encode()).hexdigest()[:12]
        return f"comp_{h}"

    print(f"  Inserting {len(comp_rows)} competitor records in batches of 100...")
    inserted = 0
    for i in range(0, len(comp_rows), 100):
        batch = comp_rows[i:i+100]
        values = []
        for r in batch:
            row_id = comp_id(r, i)
            values.append((row_id,) + r)
        try:
            execute_values(cur, """
                INSERT INTO competitor_stores (
                    id, name, brand_name, brand_category,
                    lat, lng, kec, kab, city, country,
                    address, is_in_mall, mall_id, mall_name,
                    source, source_url, last_crawled_at,
                    created_at, updated_at
                ) VALUES %s
                ON CONFLICT (id) DO NOTHING
            """, values, template="""
                (%s, %s, %s, %s::competitor_category_enum,
                 %s, %s, %s, %s, %s, %s,
                 %s, %s, %s, %s,
                 %s::scraper_source_enum, %s, %s,
                 NOW(), NOW())
            """)
            inserted += len(batch)
            if i % 500 == 0:
                print(f"    [{inserted}/{len(comp_rows)}]...", flush=True)
        except Exception as e:
            print(f"  ❌ Batch {i} failed: {e}")
            conn.rollback()
            cur = conn.cursor()
    print(f"  Inserted {inserted} competitor records")

    # ============================================================================
    # 4. MERGE stores with existing DB records (don't delete existing)
    # ============================================================================
    print(f"\n[4/5] Merging {len(stores_scraped)} fresh OSM stores with existing DB records...")

    # Get existing stores to avoid duplicates
    cur.execute("SELECT brand_id, lat, lng FROM stores")
    existing_keys = set()
    for brand_id, lat, lng in cur.fetchall():
        if lat and lng:
            existing_keys.add((brand_id, round(float(lat), 6), round(float(lng), 6)))

    # Get brand_id for each brand name
    cur.execute("SELECT name, id FROM brands")
    brand_id_map = {name: id for name, id in cur.fetchall()}

    # Get existing store names+coords to avoid duplicates
    cur.execute("SELECT name, lat, lng FROM stores")
    existing_name_keys = set()
    for name, lat, lng in cur.fetchall():
        if lat and lng and name:
            existing_name_keys.add((name.lower(), round(float(lat), 6), round(float(lng), 6)))

    print(f"  Existing stores: {len(existing_keys)}")
    print(f"  Brand ID map: {len(brand_id_map)} brands")

    inserted_stores = 0
    skipped_stores = 0
    for r in stores_scraped:
        brand_name = r.get("brand_name", "")
        brand_id = brand_id_map.get(brand_name)
        if not brand_id:
            print(f"  ⚠️  Brand '{brand_name}' not in DB — skipping")
            continue

        lat = float(r["lat"])
        lng = float(r["lng"])

        # Skip if already exists (by brand_id+lat+lng OR by name+lat+lng)
        if (brand_id, round(lat, 6), round(lng, 6)) in existing_keys:
            skipped_stores += 1
            continue
        name_key = (r.get("name", "").lower(), round(lat, 6), round(lng, 6))
        if name_key in existing_name_keys:
            skipped_stores += 1
            continue

        # Generate store ID
        import hashlib
        h = hashlib.md5(f"{brand_name}_{lat}_{lng}".encode()).hexdigest()[:12]
        store_id = f"osm_{h}"

        try:
            cur.execute("""
                INSERT INTO stores (
                    id, brand_id, brand_name, brand_category, parent, name,
                    lat, lng, kec, kab, city, country,
                    address, is_in_mall, mall_id, mall_name,
                    source, confirmed, created_at, updated_at
                ) VALUES (
                    %s, %s, %s, %s::brand_category_enum, %s::brand_parent_enum, %s,
                    %s, %s, %s, %s, %s, %s,
                    %s, false, NULL, NULL,
                    %s, false, NOW(), NOW()
                )
                ON CONFLICT (id) DO NOTHING
            """, (
                store_id, brand_id, brand_name, r.get("brand_category", "fashion"),
                r.get("parent"), r.get("name", ""),
                lat, lng, r.get("kec", ""), r.get("kab", ""), r.get("city", ""), r.get("country", "Indonesia"),
                r.get("address", ""),
                "OpenStreetMap (scraped Aug 2026)",
            ))
            if cur.rowcount > 0:
                inserted_stores += 1
                existing_keys.add((brand_id, round(lat, 6), round(lng, 6)))
        except Exception as e:
            print(f"  ❌ Failed: {r.get('name')} — {e}")
            conn.rollback()
            cur = conn.cursor()

    print(f"  Inserted: {inserted_stores}")
    print(f"  Skipped (already existed): {skipped_stores}")

    # ============================================================================
    # 5. Commit & verify
    # ============================================================================
    conn.commit()

    print(f"\n[5/5] Final verification...")
    cur.execute("SELECT COUNT(*) FROM stores")
    print(f"  stores: {cur.fetchone()[0]}")
    cur.execute("SELECT COUNT(*) FROM competitor_stores")
    print(f"  competitor_stores: {cur.fetchone()[0]}")

    cur.execute("""
        SELECT b.parent::text, COUNT(s.id)
        FROM stores s JOIN brands b ON s.brand_id = b.id
        GROUP BY b.parent
        ORDER BY b.parent
    """)
    print(f"  stores by parent:")
    for parent, cnt in cur.fetchall():
        print(f"    {parent}: {cnt}")

    cur.execute("SELECT COUNT(*) FROM competitor_stores WHERE kec IS NOT NULL AND kec != ''")
    print(f"  competitors with kec: {cur.fetchone()[0]}")

    cur.execute("SELECT COUNT(*) FROM stores WHERE kec IS NOT NULL AND kec != ''")
    print(f"  stores with kec: {cur.fetchone()[0]}")

    print("\n" + "=" * 70)
    print("✅ Task 4 complete")
    print("=" * 70)

    cur.close()
    conn.close()

if __name__ == "__main__":
    main()
