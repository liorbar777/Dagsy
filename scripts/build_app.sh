#!/usr/bin/env bash
# build_app.sh — Package Dagsy into a macOS .app bundle
#
# Usage:
#   ./scripts/build_app.sh [--dest /path/to/output]
#
# By default the .app is written to ~/Applications/Dagsy.app.
# Pre-compiled binaries are taken from the repo's bin/ directory.
# Override individual paths via env vars if needed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ── Configurable paths ────────────────────────────────────────────────────────
DEST=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest) DEST="$2"; shift 2 ;;
    *) shift ;;
  esac
done
DEST="${DEST:-$HOME/Applications/Dagsy.app}"

CONTROLLER_BIN="${CONTROLLER_BIN:-$REPO_ROOT/bin/airflow-dag-listener-controller}"
FAILURE_PANEL="${FAILURE_PANEL:-$REPO_ROOT/bin/airflow-failure-alert}"
SUCCESS_PANEL="${SUCCESS_PANEL:-$REPO_ROOT/bin/airflow-success-panel}"
# ──────────────────────────────────────────────────────────────────────────────

echo "Building Dagsy.app → $DEST"

# Validate required binaries
for bin_path in "$CONTROLLER_BIN" "$FAILURE_PANEL" "$SUCCESS_PANEL"; do
  if [[ ! -f "$bin_path" ]]; then
    echo "ERROR: Required binary not found: $bin_path"
    exit 1
  fi
done

# Remove previous build
rm -rf "$DEST"

# Create bundle layout
MACOS_DIR="$DEST/Contents/MacOS"
RESOURCES_DIR="$DEST/Contents/Resources"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Info.plist + PkgInfo
cp "$REPO_ROOT/app/Info.plist" "$DEST/Contents/Info.plist"
echo -n "APPL????" > "$DEST/Contents/PkgInfo"

# Icon
cp "$REPO_ROOT/assets/applet.icns" "$RESOURCES_DIR/applet.icns"

# Controller binary + watcher script
cp "$CONTROLLER_BIN" "$MACOS_DIR/airflow-dag-listener-controller"
chmod +x "$MACOS_DIR/airflow-dag-listener-controller"
cp "$REPO_ROOT/watch_local_airflow_failures.py" "$MACOS_DIR/watch_local_airflow_failures.py"

# Helper panel binaries — placed next to the .app
HELPERS_DIR="$(dirname "$DEST")"
cp "$FAILURE_PANEL"  "$HELPERS_DIR/airflow-failure-alert"
cp "$SUCCESS_PANEL"  "$HELPERS_DIR/airflow-success-panel"
chmod +x "$HELPERS_DIR/airflow-failure-alert" "$HELPERS_DIR/airflow-success-panel"

echo ""
echo "✓ Dagsy.app built at: $DEST"
echo "  Helper binaries:    $HELPERS_DIR/airflow-failure-alert"
echo "                      $HELPERS_DIR/airflow-success-panel"
echo ""
echo "Double-click $DEST to launch, or drag it to /Applications."
echo ""
echo "If macOS blocks the app on first launch:"
echo "  System Settings → Privacy & Security → scroll down → click 'Open Anyway'"
