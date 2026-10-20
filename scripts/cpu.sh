#!/bin/zsh
# Samples Nook's CPU for 8 s with a track shown as playing (live activity + waveform), then idle.
set -euo pipefail
cd "${0:A:h}/.."
app=build/Build/Products/Debug/Nook.app/Contents/MacOS/Nook
defaults write com.sanvith.nook hideInFullscreen -bool false
$app -preview-playing >/dev/null 2>&1 &
pid=$!
sleep 3
echo "playing (live activity):"; top -pid $pid -l 9 -s 1 -stats cpu | grep -E '^[0-9.]+$' | tail -8 | tr '\n' ' '; echo
kill $pid
$app >/dev/null 2>&1 &
pid=$!
sleep 3
echo "idle:"; top -pid $pid -l 5 -s 1 -stats cpu | grep -E '^[0-9.]+$' | tail -4 | tr '\n' ' '; echo
kill $pid
defaults delete com.sanvith.nook hideInFullscreen
