# Sourced by scripts that launch Nook. Each copy draws its own panel over the notch, so two runs at
# once would spoil each other's captures and timings: wait for the other run, and clear a lock whose
# script has died, putting back any settings it was holding.
nook_lock() {
  local lock=${TMPDIR:-/tmp}/nook-run.lock owner
  while ! mkdir $lock 2>/dev/null; do
    owner=$(cat $lock/pid 2>/dev/null)
    if [[ -n $owner ]] && ! kill -0 $owner 2>/dev/null; then
      nook_restore $lock/saved
      rm -rf $lock
      continue
    fi
    sleep 1
  done
  echo $$ > $lock/pid
  NOOK_LOCK=$lock
  # zsh runs EXIT traps on a normal exit but not on Control-C or a kill; exiting from those runs it.
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

# Keeps the island visible to this run, over full-screen apps and in screen captures, whatever the
# user's settings say. Their values wait in the lock, so nook_unlock (or the next run, if this one
# was killed outright) puts them back.
nook_show() {
  local key
  [[ -f $NOOK_LOCK/saved ]] && return 0
  for key in hideInFullscreen hideFromCapture; do
    echo "$key $(defaults read com.sanvith.nook $key 2>/dev/null || echo unset)" >> $NOOK_LOCK/saved
    defaults write com.sanvith.nook $key -bool false
  done
}

nook_restore() {
  local key saved
  [[ -f $1 ]] || return 0
  while read -r key saved; do
    if [[ $saved == unset ]]; then
      defaults delete com.sanvith.nook $key 2>/dev/null
    else
      defaults write com.sanvith.nook $key -bool $([[ $saved == 1 ]] && echo true || echo false)
    fi
  done < $1
}

nook_unlock() {
  [[ -n ${NOOK_LOCK:-} ]] || return 0
  nook_restore $NOOK_LOCK/saved
  rm -rf $NOOK_LOCK
  NOOK_LOCK=
  return 0
}
