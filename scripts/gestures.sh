#!/bin/zsh
# Two-finger gestures on the open island through the app's own event path, then a check that no page
# was left part-way (FUZZ lines; STUCK is a failure). With -probe-swipes, each swipe's missed frames too
# (GESTURE lines); count frames on an optimized build (NOOK_APP), not the plain Debug one.
# Usage: scripts/gestures.sh [seed] [flags...]
#   scripts/gestures.sh 1                          random bursts (-gesture-fuzz-bursts N, default 60)
#   scripts/gestures.sh 1 -gesture-script "swipe+ 1.2 swipe- 1.2" -gesture-fuzz-bursts 4 -probe-swipes
# Script words: rest flick nudge pull updown tap swipe dot, + or - for the direction, ^ for a touch first,
# numbers for pauses. Where: -page N, -gesture-fuzz-x <fraction across>, -gesture-fuzz-list (over a list
# that scrolls), -gesture-fuzz-beside-list <pt from its left edge>; -preview-calendar for sample events.
set -uo pipefail
cd "${0:A:h}/.."
source scripts/lib/one-at-a-time.sh
nook_lock
app=${NOOK_APP:-build/Build/Products/Debug/Nook.app/Contents/MacOS/Nook}
[[ -x $app ]] || { echo "No build at $app: run scripts/build.sh first." >&2; exit 1; }
seed=${1:-1}
(( $# )) && shift
log=$(mktemp -t nook-gestures)
# Its own settings for the run, so it neither takes the pointer and volume keys nor hides itself.
$app -hideFromCapture NO -hideInFullscreen NO -ignore-pointer -volumeHUD NO -brightnessHUD NO \
  -preview-playing -preview-sample -expand -gesture-fuzz $seed "$@" > $log 2>&1 &
pid=$!
trap 'kill $pid 2>/dev/null; rm -f $log; nook_unlock' EXIT
while kill -0 $pid 2>/dev/null && ! grep -q "FUZZ done" $log; do sleep 0.5; done
grep -E "^(FUZZ|GESTURE)" $log
