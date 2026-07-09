# Package Router

A local demo application that lets **product owners visually test a package-processing service** — no production systems, no cloud dependencies, everything on your machine.

Packages flow from a source queue through a **Processor** (validate → measure → route) into size-category consumers. Bad data never crashes the pipeline; it lands in a visible **Rejected** dead-letter lane with a reason badge.

![stack](https://img.shields.io/badge/backend-FastAPI-009688) ![stack](https://img.shields.io/badge/frontend-React%20%2B%20Vite-61dafb) ![tests](https://img.shields.io/badge/tests-58%20passing-brightgreen)

## Quick start

**Prerequisites:** Python 3.11+ and Node 18+ on PATH.

```bat
start.bat        REM Windows — installs deps on first run, launches everything
```

```bash
./start.sh       # macOS / Linux / Git Bash
```

Then open **http://localhost:5173**. The FastAPI backend runs on :8000 (interactive API docs at http://localhost:8000/docs).

## What you can do

| Action | Where |
|---|---|
| Process the 100-package sample dataset with animated routing | **▶ Process all 100** (header) |
| Watch it faster/slower | Speed slider (0.25×–4×) |
| Build any package, including invalid ones | **+ Custom package** |
| Inject bad data one click at a time | **Chaos testing** panel |
| Flip the Gigantic category live | **Gigantic Category — KAN-20** switch |
| Compare routing with the toggle off vs. on | **⇄ Before / After** |
| Clear everything | **Reset** |

## Routing rules

Routing is by dimensional volume (L × W × H, cubic inches):

| Category | Toggle OFF | Toggle ON |
|---|---|---|
| Small | < 1,000 | < 1,000 |
| Medium | 1,000 – 7,999 | 1,000 – 7,999 |
| Large | ≥ 8,000 | 8,000 – 19,999 |
| **Gigantic** | — | **≥ 20,000** |

Exact boundary values route to the upper category (a 10×10×10 box at exactly 1,000 in³ is Medium).

## Validation (the point of the demo)

Every package is validated before routing. Failures are **visible, never silent**:

| Reason | Trigger |
|---|---|
| `MISSING_DIMENSIONS` | any of length/width/height absent or null |
| `INVALID_DIMENSIONS` | zero or negative dimension |
| `TYPE_ERROR` | non-numeric dimension or weight (e.g. `"twelve"`) |
| `OUT_OF_RANGE` | dimension > 1,000 in or weight > 5,000 lbs |

## How the feature toggle works

Toggles live in [`backend/app/config.py`](backend/app/config.py) — a small named-boolean registry. `ENABLE_GIGANTIC_CATEGORY` (story **KAN-20**) is read on every routing call, so flipping it via `POST /config/toggle` (or the UI switch) changes behavior **immediately, with no restart**. Add new toggles by extending `DEFAULT_TOGGLES`.

## Project layout

```
backend/app/       FastAPI service (main, routing, validation, consumers, config)
backend/tests/     pytest suite — 58 tests: boundaries, rejections, API, toggle
data/              seeded generator + sample_packages.json (100 × 20 fields)
frontend/src/      React dashboard (pipeline animation, lanes, builder, chaos, comparison)
```

## Running the tests

```bash
cd backend
.venv/Scripts/python -m pytest tests/ -v     # Windows
```

## API surface

- `POST /packages/process` — route one package (object) or a batch (array)
- `POST /packages/process-all` — route the bundled sample dataset
- `GET /packages/sample` — raw sample data (the UI animates from this)
- `GET /consumers/state` — per-consumer counts + logs, and rejections
- `GET /config` · `POST /config/toggle` — read / flip feature toggles
- `POST /reset` — clear all consumer state

Built against Jira stories **KAN-18** (core service), **KAN-19** (dashboard), **KAN-20** (Gigantic toggle), **KAN-21** (tests & docs). See `DEMO_SCRIPT.md` for the 5-minute walkthrough.
