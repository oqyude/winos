#!/usr/bin/env bash
# Функциональные тесты oc-serve в песочнице (фальшивый HOME, фальшивый сервер).
# Ничего не трогает в реальном $HOME и не ходит в сеть. Нужен Linux/macOS
# (python3 для фальшивого сервера, pkill для его добивания).
#
#   bash oc-serve/tests/run-tests.sh
#
# Кейсы:
#   1. старт: сервер поднялся, в логе есть диагностика, лаунчер работает
#      из приватной копии;
#   2. порт занят -> rc=0 ("port busy");
#   3. остановка через oc-serve-stop.sh -> rc=0, порт освободился;
#   4. бинаря нет в PATH -> rc=127 и внятное сообщение;
#   5. ротация лога: serve.log > лимита -> serve.log.1, свежий serve.log;
#   6. deploy поверх работающего экземпляра: файл лаунчера перезаписан
#      на лету -> сервер обязан выжить (и поставить предупреждение в лог);
#   7. то же самое на СТАРОМ лаунчере (фикстура до приватной копии) —
#      НЕ-проверка: воспроизведение инцидента зависит от механики
#      перечитывания файла в конкретной версии bash, поэтому группа
#      только печатает, что получилось, и ничего не засчитывает.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
OC="$HERE/.."
SANDBOX="${TMPDIR:-/tmp/opencode}/oc-serve-test.$$"
mkdir -p "$(dirname "$SANDBOX")"
BASE_PATH="$PATH"

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
check(){ if [ "$2" = "0" ]; then ok "$1"; else bad "$1"; fi; }

kill_servers() { pkill -f 'http[.]server 4[56]0[0-9]' 2>/dev/null; sleep 0.3; return 0; }

# --- песочница -------------------------------------------------------------
make_sandbox() {          # $1 = порт фальшивого сервера
  local port="$1"
  kill_servers
  rm -rf "$SANDBOX"
  mkdir -p "$SANDBOX/home" "$SANDBOX/bin" "$SANDBOX/state"
  cat >"$SANDBOX/bin/fake-serve" <<'EOF'
#!/usr/bin/env bash
port=4599
while [ $# -gt 0 ]; do
  case "$1" in
    --port) port="$2"; shift 2 ;;
    *) shift ;;
  esac
done
exec python3 -m http.server "$port" --bind 127.0.0.1
EOF
  chmod +x "$SANDBOX/bin/fake-serve"
  cat >"$SANDBOX/home/.bashrc" <<EOF
export PATH="$SANDBOX/bin:\$PATH"
alias oc-serve="fake-serve --port $port"
EOF
}

run_launcher() {         # $1 = путь к лаунчеру; печатает rc
  env -i HOME="$SANDBOX/home" PATH="$BASE_PATH" \
      OC_SERVE_LOG_DIR="$SANDBOX/state" \
      bash "$1" >"$SANDBOX/state/stdout.txt" 2>&1
  echo $?
}

launcher_env() {         # $1 = команда
  env -i HOME="$SANDBOX/home" PATH="$BASE_PATH" \
      OC_SERVE_LOG_DIR="$SANDBOX/state" \
      bash -c "$1"
}

port_busy() { (exec 3<>"/dev/tcp/127.0.0.1/${1:-4599}") 2>/dev/null; }

wait_port() {            # $1 = порт, ждём подъёма
  for _ in $(seq 1 60); do port_busy "$1" && return 0; sleep 0.25; done
  return 1
}

echo "=== 1. старт ==="
make_sandbox 4601
( run_launcher "$OC/oc-serve-task.sh" >"$SANDBOX/rc.txt" ) &
launcher_pid=$!
wait_port 4601
check "порт 4601 слушается" $?
grep -q '^--- command: fake-serve --port 4601' "$SANDBOX/state/serve.log"
check "в логе команда из алиаса" $?
grep -q '^--- binary : fake-serve -> ' "$SANDBOX/state/serve.log"
check "в логе resolved бинарь" $?
grep -q '^--- PATH   : ' "$SANDBOX/state/serve.log"
check "в логе PATH" $?
ls "$SANDBOX/state"/.oc-serve-task.*.sh >/dev/null 2>&1
check "лаунчер работает из приватной копии" $?

echo "=== 2. порт занят -> rc=0 ==="
rc=$(run_launcher "$OC/oc-serve-task.sh")
[ "$rc" = "0" ]; check "rc=0 (порт занят)" $?
grep -q 'already listening, not starting a second instance' "$SANDBOX/state/serve.log"
check "в логе 'already listening'" $?

echo "=== 3. остановка через oc-serve-stop.sh ==="
launcher_env "bash '$OC/oc-serve-stop.sh'" >"$SANDBOX/stop.out" 2>&1; rc=$?
sed 's/^/       | /' "$SANDBOX/stop.out"
[ "$rc" = "0" ]; check "oc-serve-stop.sh вернул 0" $?
sleep 1
port_busy 4601; [ $? = "1" ]; check "порт освободился" $?
wait "$launcher_pid" 2>/dev/null
grep -q 'stopped by request' "$SANDBOX/state/serve.log"
check "в логе 'stopped by request'" $?

