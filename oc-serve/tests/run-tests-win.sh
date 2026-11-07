#!/usr/bin/env bash
# Тесты oc-serve на Windows (Git Bash) в песочнице: поддельный HOME,
# поддельный .bashrc, отдельный LOG_DIR и отдельные порты.
# Реальный $HOME, ~/.local/bin и живой сервер (4096) не трогаются.
#
#   bash oc-serve/tests/run-tests-win.sh [каталог-oc-serve] [старый-лаунчер]
#
# Старый лаунчер (для воспроизведения инцидента) берётся из
# tests/fixtures/oc-serve-task.pre-private-copy.sh; вторым аргументом можно
# подсунуть другую версию.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
OC="${1:-$HERE/..}"
SB="/tmp/oc-serve-test.$$"
BASE_PATH="$PATH"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
check(){ if [ "$2" = "0" ]; then ok "$1"; else bad "$1"; fi; }

make_sandbox() {           # $1 = порт
  local port="$1"
  rm -rf "$SB"; mkdir -p "$SB/home" "$SB/bin" "$SB/state"
  cat >"$SB/bin/fake-serve" <<'EOF'
#!/usr/bin/env bash
port=4599
while [ $# -gt 0 ]; do case "$1" in --port) port="$2"; shift 2;; *) shift;; esac; done
exec python -m http.server "$port" --bind 127.0.0.1
EOF
  cat >"$SB/bin/fake-dies" <<'EOF'
#!/usr/bin/env bash
sleep 6
EOF
  chmod +x "$SB/bin/fake-serve" "$SB/bin/fake-dies"
  printf 'export PATH="%s/bin:$PATH"\nalias oc-serve="fake-serve --port %s"\n' "$SB" "$port" \
    > "$SB/home/.bashrc"
}
run_launcher() { env -i HOME="$SB/home" PATH="$BASE_PATH" OC_SERVE_LOG_DIR="$SB/state" \
                   bash "$1" >"$SB/state/stdout.txt" 2>&1; echo $?; }
launcher_env() { env -i HOME="$SB/home" PATH="$BASE_PATH" OC_SERVE_LOG_DIR="$SB/state" bash -c "$1"; }
port_busy()  { (exec 3<>"/dev/tcp/127.0.0.1/${1:-4611}") 2>/dev/null; }
wait_port()  { for _ in $(seq 1 80); do port_busy "$1" && return 0; sleep 0.25; done; return 1; }

echo "=== W1. старт ==="
make_sandbox 4611
( run_launcher "$OC/oc-serve-task.sh" >"$SB/rc.txt" ) &
lp=$!
wait_port 4611; check "порт 4611 слушается" $?
grep -q '^--- command: fake-serve --port 4611' "$SB/state/serve.log"; check "в логе команда из алиаса" $?
grep -q '^--- binary : fake-serve -> ' "$SB/state/serve.log"; check "в логе resolved бинарь" $?
grep -q '^--- PATH   : ' "$SB/state/serve.log"; check "в логе PATH" $?
ls "$SB/state"/.oc-serve-task.*.sh >/dev/null 2>&1; check "лаунчер работает из приватной копии" $?

echo "=== W2. порт занят -> rc=0 ==="
rc=$(run_launcher "$OC/oc-serve-task.sh")
[ "$rc" = "0" ]; check "rc=0 (порт занят)" $?

echo "=== W3. остановка через oc-serve-stop.sh ==="
launcher_env "bash '$OC/oc-serve-stop.sh'" >"$SB/stop.out" 2>&1; rc=$?
sed 's/^/       | /' "$SB/stop.out"
[ "$rc" = "0" ]; check "oc-serve-stop.sh вернул 0" $?
sleep 1; port_busy 4611; [ $? = "1" ]; check "порт освободился" $?
wait "$lp" 2>/dev/null
grep -q 'stopped by request' "$SB/state/serve.log"; check "в логе 'stopped by request'" $?

echo "=== W4. бинаря нет в PATH -> rc=127 ==="
make_sandbox 4612
printf 'alias oc-serve="no-such-binary-xyz --port 4612"\n' > "$SB/home/.bashrc"
rc=$(run_launcher "$OC/oc-serve-task.sh")
[ "$rc" = "127" ]; check "rc=127" $?
grep -q 'no-such-binary-xyz не найден в PATH, PATH=' "$SB/state/serve.log"
check "в логе 'не найден в PATH, PATH=...'" $?

echo "=== W5. ротация лога ==="
make_sandbox 4613
head -c 700000 /dev/zero | tr '\0' 'x' > "$SB/state/serve.log"
printf 'old\n' >> "$SB/state/serve.log"
( run_launcher "$OC/oc-serve-task.sh" >"$SB/rc.txt" ) &
lp=$!
wait_port 4613
[ -f "$SB/state/serve.log.1" ]; check "создан serve.log.1" $?
[ "$(wc -c <"$SB/state/serve.log.1")" -gt 512000 ]; check "serve.log.1 содержит старый лог" $?
[ "$(wc -c <"$SB/state/serve.log")" -lt 512000 ]; check "новый serve.log маленький" $?
launcher_env "bash '$OC/oc-serve-stop.sh'" >/dev/null 2>&1
wait "$lp" 2>/dev/null

echo "=== W6. deploy поверх работающего экземпляра (новый лаунчер) ==="
make_sandbox 4614
cp "$OC/oc-serve-task.sh" "$SB/deployed.sh"
cp "$OC/oc-serve-common.sh" "$SB/oc-serve-common.sh"
printf 'export PATH="%s/bin:$PATH"\nalias oc-serve="fake-dies --port 4614"\n' "$SB" > "$SB/home/.bashrc"
( run_launcher "$SB/deployed.sh" >"$SB/rc.txt" ) &
lp=$!
sleep 2
cp "$OC/oc-serve-task.sh" "$SB/deployed.sh"      # deploy поверх работающего
wait "$lp" 2>/dev/null
rc=$(cat "$SB/rc.txt")
[ "$rc" != "127" ]; check "лаунчер не упал с 127 (rc=$rc)" $?
grep -q 'изменился во время работы' "$SB/state/serve.log"; check "в логе предупреждение о deploy" $?

echo "=== W7. то же на СТАРОМ лаунчере (воспроизведение инцидента) ==="
# НЕ-проверка (skip/informational), как и в run-tests.sh: результат зависит от
# механики перечитывания файла в конкретной версии bash. Разбор инцидента —
# в README, раздел «Что было поломано».
make_sandbox 4615
printf 'export PATH="%s/bin:$PATH"\nalias oc-serve="fake-dies --port 4615"\n' "$SB" > "$SB/home/.bashrc"
OLD_FIXTURE="$HERE/fixtures/oc-serve-task.pre-private-copy.sh"
if [ -f "${2:-$OLD_FIXTURE}" ]; then
  cp "${2:-$OLD_FIXTURE}" "$SB/deployed.sh"
  ( run_launcher "$SB/deployed.sh" >"$SB/rc.txt" ) &
  lp=$!
  sleep 2
  cp "$OC/oc-serve-task.sh" "$SB/deployed.sh"      # deploy поверх работающего
  wait "$lp" 2>/dev/null
  rc=$(cat "$SB/rc.txt")
  if [ "$rc" = "127" ] || grep -qE 'syntax error|command not found' "$SB/state/serve.log"; then
    echo "  skip/informational: на старом лаунчере инцидент воспроизвёлся (rc=$rc) — это и была причина"
  else
    echo "  skip/informational: воспроизведение на старом лаунчере нестабильно в песочнице (rc=$rc) — здесь bash не перечитал подменённый файл"
  fi
  grep -E 'syntax error|command not found|exit rc=' "$SB/state/serve.log" | tail -3 | sed 's/^/       | /'
else
  echo "  skip/informational: нет фикстуры $OLD_FIXTURE"
fi

rm -rf "$SB"
echo
echo "Итого: ok=$PASS fail=$FAIL"
[ "$FAIL" = "0" ]
