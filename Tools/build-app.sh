#!/usr/bin/env bash
# Builds the runnable Anon macOS app (SwiftUI + AppKit) against the M0 packages.
# Works under Command Line Tools: the app links Foundation, SwiftUI, and AppKit.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$SRC_DIR/Packages/Anon/Sources"
APP="$SRC_DIR/App/Anon/Sources"
SDK="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk}"
BUILD_DIR="${BUILD_DIR:-/tmp/anon-build}"
BIN="${BIN:-/tmp/anon-app}"

mkdir -p "$BUILD_DIR"

sc() {
  /usr/bin/swiftc -sdk "$SDK" "$@"
}

# --- Reuse/build the package static libraries (same layout as build-smoke.sh)
build_lib() {
  local name="$1"; shift
  sc -emit-library -static -parse-as-library \
     -emit-module -emit-module-path "$BUILD_DIR/$name.swiftmodule" \
     -module-name "$name" \
     -I "$BUILD_DIR" \
     -o "$BUILD_DIR/lib$name.a" \
     "$@"
}
build_lib AnonCore "$PKG/AnonCore"/*.swift
build_lib AnonRouter "$PKG/AnonRouter"/*.swift
build_lib AnonTransports "$PKG/AnonTransports"/*.swift

# --- Build the app executable
sc -I "$BUILD_DIR" \
   "$APP/Engine.swift" \
   "$APP/Theme.swift" \
   "$APP/AnonApp.swift" \
   "$APP/main.swift" \
   "$BUILD_DIR/libAnonCore.a" \
   "$BUILD_DIR/libAnonRouter.a" \
   "$BUILD_DIR/libAnonTransports.a" \
   -framework AppKit \
   -framework SwiftUI \
   -o "$BIN"

echo "Built $BIN"