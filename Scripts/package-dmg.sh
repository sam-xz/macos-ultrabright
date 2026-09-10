#!/bin/sh
set -eu

build_dir=${1:-.build}
architecture=${2:-arm64}
stage=$(mktemp -d "${TMPDIR:-/tmp}/macos-ultrabright-dmg.XXXXXX")
trap 'rm -rf "$stage"' EXIT HUP INT TERM
ditto "$build_dir/MacOS Ultrabright.app" "$stage/MacOS Ultrabright.app"
ln -s /Applications "$stage/Applications"
cp "$build_dir/INSTALL.txt" "$stage/INSTALL.txt"
hdiutil create -volname "MacOS Ultrabright" -srcfolder "$stage" -ov -format UDZO \
    "$build_dir/MacOS-Ultrabright-$architecture.dmg"
