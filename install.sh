#!/usr/bin/env bash
# install.sh — One-command installer for Dagsy
#
# Usage (no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/liorbar777/Dagsy/master/install.sh | bash
#
# Or if you've already cloned the repo:
#   ./install.sh

set -euo pipefail

REPO="liorbar777/Dagsy"
INSTALL_DIR="$HOME/Applications"
CLONE_DIR="$(mktemp -d)/Dagsy"

echo "Installing Dagsy..."
echo ""

# Check for Xcode Command Line Tools
if ! xcode-select -p &>/dev/null; then
  echo "ERROR: Xcode Command Line Tools are not installed."
  echo "  Run this first, then re-run install.sh:"
  echo ""
  echo "    xcode-select --install"
  echo ""
  exit 1
fi

# If we're running from inside a cloned repo, use it directly
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-/dev/stdin}")" 2>/dev/null && pwd || echo "")"
if [[ -f "$SCRIPT_DIR/scripts/build_app.sh" ]]; then
  REPO_ROOT="$SCRIPT_DIR"
  echo "Using local repo at: $REPO_ROOT"
else
  echo "Cloning Dagsy repository..."
  git clone --depth 1 "https://github.com/$REPO.git" "$CLONE_DIR"
  REPO_ROOT="$CLONE_DIR"
fi

mkdir -p "$INSTALL_DIR"

bash "$REPO_ROOT/scripts/build_app.sh" --dest "$INSTALL_DIR/Dagsy.app"

# ── Write LaunchAgent plist ────────────────────────────────────────────────────
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/com.wix.local-airflow-watcher.plist"
WATCHER_SCRIPT="$INSTALL_DIR/Dagsy.app/Contents/MacOS/watch_local_airflow_failures.py"
LOG_PATH="$HOME/Library/Logs/local-airflow-watcher.log"

mkdir -p "$PLIST_DIR"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.wix.local-airflow-watcher</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>$WATCHER_SCRIPT</string>
    </array>
    <key>RunAtLoad</key>
    <false/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_PATH</string>
    <key>StandardErrorPath</key>
    <string>$LOG_PATH</string>
</dict>
</plist>
PLIST

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Dagsy installed to: $INSTALL_DIR/Dagsy.app"
echo "  LaunchAgent plist:  $PLIST_PATH"
echo ""
echo "  To launch:"
echo "    open $INSTALL_DIR/Dagsy.app"
echo ""
echo "  Or find it in Finder → Applications."
echo ""
echo "  If macOS blocks the app:"
echo "    System Settings → Privacy & Security → Open Anyway"
echo ""
echo "  Created by Lior Bar — Premium DE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
