#!/usr/bin/env bash
# build_app.sh — Build Dagsy from source and package as a macOS .app bundle
#
# Usage:
#   ./scripts/build_app.sh [--dest /path/to/output]
#
# Produces universal binaries (arm64 + x86_64) that run on any Mac.
# Requires Xcode Command Line Tools: xcode-select --install

set -euo pipefail

# SDKROOT from the environment can force a macOS SDK that does not match the
# Swift compiler on PATH (common in IDEs). Always derive the SDK from the same
# DEVELOPER_DIR we use for swiftc.
unset SDKROOT

# Pick a single Apple toolchain so swiftc, clang, and the macOS SDK all match.
# Mixing sources (e.g. swift.org swiftc + Xcode SDK, or updated CLT + old Xcode)
# causes: "SDK is not supported by the compiler" / "failed to build module 'AppKit'".
_toolchain_set=false
for _xcode in "/Applications/Xcode.app" /Applications/Xcode-*.app; do
  [ -d "$_xcode" ] || continue
  if [ -x "$_xcode/Contents/Developer/usr/bin/swiftc" ]; then
    export DEVELOPER_DIR="$_xcode/Contents/Developer"
    _toolchain_set=true
    break
  fi
done
if [ "$_toolchain_set" = false ] && [ -d "/Library/Developer/CommandLineTools" ]; then
  export DEVELOPER_DIR="/Library/Developer/CommandLineTools"
  _toolchain_set=true
fi
unset _toolchain_set _xcode

if [ -z "${DEVELOPER_DIR:-}" ] || [ ! -x "$DEVELOPER_DIR/usr/bin/swiftc" ]; then
  echo ""
  echo "ERROR: No usable Apple Swift toolchain found."
  echo "  Install Xcode from the App Store, or Command Line Tools: xcode-select --install"
  exit 1
fi

export PATH="$DEVELOPER_DIR/usr/bin:$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH"
SWIFTC="$DEVELOPER_DIR/usr/bin/swiftc"

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
echo "  Using DEVELOPER_DIR=$DEVELOPER_DIR"

# ── Check dependencies ────────────────────────────────────────────────────────
if [ ! -x "$DEVELOPER_DIR/usr/bin/clang" ]; then
  echo ""
  echo "ERROR: clang not found under the active toolchain."
  echo "  Install Xcode or Command Line Tools: xcode-select --install"
  exit 1
fi

# Validate that this Swift compiler can build AppKit against the same SDK (tiny
# swiftlang build differences vs the SDK break with "SDK is not supported" /
# "failed to build module 'AppKit'").
_sdk_path="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)"
_check_tmp="$(mktemp -d)"
_sdk_compile_err="$_check_tmp/swift_sdk_err.txt"
if ! echo 'import AppKit' | "$SWIFTC" -sdk "$_sdk_path" -o "$_check_tmp/sdk_check" - 2>"$_sdk_compile_err"; then
  echo ""
  echo "ERROR: Swift compiler and macOS SDK do not match (same symptom as building in an IDE with the wrong toolchain)."
  echo "  Active toolchain: $DEVELOPER_DIR"
  echo "  SDK: $_sdk_path"
  echo ""
  echo "  Compiler output:"
  sed 's/^/    /' "$_sdk_compile_err" || true
  echo ""
  echo "  Typical fixes:"
  echo "    • Point the active developer directory at full Xcode (then retry this script):"
  echo "        sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  echo "    • Or reinstall Command Line Tools so Swift and the SDK update together:"
  echo "        sudo rm -rf /Library/Developer/CommandLineTools"
  echo "        xcode-select --install"
  echo "    • In PyCharm/IDE: do not compile airflow-dialog-helper.swift with a random swiftc;"
  echo "      run ./scripts/build_app.sh from Terminal so the toolchain stays consistent."
  rm -rf "$_check_tmp"
  exit 1
fi
rm -rf "$_check_tmp"
unset _sdk_path _check_tmp _sdk_compile_err

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
"$SWIFTC" -O -sdk "$MACOS_SDK" -target arm64-apple-macosx11.0 \
  "$REPO_ROOT/src/airflow-dialog-helper.swift" \
  -o "$BUILD_DIR/airflow-dialog-helper-arm64"

echo "  Compiling dialog helper (x86_64)..."
"$SWIFTC" -O -sdk "$MACOS_SDK" -target x86_64-apple-macosx10.15 \
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
