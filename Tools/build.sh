#!/bin/bash
# Construit l'app non signée dans build/Build/Products/<Configuration>.
# Argument optionnel : Debug ou Release (défaut).
set -o pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-Release}"
xcodebuild -project DynamicNotch.xcodeproj -scheme DynamicNotch -configuration "$CONFIG" \
  -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" | grep -v "appintentsmetadataprocessor" | tail -60
