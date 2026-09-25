#!/usr/bin/env bash
# Builds Larder and launches it in the iOS Simulator. Run it from anywhere
# inside the repo on a Mac with Xcode 16 or newer:
#
#   Larder/scripts/run-simulator.sh
#
# What it does:
#   1. checks the Xcode version
#   2. finds XcodeGen (PATH, Homebrew, or a standalone download that needs
#      no admin rights) and generates Larder.xcodeproj
#   3. picks the newest available iPhone simulator
#   4. builds the app, boots the simulator, installs and launches Larder
#   5. opens the project in Xcode so ⌘R works from then on
#
# Options:
#   --no-gui   skip opening Simulator.app and Xcode (used by CI)
set -euo pipefail

OPEN_GUI=1
for arg in "$@"; do
  case "$arg" in
    --no-gui) OPEN_GUI=0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

LARDER_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$LARDER_DIR"
BUNDLE_ID="com.example.larder"

step() { printf '\n==> %s\n' "$1"; }

step "Checking Xcode"
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found. Install Xcode from the App Store first." >&2
  exit 1
fi
XCODE_VERSION="$(xcodebuild -version | head -1 | awk '{print $2}')"
echo "Xcode $XCODE_VERSION"
if [ "${XCODE_VERSION%%.*}" -lt 16 ]; then
  echo "Larder needs Xcode 16 or newer." >&2
  exit 1
fi

step "Generating the Xcode project"
XCODEGEN=""
if command -v xcodegen >/dev/null 2>&1; then
  XCODEGEN="$(command -v xcodegen)"
elif command -v brew >/dev/null 2>&1 && brew install xcodegen >/dev/null 2>&1; then
  XCODEGEN="$(command -v xcodegen)"
else
  # Standalone release: no Homebrew or admin rights needed.
  if [ ! -x .tools/xcodegen/bin/xcodegen ]; then
    echo "Downloading XcodeGen…"
    mkdir -p .tools
    curl -fsSL -o .tools/xcodegen.zip https://github.com/yonaskolb/XcodeGen/releases/latest/download/xcodegen.zip
    unzip -q -o .tools/xcodegen.zip -d .tools
  fi
  XCODEGEN="$LARDER_DIR/.tools/xcodegen/bin/xcodegen"
fi
echo "Using $XCODEGEN"
"$XCODEGEN" generate --quiet

step "Choosing a simulator"
SIMULATOR="$(xcrun simctl list devices available --json | /usr/bin/python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
best = None
for runtime, entries in devices.items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for device in entries:
        if device["name"].startswith("iPhone") and (best is None or version > best[0]):
            best = (version, device["udid"], device["name"])
if best:
    print(best[1] + "|" + best[2] + " (iOS %d.%d)" % best[0])
')"
if [ -z "$SIMULATOR" ]; then
  echo "No iPhone simulator found. Add one in Xcode → Settings → Components." >&2
  exit 1
fi
UDID="${SIMULATOR%%|*}"
echo "${SIMULATOR#*|}"

step "Building (the first build takes a few minutes)"
mkdir -p build
if ! xcodebuild build \
    -project Larder.xcodeproj \
    -scheme Larder \
    -destination "id=$UDID" \
    -derivedDataPath build \
    CODE_SIGNING_ALLOWED=NO \
    > build/xcodebuild.log 2>&1; then
  grep -E "error:|\*\* BUILD FAILED" build/xcodebuild.log | head -40 >&2 || true
  echo "Build failed. Full log: $LARDER_DIR/build/xcodebuild.log" >&2
  exit 1
fi
APP="build/Build/Products/Debug-iphonesimulator/Larder.app"
echo "Built $APP"

step "Launching in the Simulator"
xcrun simctl boot "$UDID" 2>/dev/null || true   # already booted is fine
if [ "$OPEN_GUI" = 1 ]; then
  open -a Simulator
fi
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" "$BUNDLE_ID"

if [ "$OPEN_GUI" = 1 ]; then
  open Larder.xcodeproj
fi

cat <<'EOF'

Larder is running in the Simulator.
Tip: in the app, open Settings → Load Sample Data to fill it with example items.
From now on you can also press ⌘R in Xcode (Larder.xcodeproj is open).
EOF
