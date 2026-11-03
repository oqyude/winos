#!/usr/bin/env bash
# opencode-serve.sh -- the launcher of the opencode server.
#
# ONE launcher, ONE behaviour. The two hosts this replaces did the same
# thing in two different ways: one read ~/.bashrc and leaned on an alias,
# the other did not. A launcher that reads the profile of the user is a
# launcher whose behaviour depends on what the profile happens to export
# today; this one reads nothing but its own directory and the environment.
#
# Everything it needs is inside this file:
#
#   * the egress proxy (HTTP_PROXY / HTTPS_PROXY / NO_PROXY)
#   * OPENCODE_CONFIG_CONTENT -- the step cap of the build agent
#   * the CORS origin, derived from the hostname of the machine
#   * the log and its rotation
#   * the stop flag
#
# The layout. ROOT is the parent of the directory this file lives in:
#
#   <root>/host-scripts/opencode-serve.sh   this file
#   <root>/cache/opencode-serve.log         the log; rotated to .1
#   <root>/runtime/opencode-serve.stop      the stop flag
#   <root>/runtime/opencode-serve.pid       the pid of the running server
#
# The verbs:
#
#   (none) | start   run the server in the foreground (this is what the
#                    scheduled task does)
#   stop            ask the running server to stop (writes the stop flag)
#   status          say whether the server runs and where the log is
#
# The environment overrides the defaults; the defaults are the ones from
# docs/opencode-registry.md.

set -u

# --- where we are ---------------------------------------------------------
# The path of this file may come from Windows (the .cmd wrapper passes it
# as it is), so it is normalised first: Git Bash understands "C:\..." but
# not every bash does.
self="${BASH_SOURCE[0]:-$0}"
if command -v cygpath >/dev/null 2>&1; then
    self="$(cygpath -u "$self" 2>/dev/null || printf '%s' "$self")"
fi
SCRIPT_DIR="$(cd -- "$(dirname -- "$self")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

CACHE_DIR="$ROOT/cache"
RUNTIME_DIR="$ROOT/runtime"
LOG_FILE="$CACHE_DIR/opencode-serve.log"
STOP_FLAG="$RUNTIME_DIR/opencode-serve.stop"
PID_FILE="$RUNTIME_DIR/opencode-serve.pid"

# --- the knobs ------------------------------------------------------------
LOG_MAX_KB="${LOG_MAX_KB:-512}"
SERVE_HOST="${OPENCODE_HOST:-0.0.0.0}"
SERVE_PORT="${OPENCODE_PORT:-4096}"
CORS_SUFFIX="${OPENCODE_CORS_SUFFIX:-opencodes.zeroq.su}"
PROXY_URL="${OPENCODE_PROXY_URL:-http://127.0.0.1:10808}"
NO_PROXY_VALUE="${OPENCODE_NO_PROXY:-localhost,127.0.0.1,::1,192.168.1.0/24,100.64.0.0/10,.local,.zeroq.su,.su}"
AGENT_STEPS="${OPENCODE_AGENT_STEPS:-200}"

# --- the environment the server needs -------------------------------------
# The proxy is exported HERE, not inherited from the profile of the user:
# the server starts without a shell, and a server without the proxy cannot
# load the provider registry (docs/opencode-registry.md, section 0.1).
export HTTP_PROXY="${HTTP_PROXY:-$PROXY_URL}"
export HTTPS_PROXY="${HTTPS_PROXY:-$PROXY_URL}"
export NO_PROXY="${NO_PROXY:-$NO_PROXY_VALUE}"

# The step cap of the build agent. The default limit of opencode is lower
# than what a long build needs, and the limit is not a secret -- it belongs
# in the launcher, next to everything else the server needs.
if [ -z "${OPENCODE_CONFIG_CONTENT:-}" ]; then
    OPENCODE_CONFIG_CONTENT='{"agent":{"build":{"steps":'"$AGENT_STEPS"'}}}'
fi
export OPENCODE_CONFIG_CONTENT

machine_hostname() {
    # The name of this machine, for the CORS origin. The order matters:
    # `hostname` on Windows is the Windows one, and it wins.
    local name=""
    if command -v hostname >/dev/null 2>&1; then
        name="$(hostname 2>/dev/null || true)"
    fi
    if [ -z "$name" ] && command -v uname >/dev/null 2>&1; then
        name="$(uname -n 2>/dev/null || true)"
    fi
    if [ -z "$name" ]; then
        name="${COMPUTERNAME:-localhost}"
    fi
    printf '%s' "$name"
}

CORS_ORIGIN="https://$(machine_hostname).${CORS_SUFFIX}"

