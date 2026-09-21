#!/usr/bin/env bash
# Build qemu-system-arm with the arduino-uno-r4 machine (native, Linux/macOS).
#
#   ./build.sh                 # -> dist/bin/qemu-system-arm
#
# Environment:
#   WORK=dir      where the QEMU source is unpacked and built (default: ./work)
#   PREFIX=dir    where the binary is placed (default: ./dist)
#   JOBS=n        parallel build jobs (default: number of CPUs)
#
# Requirements: python3 (with tomli before 3.11), ninja, pkg-config, glib-2.0,
#               pixman, libfdt, curl, a C compiler.
#   Debian/Ubuntu: apt install build-essential ninja-build pkg-config \
#                  libglib2.0-dev libpixman-1-dev libfdt-dev python3-venv python3-tomli curl
#   macOS:         brew install ninja pkgconf glib pixman dtc
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$ROOT/work}
PREFIX=${PREFIX:-$ROOT/dist}
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}

for tool in python3 ninja pkg-config curl; do
    command -v "$tool" >/dev/null || { echo "error: '$tool' not found (see the top of $0)" >&2; exit 1; }
done

src=$(WORK="$WORK" "$ROOT/prepare-source.sh")
mkdir -p "$PREFIX/bin"

echo ">> configuring"
mkdir -p "$src/build"
cd "$src/build"
# Only the ARM system emulator, and nothing that needs a display: the board
# is used with -display none (serial on a socket or stdio).
../configure \
    --target-list=arm-softmmu \
    --disable-docs --disable-tools --disable-guest-agent \
    --disable-gtk --disable-sdl --disable-vnc --disable-opengl --disable-cocoa \
    --disable-slirp --disable-curl --disable-libusb \
    > configure.log 2>&1 || { tail -40 configure.log; exit 1; }

echo ">> building ($JOBS jobs)"
ninja -j "$JOBS" qemu-system-arm

cp qemu-system-arm "$PREFIX/bin/"
"$PREFIX/bin/qemu-system-arm" -machine help | grep -q '^arduino-uno-r4 ' \
    || { echo "error: arduino-uno-r4 machine missing from the build" >&2; exit 1; }
echo ">> done: $PREFIX/bin/qemu-system-arm"
