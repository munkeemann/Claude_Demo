# Change Request CHG-2026-0709

| Field | Value |
|---|---|
| **CR number** | CHG-2026-0709 |
| **Title** | Promote ParcelTrace 1.0 to L3 (Production) |
| **Environment** | L3 — Production |
| **Scheduled** | Thursday, July 9, 2026, 20:00–21:00 ET |
| **Deployed by** | A. Rivera |
| **Approver** | Release Manager |
| **Risk level** | Medium |
| **Affected components** | parceltrace-web, packages-data |
| **Story count** | 7 (23 points) |

## Scope
Promotion of the following stories from L2 (QA/Staging) to L3 (Production):

- **KAN-6** — Search shipments by tracking ID or keyword (3 pts)
- **KAN-7** — Browse all shipments in a sortable directory (3 pts)
- **KAN-9** — View full shipment detail panel (3 pts)
- **KAN-10** — See chronological scan-event tracking history (5 pts)
- **KAN-16** — Highlight exception shipments with an alert banner (3 pts)
- **KAN-17** — Surface delivery progress and ETA (3 pts)
- **KAN-11** — View planned itinerary with transport modes (3 pts)

## Rollback plan
Re-point the L3 (Production) static host to the previous release tag and invalidate the CDN cache. No database migrations in this release, so rollback is a single redeploy of the prior build (est. < 10 min).

## Backout trigger
Any P1/P2 defect in parceltrace-web or packages-data within the first 60 minutes post-deploy, or error rate above baseline.

---
*Generated from release.json + jira/stories.json. CR number derived from deploy date.*
