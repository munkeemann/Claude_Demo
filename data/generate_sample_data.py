"""Generate data/sample_packages.json — 100 packages, 20 fields each.

Seeded so the dataset is reproducible. Dimension mix is engineered to
give every size category meaningful volume, including a band of
oversized packages (>= 20,000 in³) and edge cases sitting exactly on
and adjacent to the 1,000 / 8,000 / 20,000 in³ category boundaries.

Run: python generate_sample_data.py
"""

import json
import random
from datetime import date, timedelta
from pathlib import Path
from typing import Any, Dict, List

rng = random.Random(42)

CITIES = [
    ("Seattle", "98101"), ("Portland", "97201"), ("San Francisco", "94103"),
    ("Los Angeles", "90012"), ("Denver", "80202"), ("Dallas", "75201"),
    ("Chicago", "60601"), ("Atlanta", "30303"), ("Miami", "33101"),
    ("New York", "10001"), ("Boston", "02108"), ("Philadelphia", "19103"),
    ("Phoenix", "85004"), ("Minneapolis", "55401"), ("Nashville", "37201"),
]
FIRST = ["Ava", "Liam", "Maya", "Noah", "Zoe", "Eli", "Ivy", "Owen", "Ruth", "Max",
         "Nina", "Cole", "Jade", "Finn", "Lena", "Seth", "Tara", "Drew", "Rosa", "Kai"]
LAST = ["Nguyen", "Garcia", "Smith", "Chen", "Patel", "Brooks", "Kim", "Lopez",
        "Weber", "Okafor", "Reed", "Silva", "Novak", "Hayes", "Cruz", "Larsen"]
SERVICE_TYPES = ["Ground", "Express", "Overnight"]
CONTENTS = [
    "Books and printed media", "Consumer electronics", "Apparel",
    "Kitchen appliance", "Automotive parts", "Sporting equipment",
    "Office supplies", "Medical supplies", "Furniture component",
    "Industrial fasteners", "Toys and games", "Garden tools",
]


def _name() -> str:
    return f"{rng.choice(FIRST)} {rng.choice(LAST)}"


def _dims_for_band(band: str) -> tuple:
    """Return (L, W, H) targeting a volume band."""
    if band == "small":          # < 1,000 in³
        return (rng.randint(4, 14), rng.randint(3, 10), rng.randint(2, 7))
    if band == "medium":         # 1,000 – 7,999
        return (rng.randint(14, 24), rng.randint(10, 18), rng.randint(8, 16))
    if band == "large":          # 8,000 – 19,999
        return (rng.randint(24, 34), rng.randint(18, 26), rng.randint(14, 22))
    # gigantic band: >= 20,000 (routes to Large until the Gigantic toggle exists)
    return (rng.randint(38, 60), rng.randint(26, 40), rng.randint(20, 34))


# Exact/near boundary edge cases: (dims, note)
EDGE_CASES = [
    ((10, 10, 10), "exactly 1,000 → medium"),
    ((10, 10, 9.99), "just under 1,000 → small"),
    ((20, 20, 20), "exactly 8,000 → large"),
    ((20, 20, 19.99), "just under 8,000 → medium"),
    ((25, 40, 20), "exactly 20,000 → gigantic when enabled"),
    ((25, 40, 19.99), "just under 20,000 → large"),
    ((50, 40, 10), "exactly 20,000 → gigantic when enabled"),
    ((1, 1, 999), "long tube, small volume"),
]


def make_package(i: int, dims: tuple) -> Dict[str, Any]:
    """Build one 20-field package record."""
    length, width, height = dims
    origin_city, origin_zip = rng.choice(CITIES)
    dest_city, dest_zip = rng.choice([c for c in CITIES if c[0] != origin_city])
    ship = date(2026, 7, 1) + timedelta(days=rng.randint(0, 6))
    service = rng.choice(SERVICE_TYPES)
    transit = {"Ground": rng.randint(3, 7), "Express": rng.randint(2, 3), "Overnight": 1}[service]
    volume = length * width * height
    weight = round(max(0.4, volume * rng.uniform(0.004, 0.012)), 1)

    return {
        "trackingNumber": f"PKR-{2026_000_000 + i:010d}",
        "originZip": origin_zip,
        "destinationZip": dest_zip,
        "originCity": origin_city,
        "destinationCity": dest_city,
        "serviceType": service,
        "lengthIn": length,
        "widthIn": width,
        "heightIn": height,
        "weightLbs": weight,
        "declaredValue": round(rng.uniform(10, 2400), 2),
        "shipDate": ship.isoformat(),
        "estimatedDelivery": (ship + timedelta(days=transit)).isoformat(),
        "senderName": _name(),
        "recipientName": _name(),
        "hazmatFlag": rng.random() < 0.05,
        "signatureRequired": rng.random() < 0.22,
        "residentialFlag": rng.random() < 0.6,
        "priorityScore": rng.randint(1, 100),
        "contentsDescription": rng.choice(CONTENTS),
    }


def main() -> None:
    packages: List[Dict[str, Any]] = []

    # 92 banded packages: small 30, medium 30, large 20, gigantic-band 12
    bands = ["small"] * 30 + ["medium"] * 30 + ["large"] * 20 + ["gigantic"] * 12
    rng.shuffle(bands)
    for i, band in enumerate(bands, start=1):
        packages.append(make_package(i, _dims_for_band(band)))

    # 8 boundary edge cases
    for j, (dims, _note) in enumerate(EDGE_CASES, start=len(bands) + 1):
        packages.append(make_package(j, dims))

    assert len(packages) == 100
    assert all(len(p) == 20 for p in packages)

    out = Path(__file__).parent / "sample_packages.json"
    out.write_text(json.dumps(packages, indent=2), encoding="utf-8")

    from collections import Counter
    def cat(p):
        v = p["lengthIn"] * p["widthIn"] * p["heightIn"]
        return "small" if v < 1000 else "medium" if v < 8000 else "large" if v < 20000 else "gigantic-band"
    print(f"Wrote {len(packages)} packages -> {out.name}")
    print("Volume distribution:", dict(Counter(cat(p) for p in packages)))


if __name__ == "__main__":
    main()
