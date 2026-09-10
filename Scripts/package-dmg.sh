#!/bin/sh
set -eu

build_dir=${1:-.build}
architecture=${2:-arm64}
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# Keep packaging dependencies local to the build directory.
if [ -z "${DMGBUILD:-}" ]; then
    if [ ! -x "$build_dir/dmg-tools/bin/python" ]; then
        python3 -m venv "$build_dir/dmg-tools"
    fi
    "$build_dir/dmg-tools/bin/python" -m pip install --disable-pip-version-check \
        -r "$script_dir/dmg-requirements.txt"
    DMGBUILD="$build_dir/dmg-tools/bin/dmgbuild"
fi

swiftc -o "$build_dir/make-dmg-background" "$script_dir/make-dmg-background.swift" -framework AppKit
"$build_dir/make-dmg-background" "$build_dir/Installer.tiff"

# Replace the output only when the new image is complete.
stage=$(mktemp -d "${TMPDIR:-/tmp}/macos-ultrabright-dmg.XXXXXX")
trap 'rm -rf "$stage"' EXIT HUP INT TERM
"$DMGBUILD" -s "$script_dir/dmg-settings.py" -D "build_dir=$build_dir" \
    "MacOS Ultrabright" "$stage/installer.dmg"
mv -f "$stage/installer.dmg" "$build_dir/MacOS-Ultrabright-$architecture.dmg"
