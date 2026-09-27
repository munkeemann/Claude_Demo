# Larder

An iPhone app that tracks household inventory (food and household goods), predicts when items
will expire or run out, and suggests recipes from what you have.

- Swift + SwiftUI, iOS 17+, SwiftData, local-first
- Household sharing through iCloud (CloudKit + `CKSyncEngine`)
- Claude (Anthropic Messages API) for receipt parsing, shelf photos and recipe suggestions, using
  your own API key
- VisionKit / Vision for barcode, document and text scanning; OpenFoodFacts for barcode lookup

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the design and
[docs/ONLINE_ORDERS.md](docs/ONLINE_ORDERS.md) for the Amazon / online-order plan.

## Features

| Tab | What it does |
|---|---|
| Inventory | Items grouped by storage location, with search and filters, and an estimate of what's left for items nobody logs. Swipe for used some / used up / tossed; freeze from the menu. **+** starts your usual way of adding (Quick Add, shelf photos, barcodes, a receipt, or one item by hand); hold it for the others. **−** scans things out: photos of what you're throwing away or finished, or of a recipe you cooked. |
| Soon | Items expiring soon, items that are probably finished (confirm in one tap), products predicted to run low (with confidence), regulars you're probably out of, and a monthly food-waste summary. |
| Recipes | Claude suggestions built around what's in stock, expiring items first. Filter by meal, time and missing ingredients. Add missing items to the list in one tap. "I cooked this" logs usage, and so does photographing a recipe you made. Favorites. |
| Shopping | Suggested items from run-out predictions, plus your own entries. |
| Settings | Household sharing, Claude API key and model, your default add method and how new items get dates, the household's date strictness, reminders (including "toss it" reminders) and look-ahead, storage locations, sample data, patch notes. |

### Adding and removing in batches

- **Quick Add**: type or dictate a list ("milk, a dozen eggs, 2 lb chicken thighs, paper towels").
  Claude reads it when there's a key; otherwise it's parsed on the phone. Each item goes where it's
  usually kept.
- **Scan Barcodes** keeps the camera running: scan package after package (scanning one again adds
  another), then review them all at once. Unknown barcodes can be identified from a photo of the
  package.
- **Scan a Shelf** takes several photos in one scan.
- **Scanning out**: photograph what's being thrown away (several photos for a fridge clean-out) or
  finished. Claude matches each thing to the inventory; you confirm, per item, whether it was tossed
  or used up, and whether all of it went. Tossed food is waste, not use, so it doesn't speed up
  run-out estimates. Photographing a recipe you cooked (the recipe, not the food) takes its
  ingredients off the inventory.
- **Brands** are kept wherever they show up: receipts (store brands too), barcodes, labels in shelf
  photos, and lists ("Tillamook cheddar"; Quick Add also recognizes brands the household already
  buys). Turn on **Stick to this brand** for a product and the shopping list says which brand to
  buy; leave it off where any brand will do.
- Every review screen has a circle per item: tap it to skip the item, tap the item to edit it.
  After saving, **Undo** is on screen for a few seconds.

### How expiry dates are worked out

Storage times come from USDA FSIS **FoodKeeper** (public domain), bundled with the app:
about 660 foods with separate pantry, fridge and freezer times, and times after opening and after
thawing, mostly as ranges ("3–5 days"). Each product is matched to a FoodKeeper entry by name
(it can be changed on the item screen); without a match, Claude's estimate or a per-category table
is used.

- **Household strictness** (Settings → Expiration dates, shared by everyone in the home) picks the
  point in USDA's range, from the short end (Very cautious) to the long end (Very relaxed). Relaxed
  settings also give shelf-stable categories time past their printed best-by date (up to a year for
  canned goods). Meat, poultry, seafood, deli, dairy, cheese, leftovers and baby food never go past
  USDA's longest time or their printed date.
- **Package dates** win over estimates. They can be typed or read with the camera; the text is
  recognized on the phone.
- **Opened** items get the after-opening time when that comes sooner. Using part of a single
  container marks it opened, and moving sealed food from the pantry to the fridge asks.
- **Freezing** restarts the clock on USDA's freezer time; taking something out starts the
  after-thawing time. Moving between the pantry and fridge carries over the share of shelf life
  already used.
