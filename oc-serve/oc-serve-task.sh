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
#   oc-serve-stop.sh / oc-serve-stop.cmd     (создают $LOG_DIR/stop)
#
# The watchdog polls the flag, terminates the server and exits 0, so the task
# ends cleanly and the "restart on failure" policy does not resurrect it.
#
# Что лаунчер делает сверх этого (2026-10-29, после инцидента rc=127):
#   * стартует с приватной копии себя — перезапись файла лаунчера на лету
#     (обновление) больше не ломает уже работающий экземпляр;
#   * ротирует serve.log (OC_SERVE_LOG_MAX_KB, по умолчанию 512 КБ);
#   * пишет в лог, чего не хватило: бинарь, PATH, код возврата сервера;
#   * замечает, если файл лаунчера переписали во время работы.

LOG_DIR="${OC_SERVE_LOG_DIR:-$HOME/.local/state/oc-serve}"
LOG="$LOG_DIR/serve.log"
STOP="$LOG_DIR/stop"
STOPPED="$LOG_DIR/.stopped"
LOG_MAX_KB="${OC_SERVE_LOG_MAX_KB:-512}"

# --- общие помощники (oc-serve-common.sh) ---------------------------------
# Путь запоминаем в переменной окружения: после старта с приватной копии
# $0 указывает уже на копию, а общий файл лежит рядом с оригиналом.
HELPERS="${OC_SERVE_HELPERS:-}"
if [ -z "$HELPERS" ]; then
  for _cand in "$(dirname "$0")/oc-serve-common.sh" \
               "$HOME/.local/bin/oc-serve-common.sh"; do
    if [ -f "$_cand" ]; then HELPERS="$_cand"; break; fi
  done
fi
if [ ! -f "$HELPERS" ]; then
  echo "!! не найден oc-serve-common.sh (ожидается рядом с лаунчером: $(dirname "$0"))" >&2
  exit 1
fi
export OC_SERVE_HELPERS="$HELPERS"
# shellcheck disable=SC1090
. "$HELPERS"

mkdir -p "$LOG_DIR" || exit 1

# --- приватная копия: защита от перезаписи файла на лету -------------------
# bash читает скрипт по мере выполнения (файл открыт и перечитывается), и
# если файл переписать, пока экземпляр работает, он начнёт выполнять мусор:
# в логе это видно как "syntax error near unexpected token `then'" или как
# "exit rc=127" (bash: команда не найдена). Проверено на vetymae: файл
# лаунчера перезаписали в 13:47:04, а работавший с 13:41:14 экземпляр
# умер в 13:48:00 с rc=127.
# Поэтому первый же запуск делает приватную копию и продолжает уже из неё:
# перезапись оригинала больше никого не ломает.
if [ "${OC_SERVE_SELF_COPY:-0}" != "1" ]; then
  _self="$0"
  _copy="$LOG_DIR/.oc-serve-task.$$.sh"
  export OC_SERVE_SRC_PATH="$_self"
  OC_SERVE_SRC_STAMP="$(oc_serve_file_stamp "$_self")"
  export OC_SERVE_SRC_STAMP
  if cp -- "$_self" "$_copy" 2>/dev/null; then
    OC_SERVE_SELF_COPY=1
    export OC_SERVE_SELF_COPY
    exec bash "$_copy"
  fi
  echo "!! не удалось сделать приватную копию ($_self -> $_copy), работаю из исходного файла" >&2
fi

# Убрать приватную копию на выходе (только свою: чужие копии не трогаем).
finish() {
  if [ "${OC_SERVE_SELF_COPY:-0}" = "1" ]; then rm -f -- "$0" 2>/dev/null; fi
  exit "$1"
}

# --- лог -------------------------------------------------------------------
# Ротация ДО первого `exec >>`: после открытия файла на запись сдвинуть его
# уже нельзя (на Windows файл держит открытым сам сервер).
rotated=""
rotate_failed=0
rotated=$(oc_serve_rotate_log "$LOG" "$LOG_MAX_KB") || rotate_failed=1

exec >>"$LOG" 2>&1
echo "=== $(date '+%Y-%m-%dT%H:%M:%S%z') start pid=$$ HOME=$HOME PWD=$PWD ==="
[ -n "$rotated" ] && echo "--- $rotated"
[ "$rotate_failed" = "1" ] && echo "!! не удалось сдвинуть $LOG (файл держит другой процесс?)"

# stale stop request from a previous run must not kill the fresh server
rm -f "$STOP" "$STOPPED"

