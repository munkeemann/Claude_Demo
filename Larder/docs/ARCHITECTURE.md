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
| `ShoppingListItem` | Shopping list entries, with a reason: predicted run-out, recipe, or manual (Phase 3). |
| `SavedRecipe` | Favorite and cooked recipes (Phase 4). |

Household sharing: SwiftData's built-in CloudKit sync covers the private database only. Sharing
across Apple IDs needs `CKShare`. The plan is to add a `CKSyncEngine` layer later. Stable UUIDs,
timestamps and the append-only event logs are what make that practical.

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
5. Online orders: design only (see `ONLINE_ORDERS.md`).
