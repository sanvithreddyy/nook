#!/bin/zsh
# Renders every island state over a system wallpaper to build/snapshots (Debug build).
set -euo pipefail
cd "${0:A:h}/.."
out=build/snapshots; rm -rf $out; mkdir -p $out
build/Build/Products/Debug/Nook.app/Contents/MacOS/Nook -snapshots "$PWD/$out" >/dev/null 2>&1
ls $out
