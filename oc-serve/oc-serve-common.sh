#!/usr/bin/env bash
# Общие помощники для oc-serve-task.sh и oc-serve-stop.sh.
#
# Файл только читается (source) — сам по себе ничего не выполняет.
# Вынесен отдельно, чтобы лаунчер и стоп-хелпер не разъезжались:
#   * где лежит состояние (LOG_DIR) и флаги остановки;
#   * как достать команду и порт из алиаса `oc-serve` в ~/.bashrc
#     (алиас остаётся единственным источником командной строки);
#   * как проверить, слушает ли порт;
#   * как ротировать лог.
#
# Лаунчер и стоп лежат рядом (обычно %USERPROFILE%\.local\bin).

[ -n "${__OC_SERVE_COMMON_LOADED:-}" ] && return 0
__OC_SERVE_COMMON_LOADED=1

# --- состояние -------------------------------------------------------------

# Каталог состояния: лог, флаги остановки.
oc_serve_state_dir() {
  printf '%s\n' "${OC_SERVE_LOG_DIR:-$HOME/.local/state/oc-serve}"
}

# --- ~/.bashrc --------------------------------------------------------------

# Подгружает ~/.bashrc: алиас `oc-serve`, OPENCODE_SERVER_PASSWORD, PATH scoop.
# Возвращает 0, если после подгрузки есть алиас `oc-serve`.
# Вывод .bashrc не глушим: в неинтерактивной сессии он всё равно пуст
# (на хосте есть явный guard для non-interactive), зато видно, если .bashrc
# вдруг начнёт что-то печатать.
oc_serve_load_bashrc() {
  [ -r "$HOME/.bashrc" ] || return 1
  shopt -s expand_aliases 2>/dev/null
  # shellcheck disable=SC1090,SC1091
  . "$HOME/.bashrc"
  alias oc-serve >/dev/null 2>&1
}

# Тело алиаса `oc-serve` без обрамляющих кавычек:
#   opencode serve --hostname 0.0.0.0 --port 4096 --cors https://…
oc_serve_alias_body() {
  local line
  line=$(alias oc-serve 2>/dev/null) || return 1
  line=${line#alias oc-serve=}
  case "$line" in
    \'*\') line=${line#\'}; line=${line%\'} ;;
    \"*\") line=${line#\"}; line=${line%\"} ;;
  esac
  printf '%s\n' "$line"
}

# Порт из алиаса (--port N или --port=N). Пусто, если порта в алиасе нет.
oc_serve_port() {
  oc_serve_alias_body 2>/dev/null |
    sed -n 's/.*--port[ =]\([0-9]\{1,\}\).*/\1/p' | head -n 1
}

# Исполняемый файл из алиаса (первое слово команды).
oc_serve_alias_bin() {
  local cmd
  cmd=$(oc_serve_alias_body 2>/dev/null) || return 1
  cmd=${cmd#"${cmd%%[![:space:]]*}"}
  printf '%s\n' "${cmd%%[[:space:]]*}"
}

# --- порт ------------------------------------------------------------------

# Слушает ли кто-то 127.0.0.1:$port. Тот же способ, что и у лаунчера
# (проверка занятости порта перед стартом второго экземпляра).
oc_serve_port_busy() {
  local port="${1:-}"
  [ -n "$port" ] || return 1
  (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null
}

# --- лог -------------------------------------------------------------------

# Ротация лога: serve.log -> serve.log.1 (одна копия, без цепочки).
# Печатает в stdout описание ротации (если была) — вызывающий сам решает,
# куда его положить. 0 = ок, 1 = сдвинуть не удалось (файл занят).
oc_serve_rotate_log() {
  local log="${1:-}" max_kb="${2:-512}"
  local bytes max_bytes stamp

  case "$max_kb" in ''|*[!0-9]*) max_kb=512 ;; esac
  [ -n "$log" ] || return 0
  [ -f "$log" ] || return 0

  bytes=$(wc -c <"$log" 2>/dev/null | tr -d ' ')
  case "$bytes" in ''|*[!0-9]*) return 0 ;; esac
  max_bytes=$(( max_kb * 1024 ))
  [ "$bytes" -gt "$max_bytes" ] || return 0

  if ! mv -f "$log" "$log.1" 2>/dev/null; then
    return 1
  fi
  stamp=$(date '+%Y-%m-%dT%H:%M:%S%z')
  printf -- '%s rotated %s (%s bytes > %s KB) -> %s.1\n' \
    "$stamp" "$log" "$bytes" "$max_kb" "$log" >>"$log.1"
  printf -- '%s rotated %s (%s bytes > %s KB) -> %s.1\n' \
    "$stamp" "$log" "$bytes" "$max_kb" "$log"
}

# "размер+mtime" файла — детект перезаписи файла на лету.
# %y — время с наносекундной точностью: перезапись в ту же секунду
# (частая история при установке) тоже видна.
# Пусто, если stat недоступен: тогда проверка просто не срабатывает.
oc_serve_file_stamp() {
  stat -c '%s %y' "$1" 2>/dev/null || printf ''
}
