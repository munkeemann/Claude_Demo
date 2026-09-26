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
| Inventory | Items grouped by storage location, with search and filters, and an estimate of what's left for items nobody logs. Swipe for used some / used up / tossed. Add items by hand, by barcode (Open Food Facts), from a receipt, or by photographing a whole shelf (Claude). |
| Soon | Items expiring soon, items that are probably finished (confirm in one tap), products predicted to run low (with confidence), and regulars you're probably out of. |
| Recipes | Claude suggestions built around what's in stock, expiring items first. Filter by meal, time and missing ingredients. Add missing items to the list in one tap. "I cooked this" logs usage. Favorites. |
| Shopping | Suggested items from run-out predictions, plus your own entries. |
| Settings | Household sharing, Claude API key and model, reminders (including "toss it" reminders) and look-ahead, storage locations, sample data. |

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

Turn reminders on in **Settings**. Besides heads-up reminders before items expire or run out,
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
number in `Larder/Config/testflight-build.txt` and push. The build number is the workflow run
number, so it always increases.

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
