"""
Easy Task 2: Add missing brands from official MAP/MAA websites to brands table.

Sources:
  - MAP (https://www.map.co.id/brands): Active, Fashion, F&B, Department Stores,
    Tech, Travel, Kids, Others
  - MAA (https://www.mapactive.id/brands): Sports, Leisure, Kids

Verified Aug 2026.
"""
import psycopg2
from datetime import datetime

CONN = "postgresql://postgres.fcyhrzzfvdsghtummizv:Belajar%4011%21%21@aws-0-ap-southeast-2.pooler.supabase.com:5432/postgres"

# Missing brands discovered from official websites (Aug 2026)
# Format: (name, parent, category, country, source)
MISSING_BRANDS = [
    # MAP — Active (also on MAA site, but listed as MAP)
    ("Nike", "MAA", "sports", "USA", "mapactive.id/brands (verified Aug 2026)"),
    ("Jordan", "MAA", "sports", "USA", "mapactive.id/brands (verified Aug 2026)"),
    ("Spalding", "MAP", "sports", "USA", "map.co.id/brands (verified Aug 2026)"),
    ("Speedo", "MAP", "sports", "UK", "map.co.id/brands (verified Aug 2026)"),
    # MAP — Fashion (full Inditex group + premium)
    ("Stradivarius", "MAP", "fashion", "Spain", "map.co.id/brands (verified Aug 2026)"),
    ("Oysho", "MAP", "fashion", "Spain", "map.co.id/brands (verified Aug 2026)"),
    ("Tommy Hilfiger", "MAP", "fashion", "USA", "map.co.id/portfolio_page/tommy-hilfiger (verified Aug 2026)"),
    ("Calvin Klein", "MAP", "fashion", "USA", "map.co.id/portfolio_page/calvin-klein (verified Aug 2026)"),
    ("Laneige", "MAP", "beauty", "South Korea", "map.co.id/brands (verified Aug 2026)"),
    # MAP — Tech
    ("SharkNinja", "MAP", "lifestyle", "USA", "map.co.id/brands (verified Aug 2026)"),
    # MAP — Travel
    ("American Tourister", "MAP", "lifestyle", "USA", "map.co.id/brands (verified Aug 2026)"),
    ("Bric's", "MAP", "lifestyle", "Italy", "map.co.id/brands (verified Aug 2026)"),
    ("Travelogue", "MAP", "lifestyle", "Indonesia", "map.co.id/brands (verified Aug 2026)"),
    # MAP — Others
    ("Out Of Asia", "MAP", "lifestyle", "Indonesia", "map.co.id/brands (verified Aug 2026)"),
    # MAP — Kids
    ("Majorette", "MAP", "kids", "France", "map.co.id/brands (verified Aug 2026)"),
    ("Baby Alive", "MAP", "kids", "USA", "map.co.id/brands (verified Aug 2026)"),
    ("Hape", "MAP", "kids", "Germany", "map.co.id/brands (verified Aug 2026)"),
    ("Disney", "MAP", "kids", "USA", "map.co.id/brands (verified Aug 2026)"),
    ("Dickie", "MAP", "kids", "Germany", "map.co.id/brands (verified Aug 2026)"),
    ("Discovery", "MAP", "kids", "USA", "map.co.id/brands (verified Aug 2026)"),
    ("Hasbro", "MAP", "kids", "USA", "map.co.id/brands (verified Aug 2026)"),
    ("Caterpillar", "MAP", "kids", "USA", "map.co.id/brands (verified Aug 2026)"),
    # MAA — Leisure (additional)
    ("Rockport", "MAA", "footwear", "USA", "mapactive.id/brands (verified Aug 2026)"),
    ("Nine West", "MAA", "footwear", "USA", "mapactive.id/brands (verified Aug 2026)"),
    # MAA — Kids (additional)
    ("LOL Surprise", "MAA", "kids", "USA", "mapactive.id/brands (verified Aug 2026)"),
    ("Keeppley", "MAA", "kids", "China", "mapactive.id/brands (verified Aug 2026)"),
    ("FAO Schwarz", "MAA", "kids", "USA", "mapactive.id/brands (verified Aug 2026)"),
    # MAA — Sports (additional)
    ("Under Armour", "MAA", "sports", "USA", "FT.com MAPA profile (verified Aug 2026)"),
]

# Brands to RENAME (currently wrong name → canonical)
RENAME_BRANDS = [
    ("ASICS", "ASICS"),  # case fix
    ("Planet Sports", "Planet Sports"),
    ("Planet Sports Kids", "Planet Sports Kids"),
]

# Brands to REMOVE (no longer on MAP/MAA portfolio — should not be in brands table)
# Note: Ace Hardware is on map.co.id/brands so keep it. But "The Athlete's Foot" was
# not on MAA's official Aug 2026 brand list — verify before removing.
# Looking at the MAA Aug 2026 page, "The Athlete's Foot" is NOT in Sports/Leisure/Kids,
# but Pitchbook lists it. Let's KEEP it for now and let user decide.

def main():
    conn = psycopg2.connect(CONN)
    cur = conn.cursor()

    print("=" * 70)
    print("Task 2: Add missing brands from official MAP/MAA websites")
    print("=" * 70)

    print(f"\n[1/2] Adding {len(MISSING_BRANDS)} missing brands...")
    inserted = 0
    skipped = 0
    for name, parent, category, country, source in MISSING_BRANDS:
        # Check if already exists
        cur.execute("SELECT id FROM brands WHERE name ILIKE %s", (name,))
        if cur.fetchone():
            print(f"  SKIP (already exists): {name}")
            skipped += 1
            continue

        # Generate ID
        brand_id = name.lower().replace(" ", "_").replace("&", "and").replace(".", "").replace("'", "")

        try:
            cur.execute("""
                INSERT INTO brands (id, name, parent, category, country, is_active, source, created_at, updated_at)
                VALUES (%s, %s, %s::brand_parent_enum, %s::brand_category_enum, %s, true, %s, NOW(), NOW())
            """, (brand_id, name, parent, category, country, source))
            inserted += 1
            print(f"  + ADDED: {name} [{parent}/{category}] from {country}")
        except Exception as e:
            print(f"  ❌ FAILED: {name} — {e}")
            conn.rollback()
            cur = conn.cursor()

    conn.commit()

    print(f"\n[2/2] Final brand count:")
    cur.execute("SELECT parent::text, COUNT(*) FROM brands GROUP BY parent ORDER BY parent")
    for parent, cnt in cur.fetchall():
        print(f"  {parent}: {cnt}")
    cur.execute("SELECT COUNT(*) FROM brands")
    total = cur.fetchone()[0]
    print(f"  TOTAL: {total}")

    print("\n" + "=" * 70)
    print(f"✅ Task 2 complete: {inserted} added, {skipped} skipped (existed)")
    print("=" * 70)

    cur.close()
    conn.close()

if __name__ == "__main__":
    main()
