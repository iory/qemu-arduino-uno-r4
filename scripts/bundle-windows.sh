#!/usr/bin/env bash
# Copy the MSYS2 DLLs a Windows build needs next to it, so that it runs
# outside MSYS2. Run from an MSYS2 UCRT64 shell.
#
#   scripts/bundle-windows.sh DIR      # DIR/bin/qemu-system-arm.exe -> DIR/bin/*.dll
set -euo pipefail

BIN=$1/bin/qemu-system-arm.exe
# ldd lists the whole dependency tree; keep what comes from the MSYS2
# prefix (e.g. /ucrt64/bin) and leave the Windows system DLLs alone.
prefix=$(dirname "$(command -v gcc)")
dlls=$(ldd "$BIN" | awk -v p="$prefix/" 'index($3, p) == 1 {print $3}' | sort -u)
[ -n "$dlls" ] || { echo "error: no DLLs from $prefix found (is this a UCRT64 shell?)" >&2; exit 1; }
for d in $dlls; do cp "$d" "$(dirname "$BIN")/"; done
echo ">> bundled:" >&2
for d in $dlls; do basename "$d"; done >&2
