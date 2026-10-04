#!/bin/bash
#
# Compile Vendor/mediaremote-adapter en MediaRemoteAdapter.framework et le
# copie, avec le script Perl, dans le produit en cours de build.
# Appelé par la phase « Build MediaRemoteAdapter » de la cible DynamicNotch.
#
#   build-mediaremote-adapter.sh             (variables Xcode)
#   build-mediaremote-adapter.sh <dossier>   (manuel : produit dans <dossier>)
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor/mediaremote-adapter"

if [[ -n "${1:-}" ]]; then
    FRAMEWORKS_DIR="$1"
    RESOURCES_DIR="$1"
    ARCH_LIST="arm64 x86_64"
else
    FRAMEWORKS_DIR="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
    RESOURCES_DIR="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
    ARCH_LIST="${ARCHS:-arm64 x86_64}"
fi

NAME="MediaRemoteAdapter"
FRAMEWORK="$FRAMEWORKS_DIR/$NAME.framework"
BINARY="$FRAMEWORK/Versions/A/$NAME"

mkdir -p "$RESOURCES_DIR"
cp "$VENDOR/bin/mediaremote-adapter.pl" "$RESOURCES_DIR/mediaremote-adapter.pl"

# Rien à recompiler si le binaire est plus récent que toutes les sources.
if [[ -f "$BINARY" ]] && [[ -z "$(find "$VENDOR/src" "$VENDOR/include" "$0" -newer "$BINARY" -print -quit)" ]]; then
    exit 0
fi

rm -rf "$FRAMEWORK"
mkdir -p "$FRAMEWORK/Versions/A/Resources"

ARCH_FLAGS=()
for arch in $ARCH_LIST; do
    ARCH_FLAGS+=(-arch "$arch")
done

xcrun clang -dynamiclib -fobjc-arc -fvisibility=default -O2 \
    "${ARCH_FLAGS[@]}" \
    -mmacosx-version-min="${MACOSX_DEPLOYMENT_TARGET:-14.0}" \
    -I "$VENDOR/include" -I "$VENDOR/src" \
    -framework Foundation -framework AppKit -framework MediaPlayer -framework UniformTypeIdentifiers \
    -install_name "@rpath/$NAME.framework/Versions/A/$NAME" \
    "$VENDOR"/src/adapter/*.m "$VENDOR"/src/private/*.m "$VENDOR"/src/utility/*.m \
    -o "$BINARY"

cat > "$FRAMEWORK/Versions/A/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.vandenbe.$NAME</string>
    <key>CFBundleName</key>
    <string>$NAME</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>CFBundleVersion</key>
    <string>0.1.0</string>
</dict>
</plist>
PLIST

ln -sfn A "$FRAMEWORK/Versions/Current"
ln -sfn "Versions/Current/$NAME" "$FRAMEWORK/$NAME"
ln -sfn "Versions/Current/Resources" "$FRAMEWORK/Resources"

# Signé avant l'app (Xcode signe le produit après les phases de script).
codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$FRAMEWORK"
