#!/bin/zsh
# Captures each settings pane of the Debug build to build/settings. The window shows briefly
# without taking keyboard focus.
set -euo pipefail
cd "${0:A:h}/.."
out=build/settings; rm -rf $out; mkdir -p $out
app=build/Build/Products/Debug/Nook.app/Contents/MacOS/Nook
$app -settings-capture 2>/dev/null | while read -r tag pane id; do
  [[ $tag == PANE ]] && screencapture -x -o -l $id $out/$pane.png
done
ls $out
