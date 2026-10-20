#!/bin/zsh
# Runs the unit tests. They compile the app's sources into the test bundle, so the notch app
# itself never launches.
set -euo pipefail
cd "${0:A:h}/.."
xcodegen generate --quiet
xcodebuild build-for-testing -project Nook.xcodeproj -scheme Nook -derivedDataPath build -quiet 2>&1 | grep -E "error:" || true
xcrun xctest build/Build/Products/Debug/NookTests.xctest 2>&1 | grep -E "✘|recorded an issue|Test run with"
