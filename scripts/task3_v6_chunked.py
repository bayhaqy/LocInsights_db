#!/usr/bin/env python3
"""
Task 3 (v6): Fetch Bali shops in 9 chunks (one per kabupaten/kota) — fast & reliable.

Strategy:
  - Split Bali bbox into 9 sub-bboxes (one per kabupaten)
  - Fetch shops per kabupaten (each takes 2-10 seconds)
  - Save raw responses, then filter locally
"""
import json
import os
import re
import time
import sys
import requests
from pathlib import Path
from datetime import datetime, timezone

OVERPASS_SERVERS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
]
USER_AGENT = "LocInsight/1.0 (MAP Active Adiperkasa Data Team)"

# Bali kabupaten/kota sub-bboxes (south, west, north, east)
# Source: approximated from Bali administrative boundaries
SUB_BBOXES = [
    ("badung",        "-8.95,115.00,-8.50,115.30"),   # Badung (Denpasar surround)
    ("denpasar",      "-8.75,115.15,-8.55,115.30"),   # Denpasar Kota
    ("gianyar",       "-8.65,115.20,-8.30,115.55"),   # Gianyar (incl. Ubud)
    ("bangli",        "-8.35,115.10,-8.10,115.40"),   # Bangli
    ("klungkung",     "-8.65,115.30,-8.40,115.60"),   # Klungkung
    ("karangasem",    "-8.45,115.45,-8.10,115.75"),   # Karangasem
    ("buleleng",      "-8.30,114.45,-8.00,115.25"),   # Buleleng (Singaraja)
    ("jembrana",      "-8.55,114.40,-8.20,114.85"),   # Jembrana
    ("tabanan",       "-8.65,114.85,-8.30,115.20"),   # Tabanan
]

RAW_DIR = Path("/home/z/my-project/download/bali_raw_chunks")
RAW_DIR.mkdir(parents=True, exist_ok=True)

# ============================================================================
def fetch_bbox(name, bbox, retry=3):
    """Fetch all named shops in a bbox."""
    out_path = RAW_DIR / f"{name}.json"
    if out_path.exists():
        try:
            existing = json.loads(out_path.read_text())
            if isinstance(existing, list) and len(existing) > 0:
                return existing
        except Exception:
            pass

    query = f"""
[out:json][timeout:120];
(
  nwr["shop"]["name"]({bbox});
  nwr["amenity"~"cafe|restaurant|fast_food|fuel|pharmacy"]["name"]({bbox});
  nwr["healthcare"~"pharmacy"]["name"]({bbox});
);
out center 9999;
"""
    payload = {"data": query}
    print(f"  Fetching {name} ({bbox})...", flush=True)
    for attempt in range(retry):
        url = OVERPASS_SERVERS[attempt % len(OVERPASS_SERVERS)]
        try:
            t0 = time.time()
            r = requests.post(url, data=payload, timeout=130,
                              headers={"User-Agent": USER_AGENT})
            elapsed = time.time() - t0
            if r.status_code == 200:
                elements = r.json().get("elements", [])
                print(f"    ✓ {len(elements)} elements in {elapsed:.0f}s", flush=True)
                out_path.write_text(json.dumps(elements, indent=2, ensure_ascii=False))
                return elements
            elif r.status_code == 429:
                print(f"    Rate limited, waiting 10s...", flush=True)
                time.sleep(10)
                continue
            else:
                print(f"    HTTP {r.status_code}", flush=True)
        except Exception as e:
            print(f"    ERROR: {str(e)[:80]}", flush=True)
        time.sleep(3)
    print(f"    ❌ All retries failed for {name}", flush=True)
    # Save empty so we don't retry
    out_path.write_text("[]")
    return []

def normalize(s):
    return re.sub(r"[^a-z0-9]", "", (s or "").lower())

def main():
    print(f"Started: {datetime.now(timezone.utc).isoformat()}", flush=True)
    print(f"\n🌐 Fetching Bali shops in {len(SUB_BBOXES)} chunks...", flush=True)

    all_elements = []
    t0 = time.time()
    for name, bbox in SUB_BBOXES:
        elements = fetch_bbox(name, bbox)
        all_elements.extend(elements)
        time.sleep(1)  # be nice

    print(f"\n📊 Total elements fetched: {len(all_elements)} in {time.time()-t0:.0f}s", flush=True)

    # Save combined raw
    combined_path = Path("/home/z/my-project/download/bali_all_shops_raw.json")
    combined_path.write_text(json.dumps(all_elements, indent=2, ensure_ascii=False))
    print(f"💾 Saved combined to {combined_path} ({combined_path.stat().st_size//1024} KB)", flush=True)

    # ============================================================================
    # Filter for our brands
    # ============================================================================
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

    CHUNKS_DIR = Path("/home/z/my-project/download/scrape_chunks")
    CHUNKS_DIR.mkdir(parents=True, exist_ok=True)

    # Build name index
    print(f"\n🔨 Building name index...", flush=True)
    name_index = {}
    for el in all_elements:
        tags = el.get("tags", {})
        for key in ("name", "brand", "name:en", "alt_name"):
            n = tags.get(key)
            if n:
                norm = normalize(n)
                if norm:
                    name_index.setdefault(norm, []).append(el)
    print(f"   {len(name_index)} unique normalized names", flush=True)

    # Build job list
    jobs = []
    for brand, terms in MAP_BRANDS.items():
        jobs.append((brand, terms, "MAP", categorize(brand)))
    for brand, terms in MAA_BRANDS.items():
        jobs.append((brand, terms, "MAA", categorize(brand)))
    for brand, terms in COMPETITOR_BRANDS.items():
        jobs.append((brand, terms, "COMPETITOR", categorize(brand)))

    print(f"\n🎯 Filtering {len(jobs)} brands against local index...", flush=True)

    completed = 0
    total_records = 0
    t1 = time.time()

    for brand, terms, parent, category in jobs:
        slug = slugify(brand)
        out_path = CHUNKS_DIR / f"{slug}.json"

        matches = []
        seen_keys = set()
        for term in terms:
            norm = normalize(term)
            if not norm:
                continue
            # Try direct match + substring match
            for key, els in name_index.items():
                if norm == key or norm in key or key in norm:
                    for el in els:
                        ek = (el.get("type"), el.get("id"))
                        if ek in seen_keys:
                            continue
                        seen_keys.add(ek)
                        lat = el.get("lat") or el.get("center", {}).get("lat")
                        lng = el.get("lon") or el.get("center", {}).get("lon")
                        if not lat or not lng:
                            continue
                        tags = el.get("tags", {})
                        matches.append({
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
        for r in matches:
            key = (r["name"].lower(), r["lat"], r["lng"])
            if key not in seen:
                seen.add(key)
                deduped.append(r)

        out_path.write_text(json.dumps(deduped, indent=2, ensure_ascii=False))
        completed += 1
        total_records += len(deduped)
        if completed % 10 == 0 or completed == len(jobs):
            elapsed = time.time() - t1
            print(f"  [{completed:3d}/{len(jobs)}] last: {brand:35s} → {len(deduped):3d}  "
                  f"({elapsed:.0f}s)", flush=True)

    print(f"\n✅ Filtering done in {time.time()-t1:.0f}s | Total records: {total_records}", flush=True)
    print(f"Total elapsed: {time.time()-t0:.0f}s", flush=True)

if __name__ == "__main__":
    main()
