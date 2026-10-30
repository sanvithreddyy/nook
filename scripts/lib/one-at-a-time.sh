# Sourced by scripts that launch Nook. Each copy draws its own panel over the notch, so two runs at
# once would spoil each other's captures and timings: wait for the other run. The lock is the
# kernel's, so a run that dies, however it dies, lets go of it.
zmodload zsh/system

nook_lock() {
  local base=${TMPDIR:-/tmp}/nook-run
  NOOK_SAVED_FILE=$base.saved
  # Waits for the run before; closed for anything this script starts, so a Nook it launches doesn't
  # hold the lock after the script is gone.
  : >> $base.flock
  zsystem flock -f NOOK_LOCK_FD $base.flock
  # Settings a run that was killed outright was still holding come back first.
  nook_restore $NOOK_SAVED_FILE
  rm -f $NOOK_SAVED_FILE
  # zsh runs EXIT traps on a normal exit but not on Control-C or a kill; exiting from those runs it.
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

# Keeps the island visible to this run, over full-screen apps and in screen captures, whatever the
# user's settings say. Their values wait beside the lock, so nook_unlock (or the next run, if this one
# was killed outright) puts them back.
nook_show() {
  local key
  [[ -n ${NOOK_LOCK_FD:-} ]] || { echo "nook_show: take the lock first" >&2; return 1; }
  [[ -f $NOOK_SAVED_FILE ]] && return 0
  for key in hideInFullscreen hideFromCapture; do
    echo "$key $(defaults read com.sanvith.nook $key 2>/dev/null || echo unset)" >> $NOOK_SAVED_FILE
    defaults write com.sanvith.nook $key -bool false
  done
}

nook_restore() {
  local key saved
  [[ -f $1 ]] || return 0
  while read -r key saved; do
    if [[ $saved == unset ]]; then
      defaults delete com.sanvith.nook $key 2>/dev/null || true
    else
      defaults write com.sanvith.nook $key -bool $([[ $saved == 1 ]] && echo true || echo false) || true
    fi
  done < $1
}

nook_unlock() {
  [[ -n ${NOOK_LOCK_FD:-} ]] || return 0
  nook_restore $NOOK_SAVED_FILE
  rm -f $NOOK_SAVED_FILE
  zsystem flock -u $NOOK_LOCK_FD
  NOOK_LOCK_FD=
  return 0
}
