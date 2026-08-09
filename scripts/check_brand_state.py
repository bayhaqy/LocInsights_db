"""
Check current state of stores vs competitors in DB.
Print all brands and counts for both tables.
"""
import os
import psycopg2
from collections import Counter

# Direct connection string
CONN = "postgresql://postgres.fcyhrzzfvdsghtummizv:Belajar%4011%21%21@aws-0-ap-southeast-2.pooler.supabase.com:5432/postgres"

def main():
    conn = psycopg2.connect(CONN)
    cur = conn.cursor()

    print("=" * 70)
    print("STORES TABLE — current brands (should be MAP/MAA only)")
    print("=" * 70)
    cur.execute("""
        SELECT b.name, b.parent::text, COUNT(s.id) AS store_count
        FROM stores s
        JOIN brands b ON s.brand_id = b.id
        GROUP BY b.name, b.parent
        ORDER BY b.parent, b.name
    """)
    rows = cur.fetchall()
    parent_counts = Counter()
    for name, parent, count in rows:
        print(f"  [{parent}] {name}: {count}")
        parent_counts[parent] += count
    print(f"\n  TOTAL: {sum(parent_counts.values())} stores across {len(rows)} brands")
    print(f"  By parent: {dict(parent_counts)}")

    print()
    print("=" * 70)
    print("COMPETITOR_STORES TABLE — current brands (should be NON-MAP/MAA)")
    print("=" * 70)
    cur.execute("""
        SELECT brand_name, COUNT(*) AS cnt
        FROM competitor_stores
        GROUP BY brand_name
        ORDER BY cnt DESC
    """)
    rows = cur.fetchall()
    print(f"  Total: {sum(r[1] for r in rows)} competitors across {len(rows)} brands")
    print(f"\n  Top 30 brands:")
    for brand, cnt in rows[:30]:
        print(f"    {brand}: {cnt}")

    # Check for MAP/MAA brands that might be wrongly in competitors
    map_brands = ['Zara', 'Mango', 'Pull & Bear', 'Massimo Dutti', 'Bershka',
                  'Stradivarius', 'Oysho', 'Marks & Spencer', 'Lacoste',
                  'Tommy Hilfiger', 'Calvin Klein', 'Swarovski', 'Pandora',
                  'Tumi', 'Samsonite', 'Flying Tiger Copenhagen', 'Typo', 'Guess',
                  'Abercrombie & Fitch', 'SOGO', 'Seibu', 'Galeries Lafayette',
                  'Alun Alun Indonesia', 'The FoodHall', 'Daily FoodHall',
                  'Starbucks', 'Subway', 'Pizza Marzano', 'Krispy Kreme',
                  'Cold Stone Creamery', 'Genki Sushi', 'Godiva', 'Paul',
                  'Toast Box', 'Digimap', 'Digiplus', 'Sephora', 'Kinokuniya',
                  'Planet Sports', 'Sports Station', 'Foot Locker', 'Footgear',
                  'Golf House', 'Planet Sports Kids', 'Royal Sporting House',
                  'Payless', 'Skechers', 'Reebok', 'Converse', 'New Balance',
                  'Hoka', 'Crocs', 'Asics', 'Onitsuka Tiger', 'Champion',
                  'New Era', 'Aldo', 'Birkenstock', 'Dr. Martens', 'Steve Madden',
                  'Fitflop', 'Staccato', 'Clarks', 'Pazzion', 'Kidz Station',
                  'Lego Store', 'Smiggle']

    print()
    print("=" * 70)
    print("MAP/MAA brands WRONGLY placed in competitor_stores:")
    print("=" * 70)
    found_wrong = []
    cur.execute("SELECT DISTINCT brand_name FROM competitor_stores")
    comp_brands = [r[0] for r in cur.fetchall()]
    for mb in map_brands:
        for cb in comp_brands:
            if cb and (mb.lower() in cb.lower() or cb.lower() in mb.lower()):
                cur.execute("SELECT COUNT(*) FROM competitor_stores WHERE brand_name = %s", (cb,))
                cnt = cur.fetchone()[0]
                if cnt > 0:
                    print(f"  ⚠️  {cb}: {cnt} (matches MAP/MAA brand: {mb})")
                    found_wrong.append((cb, cnt))
    if not found_wrong:
        print("  (none found)")

    print()
    print("=" * 70)
    print("STORES with brands user said are NOT MAP/MAA (A&F, Typo)")
    print("=" * 70)
    cur.execute("""
        SELECT b.name, COUNT(s.id)
        FROM stores s JOIN brands b ON s.brand_id = b.id
        WHERE b.name IN ('Abercrombie & Fitch', 'Typo')
        GROUP BY b.name
    """)
    for name, cnt in cur.fetchall():
        print(f"  {name}: {cnt} stores")

    cur.close()
    conn.close()

if __name__ == "__main__":
    main()