# --- the binary -----------------------------------------------------------
resolve_binary() {
    # The opencode binary, in the order of how sure we are about it:
    #
    #   1. the scoop junction <scoop>/apps/opencode2/current, resolved with
    #      readlink -f -- the junction points at the versioned directory, and
    #      the version moves;
    #   2. the PATH.
    #
    # The fallback is not decoration: a machine can have opencode installed
    # by npm, or by a package manager that is not scoop.
    local scoop_root="${SCOOP_ROOT:-}"
    if [ -z "$scoop_root" ] && [ -n "${USERPROFILE:-}" ]; then
        scoop_root="$USERPROFILE/scoop"
    fi
    if [ -z "$scoop_root" ] && [ -n "${HOME:-}" ]; then
        scoop_root="$HOME/scoop"
    fi

    local link="$scoop_root/apps/opencode2/current"
    local resolved=""
    if [ -n "$scoop_root" ] && [ -e "$link" ]; then
        resolved="$(readlink -f "$link" 2>/dev/null || true)"
        for candidate in \
            "$resolved/opencode.exe" "$resolved/opencode" \
            "$link/opencode.exe" "$link/opencode"
        do
            if [ -x "$candidate" ]; then
                printf '%s' "$candidate"
                return 0
            fi
        done
    fi

    local on_path
    on_path="$(command -v opencode 2>/dev/null || true)"
    if [ -n "$on_path" ]; then
        printf '%s' "$on_path"
        return 0
    fi
    return 1
}

# --- the log --------------------------------------------------------------
rotate_log_if_needed() {
    # The log grows without bound otherwise, and a log nobody can open is a
    # log nobody reads.
    #
    # The rotation COPIES and truncates instead of moving the file: the
    # server writes to the file through an open handle, and a moved file
    # would leave it writing into the rotated copy forever.
    [ -f "$LOG_FILE" ] || return 0
    local size_bytes
    size_bytes="$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)"
    if [ "$((size_bytes / 1024))" -ge "$LOG_MAX_KB" ]; then
        cp -f "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null || true
        : > "$LOG_FILE" 2>/dev/null || true
    fi
}

log_line() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE" 2>/dev/null || true
}

# --- the verbs ------------------------------------------------------------
start_server() {
    mkdir -p "$CACHE_DIR" "$RUNTIME_DIR" 2>/dev/null || true

    # A stop request that nobody answered. The server must not start into
    # it, or it would stop again a second later.
    rm -f "$STOP_FLAG" 2>/dev/null || true

    local binary
    if ! binary="$(resolve_binary)"; then
        echo "opencode-serve: the opencode binary is not found" >&2
        echo "opencode-serve: looked in <scoop>/apps/opencode2/current and in PATH" >&2
        return 1
    fi

    rotate_log_if_needed
    log_line "starting: $binary serve --hostname $SERVE_HOST --port $SERVE_PORT --cors $CORS_ORIGIN"

    "$binary" serve \
        --hostname "$SERVE_HOST" \
        --port "$SERVE_PORT" \
        --cors "$CORS_ORIGIN" >> "$LOG_FILE" 2>&1 &
    local server_pid=$!
    printf '%s' "$server_pid" > "$PID_FILE" 2>/dev/null || true

    while kill -0 "$server_pid" 2>/dev/null; do
        if [ -f "$STOP_FLAG" ]; then
            rm -f "$STOP_FLAG" 2>/dev/null || true
            log_line "stop flag found, stopping the server (pid $server_pid)"
            kill "$server_pid" 2>/dev/null || true
            wait "$server_pid" 2>/dev/null || true
            rm -f "$PID_FILE" 2>/dev/null || true
            return 0
        fi
        rotate_log_if_needed
        sleep 2
    done

    rm -f "$PID_FILE" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null
    return $?
}

stop_server() {
    mkdir -p "$RUNTIME_DIR" 2>/dev/null || true
    printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" > "$STOP_FLAG" 2>/dev/null || true
    echo "opencode-serve: stop flag written ($STOP_FLAG)"
    return 0
}

status_server() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "opencode-serve: running (pid $pid)"
            echo "opencode-serve: log $LOG_FILE"
            return 0
        fi
    fi
    echo "opencode-serve: not running"
    echo "opencode-serve: log $LOG_FILE"
    return 1
}

case "${1:-start}" in
    start)
        start_server
        ;;
    stop)
        stop_server
        ;;
    status)
        status_server
        ;;
    *)
        echo "usage: $(basename -- "$self") [start|stop|status]" >&2
        exit 2
        ;;
esac
