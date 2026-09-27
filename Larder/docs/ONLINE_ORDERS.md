# Phase 5: Amazon and online orders (design)

Status: design only. Nothing here is built yet. The receipt pipeline from Phase 2 was written so
this can reuse it.

## The constraint

Amazon has no consumer API for order history. Scraping amazon.com breaks often, violates the
terms of service, and would mean storing the user's Amazon credentials, so it's out. Order data
reaches the user in two supported ways:

1. **Order emails** (confirmation, shipment, delivery) in the user's inbox.
2. **"Request Your Data"** (Account → Privacy → Request Your Data → Your Orders). This produces a
   CSV of the full order history, delivered a few days after the request.

The plan builds on both, in three stages that each ship on their own.

## Stage A: paste or share an order email (recommended next)

**Entry points**
- **Scan Receipt → Paste Order Email.** Same paste sheet as receipts, but it accepts HTML or text.
- **Share extension** ("Larder" in the iOS share sheet). It accepts `public.plain-text`,
  `public.html` and `com.adobe.pdf`. PDF matters because of the Mail workaround: Print → pinch
  out → Share turns a whole message into a PDF.
  - Extensions can't open their containing app, so the extension writes the payload to an
    **App Group inbox** (a JSON file per import) and shows "Saved. Open Larder to review."
  - On launch the app drains the inbox into a "Pending imports" banner on the Inventory tab.
  - The SwiftData store stays in the app container. Only the inbox is shared.

**Pipeline** (new pieces are marked ◆; everything else already exists)
1. ◆ `EmailTextExtractor` (Core): HTML → text.
   - Drops `<style>`/`<script>` and decodes entities.
   - Adds line breaks at block elements (`tr`, `p`, `div`, `br`) so item rows stay rows.
   - PDF text comes from PDFKit on the app side.
2. ◆ `EmailRedactor` (Core): strips the shipping-address block, names after "Hello"/"Hi", phone
   numbers, and card digits before anything is sent to Anthropic. Unit-tested against sanitized
   fixtures.
3. ◆ **Order extraction**. `ReceiptExtractionSchema` plus these fields:
   - `merchant`
   - `orderNumber` (e.g. `113-1234567-1234567`)
   - `orderDate`
   - `deliveryDate` (nullable)
   - `emailKind` (confirmation / shipped / delivered / other)

   The prompt explains Amazon's long listing titles, for example "Charmin Ultra Soft Toilet
   Paper, 18 Family Mega Rolls = 90 Regular Rolls" → name "Toilet Paper", brand "Charmin", pack
   size "18 mega rolls", quantity 1 pack. The source is `PurchaseSource.email`.
4. **Review.** The existing `ReceiptReviewView`, with an order-number field in the header.
5. **Import.** The existing `importReceipt`, extended to:
   - stamp `PurchaseEvent.externalOrderID` (the field already exists)
   - write `AliasKind.emailText` aliases (the kind already exists), keyed by the normalized first
     ~12 words of the title, so corrections carry over exactly as they do for receipts.

**Deduplication**
- Before extraction, look up `externalOrderID`. If the order is already imported, offer "Update
  delivery date" instead of re-adding.
- Split shipments ("2 of 3 items shipped") are deduplicated per `(orderNumber, alias key)`.
- Only **order confirmations** create purchases. Shipped/delivered emails for a known order only
  update the purchase date to the delivery date, which is the better signal for run-out timing.

**Model change.** Generalize `Receipt` into a purchase document by adding:
- `kind` (receipt / email / csv)
- `externalID`
- `merchant`

These are optional fields, so it's a lightweight migration and stays CloudKit-safe.

Effort: about 1–2 days, plus a share-extension target in `project.yml`.

## Stage B: Amazon order-history CSV backfill

This is a one-time import that gives the forecaster years of purchase intervals straight away.
- ◆ `AmazonOrderCSVParser` (Core) detects columns by header name rather than position, because
  Amazon renames them. It looks for `Order ID`, `Order Date`, `Product Name`, `Quantity`,
  `Unit Price` and `ASIN`, and handles quoted fields and multiple currencies.
- Group rows by distinct ASIN. Normalize titles in batches of about 50 per Claude request, using a
  schema that also returns `isHouseholdConsumable`, so one-off purchases like electronics and
  books are skipped. A backfill isn't urgent, so the Message Batches API (half price) is a good
  fit once a backend proxy exists.
- An ASIN becomes an `emailText` alias (`asin:B0…`), so later emails match the same product
  deterministically.
- Import creates `PurchaseEvent`s only, not stock. The user confirms what is currently in the
  house separately.

Effort: about 1 day.

## Stage C: Gmail API (only with a backend, or for personal use)

**What it takes**
- **OAuth 2.0 with PKCE**, via Google's iOS client (GoogleSignIn or AppAuth over
  `ASWebAuthenticationSession`), an iOS OAuth client ID, and a custom URL-scheme redirect.
  Refresh tokens go in the Keychain.
- **Scope: `gmail.readonly`.** No narrower scope works. `gmail.metadata` excludes bodies, and
  Gmail has no per-sender scopes.
- **Fetching:**
  - `users.messages.list` with a query like
    `from:(auto-confirm@amazon.com OR shipment-tracking@amazon.com) newer_than:1y`
  - then `users.messages.get?format=full`
  - Decode the base64url MIME parts (prefer `text/html`) and feed them into the Stage A pipeline.
- **Incremental sync:**
  - Store the last `historyId` and call `users.history.list?startHistoryId=…`.
  - If the id has expired (404), fall back to the dated query.
  - Poll from the existing `BGAppRefreshTask`. Real-time push (`users.watch` → Pub/Sub) needs a
    server.
- **Never auto-add.** New orders land in the same "Pending imports" review queue.

**The catch: `gmail.readonly` is a Google *restricted* scope**
- **Testing mode** (unverified app): up to 100 named test users, and refresh tokens expire
  **every 7 days**, so users re-consent weekly. That's fine for the developer's own household.
- **Production** requires Google's OAuth verification plus an **annual third-party security
  assessment (CASA)**. That process costs time and money every year.
- A server that fetches mail is subject to the same restricted-scope rules.

**Lighter alternative once a backend exists: a forwarding address**
1. The user creates a Gmail filter that auto-forwards Amazon order emails to a per-household
   address (for example `orders+<token>@inbound.larder.app`).
2. An inbound-parse webhook (Postmark, SendGrid or SES) posts each email to the backend.
3. The backend runs the same extraction and syncs pending imports to the device through CloudKit
   or push.

This needs no Google scopes at all, and it works with any email provider and any merchant
(Walmart, Target, Instacart, Costco).

Effort: about a week of engineering for Gmail API plus verification lead time. The forwarding
route is about 2–3 days once the backend proxy exists.

## Recommendation

1. Build **Stage A** next. It covers the common case, reuses nearly all of Phase 2, and needs no
   accounts or servers.
2. Offer **Stage B** as an optional one-time backfill.
3. Treat **Stage C** as part of the future backend. Use forwarding rather than the Gmail API
   unless this stays a personal-use app, in which case testing-mode Gmail is acceptable.

## Test plan

Core fixtures (sanitized real emails) for:
- HTML → text, with row preservation
- redaction: addresses, names, card digits
- order-number and date extraction on canned model output
- CSV parsing: column reordering, quoted commas, missing columns
- deduplication: the same order twice, split shipments, a delivery update after the confirmation
