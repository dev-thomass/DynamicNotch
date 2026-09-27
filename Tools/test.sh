#!/bin/bash
# Lance les tests unitaires. Argument optionnel : nom d'une classe de test.
# Données dérivées dans build/tests : le build de test, non signé, ne remplace
# jamais l'app (éventuellement signée) de build/Build/Products/Debug.
set -o pipefail
cd "$(dirname "$0")/.."
ARGS=()
if [ -n "$1" ]; then ARGS+=("-only-testing:DynamicNotchTests/$1"); fi
xcodebuild -project DynamicNotch.xcodeproj -scheme DynamicNotch -destination 'platform=macOS' \
  -derivedDataPath build/tests CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  test "${ARGS[@]}" 2>&1 | grep -E "error:|: error|failed|passed|Executed|TEST (SUCCEEDED|FAILED)|BUILD FAILED" | tail -60
