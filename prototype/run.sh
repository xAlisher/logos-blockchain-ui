#!/usr/bin/env bash
# Blockchain-node dashboard — PROTOTYPE STUDIO (design reference, not the implementation).
#
# Runs this fork's real QML views (../src/qml/views) against the forked Logos Design System
# with a mock backend and mock state — every dashboard/settings state and interaction, WITHOUT
# a running node. Throwaway design draft; the final code is re-implemented from these designs.
#
# Requires: nix (with flakes) + git. No node, no Basecamp.
#   Usage:  bash prototype/run.sh
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
DS_DIR="${LOGOS_DS_DIR:-$HERE/.ds-cache}"

if [ ! -d "$DS_DIR/src/qml/Logos" ]; then
  echo "Fetching forked Logos Design System (feat/dashboard-additions)…"
  rm -rf "$DS_DIR"
  git clone --depth 1 -b feat/dashboard-additions https://github.com/xAlisher/logos-design-system "$DS_DIR"
fi

echo "Resolving Qt via nix…"
QTD="$(nix build --no-link --print-out-paths nixpkgs#qt6.qtdeclarative)"   # provides `qml` + QtQuick/Controls/Layouts
QTSVG="$(nix build --no-link --print-out-paths nixpkgs#qt6.qtsvg)"          # SVG image plugin for the header logo

# QtQuick.* live in qtdeclarative's qml dir; nix's Qt setup-hook isn't applied at `nix shell`
# runtime, so add it explicitly alongside the forked DS + the mock backend.
export QML_IMPORT_PATH="$DS_DIR/src/qml:$HERE/mock:$QTD/lib/qt-6/qml"
export QT_PLUGIN_PATH="$QTD/lib/qt-6/plugins:$QTSVG/lib/qt-6/plugins"
export QT_QUICK_BACKEND=software     # software rasterizer — no GPU needed

exec "$QTD/bin/qml" "$HERE/proto-studio.qml" "$@"
