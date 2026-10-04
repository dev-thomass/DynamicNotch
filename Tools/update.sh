#!/bin/zsh
# Pulls the latest main, builds a Release copy, swaps it into ~/Applications
# and relaunches it. Usage: ./Tools/update.sh
set -euo pipefail

REPO_DIR="${0:A:h:h}"
BUILD_DIR="$REPO_DIR/build"
APP_NAME="DynamicNotch.app"
INSTALL_DIR="$HOME/Applications"

cd "$REPO_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Local changes found, commit or stash them first." >&2
    exit 1
fi

echo "→ Fetching latest main"
git checkout main
git pull --ff-only origin main

echo "→ Building Release"
xcodebuild -project DynamicNotch.xcodeproj \
    -scheme DynamicNotch \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    build \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    -quiet

BUILT_APP="$BUILD_DIR/Build/Products/Release/$APP_NAME"
if [[ ! -d "$BUILT_APP" ]]; then
    echo "Build output not found at $BUILT_APP" >&2
    exit 1
fi

echo "→ Quitting the running app"
osascript -e 'quit app "DynamicNotch"' 2>/dev/null || true
for _ in {1..20}; do
    pgrep -x DynamicNotch >/dev/null || break
    sleep 0.25
done
pkill -x DynamicNotch 2>/dev/null || true

echo "→ Installing into $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME"
cp -R "$BUILT_APP" "$INSTALL_DIR/"

echo "→ Relaunching"
open "$INSTALL_DIR/$APP_NAME"
echo "✓ DynamicNotch is up to date ($(git rev-parse --short HEAD))"
