#!/usr/bin/env bash
# Non-interactive launcher for the `oc-serve` alias from ~/.bashrc.
#
# Used by the Windows Task Scheduler task "opencode-serve", which runs it as
# the user in an S4U (non-interactive, no-window) session at boot / logon.
# The alias stays the single source of truth for the command line
# (hostname / port / CORS); this script only adds what a scheduler run lacks:
# a login-shell PATH (from .bashrc) and a log file instead of a console.
#
# Stopping: Task Scheduler's "End task" does NOT terminate this process tree
# on this host (verified: the task goes Ready, bash + the server stay alive),
# and a cross-session Stop-Process from the desktop gets Access denied. So the
# server is started as a child and stopped by dropping a flag file:
#
#   oc-serve-stop.cmd            (creates $LOG_DIR/stop)
#
# The watchdog polls the flag, terminates the server and exits 0, so the task
# ends cleanly and the "restart on failure" policy does not resurrect it.

LOG_DIR="${OC_SERVE_LOG_DIR:-$HOME/.local/state/oc-serve}"
STOP="$LOG_DIR/stop"
STOPPED="$LOG_DIR/.stopped"
mkdir -p "$LOG_DIR" || exit 1

# No console: everything the server prints goes to the log.
exec >>"$LOG_DIR/serve.log" 2>&1
echo "=== $(date '+%Y-%m-%dT%H:%M:%S%z') start pid=$$ HOME=$HOME PWD=$PWD ==="

# stale stop request from a previous run must not kill the fresh server
rm -f "$STOP" "$STOPPED"

if [ ! -f "$HOME/.bashrc" ]; then
  echo "!! $HOME/.bashrc not found (HOME=$HOME)" >&2
  exit 1
fi

shopt -s expand_aliases
# shellcheck disable=SC1090
. "$HOME/.bashrc"

if ! alias oc-serve >/dev/null 2>&1; then
  echo "!! no 'oc-serve' alias after sourcing ~/.bashrc" >&2
  exit 1
fi
echo "--- $(alias oc-serve)"

# Guard against losing a race with another instance (a manual `oc-serve` in a
# terminal, a leftover from before a reboot): treat "already listening" as done
# instead of failing and entering the restart loop.
port=$(alias oc-serve | sed -n 's/.*--port[ =]\([0-9]\{1,\}\).*/\1/p')
if [ -n "$port" ] && (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
  exec 3>&- 3<&-
  echo "--- 127.0.0.1:$port already listening, not starting a second instance"
  echo "=== $(date '+%Y-%m-%dT%H:%M:%S%z') exit rc=0 (port busy) ==="
  exit 0
fi

oc-serve &
child=$!
echo "--- server pid=$child"

(
  while sleep 2; do
    [ -e "$STOP" ] || continue
    rm -f "$STOP"
    : >"$STOPPED"
    echo "--- stop requested, terminating pid=$child"
    kill "$child" 2>/dev/null
    sleep 3
    kill -9 "$child" 2>/dev/null
    exit 0
  done
) &
watchdog=$!

wait "$child"
rc=$?
kill "$watchdog" 2>/dev/null
wait "$watchdog" 2>/dev/null

if [ -e "$STOPPED" ]; then
  rm -f "$STOPPED"
  echo "=== $(date '+%Y-%m-%dT%H:%M:%S%z') stopped by request ==="
  exit 0
fi
echo "=== $(date '+%Y-%m-%dT%H:%M:%S%z') exit rc=$rc ==="
exit "$rc"