echo "=== 4. бинаря нет в PATH -> rc=127 ==="
make_sandbox 4602
cat >"$SANDBOX/home/.bashrc" <<EOF
alias oc-serve="no-such-binary-xyz --port 4602"
EOF
rc=$(run_launcher "$OC/oc-serve-task.sh")
[ "$rc" = "127" ]; check "rc=127" $?
grep -q 'no-such-binary-xyz не найден в PATH, PATH=' "$SANDBOX/state/serve.log"
check "в логе 'не найден в PATH, PATH=...'" $?

echo "=== 5. ротация лога ==="
make_sandbox 4603
head -c 700000 /dev/zero | tr '\0' 'x' >"$SANDBOX/state/serve.log"
printf 'old content\n' >>"$SANDBOX/state/serve.log"
( run_launcher "$OC/oc-serve-task.sh" >"$SANDBOX/rc.txt" ) &
launcher_pid=$!
wait_port 4603
[ -f "$SANDBOX/state/serve.log.1" ]; check "создан serve.log.1" $?
[ "$(wc -c <"$SANDBOX/state/serve.log.1")" -gt 512000 ]; check "serve.log.1 содержит старый лог" $?
grep -q 'rotated' "$SANDBOX/state/serve.log.1"; check "в serve.log.1 есть запись о ротации" $?
[ "$(wc -c <"$SANDBOX/state/serve.log")" -lt 512000 ]; check "новый serve.log маленький" $?
launcher_env "bash '$OC/oc-serve-stop.sh'" >/dev/null
wait "$launcher_pid" 2>/dev/null

echo "=== 6. deploy поверх работающего экземпляра (новый лаунчер) ==="
make_sandbox 4604
cp "$OC/oc-serve-task.sh" "$SANDBOX/deployed.sh"     # «установленный» лаунчер
cp "$OC/oc-serve-common.sh" "$SANDBOX/oc-serve-common.sh"
( run_launcher "$SANDBOX/deployed.sh" >"$SANDBOX/rc.txt" ) &
launcher_pid=$!
wait_port 4604
cp "$OC/oc-serve-task.sh" "$SANDBOX/deployed.sh"     # deploy: перезапись на лету
sleep 1
pkill -f 'http[.]server 4604'                          # сервер умирает -> лаунчер читает файл заново
sleep 3
port_busy 4604; [ $? = "1" ]; check "сервер умер, порт свободен" $?
wait "$launcher_pid" 2>/dev/null
rc=$(cat "$SANDBOX/rc.txt")
[ "$rc" = "0" ] || [ "$rc" = "143" ] || [ "$rc" = "1" ]
check "лаунчер не упал с 127 (rc=$rc)" $?
grep -q 'изменился во время работы' "$SANDBOX/state/serve.log"
check "в логе предупреждение о deploy" $?

echo "=== 7. то же на СТАРОМ лаунчере (воспроизведение инцидента) ==="
# НЕ-проверка (skip/informational): результат зависит от того, как именно bash
# перечитывает изменённый файл — это разная механика на разных версиях bash
# и при разном времени подмены. Поэтому группа ничего не засчитывает: она
# только показывает, что получилось на этой машине. Разбор инцидента — в
# README, раздел «Что было поломано».
make_sandbox 4605
OLD_FIXTURE="$HERE/fixtures/oc-serve-task.pre-private-copy.sh"
if [ -f "$OLD_FIXTURE" ]; then
  OLD="$SANDBOX/deployed.sh"
  cp "$OLD_FIXTURE" "$OLD"                 # лаунчер до приватной копии
  ( run_launcher "$OLD" >"$SANDBOX/rc.txt" ) &
  launcher_pid=$!
  wait_port 4605
  cp "$OC/oc-serve-task.sh" "$OLD"        # deploy: перезапись на лету
  sleep 1
  pkill -f 'http[.]server 4605'             # сервер умирает -> bash читает файл заново
  sleep 3
  wait "$launcher_pid" 2>/dev/null
  rc=$(cat "$SANDBOX/rc.txt")
  if [ "$rc" = "127" ] || grep -qE 'syntax error|command not found' "$SANDBOX/state/serve.log"; then
    echo "  skip/informational: на старом лаунчере инцидент воспроизвёлся (rc=$rc) — это и была причина"
  else
    echo "  skip/informational: воспроизведение на старом лаунчере нестабильно в песочнице (rc=$rc) — здесь bash не перечитал подменённый файл"
  fi
  grep -E 'syntax error|command not found|exit rc=' "$SANDBOX/state/serve.log" | tail -3 | sed 's/^/       /'
else
  echo "  skip/informational: нет фикстуры $OLD_FIXTURE"
fi
kill_servers
rm -rf "$SANDBOX"

echo
echo "Итого: ok=$PASS fail=$FAIL"
[ "$FAIL" = "0" ]
