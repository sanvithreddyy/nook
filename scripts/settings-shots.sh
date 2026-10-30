#!/bin/zsh
# Captures each settings pane of the Debug build to build/settings. The window shows briefly
# without taking keyboard focus.
set -euo pipefail
cd "${0:A:h}/.."
source scripts/lib/one-at-a-time.sh
nook_lock
trap nook_unlock EXIT
out=build/settings; rm -rf $out; mkdir -p $out
app=build/Build/Products/Debug/Nook.app/Contents/MacOS/Nook
# TALL=1: the window as tall as the screen allows, and a second shot of each long page scrolled to its end.
flags=()
[[ -n ${TALL:-} ]] && flags=(-capture-tall -capture-end)
$app -settings-capture $flags 2>/dev/null | while read -r tag pane id; do
  [[ $tag == PANE ]] && { screencapture -x -o -l $id $out/$pane.png || echo "missed $pane"; }
done
ls $out
