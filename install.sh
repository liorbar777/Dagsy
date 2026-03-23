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

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Dagsy installed to: $INSTALL_DIR/Dagsy.app"
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
