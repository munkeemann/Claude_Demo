# Larder architecture

## Goals and constraints

- Swift + SwiftUI, iOS 17+, SwiftData. Local-first with no custom backend.
- The data layer must allow CloudKit sync (and later household sharing) without a rewrite.
- LLM features call the Anthropic Messages API directly with a user-supplied key stored in the
  Keychain. Every call goes through a protocol so a backend proxy can replace it.
- Views stay thin. Forecasting and parsing logic lives in testable services with unit tests.

## Layers

```
┌──────────────────────────── Larder (app target) ────────────────────────────┐
│ Features/*       SwiftUI views + @Observable view models                    │
│ Persistence/     SwiftData @Model classes, mappers → Core snapshots,         │
│                  repositories                                               │
│ Platform/        Keychain, Vision OCR, VisionKit scanners, notifications,    │
│                  background refresh                                         │
│ App/             App entry, AppEnvironment (dependency container), tabs      │
└───────────────────────────────┬─────────────────────────────────────────────┘
                                │ plain Sendable value types
┌───────────────────────────────▼──── InventoryCore (Swift package) ──────────┐
│ Domain/          categories, climates, units + conversion, snapshots         │
│ Inventory/       filtering, quick-action math                               │
│ Forecasting/     shelf-life table, expiry + run-out forecasts, shopping list │
│ Receipts/        OCR line assembly, extraction schema, alias resolution      │
│ Recipes/         request building, ingredient matching                       │
│ LLM/             LLMService protocol, Anthropic client, mock                 │
│ ProductLookup/   OpenFoodFacts client + mapping                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

`InventoryCore` imports only Foundation. It has no SwiftUI, SwiftData, UIKit or Vision, so
`swift test` runs on macOS and Linux. The engines never see `@Model` objects. The app maps
persisted models into Core value types (`ProductSnapshot`, `PurchaseRecord`, ...) and maps results
back.

The app target builds in Swift 5 language mode with minimal concurrency checking. The package
builds in Swift 6 mode.

## Dependency seams

| Protocol | Live implementation | Test / preview | Future |
|---|---|---|---|
| `LLMService` | `AnthropicLLMService` (URLSession → Messages API) | `MockLLMService` | `ProxyLLMService` |
| `ProductLookupService` | OpenFoodFacts → Open Beauty Facts → Open Products Facts | fixture-backed stub | — |
| `SecretStore` | Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) | in-memory | — |
| `TextRecognizer` | Vision `VNRecognizeTextRequest` | canned text | — |
| `NotificationScheduler` | `UNUserNotificationCenter` | recorder | — |
| `now: () -> Date` | system clock | fixed dates | — |

An `AppEnvironment` object owns the live implementations. Views receive it through the SwiftUI
environment.

## Claude integration

- There is no official Anthropic Swift SDK, so the app uses a small URLSession client for
  `POST /v1/messages` with `anthropic-version: 2023-06-01`.
- Every call uses structured outputs (`output_config.format` with a JSON schema), so decoding is
  typed. Schemas follow the structured-output limits: `additionalProperties: false`, and no
  numeric or length constraints.
- The default model is `claude-opus-5`, selectable in Settings. Server-side refusal fallback is
  enabled. The client handles the `refusal` and `max_tokens` stop reasons explicitly.
- The API key is read from the Keychain for each request and is never logged or written to
  UserDefaults.

## Receipt pipeline (Phase 2)

1. **Capture.** `VNDocumentCameraViewController` (device), `PhotosPicker`, pasted text, or the
   bundled sample receipt.
2. **OCR.** `VNRecognizeTextRequest` at `.accurate` with language correction off, because
   correction mangles abbreviations. `OCRLineAssembler` regroups fragments into rows by vertical
   overlap, since Vision splits the description and price columns.
3. **Hints.** `ReceiptPrompt.relevantHints` picks the remembered `ProductAlias` (receiptText)
   mappings whose key appears on this receipt, and lists them in the prompt.
4. **Extraction.** `AnthropicLLMService.extractReceipt` sends a stable system prompt and a
   per-receipt user message, with a JSON schema (`ReceiptExtractionSchema`) for structured output.
   Line items include rawText, name, brand, category, quantity, unit, package size, price,
   location, shelf life and confidence.
5. **Review.** `ReceiptReview` applies remembered mappings deterministically: a matching alias
   always wins over Claude. It also checks that the line prices add up to the subtotal. The user
   can edit, skip or re-locate each line.
6. **Import.** `InventoryStore.importReceipt` creates or reuses products, items and purchase
   events linked to a `Receipt`. It upserts one receiptText alias per line, keyed by
   `ReceiptText.key` (item codes, prices and tax flags stripped), so any corrections carry over to
   the next scan. Claude's shelf-life estimate becomes the item's estimated expiry and fills the
   product's shelf-life override for that climate if it was empty.

## Forecasting (Phase 3)

**Expiry.** An item's expiry comes from the first available source:
1. a date the user set (`expiryIsOverride`, never re-estimated)
2. the product's own shelf life for the item's climate (set by the user, or learned from Claude's
   receipt suggestion)
3. `ShelfLifeTable` by category and climate

Moving an item to a location with a different climate re-estimates it.

**Run-out.** `RunOutForecaster` turns a product's history into a daily consumption rate. Nobody
logs every use, so purchases carry most of the signal. Rate observations (an amount over a number
of days) come from:
- "used up" events: purchase-to-finish time, at triple weight
- repeat-purchase intervals: quantity bought over the days until the next purchase

The rate calculation:
- Recent observations weigh more (×0.75 per step back).
- Observations whose rate is outside ⅓–3× the median are dropped.
- The rate is total weighted amount over total weighted days, so irregular gaps don't inflate it
  the way averaging per-gap rates would. The spread of the individual rates sets the confidence:
  high for 4+ observations with CV ≤ 0.35, medium for 2+ with CV ≤ 0.6, low otherwise.
- Logged partial use (recipes, "used some") is incomplete by nature, so it only sets a floor on the
  rate, or stands alone when there's nothing else.
- With no observations, the category's typical days-per-purchase is used at low confidence.

Stock is projected item by item, oldest first: each item starts being used at the later of when it
was last observed (`quantityObservedAt`, a count, or its purchase) and when the previous item runs
out. The per-item result (`ItemEstimate`) drives "~½ gal left" in the list, "Finished?" for items
projected at zero, and the product's run-out date with an earliest/latest range. Confirming
"finished" logs no usage (the item ran out earlier, and purchases already carry the rate); a count
pins the projection.

**Shopping list.** `ShoppingListGenerator` suggests products predicted to run out within the
look-ahead window (at medium confidence or better, or already marked low), plus regular purchases
that are probably out. It suggests the usual purchase amount.

**Notifications.** iOS keeps only 64 pending local notifications. `NotificationPlanner` therefore
merges reminders that fall on the same day into one notification, schedules at most 60, and skips
heads-up reminders whose time has passed (the Soon tab covers those). Toss reminders fire at the
toss hour (6 PM by default) the day after an item's date; items that expired within the last week
and are still in stock get the next toss time. Their "Tossed them" action is handled by the app
delegate, which can run before any UI. The plan is recomputed:
- when the app becomes active or goes to the background
- in a `BGAppRefreshTask` (`com.munkeemann.larder.refresh`)
- whenever reminder settings change

## Recipes (Phase 4)

1. **Request.** `InventoryStore.recipeRequest` collects in-stock items whose product is an
   ingredient. It sorts them soonest-expiring first, gives each a short prompt id (`i1`, `i2`, …)
   and caps the list at 80.
2. **Prompt.** `RecipePrompt` has a stable system prompt and a user message listing
   `id | item | amount | expires`, followed by the filters: meal type, max time, allowed missing
   ingredients, whether staples are assumed, and free-text preferences. The response is structured
   output against `RecipePrompt.schema` (title, summary, meal type, minutes, servings, ingredients
   with `inventoryItemId`/`have`/`isStaple`, steps).
3. **Local verification.** `IngredientMatcher` decides availability itself. An ingredient is in
   the inventory if Claude referenced a valid id, or if its name matches an item word-for-word
   (plurals folded, descriptors like "fresh" ignored, "garlic cloves" matches "Garlic",
   "spaghetti squash" does not match "Spaghetti"). Staples count only when assumed. A `have: true`
   with no match is treated as missing.
4. **Ranking.** `RecipeRanking` re-applies the missing-ingredient and time filters. Recipes that
   use expiring items come first, then those with fewer missing ingredients, then the faster ones.
5. **Actions.** One tap adds missing ingredients to the shopping list (reason `recipe`, with the
   recipe title as a note). "I cooked this" suggests how much of each item was used, via
   `CookedUsagePlanner` (converts "2 cups" to gallons, "6" eggs to 0.5 dozen, and so on). After
   the user confirms, it logs `usedSome` usage events that feed the forecasts. Favorites and
   cooked history are stored as `SavedRecipe`, as JSON with the prompt ids stripped so they are
   re-matched against current stock.

## Data model (SwiftData, CloudKit-ready)

CloudKit compatibility rules, applied from day one:
- no `@Attribute(.unique)`; deduplication happens in code
- every property is optional or has a default
- every relationship is optional and has an inverse
- no `.deny` delete rules
- enums are stored as raw strings
- every record has a stable `id: UUID` and `createdAt`/`updatedAt`

| Entity | Purpose |
|---|---|
| `Product` | Canonical product: name, brand, category, default unit, shelf-life overrides per climate, and the flags `isIngredient` / `tracksRunOut` / `tracksExpiry`, which default from the category. |
| `ProductAlias` | Maps external text to a product: barcodes, raw receipt lines, email titles. This is how receipt corrections are remembered. |
| `StorageLocation` | Built-in (pantry, fridge, freezer, bathroom, cleaning) and custom locations. Each has a climate. |
| `InventoryItem` | A stocked instance of a product: quantity, initial quantity, unit, location, purchase date, expiry, and status. |
| `PurchaseEvent` | An append-only purchase log: quantity, price in cents, currency, source, store, and receipt / external order ID. |
| `UsageEvent` | An append-only usage log: used up / partially used / discarded. Every quick action writes one. |
| `Receipt` | Raw OCR text and metadata for a scanned receipt (Phase 2). |
| `ShoppingListItem` | Shopping list entries, with a reason: predicted run-out, recipe, or manual. Optionally linked to a product. |
| `SavedRecipe` | Favorite and cooked recipes, stored as JSON, with times cooked and last cooked date. |

`SyncRecordState` is local bookkeeping for household sharing and is never shared itself.

## Household sharing (CKSyncEngine)

SwiftData's built-in CloudKit mirroring can't share across Apple IDs, so sharing is a separate
layer (`Larder/Sync`) on top of an unchanged local store.

- **Where the data lives.** The owner's inventory is a record zone (`LarderHome`) in their private
  database, shared in full with a zone-wide `CKShare`. Participants read and write it through their
  shared database. One `CKSyncEngine` per phone (private for the owner, shared for participants)
  handles fetching, sending, retries, pushes and account changes.
- **One record type.** Every shared object travels as a `LarderRecord` whose `payload` is a
  `SyncEnvelope` (in `InventoryCore`): the object's fields as JSON, its references as
  `(kind, UUID)` pairs, and a format version. The CloudKit schema never changes when a field is
  added, and a phone running an older version carries unknown fields forward instead of erasing
  them.
- **Finding local changes by diffing.** Every few seconds while the app is open, and when it goes
  to the background, `HomeSync` encodes every shared object canonically (sorted keys, dates as
  reference-date seconds) and compares it with the payload iCloud last confirmed
  (`SyncRecordState`). Differences become pending saves or deletes. This catches every write path,
  including SwiftData cascades, with no hooks in the rest of the app.
- **Applying remote changes.** Incoming records are applied in dependency order (locations and
  products before items and events). A reference whose target hasn't arrived yet is kept in the
  agreed payload and re-resolved after the fetch, so a half-synced phone never uploads it as
  cleared.
- **Conflicts.** Record-level last-writer-wins: a local edit that hasn't reached iCloud yet wins
  if it's newer than the server's copy; otherwise the server's copy is applied.
- **Joining.** A new participant fetches the home before uploading anything. Built-in locations,
  and products with the same name and brand that were never shared before, merge into the
  incoming records by adopting their IDs, so joining doesn't duplicate "Fridge" or "Whole Milk".
- **Leaving.** Leaving (participant) or stopping sharing (owner) stops sync; everyone keeps a
  copy of the inventory as it was.

## Phases

0. Scaffold: XcodeGen project, tab shell, Core package, CI.
1. Inventory foundation: models, CRUD by location, quick actions, search/filter, barcode scanning
   with OpenFoodFacts, sample data.
2. Receipt scanning: document camera + Vision OCR, Claude extraction, review screen, learned
   corrections.
3. Forecasting: expiry and run-out forecasts with confidence, "running low" / "expiring soon"
   views, notifications, auto shopping list.
4. Recipes: Claude suggestions prioritizing expiring items, filters, missing-to-shopping-list,
   cooked → usage events, favorites.
5. Online orders: design only (see [ONLINE_ORDERS.md](ONLINE_ORDERS.md)).
6. Household release: household sharing, shelf scanning with Claude vision, usage estimates from
   purchase history with oldest-first stock projection, toss reminders, and a theme drawn from the
   app icon.