- How new items get dates is personal (Settings → Adding items): estimate them, scan package dates
  (after adding, Larder walks through the items that usually have one), or leave them blank.

`Larder/scripts/foodkeeper.py` regenerates the bundled data from the copy that the **FoodKeeper
data** workflow downloads.

### Siri and Shortcuts

"Add to Larder" (then say the list), "Used something up in Larder", "Toss something in Larder" and
"What's expiring in Larder" work from Siri, Shortcuts and the Action button.

### How usage is estimated

Nobody logs every glass of milk, so Larder learns mostly from what you buy: in the long run, what
a household buys is what it uses. Each product's pace comes from the gaps between purchases (total
bought over total time, weighted toward recent trips, outliers dropped), sharpened by any "used up"
taps. Logged use from recipes and "used some" only raises the estimate, since it's always
incomplete. Stock is then projected forward oldest-first, so three unlogged gallons bought a week
apart count as one gallon, partly used. When a projection says something is gone, it shows up as
"Finished?"; a tap confirms it, and a quick count ("How much is left?", or a shelf scan) resets
the estimate. "Running low" reminders fire a few days before the projected run-out.

### Reminders

Turn reminders on in **Settings**. Besides heads-up reminders before items expire or run out
(with **Freeze It** and **Find a Recipe** buttons),
**toss reminders** arrive the evening after something passes its date (6 PM by default), with a
**Tossed them** button that clears the items without opening the app. The app icon badge counts
items past their date.

### Scan a shelf

**Inventory → + → Scan a Shelf**: photograph a shelf, the fridge or a cupboard. Claude goes over
the photo shelf by shelf, lists everything it sees with counts (or how full an opened container
is), guessing at unlabeled jars and tubs rather than skipping them, matches things already tracked
at that location, and shows a review: new items to add, new counts for tracked ones, and tracked
items that weren't in the photo (mark them finished if they're gone). If the photo looks like a
different kind of storage from the location you picked (a fridge door filed under Pantry), the
review offers to scan again for the right one. By default a scan is a stock-take;
switch on **I just bought these** after a shopping trip without a receipt so the purchases count
toward usage estimates.

## Household sharing

Everyone in a home shares one inventory, shopping list and history, synced through iCloud. The
owner's data lives in a record zone in their private CloudKit database, shared with a zone-wide
`CKShare`; others join from an invitation link.

**Settings → Household → Share Inventory…** creates the home and opens Apple's sharing sheet
(Messages, Mail or a link). The other person taps the link on their iPhone, with Larder
installed, and chooses whether to start from the shared inventory or add their own items to it.
Reminders and the Claude API key stay per phone.

One-time setup in Apple's developer tools (the app shows "iCloud sharing isn't set up" until it's
done):
1. **Certificates, Identifiers & Profiles → Identifiers → +** → **iCloud Containers** → identifier
   `iCloud.com.munkeemann.larder`.
2. Edit the App ID `com.munkeemann.larder`: enable **iCloud** (check **CloudKit**, then
   **Configure** and select the container) and **Push Notifications**. Save.
