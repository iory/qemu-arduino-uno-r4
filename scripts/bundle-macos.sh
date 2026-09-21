#!/usr/bin/env bash
# Make a macOS build self-contained: copy every non-system dylib it needs
# (glib from Homebrew and what glib pulls in) next to it and point the load
# commands there, then re-sign ad hoc.
#
#   scripts/bundle-macos.sh DIR        # DIR/bin/qemu-system-arm -> DIR/lib/*.dylib
set -euo pipefail

DIR=$1
BIN=$DIR/bin/qemu-system-arm
LIB=$DIR/lib
mkdir -p "$LIB"

# Libraries that ship with macOS are not copied.
is_system() { case $1 in /usr/lib/*|/System/*) return 0;; *) return 1;; esac; }

# Non-system dependencies of a Mach-O file, as written in its load commands.
# The first line of `otool -L` is the file itself; for a dylib the second is
# its own install name, which is skipped by comparing basenames.
deps() {
    otool -L "$1" | tail -n +2 | awk '{print $1}' | while read -r d; do
        is_system "$d" && continue
        [ "$(basename "$d")" = "$(basename "$1")" ] && continue
        echo "$d"
    done
}

# install_name_tool warns on every edit of a signed file; the files are all
# signed again below, so drop that one warning and keep any others.
change() {
    install_name_tool "$@" 2> >(grep -v 'will invalidate the code signature' >&2)
}

resolve() {
    # @rpath / @loader_path references inside Homebrew dylibs point at
    # siblings in the same prefix.
    case $1 in
        @rpath/*|@loader_path/*) echo "$(dirname "$2")/$(basename "$1")";;
        *) echo "$1";;
    esac
}

# Breadth-first over the dependency graph; every file is copied once.
queue=("$BIN")
seen=" "
while [ ${#queue[@]} -gt 0 ]; do
    f=${queue[0]}; queue=("${queue[@]:1}")
    src=$f
    [ "$f" = "$BIN" ] || src=$(cat "$LIB/.src-$(basename "$f")")
    for d in $(deps "$f"); do
        real=$(resolve "$d" "$src")
        name=$(basename "$real")
        if [ "$f" = "$BIN" ]; then
            change -change "$d" "@executable_path/../lib/$name" "$f"
        else
            change -change "$d" "@loader_path/$name" "$f"
        fi
        case $seen in *" $name "*) continue;; esac
        seen="$seen$name "
        [ -f "$real" ] || { echo "error: $real (needed by $f) not found" >&2; exit 1; }
        cp "$real" "$LIB/$name"
        chmod u+w "$LIB/$name"
        change -id "@loader_path/$name" "$LIB/$name"
        echo "$real" > "$LIB/.src-$name"
        queue+=("$LIB/$name")
    done
done
rm -f "$LIB"/.src-*

# install_name_tool invalidates the signatures; arm64 refuses to run
# unsigned code, so sign everything again (ad hoc, no identity).
for f in "$LIB"/*.dylib; do codesign --force -s - "$f" 2>/dev/null; done
codesign --force -s - --preserve-metadata=entitlements "$BIN" 2>/dev/null
codesign --verify "$BIN" "$LIB"/*.dylib

echo ">> bundled:" >&2
ls "$LIB" >&2
# Nothing may point outside the bundle or the system any more.
bad=$(for f in "$BIN" "$LIB"/*.dylib; do otool -L "$f" | tail -n +2 | awk '{print $1}'; done \
      | grep -v -e '^/usr/lib/' -e '^/System/' -e '^@executable_path/' -e '^@loader_path/' || true)
if [ -n "$bad" ]; then
    echo "error: unbundled references left:" >&2
    echo "$bad" >&2
    exit 1
fi
