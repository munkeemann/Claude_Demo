**Subject:** [Release] ParcelTrace 1.0 → L3 (Production) — Thursday, July 9, 2026

Hi all,

**ParcelTrace 1.0** is scheduled to promote to **L3 (Production)** on **Thursday, July 9, 2026**, during the **20:00–21:00 ET** window. This release moves **7 stories (23 points)** across 3 feature areas: Shipment Search & Directory, Shipment Detail & Tracking History, Exceptions & Delivery Alerts.

### Why it matters (business value)
- **Search shipments by tracking ID or keyword** (KAN-6) — Cuts lookup time from minutes to seconds; the single most-used action for support agents fielding "where is my package" calls.
- **Browse all shipments in a sortable directory** (KAN-7) — Gives supervisors a single triage surface instead of exporting to spreadsheets.
- **View full shipment detail panel** (KAN-9) — Keeps agents in flow; no full-page navigation means faster case handling.
- **See chronological scan-event tracking history** (KAN-10) — The core promise of a tracking product; directly reduces "where is it" contacts.
- **Highlight exception shipments with an alert banner** (KAN-16) — Drives proactive outreach on weather delays, address issues, and customs holds — the shipments most likely to generate complaints.
- **Surface delivery progress and ETA** (KAN-17) — Improves first-contact resolution by giving agents an ETA they can quote with confidence.
- **View planned itinerary with transport modes** (KAN-11) — Enables proactive intervention on at-risk connections before they become exceptions.

### What's changing (technical summary)
- **KAN-6** — Client-side substring match over a precomputed haystack string per shipment; debounced input event.
- **KAN-7** — Stable comparator keyed by column; status sorts by a fixed severity order rather than alphabetically.
- **KAN-9** — Single reusable drawer element repopulated on open; overlay + transform transition; keydown listener for Escape.
- **KAN-10** — Reverse-ordered scanEvents array; CSS pseudo-element rail with a highlighted head node.
- **KAN-16** — Reads exception.{code,description}; banner is conditional; status color tokens per status.
- **KAN-17** — Status→progress mapping; date formatting via toLocaleString; delivered vs shipped chosen by presence of deliveredAt.
- **KAN-11** — Maps itinerary[].mode to an icon lookup; planned times formatted to short dates.

### Deployment
- **Environment:** L3 — Production
- **Window:** Thursday, July 9, 2026, 20:00–21:00 ET
- **Deployed by:** A. Rivera
- **Approver:** Release Manager
- **Risk:** Medium
- **Change request:** CHG-2026-0709
- **Components:** parceltrace-web, packages-data

### Rollback
Re-point the L3 (Production) static host to the previous release tag and invalidate the CDN cache. No database migrations in this release, so rollback is a single redeploy of the prior build (est. < 10 min).

Tracking in Jira: KAN-6, KAN-7, KAN-9, KAN-10, KAN-16, KAN-17, KAN-11.

Thanks,
A. Rivera
