# Package Router — 5-Minute Executive Demo

**Setup (before the room fills):** run `start.bat`, open http://localhost:5173, click **Reset**. Keep the Gigantic toggle **OFF**. Have the Jira board open in a browser tab (KAN project).

---

## 1 · Watch the router work (~90 seconds)

Click **▶ Process all 100**.

A hundred real-shaped packages stream out of the queue, through the Processor, and sort themselves into Small / Medium / Large lanes — live counts climbing, every chip color-coded. Click a lane header to expand it and show individual packages with dimensions and computed volume.

> **Talking point:** *"This is our routing logic running against realistic data — not a slide about it. When a product owner can watch behavior instead of reading a spec, misunderstandings surface in minutes instead of in production."*

## 2 · Try to break it (~60 seconds)

In the **Chaos testing** panel click each preset: missing dimensions, negative dimensions, text where a number belongs, absurd values, an empty payload. Optionally open **+ Custom package** and type something ridiculous yourself.

Every bad package lands in the red **Rejected** lane with a reason badge. Nothing crashes; nothing disappears silently.

> **Talking point:** *"Bad data is a when, not an if. The service turns every failure into a labeled, auditable rejection — and the PO can verify that behavior themselves, with zero engineering time."*

## 3 · Ship a routing change live — Jira story KAN-20 (~60 seconds)

Show the board: story **KAN-20, "Add Gigantic routing category behind ENABLE_GIGANTIC_CATEGORY feature toggle"** — created, worked against in commits, closed with delivery notes.

Now flip the header switch labeled **"Gigantic Category — KAN-20"**. Instantly: a magenta **Gigantic** lane appears and Large's range narrows to 8,000–19,999 in³. No deploy, no restart. Click **▶ Process all 100** again — oversized packages now stream into Gigantic.

> **Talking point:** *"The ticket, the code, and the behavior are one traceable thread. And because it's behind a toggle, the business — not a release calendar — decides when it turns on."*

## 4 · The decision slide (~60 seconds)

Click **⇄ Before / After**.

The dataset runs both ways against the live service and renders the impact side-by-side: **Large 36 → 22, Gigantic 0 → 14**, Small and Medium untouched — plus the exact 14 packages that would move, largest first.

> **Talking point:** *"This is what PO-driven testing buys us: before we commit to a change, we know precisely what it does — which categories shift, by how much, and which specific shipments are affected. That's a business decision made with evidence, not a bet."*

---

**Close:** Reset, leave the pipeline idle, and note the whole thing — backlog, code, tests, and this demo — was built ticket-by-ticket on the board they just saw. Total build: 4 tickets, 4 commits, 58 tests.

### If asked

- **"Is the data real?"** Seeded synthetic data — 100 packages, 20 fields, engineered to cover every category and boundary (including exactly 1,000 / 8,000 / 20,000 in³).
- **"What's the stack?"** FastAPI (Python) + React. Runs on any Windows laptop with one command.
- **"Can we add another category / rule?"** Yes — routing thresholds and toggles are isolated in two small modules; a new rule is a story like KAN-20 was.
