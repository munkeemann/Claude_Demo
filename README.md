# ParcelTrace — Package Tracking Demo

A demo of an end-to-end package-tracking product: a working web console over a mock
dataset of **100 shipments**, a live **Jira backlog**, and a **"Move to L3" release
automation** that drafts an email, a Teams message, a change request, and an Excel
deployment log — all from one input file.

## 1. The web app

Open [`index.html`](index.html) (double-click, or serve the folder). Vanilla JS, no build step.

- **Directory** — searchable, filterable, sortable list of all 100 shipments
- **Status chips** — live counts per status; click to filter
- **Detail drawer** — scan-event timeline, planned itinerary, dimensions/weight/value, sender/recipient, exception banner, progress + ETA

Data loads from [`data/packages.js`](data/packages.js) (`window.PACKAGES`).

## 2. The data

| File | Description |
|---|---|
| [`data/packages.csv`](data/packages.csv) | Flat summary table — one row per package (GitHub renders this as a searchable table) |
| [`data/packages.json`](data/packages.json) | Full nested dataset the app consumes |
| [`data/packages.js`](data/packages.js) | Browser-friendly copy (`window.PACKAGES`) for the app |
| [`scripts/generate-mock-packages.js`](scripts/generate-mock-packages.js) | Seeded generator — `node scripts/generate-mock-packages.js` regenerates identical data |

**Dataset:** 4 fictional carriers · status mix of 42 delivered / 30 in transit / 10 out for delivery / 8 exceptions / 5 awaiting pickup / 5 returned · 640 scan events · per-package weight, L×W×H dimensions, declared value, contents, fragile/signature flags, sender/recipient, itinerary legs (truck/air/rail). ~18% international. Deterministic (seeded PRNG).

## 3. Jira backlog

Created live in Jira project **KAN** — 1 Epic, 4 Features, 12 Stories (33 points).
See [`release/jira/backlog.md`](release/jira/backlog.md) for the tree with issue links.
[`release/jira/stories.json`](release/jira/stories.json) is the machine-readable source of
truth (real `KAN-##` keys, business value, tech notes, acceptance criteria) that the
release workflow references.

## 4. Release automation — "Move to L3"

One input drives every output. Edit [`release/release.json`](release/release.json) — the
stories in the release, deploy date, deployer, risk — then run:

```
node release/scripts/generate-release.js
```

That regenerates, for the stories being promoted to L3 (Production):

| Output | What it is |
|---|---|
| [`release/out/email-draft.html`](release/out/email-draft.html) / `.md` | Stakeholder release email — business value + technical summary + deploy details |
| [`release/out/teams-message.md`](release/out/teams-message.md) | Concise Teams message (posted live into the Teams desktop app) |
| [`release/out/change-request.md`](release/out/change-request.md) | Mocked change request (CR number, risk, rollback, approver, window) |
| [`release/deployment-log.xlsx`](release/deployment-log.xlsx) | Real Excel log — one row per released story (release, story, env, date, deployer, CR, status) |

The Node generator writes the text artifacts and then invokes
[`release/scripts/build-xlsx.py`](release/scripts/build-xlsx.py) (openpyxl) for the Excel
log — so it's a single command. The CR number is derived from the deploy date; the
Excel log rebuilds from the current release each run, keeping all four outputs in lockstep.

**The demo:** change one field in `release.json` (add a story, swap the deployer, move the
date), re-run, and the email, Teams message, change request, and Excel row all update together.

### Requirements
- Node (for the app data + release generator)
- Python 3 with `openpyxl` (`pip install openpyxl`) for the Excel log
