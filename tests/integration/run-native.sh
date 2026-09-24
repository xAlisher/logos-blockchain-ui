#!/usr/bin/env bash
# Build ONLY this harness; never builds, installs, starts, or mutates the module.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd -- "$here/../.." && pwd)
plugin=${1:?Usage: bash tests/integration/run-native.sh /absolute/path/to/packaged-plugin.so [build-directory]}
build=${2:-/extra/tmp/blend-native-harness}
include=${LOGOS_QT_INCLUDE:-/nix/store/kc44vpw5y7rxy91zdvch0ay54j1kfs6d-logos-qt-sdk-headers-0.1.0/include/cpp}
case "$build" in /extra/*) ;; *) printf 'Build directory must be under /extra\n' >&2; exit 2;; esac
if [[ ! -f "$plugin" || "$plugin" != /* ]]; then
    printf 'BLOCKED: supply an existing absolute path to the packaged native .so: %s\n' "$plugin" >&2
    exit 2
fi
cd "$repo"
# Pin the same Qt/toolchain as the module; do not mix local Qt 6.9.3 with Nix 6.9.2.
nix develop --offline --command cmake -S "$here" -B "$build" \
    -DLOGOS_QT_INCLUDE="$include" -DBLEND_SOURCE="$repo" -DBLEND_PLUGIN="$plugin"
nix develop --offline --command cmake --build "$build" --target blend_native -j2
sha256sum "$plugin"
exec /usr/bin/python3 -I "$here/run.py" --binary "$build/blend_native"
