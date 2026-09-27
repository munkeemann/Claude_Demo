#!/usr/bin/env python3
"""Turns USDA FSIS FoodKeeper data into Larder's bundled shelf-life table.

Input: .github/foodkeeper/raw/foodkeeper.json, the FoodKeeper spreadsheet as
FSIS publishes it in JSON (fetched by the "FoodKeeper data" workflow).
Output: Packages/InventoryCore/Sources/InventoryCore/Expiry/FoodKeeperData.swift

Each product keeps its name, subtitle, keywords and, per storage, a range in
days or a special value:

  p   pantry, unopened          po  pantry after opening
  f   fridge, unopened          fo  fridge after opening
  ft  fridge after thawing      z   freezer

  [min, max]  days
  "date"      keep until the package date
  "no"        not recommended
  "ever"      keeps indefinitely
  "ripe"      until ripe

FoodKeeper gives some times from the date of purchase (the DOP_ columns) and
some without that qualifier; the purchase-based ones win when both exist.
FoodKeeper data is a US government work in the public domain.
"""

import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
SOURCE = os.path.join(ROOT, ".github", "foodkeeper", "raw", "foodkeeper.json")
OUTPUT = os.path.join(HERE, "..", "Packages", "InventoryCore", "Sources", "InventoryCore", "Expiry", "FoodKeeperData.swift")

UNIT_DAYS = {"days": 1, "day": 1, "weeks": 7, "week": 7, "months": 30, "month": 30, "years": 365, "year": 365}

# (slot, preferred column prefix, fallback prefix)
SLOTS = [
    ("p", "DOP_Pantry", "Pantry"),
    ("po", "Pantry_After_Opening", None),
    ("f", "DOP_Refrigerate", "Refrigerate"),
    ("fo", "Refrigerate_After_Opening", None),
    ("ft", "Refrigerate_After_Thawing", None),
    ("z", "DOP_Freeze", "Freeze"),
]

TIPS = [("p", ["Pantry_tips", "DOP_Pantry_tips"]), ("f", ["Refrigerate_tips", "DOP_Refrigerate_tips"]), ("z", ["Freeze_Tips", "DOP_Freeze_Tips"])]


def rows(sheets, name):
    out = []
    for row in sheets[name]:
        record = {}
        for cell in row:
            record.update(cell)
        out.append(record)
    return out


def number(value):
    if isinstance(value, (int, float)) and not (isinstance(value, float) and math.isnan(value)):
        return float(value)
    return None


def guidance(product, prefix):
    """The storage value for one column group, or None when it says nothing."""
    if prefix is None:
        return None
    low, high = number(product.get(prefix + "_Min")), number(product.get(prefix + "_Max"))
    metric = (product.get(prefix + "_Metric") or "").strip().lower()
    raw_min = product.get(prefix + "_Min")
    if isinstance(raw_min, str) and "date" in raw_min.lower():
        return "date"
    if metric == "package use-by date":
        return "date"
    if metric == "not recommended":
        return "no"
    if metric == "indefinitely":
        return "ever"
    if metric == "when ripe":
        return "ripe"
    if low is None and high is None:
        return None
    low = high if low is None else low
    high = low if high is None else high
    if metric == "hours":
        days = lambda v: int(v // 24)
    elif metric in UNIT_DAYS:
        days = lambda v: int(round(v * UNIT_DAYS[metric]))
    else:
        print(f"warning: product {product.get('ID')} has unknown metric {metric!r}", file=sys.stderr)
        return None
    return [days(min(low, high)), days(max(low, high))]


def keywords(product):
    parts = []
    for text in (product.get("Keywords") or "").split(","):
        text = " ".join(text.strip().lower().split())
        if text and text not in parts:
            parts.append(text)
    return parts


def clean(text):
    if not isinstance(text, str):
        return None
    text = " ".join(text.split())
    return text or None


def main():
    with open(SOURCE) as handle:
        data = json.load(handle)
    sheets = {sheet["name"]: sheet["data"] for sheet in data["sheets"]}
    version = rows(sheets, "Version")[0]

    categories = {}
    for category in rows(sheets, "Category"):
        name = category["Category_Name"].strip()
        sub = clean(category.get("Subcategory_Name"))
        categories[str(int(category["ID"]))] = name + (" / " + sub if sub else "")

    products = []
    for product in rows(sheets, "Product"):
        name = clean(product.get("Name"))
        if not name:
            continue
        times = {}
        for slot, preferred, fallback in SLOTS:
            value = guidance(product, preferred)
            if value is None:
                value = guidance(product, fallback)
            if value is not None:
                times[slot] = value
        tips = {}
        for slot, columns in TIPS:
            for column in columns:
                tip = clean(product.get(column))
                if tip:
                    tips[slot] = tip
                    break
        entry = {"i": int(product["ID"]), "c": int(product["Category_ID"]), "n": name, "k": keywords(product), "t": times}
        subtitle = clean(product.get("Name_subtitle"))
        if subtitle:
            entry["s"] = subtitle
        if tips:
            entry["tips"] = tips
        products.append(entry)

    products.sort(key=lambda entry: entry["i"])
    payload = {
        "source": "USDA FSIS FoodKeeper, data version %d (%s)" % (int(version["Data_Version_Number"]), data.get("fileName", "")),
        "categories": categories,
        "products": products,
    }
    text = json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    assert '"""#' not in text

    swift = (
        "// Generated by Larder/scripts/foodkeeper.py from USDA FSIS FoodKeeper data\n"
        "// (public domain). Don't edit by hand; rerun the script instead.\n\n"
        "enum FoodKeeperData {\n"
        "    static let json = #\"\"\"\n" + text + "\n\"\"\"#\n"
        "}\n"
    )
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(OUTPUT, "w") as handle:
        handle.write(swift)
    print(f"{len(products)} products, {len(text) // 1024} KB -> {os.path.relpath(OUTPUT, ROOT)}")


if __name__ == "__main__":
    main()
