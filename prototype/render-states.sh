#!/usr/bin/env bash
# Offscreen-render prototype-studio states to PNGs (prototype/screenshots/).
#   Usage:
#     bash prototype/render-states.sh                 # all dashboard scenarios
#     bash prototype/render-states.sh 7 8 9           # only these scenario indices
#     bash prototype/render-states.sh --blend         # the Blend card + modal set (blend-*.png)
#
# Portable: resolves Qt + the forked Logos DS exactly like run.sh (nix + .ds-cache), so it works
# from any checkout — no machine-specific paths.
#
# THE GOTCHA IT FIXES: Qt's OFFSCREEN platform ABORTS (SIGABRT) when BOTH $DISPLAY and $XAUTHORITY
# are set (an X11 probe in the offscreen path). An interactive shell has both, so a naive
# `qml --grab` cores before it can grab. Each render therefore runs in a CLEAN env (`env -i`) that
# carries only what the render needs — never reintroduce the ambient environment here.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
DS_DIR="${LOGOS_DS_DIR:-$HERE/.ds-cache}"
OUT="$HERE/screenshots"; mkdir -p "$OUT"

if [ ! -d "$DS_DIR/src/qml/Logos" ]; then
  echo "Fetching forked Logos Design System (feat/dashboard-additions)…"
  rm -rf "$DS_DIR"
  git clone --depth 1 -b feat/dashboard-additions https://github.com/xAlisher/logos-design-system "$DS_DIR"
fi

echo "Resolving Qt via nix…"
QTD="$(nix build --no-link --print-out-paths nixpkgs#qt6.qtdeclarative)"
QTSVG="$(nix build --no-link --print-out-paths nixpkgs#qt6.qtsvg)"
QMLIMPORT="$DS_DIR/src/qml:$HERE/mock:$QTD/lib/qt-6/qml"
QTPLUGIN="$QTD/lib/qt-6/plugins:$QTSVG/lib/qt-6/plugins"

# CLEAN-env offscreen grab (no $DISPLAY / $XAUTHORITY). $1 = extra args, $2 = output file.
grab() {
  local args="$1" out="$2"
  for attempt in 1 2 3; do
    rm -f "$OUT/.grab.png"
    env -i HOME="$HOME" PATH=/usr/bin:/bin \
      QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
      QT_PLUGIN_PATH="$QTPLUGIN" QML_IMPORT_PATH="$QMLIMPORT" \
      timeout 45 "$QTD/bin/qml" "$HERE/proto-studio.qml" --grab --grabdelay 2000 \
        --grabout "$OUT/.grab.png" $args >/dev/null 2>&1 || true
    if [ -f "$OUT/.grab.png" ]; then mv "$OUT/.grab.png" "$out"; echo "  ✓ $(basename "$out")"; return 0; fi
  done
  echo "  ✗ $(basename "$out") — no frame after 3 tries"; return 1
}

# The Blend card + modal set (keep in sync with the scenarios array in proto-studio.qml).
if [ "${1:-}" = "--blend" ]; then
  echo "Rendering Blend states → $OUT"
  grab "--scenario 7  --tab 0"                    "$OUT/blend-card-edge.png"
  grab "--scenario 8  --tab 0"                    "$OUT/blend-card-core.png"
  grab "--scenario 9  --tab 0"                    "$OUT/blend-card-declared.png"
  grab "--scenario 10 --tab 0 --blendmodal --port" "$OUT/blend-modal-withdrawing.png"
  grab "--scenario 7  --tab 0 --blendmodal --port" "$OUT/blend-modal-ready.png"
  grab "--scenario 7  --tab 0 --blendmodal"        "$OUT/blend-modal-port-closed.png"
  exit 0
fi

# Dashboard scenario grid (index → slug; keep in sync with the scenarios array).
NAMES=(fresh starting bootstrapping online funded-aging aged-eligible validating \
       blend-edge blend-core blend-declared-not-mixing blend-withdrawing blend-maturing \
       replaying-blocks bootstrap-stuck sync-stalled node-auto-paused error)
if [ "$#" -gt 0 ]; then IDXS=("$@"); else IDXS=($(seq 0 $((${#NAMES[@]} - 1)))); fi
echo "Rendering ${#IDXS[@]} scenario(s) → $OUT"
fail=0
for i in "${IDXS[@]}"; do grab "--scenario $i --tab 0" "$OUT/$(printf '%02d' "$i")-${NAMES[$i]:-scenario-$i}.png" || fail=1; done
exit $fail