if [ ! -f "$HOME/.bashrc" ]; then
  echo "!! $HOME/.bashrc not found (HOME=$HOME)" >&2
  finish 1
fi

if ! oc_serve_load_bashrc; then
  echo "!! нет алиаса oc-serve после подгрузки $HOME/.bashrc" >&2
  finish 1
fi
echo "--- $(alias oc-serve)"

# --- диагностика окружения -------------------------------------------------
# Пишется один раз за запуск, но всегда: по логу должно быть видно, что
# запускалось, чем и из какого PATH — иначе падение объяснить нечем.
CMD=$(oc_serve_alias_body)
BIN=$(oc_serve_alias_bin)
echo "--- command: $CMD"
echo "--- binary : $BIN -> $(command -v "$BIN" 2>/dev/null || printf 'НЕ НАЙДЕН в PATH')"
echo "--- PATH   : $PATH"

# Guard against losing a race with another instance (a manual `oc-serve` in a
# terminal, a leftover from before a reboot): treat "already listening" as done
# instead of failing and entering the restart loop.
port=$(oc_serve_port)
if [ -n "$port" ] && oc_serve_port_busy "$port"; then
  echo "--- 127.0.0.1:$port already listening, not starting a second instance"
  echo "=== $(date '+%Y-%m-%dT%H:%M:%S%z') exit rc=0 (port busy) ==="
  finish 0
fi

# 127 — это код bash «команда не найдена». Если исполняемого файла нет в
# PATH, запускать всё равно нечего: говорим, чего не хватило, и выходим
# с тем же кодом, который иначе поймал бы Task Scheduler.
if [ -z "$BIN" ]; then
  echo "!! алиас oc-serve пустой, нечего запускать" >&2
  finish 127
fi
if ! command -v "$BIN" >/dev/null 2>&1; then
  echo "!! $BIN не найден в PATH, PATH=$PATH" >&2
  finish 127
fi

oc-serve &
child=$!
echo "--- server pid=$child"

(
  deploy_warned=""
  while sleep 2; do
    if [ -e "$STOP" ]; then
      rm -f "$STOP"
      : >"$STOPPED"
      echo "--- stop requested, terminating pid=$child"
      kill "$child" 2>/dev/null
      sleep 3
      kill -9 "$child" 2>/dev/null
      exit 0
    fi
    # файл лаунчера переписали, пока мы работаем (обновление на лету)
    if [ -z "$deploy_warned" ] && [ -n "${OC_SERVE_SRC_STAMP:-}" ]; then
      _now=$(oc_serve_file_stamp "${OC_SERVE_SRC_PATH:-}")
      if [ -n "$_now" ] && [ "$_now" != "$OC_SERVE_SRC_STAMP" ]; then
        echo "!! файл лаунчера $OC_SERVE_SRC_PATH изменился во время работы — это обновление поверх работающего экземпляра (сам экземпляр продолжает из приватной копии)"
        deploy_warned=1
      fi
    fi
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
  finish 0
fi

if [ "$rc" != "0" ]; then
  echo "!! сервер завершился с rc=$rc — что не так:"
  echo "--- command: $CMD"
  echo "--- binary : $BIN -> $(command -v "$BIN" 2>/dev/null || printf 'НЕ НАЙДЕН в PATH')"
  echo "--- PATH   : $PATH"
  if [ "$rc" = "127" ]; then
    echo "!! rc=127 — это код bash «команда не найдена»: либо $BIN исчез из PATH, либо файл лаунчера переписали во время работы (bash перечитал файл и выполнил мусор)"
  fi
  if [ -n "$port" ] && oc_serve_port_busy "$port"; then
    echo "--- порт $port всё ещё слушается — процесс сервера мог остаться жить"
  else
    echo "--- порт $port свободен — сервер действительно умер"
  fi
fi

if [ -n "${OC_SERVE_SRC_STAMP:-}" ]; then
  _now=$(oc_serve_file_stamp "${OC_SERVE_SRC_PATH:-}")
  if [ -n "$_now" ] && [ "$_now" != "$OC_SERVE_SRC_STAMP" ]; then
    echo "!! файл лаунчера $OC_SERVE_SRC_PATH изменился во время работы (было '$OC_SERVE_SRC_STAMP', стало '$_now')"
  fi
fi

echo "=== $(date '+%Y-%m-%dT%H:%M:%S%z') exit rc=$rc ==="
finish "$rc"