3. In [CloudKit Console](https://icloud.developer.apple.com) → the container → **Development** →
   **Schema → Record Types → +**: create `LarderRecord` with two fields, `kind` (String) and
   `payload` (String). Then **Deploy Schema Changes…** to Production. TestFlight builds use the
   Production environment, so this step is required.

The upload job checks that the signed app carries its iCloud and push entitlements before
anything reaches TestFlight.

## Requirements

- Xcode 16 or later (Swift 6 toolchain) to build and run; App Store Connect uploads need Xcode 26,
  which the TestFlight workflow uses
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Run it in the Simulator (one command)

On a Mac with Xcode 16 or newer, including a rented one like MacinCloud, open Terminal and run:

```sh
git clone -b claude/household-inventory-app-s6xsut https://github.com/munkeemann/Claude_Demo.git && Claude_Demo/Larder/scripts/run-simulator.sh
```

The script:
- generates the Xcode project, fetching XcodeGen if needed (no admin rights required)
- builds the app, then boots an iPhone simulator and launches Larder
- opens the project in Xcode

After pulling new changes, run `Larder/scripts/run-simulator.sh` again from the `Claude_Demo` folder.

## Install on your iPhone (TestFlight)

Builds reach TestFlight automatically. Every push to `main` or a `claude/**` branch that changes
the app runs the **Larder iOS** workflow (`.github/workflows/larder-ios.yml`) on GitHub's macOS
runners. When the tests pass, its **Upload to TestFlight** job archives a release build and signs
and uploads it. No Mac is needed at any point.

Apple's cloud-managed signing can't provision an app that uses iCloud when it's driven by an API
key, so each build signs with its own temporary Apple Distribution certificate and App Store
profile, created through the App Store Connect API (`scripts/asc_signing.py`). After Apple finishes
processing the build, the job revokes the certificate and deletes the profile, so nothing
accumulates in the developer account. Apple may email the account holder about these
certificates.

One-time setup:
1. In App Store Connect → Apps → **+ New App**, create "Larder" with bundle ID
   `com.munkeemann.larder`.
2. Add three repository secrets under GitHub → Settings → Secrets and variables → Actions:
   - `ASC_KEY_ID`: the key ID
   - `ASC_ISSUER_ID`: the issuer ID
   - `ASC_KEY_P8`: the full contents of the `.p8` file

   All three come from the App Store Connect API key (Users and Access → Integrations). Creating
   certificates needs a key with the Admin role.
3. In App Store Connect → TestFlight, create an **Internal Testing** group with automatic
   distribution on, and add the testers. In the TestFlight app on each phone, turn on
   **Automatic Updates** for Larder.

After a push, a build shows up in TestFlight about 30–45 minutes later (tests, upload, then Apple's
processing; the job waits for processing before revoking its certificate). Docs-only changes don't upload a build. To upload one without a code change, bump the
number in `Larder/Config/testflight-build.txt` and push, or run the **Larder iOS** workflow by hand
(Actions → Run workflow). A manual run with **Upload to TestFlight** unticked only builds and
tests. The build number is the workflow run number, so it always increases.

```sh
cd Larder
xcodegen generate        # creates Larder.xcodeproj from project.yml
open Larder.xcodeproj
```

The Xcode project is generated and git-ignored. After pulling changes that add or remove files,
run `xcodegen generate` again. Change project settings in `project.yml`, not in Xcode.

To run on a device, set your team in `project.yml` (`DEVELOPMENT_TEAM`) or in Xcode's Signing
settings. The camera features (barcode scanner, document camera, shelf photos) only work on a real
device; the Simulator offers manual barcode entry, receipt paste/import and photo-library picks
instead.

## Claude features

Receipt scanning, shelf scanning and recipe suggestions call the Anthropic Messages API with your own key. In the app, open **Settings → Claude**, paste a key from
[console.anthropic.com](https://console.anthropic.com), and tap **Test Connection**. The key is
stored in the iOS Keychain (this device only). The model picker defaults to Claude Opus 5.

Without a key you can still try **Scan Receipt → Try the Sample Receipt**, **Scan a Shelf → Try a
Sample Shelf** and **Recipes → Suggest Recipes**. Both show pre-computed results for the bundled sample data (load it from
**Settings → Load Sample Data**).

## Tests

All forecasting, parsing, and client logic lives in the `InventoryCore` Swift package, which has
no Apple-only dependencies:

```sh
swift test --package-path Packages/InventoryCore
```

It also runs on Linux. `scripts/check-linux.sh` runs the package tests plus a syntax check of the
app sources inside the `swift:6.1-noble` Docker image.

App-level tests (SwiftData mappers and repositories) run in Xcode with ⌘U or:

```sh
xcodebuild test -project Larder.xcodeproj -scheme Larder \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

CI (`.github/workflows/larder-ios.yml`) runs the package tests on Linux and macOS and builds and
tests the app on an iOS Simulator for every push that touches `Larder/`. On `main` and `claude/**`
branches, a green run then uploads the build to TestFlight.

## Layout

```
Larder/
  project.yml                 XcodeGen spec
  Config/Info.plist           extra Info.plist keys (the rest are generated)
  Packages/InventoryCore/     pure-Swift logic + tests
  Larder/                     app target (SwiftUI, SwiftData, platform adapters)
  LarderTests/                app-level tests
  docs/                       architecture and design notes
```
