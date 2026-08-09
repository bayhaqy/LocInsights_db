#!/usr/bin/env python3
"""
Task 3 (v7): Re-filter Bali shops with STRICT matching (no false positives).

Strategy:
  - Use the already-fetched raw data (bali_all_shops_raw.json)
  - For each brand, do EXACT normalized match (not substring)
  - For brands with multi-word names, also match by word boundary
  - Avoid false positives: "af" shouldn't match "Cafe"
"""
import json
import re
from pathlib import Path
from collections import Counter
from datetime import datetime, timezone

RAW_FILE = Path("/home/z/my-project/download/bali_all_shops_raw.json")
CHUNKS_DIR = Path("/home/z/my-project/download/scrape_chunks")
CHUNKS_DIR.mkdir(parents=True, exist_ok=True)

# ============================================================================
def normalize(s):
    """Lowercase + strip non-alphanumeric."""
    return re.sub(r"[^a-z0-9]", "", (s or "").lower())

def normalize_words(s):
    """Lowercase + extract word list (split on non-alphanumeric)."""
    if not s:
        return []
    return [w for w in re.split(r"[^a-z0-9]+", s.lower()) if w]

# ============================================================================
# Load raw elements
print(f"Loading raw data from {RAW_FILE}...", flush=True)
elements = json.loads(RAW_FILE.read_text())
print(f"  {len(elements)} elements", flush=True)

# Load brands from v4 file
src = open("/home/z/my-project/scripts/task3_v4_simple.py").read()
src_no_main = src.replace('if __name__ == "__main__":\n    main()', '')
ns = {}
exec(src_no_main, ns)
MAP_BRANDS = ns["MAP_BRANDS"]
MAA_BRANDS = ns["MAA_BRANDS"]
COMPETITOR_BRANDS = ns["COMPETITOR_BRANDS"]
slugify = ns["slugify"]
categorize = ns["categorize"]

# Build job list
jobs = []
for brand, terms in MAP_BRANDS.items():
    jobs.append((brand, terms, "MAP", categorize(brand)))
for brand, terms in MAA_BRANDS.items():
    jobs.append((brand, terms, "MAA", categorize(brand)))
for brand, terms in COMPETITOR_BRANDS.items():
    jobs.append((brand, terms, "COMPETITOR", categorize(brand)))

# ============================================================================
# Build better name index:
# 1. Exact normalized name → list of elements
# 2. For multi-word brands: also store as word sets
# ============================================================================
print(f"\n🔨 Building strict name index...", flush=True)
exact_index = {}     # normalized full name → elements
word_index = {}      # word → set of element keys (for AND matching)

for el in elements:
    tags = el.get("tags", {})
    name = tags.get("name", "")
    if not name:
        continue
    norm = normalize(name)
    if norm:
        exact_index.setdefault(norm, []).append(el)

    # Build word index for multi-word matching
    words = set(normalize_words(name))
    el_key = (el.get("type"), el.get("id"))
    for w in words:
        word_index.setdefault(w, set()).add(el_key)

print(f"  {len(exact_index)} exact names, {len(word_index)} words", flush=True)

# Element lookup by key
element_lookup = {}
for el in elements:
    key = (el.get("type"), el.get("id"))
    element_lookup[key] = el

# ============================================================================
# Match each brand: use EXACT match OR multi-word AND match
# ============================================================================
print(f"\n🎯 Strict matching {len(jobs)} brands...", flush=True)

total_records = 0
t0 = datetime.now()

for brand, terms, parent, category in jobs:
    slug = slugify(brand)
    out_path = CHUNKS_DIR / f"{slug}.json"

    matches = []
    seen_keys = set()

    for term in terms:
        norm_term = normalize(term)
        if not norm_term:
            continue

        # Strategy 1: EXACT match (most reliable)
        if norm_term in exact_index:
            for el in exact_index[norm_term]:
                key = (el.get("type"), el.get("id"))
                if key not in seen_keys:
                    seen_keys.add(key)
                    matches.append(el)

        # Strategy 2: For multi-word terms (≥2 words), require ALL words to match
        term_words = normalize_words(term)
        if len(term_words) >= 2:
            # Find elements whose name contains ALL term words
            word_sets = [word_index.get(w, set()) for w in term_words]
            if all(word_sets):
                # Intersect all sets
                common = set.intersection(*word_sets)
                for key in common:
                    if key not in seen_keys:
                        seen_keys.add(key)
                        el = element_lookup.get(key)
                        if el:
                            matches.append(el)

        # Strategy 3: For single-word terms ≥4 chars, do prefix match
        # (e.g., "starbucks" matches "Starbucks Coffee Kuta")
        elif len(norm_term) >= 4:
            for name, els in exact_index.items():
                if name.startswith(norm_term) or norm_term.startswith(name):
                    for el in els:
                        key = (el.get("type"), el.get("id"))
                        if key not in seen_keys:
                            seen_keys.add(key)
                            matches.append(el)

    # Build records
    records = []
    for el in matches:
        lat = el.get("lat") or el.get("center", {}).get("lat")
        lng = el.get("lon") or el.get("center", {}).get("lon")
        if not lat or not lng:
            continue
        tags = el.get("tags", {})
        records.append({
            "osm_id": f"{el['type']}/{el['id']}",
            "name": tags.get("name", "").strip(),
            "brand": tags.get("brand", brand),
            "shop": tags.get("shop", ""),
            "amenity": tags.get("amenity", ""),
            "lat": round(float(lat), 6),
            "lng": round(float(lng), 6),
            "source": "OpenStreetMap",
            "source_url": f"https://www.openstreetmap.org/{el['type']}/{el['id']}",
            "address": " ".join(filter(None, [
                tags.get("addr:housenumber", ""),
                tags.get("addr:street", ""),
                tags.get("addr:city", ""),
            ])).strip(),
            "phone": tags.get("phone", tags.get("contact:phone", "")),
            "website": tags.get("website", tags.get("contact:website", "")),
            "parent": parent,
            "brand_name": brand,
            "brand_category": category,
        })

    # Dedupe by name+lat+lng
    seen = set()
    deduped = []
    for r in records:
        key = (r["name"].lower(), r["lat"], r["lng"])
        if key not in seen:
            seen.add(key)
            deduped.append(r)

    out_path.write_text(json.dumps(deduped, indent=2, ensure_ascii=False))
    total_records += len(deduped)

# ============================================================================
# Report
# ============================================================================
print(f"\n✅ Strict matching done in {(datetime.now()-t0).total_seconds():.0f}s", flush=True)
print(f"   Total records: {total_records}", flush=True)

print(f"\n📊 By parent:")
parent_totals = Counter()
for f in CHUNKS_DIR.glob("*.json"):
    for r in json.loads(f.read_text()):
        parent_totals[r.get("parent")] += 1
for parent, cnt in sorted(parent_totals.items()):
    print(f"  {parent}: {cnt}")

print(f"\n📊 Top 30 brands:")
brand_counts = Counter()
for f in CHUNKS_DIR.glob("*.json"):
    for r in json.loads(f.read_text()):
        brand_counts[(r.get("parent"), r.get("brand_name"))] += 1
for (parent, brand), cnt in sorted(brand_counts.items(), key=lambda x: -x[1])[:30]:
    print(f"  [{parent}] {brand}: {cnt}")
