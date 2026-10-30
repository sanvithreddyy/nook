#!/bin/zsh
# Records the debug tour (every island state) to build/tour/tour.mov and extracts one still per step.
set -euo pipefail
cd "${0:A:h}/.."
source scripts/lib/one-at-a-time.sh
nook_lock
out=build/tour; rm -rf $out; mkdir -p $out
app=build/Build/Products/Debug/Nook.app/Contents/MacOS/Nook
pkill -f "$app" 2>/dev/null || true
# Recording happens over whatever is on screen, fullscreen apps included.
# On any exit, the recording and the tour's Nook stop too (background jobs don't get Control-C).
trap 'kill ${rec:-} ${appPID:-} 2>/dev/null || true; nook_unlock' EXIT
nook_show
screen_w=$(osascript -l JavaScript -e 'ObjC.import("AppKit"); $.NSScreen.screens.objectAtIndex(0).frame.size.width' 2>/dev/null || echo 1512)
w=820; h=260; x=$(( (${screen_w%.*} - w) / 2 ))
screencapture -x -v -V 52 -R$x,0,$w,$h $out/tour.mov &
rec=$!
sleep 0.5
start=$(python3 -c 'import time; print(time.time())')
echo $start > $out/start.txt
$app -tour > $out/tour.log 2>&1 &
appPID=$!
wait $rec
kill $appPID 2>/dev/null || true
# One still 1.2 s into each step.
grep '^TOUR' $out/tour.log | while read -r _ name ts; do
  offset=$(python3 -c "print(max(0, $ts - $start + 1.2))")
  ffmpeg -loglevel error -y -ss $offset -i $out/tour.mov -frames:v 1 $out/$name.png
done
ls $out
