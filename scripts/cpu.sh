#!/bin/zsh
# Exact average CPU of Nook over a 10 s window in each steady state (cumulative CPU time / wall time).
set -uo pipefail
cd "${0:A:h}/.."
source scripts/lib/one-at-a-time.sh
nook_lock
# CONFIG=Release measures the build people run (it has no preview flags, so only its real state).
app=build/Build/Products/${CONFIG:-Debug}/Nook.app/Contents/MacOS/Nook
cputime() { ps -o time= -p $1 | awk -F'[:.]' '{ if (NF==3) print $1*60+$2+$3/100; else print $1*3600+$2*60+$3+$4/100 }'; }
# Keep the island visible over fullscreen apps for the run, then restore the user's setting.
saved=$(defaults read com.sanvith.nook hideInFullscreen 2>/dev/null || echo unset)
restore() { [[ -n ${pid:-} ]] && kill $pid 2>/dev/null; if [[ $saved == unset ]]; then defaults delete com.sanvith.nook hideInFullscreen 2>/dev/null; else defaults write com.sanvith.nook hideInFullscreen -bool $([[ $saved == 1 ]] && echo true || echo false); fi; nook_unlock; }
trap restore EXIT
defaults write com.sanvith.nook hideInFullscreen -bool false
modes=("" "-preview-playing" "-preview-playing -peek" "-preview-playing -preview-calendar -preview-batteries -expand")
[[ ${CONFIG:-Debug} == Release ]] && modes=("")
for mode in "${modes[@]}"; do
  $app ${=mode} >/dev/null 2>&1 &
  pid=$!
  sleep 4
  a=$(cputime $pid); sleep 10; b=$(cputime $pid)
  printf "%-28s %5.2f%%  %4d MB\n" "${mode:-idle}" $(( (b - a) * 10 )) $(( $(ps -o rss= -p $pid) / 1024 ))
  kill $pid; sleep 0.5
done
