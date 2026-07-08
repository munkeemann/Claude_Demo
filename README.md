# Package Tracking Demo — Mock Data

Mock dataset for a package tracking application demo: **100 packages** with scan events, itineraries, dimensions, and more.

## Files

| File | Description |
|---|---|
| [`data/packages.csv`](data/packages.csv) | Flat summary table — one row per package (GitHub renders this as a searchable table) |
| [`data/packages.json`](data/packages.json) | Full nested dataset the app consumes |
| [`scripts/generate-mock-packages.js`](scripts/generate-mock-packages.js) | Seeded generator — `node scripts/generate-mock-packages.js` regenerates identical data |

## Dataset overview

- **4 fictional carriers**: SwiftShip, Meteor Express, NorthStar Logistics, GlobalParcel (each with its own tracking-ID format)
- **Status mix**: 42 delivered, 30 in transit, 10 out for delivery, 8 exceptions, 5 awaiting pickup, 5 returned
- **640 scan events** total (1–12 per package): pickup, facility arrivals/departures, customs clearance, delivery attempts, exceptions
- **Per-package details**: weight, L×W×H dimensions, declared value, contents category, fragile/signature flags, sender/recipient, origin/destination with coordinates, planned itinerary legs (truck/air/rail)
- ~18% international shipments (CA, GB, DE, JP, CN)

Data is deterministic (seeded PRNG) — re-running the generator produces the same dataset.
