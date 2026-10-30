#!/bin/zsh
# Launches the Debug build with the given debug flags, captures the notch area, quits.
# Usage: scripts/capture.sh out.png -preview-playing -expand ...
set -uo pipefail
cd "${0:A:h}/.."
out=$1; shift
app=build/Build/Products/Debug/Nook.app/Contents/MacOS/Nook
saved=$(defaults read com.sanvith.nook hideInFullscreen 2>/dev/null || echo unset)
restore() { kill $pid 2>/dev/null; if [[ $saved == unset ]]; then defaults delete com.sanvith.nook hideInFullscreen 2>/dev/null; else defaults write com.sanvith.nook hideInFullscreen -bool $saved; fi; }
trap restore EXIT
defaults write com.sanvith.nook hideInFullscreen -bool false
$app "$@" >/dev/null 2>&1 &
pid=$!
sleep ${WAIT:-4}
w=$(osascript -l JavaScript -e 'ObjC.import("AppKit"); $.NSScreen.screens.objectAtIndex(0).frame.size.width' 2>/dev/null || echo 1512)
cw=${CW:-780}; x=$(( (${w%.*} - cw) / 2 ))
screencapture -x -R$x,0,$cw,${CH:-215} "$out"
