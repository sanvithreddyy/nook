#!/bin/zsh
# Regenerates the Xcode project and builds Nook (Debug by default).
set -euo pipefail
cd "${0:A:h}/.."
xcodegen generate --quiet
xcodebuild -project Nook.xcodeproj -scheme Nook -configuration "${1:-Debug}" -derivedDataPath build build \
  | grep -E "error:|warning: |BUILD (SUCCEEDED|FAILED)" | grep -v appintentsmetadataprocessor | sort -u
