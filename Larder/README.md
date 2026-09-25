# Larder

An iPhone app that tracks household inventory (food and household goods), predicts when items
will expire or run out, and suggests recipes from what you have.

- Swift + SwiftUI, iOS 17+, SwiftData, local-first
- Claude (Anthropic Messages API) for receipt parsing and recipe suggestions, using your own API key
- VisionKit / Vision for barcode, document and text scanning; OpenFoodFacts for barcode lookup

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the design and
[docs/ONLINE_ORDERS.md](docs/ONLINE_ORDERS.md) for the Amazon / online-order plan.

## Features

| Tab | What it does |
|---|---|
| Inventory | Items grouped by storage location, with search and filters. Swipe for used some / used up / tossed. Add items by hand, by barcode (Open Food Facts), or from a receipt (Claude). |
| Soon | Items expiring soon, products predicted to run low (with confidence), and regulars you're probably out of. |
| Recipes | Claude suggestions built around what's in stock, expiring items first. Filter by meal, time and missing ingredients. Add missing items to the list in one tap. "I cooked this" logs usage. Favorites. |
| Shopping | Suggested items from run-out predictions, plus your own entries. |
| Settings | Claude API key and model, reminders and look-ahead, storage locations, sample data. |

## Requirements

- Xcode 16 or later (Swift 6 toolchain)
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

The **Larder TestFlight** workflow (`.github/workflows/larder-testflight.yml`) builds a release,
signs it with Apple's cloud-managed certificate and uploads it to TestFlight, so no Mac is needed.

One-time setup:
1. In App Store Connect → Apps → **+ New App**, create "Larder" with bundle ID
   `com.munkeemann.larder`.
2. Add three repository secrets under GitHub → Settings → Secrets and variables → Actions:
   - `ASC_KEY_ID`: the key ID
   - `ASC_ISSUER_ID`: the issuer ID
   - `ASC_KEY_P8`: the full contents of the `.p8` file

   All three come from the App Store Connect API key (Users and Access → Integrations). Cloud
   signing needs a key with the Admin role.

Each build: push a tag named `larder-testflight-<anything>`, for example
`git tag larder-testflight-1 && git push origin larder-testflight-1`. Once the workflow is on the
default branch, you can also use **Run workflow** instead. After Apple finishes processing, install
the build from the TestFlight app. The build number is the workflow run number, so it always
increases.


```sh
cd Larder
xcodegen generate        # creates Larder.xcodeproj from project.yml
open Larder.xcodeproj
```

The Xcode project is generated and git-ignored. After pulling changes that add or remove files,
run `xcodegen generate` again. Change project settings in `project.yml`, not in Xcode.

To run on a device, set your team in `project.yml` (`DEVELOPMENT_TEAM`) or in Xcode's Signing
settings. The camera features (barcode scanner, document camera) only work on a real device; the
Simulator offers manual barcode entry and receipt paste/import instead.

## Claude features

Receipt scanning and recipe suggestions call the Anthropic Messages API with your own key. In the app, open **Settings → Claude**, paste a key from
[console.anthropic.com](https://console.anthropic.com), and tap **Test Connection**. The key is
stored in the iOS Keychain (this device only). The model picker defaults to Claude Opus 5.

Without a key you can still try **Scan Receipt → Try the Sample Receipt** and **Recipes → Suggest
Recipes**. Both show pre-computed results for the bundled sample data (load it from
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
tests the app on an iOS Simulator for every push that touches `Larder/`.

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
