#!/usr/bin/env bash
# Build qemu-system-arm with the arduino-uno-r4 machine (native: Linux, macOS,
# or Windows in an MSYS2 UCRT64 shell).
#
#   ./build.sh                 # -> dist/bin/qemu-system-arm
#
# Environment:
#   WORK=dir      where the QEMU source is unpacked and built (default: ./work)
#   PREFIX=dir    where the binary is placed (default: ./dist)
#   JOBS=n        parallel build jobs (default: number of CPUs)
#
#   QEMU_CONFIGURE_EXTRA=...  extra arguments for QEMU's configure
#
# Requirements: python3 (with tomli before 3.11), ninja, pkg-config, glib-2.0,
#               curl, git, a C compiler.
#   Debian/Ubuntu: apt install build-essential ninja-build pkg-config \
#                  libglib2.0-dev python3-venv python3-tomli curl git
#   macOS:         brew install ninja pkgconf glib
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$ROOT/work}
PREFIX=${PREFIX:-$ROOT/dist}
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}

for tool in python3 ninja pkg-config curl git; do
    command -v "$tool" >/dev/null || { echo "error: '$tool' not found (see the top of $0)" >&2; exit 1; }
done

case $(uname -s) in MINGW*|MSYS*) EXE=.exe;; *) EXE=;; esac

src=$(WORK="$WORK" "$ROOT/prepare-source.sh")
mkdir -p "$PREFIX/bin"

echo ">> configuring"
mkdir -p "$src/build"
cd "$src/build"
# Only the ARM system emulator and none of the optional host features: the
# board is used with -display none (serial on a socket or stdio), and every
# library left out is one fewer to install or ship next to the binary.
# libfdt is required by the ARM targets; the copy QEMU pins (a meson
# subproject fetched with git) is linked in statically, so the binary does
# not depend on a system libfdt.
../configure \
    --target-list=arm-softmmu \
    --without-default-features \
    --enable-fdt=internal \
    --disable-docs --disable-tools --disable-guest-agent \
    ${QEMU_CONFIGURE_EXTRA:-} \
    > configure.log 2>&1 || { tail -40 configure.log; exit 1; }

echo ">> building ($JOBS jobs)"
ninja -j "$JOBS" "qemu-system-arm$EXE"

cp "qemu-system-arm$EXE" "$PREFIX/bin/"
"$PREFIX/bin/qemu-system-arm$EXE" -machine help | grep -q '^arduino-uno-r4 ' \
    || { echo "error: arduino-uno-r4 machine missing from the build" >&2; exit 1; }
echo ">> done: $PREFIX/bin/qemu-system-arm$EXE"
