#!/usr/bin/env bash
# Download the pinned QEMU release, verify it and apply the patches.
#
#   ./prepare-source.sh          # prints the path of the patched source tree
#
# The result is also the "corresponding source" shipped with every release.
# Environment: WORK=dir (default: ./work)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=QEMU_VERSION
. "$ROOT/QEMU_VERSION"
WORK=${WORK:-$ROOT/work}

sha256() {
    if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi \
        | awk '{print $1}'
}

mkdir -p "$WORK"
cd "$WORK"

tarball="qemu-$QEMU_VERSION.tar.xz"
if [ ! -f "$tarball" ]; then
    echo ">> downloading $tarball" >&2
    curl -fL --retry 3 -o "$tarball.part" "https://download.qemu.org/$tarball"
    mv "$tarball.part" "$tarball"
fi
actual=$(sha256 "$tarball")
if [ "$actual" != "$QEMU_SHA256" ]; then
    echo "error: $tarball sha256 mismatch" >&2
    echo "  expected $QEMU_SHA256" >&2
    echo "  actual   $actual" >&2
    exit 1
fi

src="qemu-$QEMU_VERSION"
echo ">> unpacking and applying patches" >&2
rm -rf "$src"
tar xf "$tarball"
for p in "$ROOT"/patches/*.patch; do
    echo "   $(basename "$p")" >&2
    patch -d "$src" -p1 --forward --quiet < "$p"
done
echo "$WORK/$src"
