#!/usr/bin/env bash
# Builds the Anon M0 Swift packages as separate static libraries and links the
# router smoke-test harness against them. Works under Command Line Tools (no
# full Xcode.app required) because AnonCore/AnonRouter/AnonNetwork/
# AnonTransports are Foundation-only.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$SRC_DIR/Packages/Anon/Sources"
SDK="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk}"
BUILD_DIR="${BUILD_DIR:-/tmp/anon-build}"
BIN="${BIN:-/tmp/anon-router-smoke}"

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
     -o "$BUILD_DIR/lib$name.a" \
     "$@"
}

# AnonCore (no dependencies)
build_lib AnonCore "$PKG/AnonCore"/*.swift

# AnonRouter (depends on AnonCore)
build_lib AnonRouter "$PKG/AnonRouter"/*.swift

# AnonNetwork (depends on AnonCore)
build_lib AnonNetwork "$PKG/AnonNetwork"/*.swift

# AnonTransports (depends on AnonCore + AnonRouter)
build_lib AnonTransports "$PKG/AnonTransports"/*.swift

# Link the harness + all package archives into an executable.
sc -I "$BUILD_DIR" \
   "$SRC_DIR/Tools/router-smoke/main.swift" \
   "$BUILD_DIR/libAnonCore.a" \
   "$BUILD_DIR/libAnonRouter.a" \
   "$BUILD_DIR/libAnonNetwork.a" \
   "$BUILD_DIR/libAnonTransports.a" \
   -o "$BIN"

echo "Built $BIN"