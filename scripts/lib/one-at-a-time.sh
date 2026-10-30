# Sourced by scripts that launch Nook. Each copy draws its own panel over the notch, so two runs at
# once would spoil each other's captures and timings: wait for the other run, and clear a lock whose
# script has died.
nook_lock() {
  local lock=${TMPDIR:-/tmp}/nook-run.lock owner
  while ! mkdir $lock 2>/dev/null; do
    owner=$(cat $lock/pid 2>/dev/null)
    if [[ -n $owner ]] && ! kill -0 $owner 2>/dev/null; then rm -rf $lock; continue; fi
    sleep 1
  done
  echo $$ > $lock/pid
  NOOK_LOCK=$lock
}

# Keeps the island visible to this run, over full-screen apps and in screen captures, whatever the
# user's settings say. nook_unlock puts their settings back.
typeset -ga NOOK_SAVED=()
nook_show() {
  local key
  for key in hideInFullscreen hideFromCapture; do
    NOOK_SAVED+=("$key" "$(defaults read com.sanvith.nook $key 2>/dev/null || echo unset)")
    defaults write com.sanvith.nook $key -bool false
  done
}

nook_unlock() {
  local i key saved
  for (( i = 1; i < ${#NOOK_SAVED[@]}; i += 2 )); do
    key=${NOOK_SAVED[i]}
    saved=${NOOK_SAVED[i+1]}
    if [[ $saved == unset ]]; then
      defaults delete com.sanvith.nook $key 2>/dev/null
    else
      defaults write com.sanvith.nook $key -bool $([[ $saved == 1 ]] && echo true || echo false)
    fi
  done
  NOOK_SAVED=()
  [[ -n ${NOOK_LOCK:-} ]] && rm -rf $NOOK_LOCK
  return 0
}
