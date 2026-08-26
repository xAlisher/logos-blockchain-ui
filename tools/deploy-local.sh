#!/usr/bin/env bash
# Deploy the built logos_node_1click plugin + qml into the LOCAL Basecamp.
# Encodes the deploy gotchas that cost us before:
#  - nix-store copies are read-only (444): a later plain `cp` silently fails and
#    leaves STALE QML → chmod -R u+w after every copy, rm -rf before it.
#  - after any .rep change deploy BOTH .so (plugin + replica factory) — a stale
#    factory means the replica never connects (props default, slots dead).
#    (This release has no .rep change, but copying both is free insurance.)
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$REPO/result"
DEST="$HOME/.local/share/Logos/LogosBasecamp/plugins/logos_node_1click"

[ -e "$OUT" ] || { echo "no ./result — run: TMPDIR=/extra/tmp nix build .#"; exit 1; }
SRC=$(find -L "$OUT" -name 'logos_node_1click_plugin.so' -printf '%h\n' | head -1)
[ -n "$SRC" ] || { echo "plugin .so not found under $OUT"; exit 1; }

echo "deploying from $SRC -> $DEST"
mkdir -p "$DEST"
chmod -R u+w "$DEST" 2>/dev/null || true
for f in logos_node_1click_plugin.so logos_node_1click_replica_factory.so metadata.json; do
  [ -f "$SRC/$f" ] && { rm -f "$DEST/$f"; cp -L --no-preserve=mode "$SRC/$f" "$DEST/$f"; echo "  $f"; }
done
if [ -d "$SRC/qml" ]; then
  rm -rf "$DEST/qml"
  cp -rL --no-preserve=mode "$SRC/qml" "$DEST/qml"
  echo "  qml/ ($(find "$DEST/qml" -name '*.qml' | wc -l) files)"
fi
chmod -R u+w "$DEST"
echo "done — restart Basecamp to load 0.2.20"
