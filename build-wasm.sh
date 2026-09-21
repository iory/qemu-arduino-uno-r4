#!/usr/bin/env bash
# Build qemu-system-arm with the arduino-uno-r4 machine for WebAssembly.
#
#   ./build-wasm.sh            # -> dist/wasm/qemu-system-arm.{js,wasm}
#
# Uses QEMU's own Emscripten cross-build container
# (tests/docker/dockerfiles/emsdk-wasm64-cross.docker), so only Docker is
# needed on the host.
#
# QEMU's WebAssembly host is wasm64 with the TCG interpreter. We build with
# --wasm64-32bit-address-limit (Emscripten MEMORY64=2): the code uses 64-bit
# pointers but the module is lowered to wasm32, so it also runs in browsers
# without Memory64 (e.g. Safari). The guest is a 32 KiB-RAM MCU, so the 4 GiB
# limit does not matter, and we measured no speed difference against a true
# wasm64 build.
#
# Environment: WORK, PREFIX, JOBS as in build.sh; IMAGE=name of the container.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$ROOT/work}
PREFIX=${PREFIX:-$ROOT/dist}
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}
IMAGE=${IMAGE:-qemu-emsdk-wasm64-cross}

command -v docker >/dev/null || { echo "error: docker not found" >&2; exit 1; }

src=$(WORK="$WORK" "$ROOT/prepare-source.sh")

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo ">> building the Emscripten container (takes a while the first time)"
    docker build -t "$IMAGE" \
        -f "$src/tests/docker/dockerfiles/emsdk-wasm64-cross.docker" \
        "$src/tests/docker/dockerfiles"
fi

echo ">> building qemu-system-arm.js ($JOBS jobs)"
# The container runs as root; hand the build tree back to the caller.
owner="$(id -u):$(id -g)"
docker run --rm -v "$src:/qemu" -w /qemu "$IMAGE" bash -c "
    set -e
    trap 'chown -R $owner /qemu/build-wasm' EXIT
    mkdir -p build-wasm && cd build-wasm
    emconfigure ../configure --static --cpu=wasm64 --wasm64-32bit-address-limit \
        --enable-tcg-interpreter --disable-tools --disable-docs \
        --target-list=arm-softmmu > configure.log 2>&1 \
        || { tail -40 configure.log; exit 1; }
    emmake make -j$JOBS qemu-system-arm.js
"

mkdir -p "$PREFIX/wasm"
cp "$src/build-wasm/qemu-system-arm.js" "$src/build-wasm/qemu-system-arm.wasm" "$PREFIX/wasm/"
echo ">> done: $PREFIX/wasm/qemu-system-arm.{js,wasm}"
