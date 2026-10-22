#!/usr/bin/env bash
# Builds the runnable Anon macOS app (SwiftUI + AppKit) against the M0 packages
# and bundles it into a real .app. Works under Command Line Tools.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$SRC_DIR/Packages/Anon/Sources"
APP="$SRC_DIR/App/Anon/Sources"

SDK="${SDKROOT:-}"
if [ -z "$SDK" ]; then
  SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
fi
if [ -z "$SDK" ]; then
  SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
fi

BUILD_DIR="${BUILD_DIR:-/tmp/anon-build}"
BIN="${BIN:-/tmp/anon-app}"
APP_BUNDLE="${APP_BUNDLE:-/tmp/Anon.app}"

mkdir -p "$BUILD_DIR"

sc() {
  /usr/bin/swiftc -sdk "$SDK" "$@"
}

build_lib() {
  local name="$1"; shift
  sc -emit-library -static -parse-as-library \
     -emit-module -emit-module-path "$BUILD_DIR/$name.swiftmodule" \
     -module-name "$name" \
     -I "$BUILD_DIR" \
     -framework CryptoKit \
     -o "$BUILD_DIR/lib$name.a" \
     "$@"
}

build_lib AnonCore "$PKG/AnonCore"/*.swift
build_lib AnonCrypto "$PKG/AnonCrypto"/*.swift
build_lib AnonRouter "$PKG/AnonRouter"/*.swift
build_lib AnonTransports "$PKG/AnonTransports"/*.swift

# --- Build the app executable
sc -I "$BUILD_DIR" \
   "$APP/Engine.swift" \
   "$APP/Theme.swift" \
   "$APP/AnonApp.swift" \
   "$APP/main.swift" \
   "$BUILD_DIR/libAnonCore.a" \
   "$BUILD_DIR/libAnonCrypto.a" \
   "$BUILD_DIR/libAnonRouter.a" \
   "$BUILD_DIR/libAnonTransports.a" \
   -framework CryptoKit \
   -framework AppKit \
   -framework SwiftUI \
   -o "$BIN"

# --- Generate app icons from the Anon logo
ICONSET="$BUILD_DIR/Anon.iconset"
mkdir -p "$ICONSET"
APP_LOGO="$SRC_DIR/App/Anon/Resources/anon.jpg"
SIPS_BIN="$(xcrun --find sips 2>/dev/null || echo /usr/bin/sips)"

# Generated assets land here first, then are copied into the bundle.
GEN_RESOURCES="$BUILD_DIR/resources"
mkdir -p "$GEN_RESOURCES"

make_icon() {
  local out="$1" size="$2"
  "$SIPS_BIN" -s format png "$APP_LOGO" --out "$out" >/dev/null 2>&1
  "$SIPS_BIN" -z "$size" "$size" "$out" >/dev/null 2>&1
}

make_icon "$ICONSET/icon_16x16.png" 16
make_icon "$ICONSET/icon_16x16@2x.png" 32
make_icon "$ICONSET/icon_32x32.png" 32
make_icon "$ICONSET/icon_32x32@2x.png" 64
make_icon "$ICONSET/icon_128x128.png" 128
make_icon "$ICONSET/icon_128x128@2x.png" 256
make_icon "$ICONSET/icon_256x256.png" 256
make_icon "$ICONSET/icon_256x256@2x.png" 512
make_icon "$ICONSET/icon_512x512.png" 512
make_icon "$ICONSET/icon_512x512@2x.png" 1024

ICONUTIL="$(xcrun --find iconutil 2>/dev/null || echo /usr/bin/iconutil)"
"$ICONUTIL" -c icns "$ICONSET" -o "$GEN_RESOURCES/Anon.icns" >/dev/null 2>&1

# In-app logo PNG (square, 256px) used by the onboarding + sidebar views.
make_icon "$GEN_RESOURCES/anon.png" 256

# --- Assemble a launchable .app bundle
mkdir -p "$APP_BUNDLE/Contents/MacOS"
BUNDLE_RESOURCES="$APP_BUNDLE/Contents/Resources"
mkdir -p "$BUNDLE_RESOURCES"
cp "$BIN" "$APP_BUNDLE/Contents/MacOS/Anon"
cp "$GEN_RESOURCES/Anon.icns" "$BUNDLE_RESOURCES/Anon.icns"
cp "$GEN_RESOURCES/anon.png" "$BUNDLE_RESOURCES/anon.png"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Anon</string>
    <key>CFBundleDisplayName</key><string>Anon</string>
    <key>CFBundleIdentifier</key><string>org.anon-messenger.anon</string>
    <key>CFBundleVersion</key><string>0.1.0</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>Anon</string>
    <key>CFBundleIconFile</key><string>Anon</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

echo "Built $APP_BUNDLE"