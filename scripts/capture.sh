#!/bin/zsh
# Launches the Debug build with the given debug flags, captures the notch area, quits.
# Usage: scripts/capture.sh out.png -preview-playing -expand ...
set -uo pipefail
cd "${0:A:h}/.."
source scripts/lib/one-at-a-time.sh
nook_lock
out=$1; shift
app=build/Build/Products/Debug/Nook.app/Contents/MacOS/Nook
restore() { [[ -n ${pid:-} ]] && kill $pid 2>/dev/null; nook_unlock; }
trap restore EXIT
nook_show
$app "$@" >/dev/null 2>&1 &
pid=$!
sleep ${WAIT:-4}
w=$(osascript -l JavaScript -e 'ObjC.import("AppKit"); $.NSScreen.screens.objectAtIndex(0).frame.size.width' 2>/dev/null || echo 1512)
cw=${CW:-780}; x=$(( (${w%.*} - cw) / 2 ))
screencapture -x -R$x,0,$cw,${CH:-215} "$out"
