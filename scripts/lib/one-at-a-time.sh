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

nook_unlock() { [[ -n ${NOOK_LOCK:-} ]] && rm -rf $NOOK_LOCK; return 0; }
