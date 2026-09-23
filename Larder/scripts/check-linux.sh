#!/usr/bin/env bash
# Runs what can be checked without Xcode, inside the official Swift image:
#   1. InventoryCore unit tests
#   2. a syntax-only parse of every app and app-test source file
# Usage: scripts/check-linux.sh   (from the Larder directory; needs Docker)
set -euo pipefail
IMAGE="${SWIFT_IMAGE:-swift:6.1-noble}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
docker run --rm -v "$ROOT":/work -w /work "$IMAGE" bash -c '
  set -euo pipefail
  status=0
  for f in $(find Larder LarderTests -name "*.swift"); do
    if ! out=$(swiftc -parse "$f" 2>&1); then echo "$out"; status=1; fi
  done
  echo "App sources parsed (status $status)"
  swift test --package-path Packages/InventoryCore 2>&1 | grep -E "error:|warning:|✘|recorded an issue|Test run" || true
  exit $status
'
