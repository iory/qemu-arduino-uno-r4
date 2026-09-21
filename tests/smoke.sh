#!/usr/bin/env bash
# Boot tests/hello on the arduino-uno-r4 machine and check what it prints.
#
#   tests/smoke.sh [path/to/qemu-system-arm]
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
QEMU=${1:-$HERE/../dist/bin/qemu-system-arm}
ELF=$HERE/hello/hello.elf
out=$(mktemp)
trap 'rm -f "$out"' EXIT

"$QEMU" -M arduino-uno-r4 -kernel "$ELF" -display none -monitor none \
        -serial "file:$out" 2>/dev/null &
pid=$!
for _ in $(seq 100); do
    grep -q "D13:" "$out" 2>/dev/null && break
    sleep 0.1
done
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true

cat "$out"
if grep -q "hello from 0x4000" "$out" && grep -q "D13: high" "$out"; then
    echo "smoke test passed"
else
    echo "smoke test FAILED" >&2
    exit 1
fi
