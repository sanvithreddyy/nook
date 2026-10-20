#!/bin/zsh
# Exact average CPU of Nook over a 10 s window in each steady state (cumulative CPU time / wall time).
set -uo pipefail
cd "${0:A:h}/.."
app=build/Build/Products/Debug/Nook.app/Contents/MacOS/Nook
cputime() { ps -o time= -p $1 | awk -F'[:.]' '{ if (NF==3) print $1*60+$2+$3/100; else print $1*3600+$2*60+$3+$4/100 }'; }
# Keep the island visible over fullscreen apps for the run, then restore the user's setting.
saved=$(defaults read com.sanvith.nook hideInFullscreen 2>/dev/null || echo unset)
restore() { if [[ $saved == unset ]]; then defaults delete com.sanvith.nook hideInFullscreen 2>/dev/null; else defaults write com.sanvith.nook hideInFullscreen -bool $saved; fi; }
trap restore EXIT
defaults write com.sanvith.nook hideInFullscreen -bool false
for mode in "" "-preview-playing" "-preview-playing -peek" "-preview-playing -expand"; do
  $app ${=mode} >/dev/null 2>&1 &
  pid=$!
  sleep 4
  a=$(cputime $pid); sleep 10; b=$(cputime $pid)
  printf "%-28s %5.2f%%\n" "${mode:-idle}" $(( (b - a) * 10 ))
  kill $pid; sleep 0.5
done
