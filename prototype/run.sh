#!/usr/bin/env bash
# Blockchain-node dashboard — PROTOTYPE STUDIO (design reference, not the implementation).
#
# Runs this fork's real QML views (../src/qml/views) against the forked Logos Design System
# with a mock backend and mock state — so every dashboard/settings state and interaction can
# be explored WITHOUT a running node. This is a throwaway design draft; the final code is
# re-implemented from these designs.
#
# Requires: nix (for the Qt QML runtime) and git. No node, no Basecamp.
#   Usage:  bash prototype/run.sh
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
DS_DIR="${LOGOS_DS_DIR:-$HERE/.ds-cache}"

if [ ! -d "$DS_DIR/src/qml/Logos" ]; then
  echo "Fetching forked Logos Design System (feat/dashboard-additions)…"
  rm -rf "$DS_DIR"
  git clone --depth 1 -b feat/dashboard-additions https://github.com/xAlisher/logos-design-system "$DS_DIR"
fi

# forked DS provides Logos.Theme/Controls/Icons; mock/ provides the Logos.BlockchainBackend enum
export QML_IMPORT_PATH="$DS_DIR/src/qml:$HERE/mock"
export QT_QUICK_BACKEND=software     # software rasterizer — no GPU needed

exec nix shell nixpkgs#qt6.qtdeclarative nixpkgs#qt6.qtsvg --command qml "$HERE/proto-studio.qml"
