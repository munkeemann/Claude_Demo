# Larder

An iPhone app that tracks household inventory (food and household goods), predicts when items
will expire or run out, and suggests recipes from what you have.

- Swift + SwiftUI, iOS 17+, SwiftData, local-first
- Claude (Anthropic Messages API) for receipt parsing and recipe suggestions, using your own API key
- VisionKit / Vision for barcode, document and text scanning; OpenFoodFacts for barcode lookup

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the design.

## Requirements

- Xcode 16 or later (Swift 6 toolchain)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Getting started

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

## Tests

All forecasting, parsing, and client logic lives in the `InventoryCore` Swift package, which has
no Apple-only dependencies:

```sh
swift test --package-path Packages/InventoryCore
```

It also runs on Linux (for example `docker run --rm -v "$PWD/Packages/InventoryCore":/pkg -w /pkg swift:6.1-noble swift test`).

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
