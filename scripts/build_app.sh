#!/usr/bin/env bash
# build_app.sh — Build Dagsy from source and package as a macOS .app bundle
#
# Usage:
#   ./scripts/build_app.sh [--dest /path/to/output]
#
# Produces universal binaries (arm64 + x86_64) that run on any Mac.
# Requires Xcode Command Line Tools: xcode-select --install

set -euo pipefail

# Pick a consistent toolchain so swiftc and the SDK always match.
# Without this, xcrun may mix a swift.org swiftc with a CLT SDK, causing
# "SDK is not supported by the compiler" version-skew errors.
_toolchain_set=false
for _xcode in "/Applications/Xcode.app" /Applications/Xcode-*.app; do
  if [ -x "$_xcode/Contents/Developer/usr/bin/swiftc" ]; then
    export DEVELOPER_DIR="$_xcode/Contents/Developer"
    _toolchain_set=true
    break
  fi
done
if [ "$_toolchain_set" = false ] && [ -d "/Library/Developer/CommandLineTools" ]; then
  # Force CLT so xcrun doesn't accidentally pick a swift.org swiftc
  export DEVELOPER_DIR="/Library/Developer/CommandLineTools"
fi
unset _toolchain_set _xcode

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ── Args ──────────────────────────────────────────────────────────────────────
DEST=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest) DEST="$2"; shift 2 ;;
    *) shift ;;
  esac
done
DEST="${DEST:-$HOME/Applications/Dagsy.app}"

echo "Building Dagsy.app → $DEST"

# ── Check dependencies ────────────────────────────────────────────────────────
if ! command -v clang &>/dev/null; then
  echo ""
  echo "ERROR: clang not found. Install Xcode Command Line Tools:"
  echo "  xcode-select --install"
  exit 1
fi
if ! command -v swiftc &>/dev/null; then
  echo ""
  echo "ERROR: swiftc not found. Install Xcode Command Line Tools:"
  echo "  xcode-select --install"
  exit 1
fi

# Validate that swiftc and the macOS SDK versions match.
# A mismatch (e.g. CLT ships mismatched swiftlang builds) causes:
#   "SDK is not supported by the compiler"
_sdk_path="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)"
_check_tmp="$(mktemp -d)"
_mismatch="$(echo 'import Foundation' | xcrun swiftc -sdk "$_sdk_path" -o "$_check_tmp/sdk_check" - 2>&1 | grep 'SDK is not supported by the compiler' || true)"
rm -rf "$_check_tmp"
if [ -n "$_mismatch" ]; then
  echo ""
  echo "ERROR: Swift compiler/SDK version mismatch on this machine."
  echo "  Fix: update Xcode Command Line Tools, then retry:"
  echo "    sudo rm -rf /Library/Developer/CommandLineTools"
  echo "    xcode-select --install"
  echo ""
  echo "  If that doesn't help, install Xcode from the App Store."
  exit 1
fi
unset _sdk_path _check_tmp _mismatch

# ── Compile ───────────────────────────────────────────────────────────────────
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

MACOS_SDK="$(xcrun --sdk macosx --show-sdk-path)"

echo "  Compiling controller..."
xcrun clang -arch arm64 -arch x86_64 -isysroot "$MACOS_SDK" \
  -mmacosx-version-min=10.15 \
  -framework AppKit -framework Foundation \
  "$REPO_ROOT/src/dagsy_controller.m" \
  -o "$BUILD_DIR/airflow-dag-listener-controller"

echo "  Compiling panels..."
xcrun clang -arch arm64 -arch x86_64 -isysroot "$MACOS_SDK" \
  -mmacosx-version-min=10.15 \
  -framework AppKit -framework Foundation \
  "$REPO_ROOT/src/airflow_stack_panel.m" \
  -o "$BUILD_DIR/airflow-stack-panel"

echo "  Compiling dialog helper (arm64)..."
xcrun swiftc -O -target arm64-apple-macosx11.0 \
  "$REPO_ROOT/src/airflow-dialog-helper.swift" \
  -o "$BUILD_DIR/airflow-dialog-helper-arm64"

echo "  Compiling dialog helper (x86_64)..."
xcrun swiftc -O -target x86_64-apple-macosx10.15 \
  "$REPO_ROOT/src/airflow-dialog-helper.swift" \
  -o "$BUILD_DIR/airflow-dialog-helper-x86_64"

echo "  Creating universal dialog helper..."
lipo -create \
  "$BUILD_DIR/airflow-dialog-helper-arm64" \
  "$BUILD_DIR/airflow-dialog-helper-x86_64" \
  -output "$BUILD_DIR/airflow-dialog-helper"

# ── Package .app ──────────────────────────────────────────────────────────────
rm -rf "$DEST"

MACOS_DIR="$DEST/Contents/MacOS"
RESOURCES_DIR="$DEST/Contents/Resources"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$REPO_ROOT/app/Info.plist"        "$DEST/Contents/Info.plist"
echo -n "APPL????"                   > "$DEST/Contents/PkgInfo"
cp "$REPO_ROOT/assets/applet.icns"    "$RESOURCES_DIR/applet.icns"

cp "$BUILD_DIR/airflow-dag-listener-controller" "$MACOS_DIR/airflow-dag-listener-controller"
chmod +x "$MACOS_DIR/airflow-dag-listener-controller"
cp "$REPO_ROOT/watch_local_airflow_failures.py" "$MACOS_DIR/watch_local_airflow_failures.py"

# Helper binaries — placed next to the .app
HELPERS_DIR="$(dirname "$DEST")"
cp "$BUILD_DIR/airflow-stack-panel"   "$HELPERS_DIR/airflow-failure-alert"
cp "$BUILD_DIR/airflow-stack-panel"   "$HELPERS_DIR/airflow-success-panel"
cp "$BUILD_DIR/airflow-dialog-helper" "$HELPERS_DIR/airflow-dialog-helper"
chmod +x "$HELPERS_DIR/airflow-failure-alert" \
         "$HELPERS_DIR/airflow-success-panel" \
         "$HELPERS_DIR/airflow-dialog-helper"

echo ""
echo "✓ Dagsy.app built at: $DEST"
echo "  Helper binaries:    $HELPERS_DIR/airflow-failure-alert"
echo "                      $HELPERS_DIR/airflow-success-panel"
echo "                      $HELPERS_DIR/airflow-dialog-helper"
echo ""
echo "Double-click $DEST to launch, or drag it to /Applications."
echo ""
echo "If macOS blocks the app on first launch:"
echo "  System Settings → Privacy & Security → scroll down → click 'Open Anyway'"
