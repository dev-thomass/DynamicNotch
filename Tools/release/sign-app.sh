#!/bin/bash
#
# Signe DynamicNotch.app de l'intérieur vers l'extérieur (Sparkle d'abord).
#
#   sign-app.sh DynamicNotch.app                  → signature ad hoc
#   sign-app.sh DynamicNotch.app "Developer ID…"  → Developer ID + runtime renforcé
#
# En ad hoc, pas de runtime renforcé : la validation des bibliothèques
# exigerait une Team ID commune entre l'app et Sparkle.framework.
#
set -euo pipefail

APP="${1:?usage: sign-app.sh DynamicNotch.app [identité]}"
IDENTITY="${2:-}"
ENTITLEMENTS="$(cd "$(dirname "$0")" && pwd)/DynamicNotch.entitlements"

if [[ -n "$IDENTITY" ]]; then
    OPTS=(--force --sign "$IDENTITY" --options runtime --timestamp)
else
    OPTS=(--force --sign -)
fi

FRAMEWORKS="$APP/Contents/Frameworks"
SPARKLE="$FRAMEWORKS/Sparkle.framework"
if [[ -d "$SPARKLE" ]]; then
    codesign "${OPTS[@]}" "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
    codesign "${OPTS[@]}" --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
    codesign "${OPTS[@]}" "$SPARKLE/Versions/B/Autoupdate"
    codesign "${OPTS[@]}" "$SPARKLE/Versions/B/Updater.app"
    codesign "${OPTS[@]}" "$SPARKLE"
fi

# Autres frameworks / dylibs embarqués par les paquets Swift.
if [[ -d "$FRAMEWORKS" ]]; then
    find "$FRAMEWORKS" -mindepth 1 -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) \
        ! -name "Sparkle.framework" -print0 |
        while IFS= read -r -d '' item; do
            codesign "${OPTS[@]}" "$item"
        done
fi

codesign "${OPTS[@]}" --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
