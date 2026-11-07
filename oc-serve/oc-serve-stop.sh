#!/usr/bin/env bash
# Остановка сервера oc-serve из bash/ssh — тот же контракт, что у
# oc-serve-stop.cmd (для Windows-консоли):
#
#   * создать файл-флаг $STATE_DIR/stop -> watchdog лаунчера гасит сервер;
#   * ждать освобождения порта до 20 с;
#   * код 0 — сервер остановился, код 1 — порт всё ещё слушается.
#
# Порт берётся из того же места, что и в лаунчере: из алиаса `oc-serve`
# в ~/.bashrc (см. общий oc-serve-common.sh). Запасной путь — переменная
# окружения OC_SERVE_PORT, последний — 4096.

STATE_DIR="${OC_SERVE_LOG_DIR:-$HOME/.local/state/oc-serve}"
STOP="$STATE_DIR/stop"
LOG="$STATE_DIR/serve.log"
WAIT_SECS="${OC_SERVE_STOP_WAIT:-20}"

# --- общие помощники -------------------------------------------------------
HELPERS="${OC_SERVE_HELPERS:-}"
if [ -z "$HELPERS" ]; then
  for _cand in "$(dirname "$0")/oc-serve-common.sh" \
               "$HOME/.local/bin/oc-serve-common.sh"; do
    if [ -f "$_cand" ]; then HELPERS="$_cand"; break; fi
  done
fi
if [ ! -f "$HELPERS" ]; then
  echo "!! не найден oc-serve-common.sh (ожидается рядом с oc-serve-stop.sh: $(dirname "$0"))" >&2
  exit 1
fi
# shellcheck disable=SC1090
. "$HELPERS"

# Порт: алиас -> $OC_SERVE_PORT -> 4096.
# Алиас живёт в ~/.bashrc; подгружаем его так же, как это делает лаунчер.
oc_serve_load_bashrc >/dev/null 2>&1
port=$(oc_serve_port)
[ -n "$port" ] || port="${OC_SERVE_PORT:-4096}"

mkdir -p "$STATE_DIR" || exit 1

# Флаг остановки: его ждёт watchdog лаунчера.
: >"$STOP"

echo "Stop requested, waiting for the server to exit (port $port)..."

waited=0
while [ "$waited" -lt "$WAIT_SECS" ]; do
  if ! oc_serve_port_busy "$port"; then
    echo "Server stopped."
    exit 0
  fi
  sleep 1
  waited=$(( waited + 1 ))
done

echo "Still listening on port $port - see \"$LOG\""
exit 1
