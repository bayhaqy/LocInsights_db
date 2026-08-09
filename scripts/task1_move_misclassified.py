"""
Easy Task 1: Move misclassified MAP/MAA brands from competitor_stores → stores.

Brands to move:
- Adidas (MAA — confirmed at map.co.id/portfolio_page/adidas)
- Zara (MAP — confirmed at map.co.id/brands)
- Foodhall (MAP — same as "The FoodHall" on map.co.id/brands)

This is a small, deterministic DB operation that should always succeed.
"""
import psycopg2
from psycopg2.extras import execute_values
from datetime import datetime, timezone

CONN = "postgresql://postgres.fcyhrzzfvdsghtummizv:Belajar%4011%21%21@aws-0-ap-southeast-2.pooler.supabase.com:5432/postgres"

# Brands to move (competitor_stores.brand_name → stores with parent)
BRANDS_TO_MOVE = [
    {"comp_brand_name": "Adidas", "canonical": "Adidas", "parent": "MAA", "category": "sports"},
    {"comp_brand_name": "Zara", "canonical": "Zara", "parent": "MAP", "category": "fashion"},
    {"comp_brand_name": "Foodhall", "canonical": "The FoodHall", "parent": "MAP", "category": "department_store"},
]

def main():
    conn = psycopg2.connect(CONN)
    conn.autocommit = False
    cur = conn.cursor()

    print("=" * 70)
    print("Task 1: Move misclassified MAP/MAA brands from competitor_stores → stores")
    print("=" * 70)

    # First check: ensure each target brand exists in `brands` table
    print("\n[1/3] Verifying target brands exist in `brands` table...")
    for b in BRANDS_TO_MOVE:
        cur.execute("SELECT id, name FROM brands WHERE name = %s", (b["canonical"],))
        row = cur.fetchone()
        if row:
            print(f"  ✓ {b['canonical']} exists (id={row[0]})")
            b["brand_id"] = row[0]
        else:
            # Create the brand
            print(f"  + Creating missing brand: {b['canonical']}")
            cur.execute("""
                INSERT INTO brands (id, name, parent, category, country, is_active, source, created_at, updated_at)
                VALUES (%s, %s, %s::brand_parent_enum, %s::brand_category_enum, 'Indonesia', true, 'map.co.id/brands (verified Aug 2026)', NOW(), NOW())
                RETURNING id
            """, (b["canonical"].lower().replace(" ", "_"), b["canonical"], b["parent"], b["category"]))
            b["brand_id"] = cur.fetchone()[0]

    # Fetch competitors to move
    print("\n[2/3] Fetching competitor records to move...")
    to_move = []
    for b in BRANDS_TO_MOVE:
        cur.execute("""
            SELECT id, brand_name, name, lat, lng, kec, kab, city, country,
                   address, is_in_mall, mall_id, mall_name, source, source_url
            FROM competitor_stores
            WHERE brand_name = %s
        """, (b["comp_brand_name"],))
        rows = cur.fetchall()
        print(f"  {b['comp_brand_name']} → {b['canonical']} ({b['parent']}): {len(rows)} records")
        for r in rows:
            to_move.append({
                "comp_id": r[0],
                "brand_name_orig": r[1],
                "name": r[2],
                "lat": r[3],
                "lng": r[4],
                "kec": r[5],
                "kab": r[6],
                "city": r[7],
                "country": r[8],
                "address": r[9],
                "is_in_mall": r[10],
                "mall_id": r[11],
                "mall_name": r[12],
                "source": r[13],
                "source_url": r[14],
                "brand_id": b["brand_id"],
                "canonical": b["canonical"],
                "parent": b["parent"],
                "category": b["category"],
            })

    if not to_move:
        print("\n  No records to move. Exiting.")
        cur.close()
        conn.close()
        return

    # Insert into stores (deduplicate against existing stores by name+lat+lng)
    print(f"\n[3/3] Moving {len(to_move)} records into `stores` table...")
    inserted = 0
    skipped = 0
    for r in to_move:
        # Check if a store with same name+lat+lng already exists
        cur.execute("""
            SELECT id FROM stores
            WHERE brand_id = %s AND lat = %s AND lng = %s
        """, (r["brand_id"], r["lat"], r["lng"]))
        if cur.fetchone():
            print(f"  SKIP (already exists): {r['name']} @ ({r['lat']}, {r['lng']})")
            skipped += 1
            continue

        # Generate store id
        store_id = f"{r['canonical'].lower().replace(' ', '_')}_{r['lat']}_{r['lng']}".replace("-", "m").replace(".", "p")

        # stores.source is text — use descriptive string
        source_val = "map.co.id/brands (verified Aug 2026) + OpenStreetMap"
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
                    %s, %s, %s, %s,
                    %s, true, NOW(), NOW()
                )
            """, (
                store_id, r["brand_id"], r["canonical"], r["category"], r["parent"], r["name"],
                r["lat"], r["lng"], r["kec"], r["kab"], r["city"], r["country"],
                r["address"], r["is_in_mall"], r["mall_id"], r["mall_name"],
                source_val,
            ))
            inserted += 1
            print(f"  + INSERTED: {r['name']} @ ({r['lat']}, {r['lng']}) [{r['parent']}]")
        except Exception as e:
            print(f"  ❌ FAILED: {r['name']} — {e}")
            conn.rollback()
            cur = conn.cursor()
            continue

        # geom column is auto-generated (GENERATED ALWAYS) — skip update

    # Delete moved records from competitor_stores
    print(f"\n[Cleanup] Deleting {len(to_move)} moved records from competitor_stores...")
    for r in to_move:
        cur.execute("DELETE FROM competitor_stores WHERE id = %s", (r["comp_id"],))
    deleted = cur.rowcount

    conn.commit()

    print("\n" + "=" * 70)
    print("✅ Task 1 complete")
    print(f"   Inserted into stores: {inserted}")
    print(f"   Skipped (already existed): {skipped}")
    print(f"   Deleted from competitor_stores: {deleted}")
    print("=" * 70)

    cur.close()
    conn.close()

if __name__ == "__main__":
    main()
