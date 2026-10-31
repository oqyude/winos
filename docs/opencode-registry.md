# Реестр зависимостей opencode на lamet

Снято 2026-10-30 с машины `lamet` (Windows 11, `C:\Git`, пользователь `oqyude`).
Документ — источник правды для переустановки opencode «с нуля» после сноса машины.
Установщик: [`scripts/install-opencode.ps1`](../scripts/install-opencode.ps1).

Проверка соответствия факта реестру: `powershell -File scripts/install-opencode.ps1 -Verify`
(код 0 — всё на месте, 1 — есть расхождения).

> **Обновлено 2026-10-31** (после переустановки lamet). Три правки в реестре и в
> установщике:
>
> * **A.** Плагин не «объявляется», а **устанавливается**: `bun add` в
>   `~/.config/opencode` + проверка лога плагина — п. 1.5.
> * **B.** Конфиг обязан быть **валидным JSON** — п. 1.5.
> * **C.** Форма объявления плагина: `{"package": "..."}`, а не голая строка — п. 1.5.
> * плюс **пин против бакета** для `opencode2` (2.2.1 → 2.2.4) — п. 1.2.
>
> **Обновлено 2026-10-31 (вторая итерация).** Три проверки, которых не хватало:
>
> * `auth:login` читает **`opencode.db`, таблицу `credential`** (только
>   `integration_id`, никогда `value`); `auth.json` — вторичный источник, и его
>   отсутствие **не** значит «не залогинен» — п. 0.2.
> * `env:bashrc`: launcher стартует через `bash -lc`, поэтому профиль обязан
>   экспортировать `OPENCODE_SERVER_PASSWORD`; печатается **только длина**.
>   `~/.bashrc` **не перезаписывается** — п. 1.7.
> * `mcp:<server>` — по каждому серверу из живого конфига: абсолютный путь
>   существует, имя резолвится, `cwd` существует; для `cmd /c <path>` проверяется
>   именно `<path>` — п. 1.6.
>
> Репозиторий переехал в `C:\metaagent\work\winos` (клона в `C:\Git` больше нет).

---

## 0. Три пункта, без которых opencode на этой машине не работает

Это не примечания, а условия работоспособности. Проверено сегодня, 2026-10-30.

### 0.1. Переменные окружения эгресса — ОБЯЗАТЕЛЬНЫ

```
HTTP_PROXY=http://127.0.0.1:10808
HTTPS_PROXY=http://127.0.0.1:10808
NO_PROXY=localhost,127.0.0.1,::1,192.168.1.0/24,100.64.0.0/10,.local,.zeroq.su,.su
```

**Что происходит без них.** opencode не грузит конфиг провайдеров. В
`~/.local/share/opencode/log/opencode.log` сегодня, 2026-10-30, повторяется:

```
level=WARN message="failed to load OpenCode provider config"
  cause="HttpClientError: Transport error (GET https://opencode.ai/console/api/v2/config)
  (cause: TypeError: ECONNRESET: The socket connection was closed unexpectedly. ...)"
```

**Последствие, измеренное напрямую.** Провайдер `opencode-go` в реестре моделей
отсутствует. Замер на одной и той же машине, один и тот же бинарь:

| Окружение | `opencode models --standalone` | Строк `opencode-go/*` |
|---|---|---|
| с `HTTP(S)_PROXY` + `NO_PROXY` | отрабатывает, 5 прогонов подряд | **30** (включая `opencode-go/deepseek-v4.1-flash`) |
| без них | не отрабатывает либо 0 строк | **0** |

**Уточнение механизма (важно для переустановки).** У провайдера `opencode-go`
два независимых условия, и нужны оба:

1. **Сеть.** `GET https://opencode.ai/console/api/v2/config` без прокси падает
   с `ECONNRESET` — это и есть строка `failed to load OpenCode provider config`
   в логе. Endpoint отвечает `401` без авторизации, то есть он в принципе
   достижим, но обход прокси на этой машине рвёт соединение.
2. **Учётная запись.** Провайдер `opencode-go` — это OpenCode Console, и его
   учётка лежит в `~/.local/share/opencode` (таблица `credential`,
   `integration_id='opencode'`, `label='Personal'`, `active=1`). Проверено:
   в изолированном `HOME` с прокси, но без каталога данных, `opencode-go`
   тоже даёт 0 строк.

Без прокси ломается ещё и запуск: CLI часто обрывается на фазе активации
плагинов — `ServiceUnavailableError: Location plugins did not finish activating`.
Это тот же симптом (сеть), просто проявляется раньше и громче.

**Почему это не «просто через прокси-алиас».** На машине прокси есть
(`127.0.0.1:10808` слушает, PID 12968), и в `~/.bashrc` есть алиасы
`zh-proxy` / `z-proxy`. Но:

* `~/.bashrc` прокси **не экспортирует** в окружение — есть только алиасы
  (`export HTTPS_PROXY=http://localhost:10808 && export HTTP_PROXY=http://localhost:10808`),
  а алиасы не раскрываются в неинтерактивном шелле (`bash -lc`), которым поднимается сервер;
* в пользовательских и машинных переменных окружения (`HKCU\Environment`,
  `HKLM\...\Session Manager\Environment`) переменных `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY`
  **нет вообще**;
* запускающий скрипт `~/opencode-serve.sh` (`bash -lc`, затем `exec opencode.exe serve`)
  прокси тоже не экспортирует.

Итог: процесс сервера стартует без прокси → `GET .../console/api/v2/config` → `ECONNRESET` →
провайдер `opencode-go` не появляется → дефолтная модель не резолвится (см. 0.3).
Живой сервер на :4096 это подтверждает: `opencode models` (через него) даёт
0 строк `opencode-go/*` и 80 строк `opencode/*` — то есть провайдер Console
в реестре отсутствует именно у работающего сервера.

**Что делать при переустановке.** Прописать переменные в окружение, из которого
запускается сервер opencode (в `~/opencode-serve.sh` до строки `exec`, либо как
пользовательские переменные окружения). `NO_PROXY` нужен, чтобы локальные адреса
(`127.0.0.1`, `::1`), локальная сеть `192.168.1.0/24`, CGNAT `100.64.0.0/10` и
внутренние домены `.local`, `.zeroq.su`, `.su` ходили напрямую, минуя прокси.
Установщик **не** меняет системные переменные окружения (`setx` запрещён) — он только
проверяет их наличие и печатает готовые строки для вставки.
Учётную запись OpenCode Console (`opencode auth login`) нужно завести заново
в любом случае — см. 0.2.

### 0.2. Учётки лежат в `opencode.db`, а не в `auth.json`

`~/.local/share/opencode/auth.json` (192 байта) — **не** переносится при переустановке.
Логины делаются заново:

```
opencode auth login
```

На этой машине `auth.json` содержит одну запись — `minimax-coding-plan` (тип `api`).
Ключ в реестр не попадает.

**Важное уточнение, которое видно только на живой машине:** **консольный** провайдер
(`OpenCode Console` → `Personal`) хранится не в `auth.json`, а в базе
`~/.local/share/opencode/opencode.db` (таблица `credential`, `integration_id='opencode'`,
`active=1`). `opencode auth list` показывает и его, и `minimax-coding-plan` (две записи),
и четыре внешних провайдера, чьи ключи берутся из переменных окружения
(`GEMINI_API_KEY`, `GROQ_API_KEY`, `OPENROUTER_API_KEY` — лежат в `~/.bashrc`).

Живой срез базы (2026-10-31), `sqlite3 ~/.local/share/opencode/opencode.db`:

```
sqlite> SELECT integration_id, label, active FROM credential;
opencode-go|OpenCode Go|1
minimax-coding-plan|MiniMax Token Plan (minimax.io)|0
minimax-coding-plan|oqyude|1
```

То есть **активных интеграций две** (`opencode-go`, `minimax-coding-plan`), а
`auth.json` на этой машине может отсутствовать вовсе — это **не** признак «не залогинен».

Значит при переустановке: `auth.json` пересоздаётся через `opencode auth login`,
а база `opencode.db` либо переносится целиком, либо консольная учётка заводится заново
через тот же `opencode auth login`. Установщик ничего из этого не копирует и секретов
не хранит.

**Как это проверяется.** Проверка `auth:login` читает `opencode.db`, таблицу
`credential`, и считает строки с `active = 1`. Печатаются **только имена
`integration_id`** — колонка `value` (секрет) не читается вообще:

```
[ OK ] auth:login - opencode.db (table credential) - the active integrations of the machine | 2 active: opencode-go, minimax-coding-plan (opencode.db (table credential))
```

Пустая таблица — `[WARN]`, непустая — `[ OK ]`. Если `sqlite3` на машине нет,
источником становится `opencode auth list` (считаются записи `stored`), а
`auth.json` — последний резервный источник.

### 0.3. Дефолтная модель `opencode-go/deepseek-v4.1-flash` — решить явно

В `~/.config/opencode/opencode.jsonc` прописано:

```jsonc
"model": "opencode-go/deepseek-v4.1-flash"
```

На этой машине модель **не работает** — в логе сегодня:

```
level=ERROR message="Failed to drain Session"
  cause="SessionRunnerModel.ModelUnavailableError: Model unavailable: opencode-go/deepseek-v4.1-flash"
```

Проверено и то, что это не «нет подписки»:

* без прокси (0.1) провайдер `opencode-go` вообще отсутствует в реестре → модель не резолвится;
* с прокси, в отдельном процессе (`--standalone`), та же модель отвечает:
  `opencode run --standalone -m opencode-go/deepseek-v4.1-flash "reply with the single word OK"` → `OK`.

То есть авторизация модели есть (консольная учётка `Personal` в `opencode.db`),
а ломается именно загрузка реестра провайдеров из-за отсутствия прокси в окружении сервера.
Замечание для переустановки: обе части нужны одновременно — и сеть (прокси),
и учётная запись Console. Перенос только `opencode.db` или только `auth.json`
без прокси не поможет; перенос без учётной записи — тоже.

**Что решить при переустановке (варианты, выбор владельца):**

1. задать прокси в окружении сервера (0.1) — тогда `opencode-go/deepseek-v4.1-flash`
   работает как сейчас задумано; **рекомендуется**, это же чинит `opencode-go` в реестре;
2. сменить дефолт на модель другого провайдера, у которого есть живой ключ
   (`minimax-coding-plan/MiniMax-M3.1-Flash` — из `auth.json`; либо
   `openrouter/...`, `google/...`, `groq/...` — из переменных окружения);
3. оставить как есть и считать, что до первого починения прокси opencode нерабочий.

Установщик вариант 3 не чинит молча: он печатает предупреждение, если прокси в
окружении отсутствуют, и проверяет, что модель из `opencode.jsonc` присутствует
в реестре моделей.

---

## 1. Сводная таблица

Счёт: **40 пунктов** в сводной таблице (разделы 1.1–1.8). Колонка «команда установки» —
одна строка, готовая к вставке.

### 1.1. Менеджер пакетов и бакеты

| Имя | Версия | Откуда ставится | Зачем | Что сломается без него | Команда установки |
|---|---|---|---|---|---|
| `scoop` | v0.6.0 | официальный установщик, `C:\Users\oqyude\scoop` | менеджер пакетов, из которого ставятся nodejs, bun, git, python, lazygit, opencode2 | ничего не ставится без менеджера; `scoop` сам лежит вне пакетов | `Invoke-WebRequest https://get.scoop.sh -UseBasicParsing \| Invoke-Expression` |
| bucket `main` | — (1702 манифеста) | `https://github.com/ScoopInstaller/Main.git` | базовый бакет: nodejs, bun, git, python, uv | не ставятся `nodejs`, `bun`, `git`, `python` | `scoop bucket add main https://github.com/ScoopInstaller/Main.git` |
| bucket `extras` | — (2449 манифестов) | `https://github.com/ScoopInstaller/Extras` | `lazygit` и прочие «не-дефолтные» приложения | не ставится `lazygit` | `scoop bucket add extras https://github.com/ScoopInstaller/Extras` |
| bucket `versions` | — (630 манифестов) | `https://github.com/ScoopInstaller/Versions` | **`opencode2`** (v2 не в `main`) и `python312` | не ставится opencode v2 и python 3.12 | `scoop bucket add versions https://github.com/ScoopInstaller/Versions` |
| bucket `winos` | — (16 манифестов) | `https://github.com/oqyude/winos` | манифесты winos-приложений (`kvrt`, `winsetview`, `zapretcontrol`, `pcbu-desktop`, …) | не обновляются winos-манифесты | `scoop bucket add winos https://github.com/oqyude/winos` |

### 1.2. opencode

| Имя | Версия | Откуда ставится | Зачем | Что сломается без него | Команда установки |
|---|---|---|---|---|---|
| `opencode2` | **2.2.4** | бакет `versions`; манифест тянет `@opencode/cli-windows-x64-<v>.tgz` с npm | сам агент | агента нет | `scoop install versions/opencode2` — ставит ровно то, что лежит в манифесте бакета (на 2026-10-31 это **2.2.4**) |
| `opencode2` (пин) | 2.2.1 и старше | манифест в **истории** бакета `versions` (`git log -- bucket/opencode2.json`) | откат на конкретный бинарь, если свежий не работает | — | `scoop install https://raw.githubusercontent.com/ScoopInstaller/Versions/<commit>/bucket/opencode2.json` — коммит ищется по `git log` **в клоне бакета** |
| shim `opencode` | 2.2.4 | `scoop/shims/opencode.exe` → `apps/opencode2/current` | команда `opencode` в PATH | `opencode` не находится | ставится вместе с `opencode2` |

> **Пин против бакета (обновлено 2026-10-31).** Бакет `versions` держит в рабочем дереве
> **только одну** — последнюю — версию каждого приложения; предыдущие версии остаются
> в истории git. Поэтому «зафиксировать 2.2.1» и «поставить 2.2.1 из бакета» — разные
> вещи: `scoop install versions/opencode2` всегда берёт текущий манифест, и именно
> его версию показывает `scoop list`.
>
> Установщик проверяет **три** величины и печатает их рядом: что **установлено**
> (факт), что **в бакете** (манифест) и что **ожидает реестр**:
>
> ```
> [ OK ] app:opencode2 - opencode2 2.2.4 (bucket versions) | installed 2.2.4, bucket ships 2.2.4, registry expects 2.2.4
> ```
>
> Расхождение версии — это `[WARN]` с обоими числами, а не `[ OK ]`:
>
> ```
> [WARN] app:opencode2 - opencode2 2.2.4 (bucket versions) | installed 2.2.3, bucket ships 2.2.4, registry expects 2.2.4 | the installed version differs from the registry
> ```
>
> Старый установщик печатал `[ OK ] opencode2 2.2.1` при фактических 2.2.4: версия
> вообще не сверялась, ожидаемое значение выдавалось за факт. `-Verify` теперь
> завершается кодом 1 и при расхождении версии, не только при отсутствии пакета.
>
> Если нужен именно старый бинарь, установщик ищет его манифест в истории бакета
> (`git log` **внутри клона бакета** — в прежней версии команда выполнялась в
> текущем каталоге, поэтому поиск всегда молча проваливался) и ставит его по
> прямой ссылке на манифест. Если такого манифеста в истории нет — ставится версия
> бакета, а расхождение с реестром печатается как `[WARN]`.


### 1.3. Инструменты (версии — с этой машины)

| Имя | Версия | Откуда ставится | Зачем | Что сломается без него | Команда установки |
|---|---|---|---|---|---|
| `nodejs` | **26.13.0** (рядом 26.12.1) | бакет `main` | рантайм для npm-пакетов, MCP `webpage` (npx), `browser-control` | не работают MCP `webpage` и `browser-control`; не ставятся глобальные npm-пакеты | `scoop install nodejs` |
| `bun` | **1.4.4** | бакет `main` | рантайм, которым собран opencode; быстрые скрипты | `opencode` (нативный бинарь) не запустится | `scoop install bun` |
| `git` | **2.56.0.4** | бакет `main` | VCS: нужен opencode для работы с репозиториями и для scoop-бакетов | opencode не видит репозитории; scoop не обновляет бакеты | `scoop install git` |
| `python` | **3.15.2** (рядом 3.15.1) | бакет `main` | скрипты, часть MCP-пайплайнов | часть автоматизаций не запускается | `scoop install python` |
| `python312` | **3.12.10** | бакет `versions` | Python 3.12 под `python312` (нужен в т.ч. для venv `computer-use`) | `python312` не находится | `scoop install versions/python312` |
| `lazygit` | **0.66.2** | бакет `extras` | TUI для git | нет, opencode работает | `scoop install lazygit` |
| `uv` | **0.13.6** | бакет `main` | менеджер venv/пакетов Python; им собран venv `computer-use` | не пересобрать окружение `computer-use` | `scoop install uv` |

Замечание по `python`: в PATH shim `python` указывает на **3.12.10** (то есть на
`python312`), а `python/current` — это 3.15.2. `python312` в PATH явно указывает на 3.12.10.
В реестре зафиксированы обе линии.

### 1.4. Глобальные npm-пакеты

| Имя | Версия | Откуда ставится | Зачем | Что сломается без него | Команда установки |
|---|---|---|---|---|---|
| `@opencode-ai/browser-control` | **0.8.4** | `npm -g` (npm prefix: `C:\Users\oqyude\scoop\persist\nodejs\bin`) — **единственный** глобальный npm-пакет на машине | MCP-сервер `browser-control` + скилл `browser-control` | MCP `browser-control` не поднимается, `opencode mcp list` показывает ошибку | `npm install -g @opencode-ai/browser-control@0.8.4` |

### 1.5. Плагины opencode

| Имя | Версия | Откуда ставится | Зачем | Что слокается без него | Команда установки |
|---|---|---|---|---|---|
| `oh-my-opencode-slim` | **3.0.5** | `plugins` в `~/.config/opencode/opencode.jsonc` **и** в `~/.config/opencode/cli.json` (объект `{"package": "..."}`) + **зависимости в `~/.config/opencode/node_modules`** (bun, 143 верхнеуровневых пакета, ~330 МБ) | агентный слой: оркестратор, subagent-ы, task-manager | агентов (`orchestrator`, `explorer`, `oracle`, `designer`, `fixer`) не будет, команды агентов не сработают; opencode **молча** игнорирует плагин — ни строки в логе, ни ошибки | `cd ~/.config/opencode && bun add oh-my-opencode-slim@3.0.5` |
| `oh-my-openagent` | `latest` | **расхождение**: указан в `~/.config/opencode/tui.json` (строка `oh-my-openagent@latest`), тогда как в `opencode.jsonc`/`cli.json` — `oh-my-opencode-slim@3.0.5` | не определено: **ни одного** события загрузки `oh-my-openagent` в логе сервера нет; в npm-кэше лежит только каталог `.staging-…` от недокачанной установки 2026-10-24 (134 МБ) — то есть пакет **не установлен** | ничего не ломает, но 134 МБ мёртвого кэша и два разных плагина в конфигах | **не «чинить» молча** — см. примечание ниже |

#### A. Плагин не «объявляется», а **устанавливается**

Конфиг объявляет плагин, но opencode грузит его из `node_modules` **каталога
конфига**. Объявления в конфиге недостаточно: без `~/.config/opencode/node_modules`
opencode не пишет в лог ни строки и не выдаёт ошибку — выглядит как «плагин есть,
просто ничего не делает».

Проверка «плагин живой» состоит из двух независимых частей, и обе обязательны:

1. **каталог** `~/.config/opencode/node_modules/oh-my-opencode-slim` существует,
   в нём `package.json` версии `3.0.5`;
2. **лог плагина** `~/.local/share/opencode/log/oh-my-opencode-slim.<время>-<pid>.log`
   содержит строки `tools registered {"count":11}`,
   `agents registered {"count":5}` и `bundled skills registered in-process {"count":11}`.

Второе — единственное доказательство, что расширение **живое**, а не объявленное.
`-Verify` проверяет и каталог, и лог, и печатает факт:

```
[ OK ] plugin:oh-my-opencode-slim - bun add oh-my-opencode-slim@3.0.5 in C:\Users\oqyude\.config\opencode | node_modules present, version 3.0.5, declared in the config package.json: True
[ OK ] plugin-live:oh-my-opencode-slim - the plugin log must contain "tools registered" | tools=11 agents=5 skills=11 (log oh-my-opencode-slim.20261030T235255-8512.log)
```

**Ловушка `bun add`.** `bun add` без `cd` в каталог конфига кладёт `node_modules`,
`package.json` и `bun.lock` в **`$HOME`** — это мусор в домашнем каталоге
(красная линия владельца). Установщик поэтому:

* вызывает `bun add` с явным рабочим каталогом (`Push-Location $ConfigDir`);
* после установки проверяет, что `node_modules\<пакет>` появился **именно** в
  `~/.config/opencode`, а не в `$HOME`;
* запоминает состояние `$HOME` до установки и **удаляет** всё, что появилось там
  во время прогона (в том числе осиротевший `bun.lock` от ручной починки);
* отдельной проверкой `home:hygiene` следит, чтобы в `$HOME` не появилось
  `node_modules` / `package.json` / `bun.lock`.

#### B. Конфиг обязан быть **валидным JSON**

Windows-пути в JSON требуют удвоения обратного слэша. Строка

```json
"command": ["cmd", "/c", "C:\Users\oqyude\\scoop\\apps\\nodejs\\current\\npx.cmd"]
```

содержит `\U` — недопустимую escape-последовательность: `python -c "json.load(...)"`
такой файл **не читает** (`Invalid control character` / битые escapes), а мягкий
парсер opencode читает — и получает путь с искажёнными символами.

Поэтому установщик больше не подставляет пути в текстовый шаблон:

* конфиг собирается как объект (`[ordered]@{}`) и сериализуется `ConvertTo-Json`;
* пути пишутся **прямыми слэшами** (`C:/Users/oqyude/scoop/...`) — Windows их
  принимает, а экранировать нечего;
* **перед записью** файл разбирается обратно `ConvertFrom-Json`: это Json.NET,
  он отвергает недопустимые escape-последовательности. Конфиг, который не
  прошёл разбор, на диск не попадает;
* `-Verify` проверяет то же самое на **живом** файле и сверяет, что путь в
  `mcp.servers.webpage.command` совпадает с ожидаемым (`.../npx.cmd`).

#### C. Форма объявления плагина

Схема `https://opencode.ai/config.json` (снята живьём 2026-10-31):

* `plugins` — актуальный ключ; элемент — строка **или** `Config.Plugin.EntryEncoded`;
* строка в `plugins` — это **enablement-директива** («включить уже установленное»),
  а не «поставь пакет»;
* внешний пакет объявляется объектом: `{"package": "oh-my-opencode-slim@3.0.5"}`
  (поле `package` обязательно, `additionalProperties: false`);
* `plugin` (единственное число) — **deprecated**.

Рабочая форма (проверена живьём, плагин поднялся):

```json
"plugins": [ { "package": "oh-my-opencode-slim@3.0.5" } ]
```

Её и пишет установщик — в `opencode.jsonc` и в `cli.json` (в `cli.json` схема
`https://opencode.ai/v2/cli.json` допускает ту же форму и не имеет ключа
`plugin`). Устаревшая форма `"plugins": ["oh-my-opencode-slim@3.0.5"]` — это
директива включения, а не установка пакета.

> **Расхождение названо прямо, а не исправлено.** `tui.json` и `opencode.jsonc`/`cli.json`
> называют разные плагины. Оба присутствуют в конфигурации. Ничего не «приводится к
> единому виду»: выбор — за владельцем. Установщик воспроизводит текущее состояние
> как есть и в `-Verify` печатает предупреждение о расхождении.
>
> Факты по `tui.json`, установленные при разборе (важно для переустановки):
>
> * opencode v2 читает `opencode/opencode.json`, `opencode/cli.json`, `opencode/client.json`;
>   `tui.json` в списке **нет** — это файл v1, из которого v2 умеет мигрировать
>   (`migrated cli config` в коде бинаря). Миграция отрабатывает только при наличии
>   `~/.local/share/opencode/kv.json` — такого файла нет, миграция не происходит.
> * Плагин из `tui.json` (`oh-my-openagent@latest`) **не качается**: подставной
>   `MARKER-PLUGIN-XYZ-9999` в `tui.json` не породил ни одной попытки загрузки.
> * В npm-кэше `oh-my-openagent@latest` — только `.staging-…` (134 МБ) от прерванной
>   установки 2026-10-24, без `package.json`; полноценной установки нет.
> * Итог: `tui.json` сейчас **инертен**. Строка `oh-my-openagent@latest` в нём —
>   остаток v1, а не рабочая зависимость.
>
> Ключ в `tui.json` переведён в не-депрекейтованный вид (`plugins` со строкой
> `oh-my-openagent@latest`): строка — это enablement-директива, поэтому она не
> тянет пакет и не запускает загрузку. Переименование `plugin` → `plugins` в
> живом `tui.json` делается `-Force`; в `-Verify` старый ключ виден как `[WARN]`.
>
> Риск для переустановки: если на новой машине opencode v2 всё-таки попытается
> выполнить миграцию `tui.json` (появится `kv.json`), он попробует поставить
> `oh-my-openagent@latest` — пакет большой (134 МБ) и качается долго; без прокси
> (п. 0.1) это упадёт. Это ещё один аргумент решить вопрос с `tui.json` при сносе.

### 1.6. MCP-серверы (все из `~/.config/opencode/opencode.jsonc`)

| Имя | Версия / источник | Откуда ставится | Зачем | Что сломается без него | Команда установки |
|---|---|---|---|---|---|
| `webpage` | `webpage-mcp@latest` (на npm сейчас 0.10.2) | локальный: `cmd /c <nodejs>\<версия>\npx.cmd -y -p webpage-mcp@latest webpage-mcp-stdio` | чтение веб-страниц | агент не может читать веб | ставится самим `npx` при первом старте; нужен `nodejs` |
| `browser-control` | `@opencode-ai/browser-control@0.8.4` | локальный: `cmd /c <npm prefix>\browser-control-mcp.cmd` (создаётся глобальным npm-пакетом; на lamet это `C:\Users\oqyude\scoop\persist\nodejs\bin\`) | управление браузером | агент не управляет браузером | `npm install -g @opencode-ai/browser-control@0.8.4` |
| `computer-use` | `opencode-computer-use` 0.1.2 | локальный: `C:\Tools\opencode-computer-use\.venv\Scripts\python.exe -m opencode_computer_use`, cwd `C:\Tools\opencode-computer-use`; venv собран `uv` (0.13.5) на CPython 3.12.15 (`scoop/persist/uv/python/versions/cpython-3.12-windows-x86_64-none`), зависимости `mcp>=2.0`, `mss>=9.0`, `Pillow>=10.0` (+ `comtypes`, `pywinauto`, `rapidocr-onnxruntime` в `[all]`) | управление рабочим столом, скриншоты, OCR | агент не управляет десктопом | `uv venv C:\Tools\opencode-computer-use\.venv --python 3.12` + `uv pip install -e "C:\Tools\opencode-computer-use[all]"` |
| `genoffice` | `genoffice` 0.12.29 (CLI-пакет 0.10.0) | локальный: `cmd /c %LOCALAPPDATA%\Programs\GenOffice\resources\cli\genoffice.cmd mcp` | работа с Office-документами | агент не создаёт/не читает docx/xlsx/pptx/pdf | ставится установщиком приложения GenOffice (вне scoop) |

#### Пути в конфиге проверяются как пути, а не как строки

Живой случай (2026-10-31): конфиг ссылался на
`C:\Users\oqyude\scoop\apps\nodejs\current\npx.cmd` — **такого файла нет**
(каталог `apps\nodejs\current` есть, но `npx.cmd` в нём нет; настоящий файл —
в версионном каталоге `apps\nodejs\26.13.0\`). Второй: `browser-control-mcp.cmd`
есть в `scoop\persist\nodejs\bin\`, но **не в PATH**, поэтому `where.exe` его не
находил. Итог: два MCP-сервера падали с `MCP server process exited with code 1`.

Поэтому:

* установщик **разрешает** пути (`where.exe npx.cmd`, `npm prefix -g`), а не
  угадывает их; в конфиг попадает файл, который существует;
* проверка `mcp:<server>` создаётся **по каждому серверу из живого конфига**:
  * `command[0]` — абсолютный путь → файл **должен существовать**;
  * `command[0]` — имя (`npx`, `cmd`) → должно **резолвиться** (`where.exe`);
  * для `cmd /c <path>` проверяется именно `<path>` (то, что запускает cmd);
  * `cwd`, если задан, должен существовать;
  * при провале — `[FAIL]` с именем сервера и путём.

```
[ OK ] mcp:webpage - MCP server 'webpage' - cmd /c npx | cmd /c npx
[ OK ] mcp:browser-control - MCP server 'browser-control' - cmd /c C:\Users\oqyude\scoop\persist\nodejs\bin\browser-control-mcp.cmd | cmd /c C:\Users\oqyude\scoop\persist\nodejs\bin\browser-control-mcp.cmd
[ OK ] mcp:computer-use - MCP server 'computer-use' - C:\Tools\opencode-computer-use\.venv\Scripts\python.exe -m opencode_computer_use | ... | cwd C:\Tools\opencode-computer-use
[ OK ] mcp:genoffice - MCP server 'genoffice' - cmd /c C:\Users\oqyude\AppData\Local\Programs\GenOffice\resources\cli\genoffice.cmd | ...
```

Замечание про слэши: `cmd /c` понимает и прямые, и обратные слэши — если файл
существует. Проверено на живой машине: `cmd /c "C:/Users/oqyude/scoop/apps/nodejs/26.13.0/npx.cmd --version"`
→ `11.20.0`, exit 0. Ломается не слэш, а **отсутствующий файл**. В конфиг пишутся
обратные слэши (их экранирует `ConvertTo-Json`), прямые тоже работают.

> opencode **сам переписывает** `opencode.jsonc` и `tui.json` при старте: сводит
> команду `webpage` к голому `npx`, а `browser-control` — к полному пути в npm-префиксе.
> Проверки это принимают (имя резолвится, путь существует), а установщик не воюет
> с opencode за файл: перезапись конфига делается только когда он **сломан**
> (не парсится или плагин объявлен не в той форме) — с бэкапом `.bak-<метка>`.

### 1.7. Переменные окружения (НЕ меняются установщиком)

| Имя | Значение | Откуда ставится | Зачем | Что сломается без него | Команда установки |
|---|---|---|---|---|---|
| `HTTP_PROXY` | `http://127.0.0.1:10808` | окружение, из которого стартует сервер | обход блокировки до `opencode.ai` | **не грузится конфиг провайдеров**, провайдер `opencode-go` отсутствует → дефолтная модель недоступна | `export HTTP_PROXY=http://127.0.0.1:10808` (в `~/opencode-serve.sh` или в пользовательские переменные) |
| `HTTPS_PROXY` | `http://127.0.0.1:10808` | то же | то же | то же | `export HTTPS_PROXY=http://127.0.0.1:10808` |
| `NO_PROXY` | `localhost,127.0.0.1,::1,192.168.1.0/24,100.64.0.0/10,.local,.zeroq.su,.su` | то же | локальные адреса и внутренние домены — напрямую | часть внутренних адресов уходит в прокси и ломается | `export NO_PROXY=localhost,127.0.0.1,::1,192.168.1.0/24,100.64.0.0/10,.local,.zeroq.su,.su` |
| `OPENCODE_CONFIG_CONTENT` | `{"agent":{"build":{"steps":200}}}` | пользовательские переменные окружения **и** `~/opencode-serve.sh` | лимит шагов сборки агента | агент упирается в дефолтный лимит шагов | задать в пользовательских переменных окружения |
| `OPENCODE_SERVER_USERNAME` / `OPENCODE_SERVER_PASSWORD` | секрет | `~/.bashrc` (+ `~/.config/opencode/service.json`; на lamet продублировано в пользовательских переменных окружения) | аутентификация HTTP-сервера opencode на 4096 | сервер не принимает подключения | владелец задаёт сам; секреты в реестр не попадают |
| `GEMINI_API_KEY` / `GROQ_API_KEY` / `OPENROUTER_API_KEY` | секреты | `~/.bashrc` | внешние провайдеры моделей | эти провайдеры не авторизованы | владелец задаёт сам; в реестр не копируются |

#### `~/.bashrc` — часть установки, и его не перезаписывают

Launcher поднимает сервер через `bash -lc` **именно чтобы подхватились экспорты
профиля**. На lamet и на vetymae:

```
~/.bash_profile:  test -f ~/.bashrc && . ~/.bashrc
~/.bashrc:        OPENCODE_SERVER_USERNAME, OPENCODE_SERVER_PASSWORD,
                  OPENCODE_ENABLE_EXA, OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS
bash -lc 'echo ${#OPENCODE_SERVER_PASSWORD}' → 20
```

Без этих строк сервер **поднимется** и будет отдавать **401**, а в логе не будет
ничего — самая неприятная картина из возможных.

**Правило реестра: `~/.bashrc` не перезаписывается целиком.** Файл держит секрет,
а не настройки стиля; на vetymae его однажды «починили» правкой и пришлось
восстанавливать **побайтово**. Поэтому установщик:

* **не трогает** `~/.bashrc` вообще (ни строки, ни бэкапа);
* только **проверяет** окружение логера: `bash -lc 'echo ${#OPENCODE_SERVER_PASSWORD}'`
  должен дать непустую длину; при пустом — `[FAIL]` с текстом, что launcher без
  него не авторизуется;
* печатает **только длину**, значение секрета не выводится никогда.

```
[ OK ] env:bashrc - bash -lc must export OPENCODE_SERVER_PASSWORD (the launcher runs through it) | OPENCODE_SERVER_PASSWORD length: 20 (the value is never printed); the process environment carries it too
```

Если проверка падает, правка делается **вручную и точечно**, с бэкапом:

```
cp ~/.bashrc ~/.bashrc.bak-<метка>
# дописать в конец (не переписывая файл):
export OPENCODE_SERVER_USERNAME=<user>
export OPENCODE_SERVER_PASSWORD=<secret>
```

### 1.8. Файлы конфигурации и данные

| Имя | Версия / размер | Откуда ставится | Зачем | Что сломается без него | Команда установки |
|---|---|---|---|---|---|
| `~/.config/opencode/opencode.jsonc` | 1593 байта | файл конфига | основной конфиг: дефолтная модель, MCP-серверы, плагин | opencode стартует с дефолтами, MCP-серверы не поднимаются | восстанавливается установщиком (пишется, только если файла нет **или** он сломан) |
| `~/.config/opencode/cli.json` | 94 байта | файл конфига | плагин для CLI-режима | CLI-режим без агентного слоя | то же |
| `~/.config/opencode/tui.json` | 50 байт | файл конфига | TUI-конфиг; **содержит расхождение** (`oh-my-openagent@latest`) | TUI без плагина | то же (как есть) |
| `~/.config/opencode/oh-my-opencode-slim.json` | 389 байт | файл конфига | привязка агентов (`orchestrator`, `explorer`, `oracle`, `designer`, `fixer`) к модели `opencode-go/deepseek-v4.1-flash` | агенты стартуют на дефолтной модели | восстанавливается установщиком |
| `~/.config/opencode/node_modules/` + `package.json` + `bun.lock` | `oh-my-opencode-slim` 3.0.5, 143 верхнеуровневых пакета, ~330 МБ | `bun add` **в каталоге конфига** | рантайм плагина: без него opencode **молча** игнорирует объявленный плагин | плагин не грузится: ни tools, ни агентов, ни скиллов — и ни одной строки в логе | `cd ~/.config/opencode && bun add oh-my-opencode-slim@3.0.5` |
| `~/.local/share/opencode/log/oh-my-opencode-slim.<время>-<pid>.log` | 7–8 КБ | пишет сам плагин при загрузке | доказательство, что плагин **живой** | — | появляется при первом старте opencode |
| `~/.config/opencode/skills/` | `browser-control` (36 КБ), `genoffice` (80 КБ) | ставятся opencode при первой активации соответствующих MCP/плагинов | скиллы браузера и офисных документов | скиллы не появятся в списке | появляются сами; вручную — `opencode skill` |
| `~/.config/opencode/lsp-install-decisions.json` | 181 байт | opencode | пометки «отклонено» для LSP `nixd`, `bash` | opencode заново предложит поставить LSP | копируется вручную при желании |
| `~/.config/opencode/service.json` | 41 байт, содержит пароль | opencode service | пароль локального HTTP-сервера | сервер не поднимется с тем же паролем | **установщик не создаёт** (секрет) — владелец задаёт сам |
| `~/.local/share/opencode/` | `opencode.db` 96 МБ + WAL 14 МБ, `logs/`, `storage/`, `snapshot/`, `shell/`, `tool-output/`, `repos/` | состояние opencode | база сессий и данных | история сессий теряется | переносится при желании; база хранит и консольную учётку (п. 0.2) |
| `~/.cache/opencode/npm/` | 418 МБ (`oh-my-opencode-slim@3.0.5` — 285 МБ, установлен; `oh-my-openagent@latest` — 134 МБ, **только `.staging-…`, не установлен**) | npm-кэш opencode для плагинов | оффлайн-запуск плагинов | плагины качаются заново при первом старте | качается автоматически |
| `~/opencode-serve.sh` | 625 байт | скрипт запуска сервера | поднимает `opencode serve --hostname 0.0.0.0 --port 4096 --cors https://<host>.opencodes.zeroq.su`, лог в `%TEMP%\opencode-serve.log` | сервер на 4096 не поднимается | восстанавливается; **в нём же задаётся `HTTP(S)_PROXY`/`NO_PROXY`** |
| `~/.bashrc` | ~4.4 КБ | dotfiles | `OPENCODE_SERVER_*`, ключи внешних провайдеров, алиасы прокси, `PATH`-фиксы для scoop | сервер без пароля; внешние провайдеры не авторизованы | восстанавливается из dotfiles (`~/.Storage/chezmoi`) владельцем; **установщик не перезаписывает файл целиком** — только точечная правка с бэкапом (п. 1.7) |

---

## 2. Порядок установки (порядок важен)

1. `scoop` (если его нет) → 2. бакеты `main`, `extras`, `versions`, `winos`
3. `git`, `nodejs`, `bun`, `python`, `python312`, `lazygit`, `uv`
4. `opencode2` **2.2.4** — то, что лежит в манифесте бакета `versions`
   (пин по манифесту из истории бакета — только если нужен именно этот бинарь, см. п. 1.2)
5. `npm install -g @opencode-ai/browser-control@0.8.4`
6. восстановить конфиги opencode (`opencode.jsonc`, `cli.json`, `tui.json`, `oh-my-opencode-slim.json`)
7. **материализовать зависимости плагина**: `cd ~/.config/opencode && bun add oh-my-opencode-slim@3.0.5`
   (шаг 6 без шага 7 = «плагин объявлен, но не установлен», см. п. 1.5 A)
8. поднять окружение `computer-use` (`uv venv` + `uv pip install -e "…[all]"`)
9. прописать `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY` в окружение сервера
10. **проверить окружение логера**: `bash -lc 'echo ${#OPENCODE_SERVER_PASSWORD}'`
    → непустая длина (п. 1.7). `~/.bashrc` при этом **не перезаписывается**
11. `opencode auth login` (консоль + minimax) — **логины заново**; учётки лежат
    в `opencode.db`, `auth.json` может отсутствовать и это нормально (п. 0.2)
12. **запустить opencode хотя бы раз** — только тогда появляется лог плагина,
    по которому `-Verify` доказывает, что плагин живой (п. 1.5 A)
13. проверить: `opencode models | grep opencode-go` (должно быть 30 строк), `opencode auth list`, `opencode mcp list`

Автоматизация шагов 1–8: `powershell -File scripts/install-opencode.ps1`.
Шаги 9–13 — руками: прокси, логины и секрет требуют решения владельца.

## 3. Проверка после установки

```
opencode --version                  # ожидается opencode v2.2.4
scoop list                          # opencode2 2.2.4, nodejs, bun, git, python, python312, lazygit
npm ls -g --depth=0                 # @opencode-ai/browser-control@0.8.4
opencode auth list                  # есть OpenCode Console и minimax-coding-plan
opencode mcp list                   # webpage, browser-control, computer-use, genoffice — connected

# проверка прокси (п. 0.1) — запускать В ТОМ ЖЕ окружении, что и сервер:
echo "HTTP_PROXY=$HTTP_PROXY"; echo "NO_PROXY=$NO_PROXY"
opencode models | grep -c opencode-go/   # ожидается 30
# 0 = прокси не дошёл до процесса opencode (или нет учётной записи Console)

# доказательство, что плагин живой:
grep -E 'tools registered|agents registered|skills registered' \
  ~/.local/share/opencode/log/oh-my-opencode-slim.*.log | tail -3
# ожидается: tools registered {"count":11} / agents registered {"count":5}
#            / bundled skills registered in-process {"count":11,"disabled":0}

# активные интеграции (учётки лежат в opencode.db, auth.json может отсутствовать):
sqlite3 ~/.local/share/opencode/opencode.db \
  'SELECT integration_id, active FROM credential;'
# ожидается: opencode-go|1, minimax-coding-plan|1 (+ может быть inactive)

# окружение логера - печатается ТОЛЬКО длина секрета:
bash -lc 'echo ${#OPENCODE_SERVER_PASSWORD}'
# ожидается непустое число (на lamet 20)
```

Сверка «факт против реестра» целиком: `powershell -File scripts/install-opencode.ps1 -Verify`
(код возврата 0 — совпало, 1 — расхождение с реестром или отсутствующий пункт;
предупреждения (`[WARN]`, например deprecated-ключ в `tui.json`) на код возврата
не влияют; список расхождений печатается в stdout).

`-Verify` печатает **факт рядом с ожидаемым** по каждому пункту:

```
[ OK ] app:opencode2 - opencode2 2.2.4 (bucket versions) | installed 2.2.4, bucket ships 2.2.4, registry expects 2.2.4
[ OK ] plugin:oh-my-opencode-slim - bun add oh-my-opencode-slim@3.0.5 in C:\Users\oqyude\.config\opencode | node_modules present, version 3.0.5, declared in the config package.json: True
[ OK ] plugin-live:oh-my-opencode-slim - the plugin log must contain "tools registered" | tools=11 agents=5 skills=11 (log oh-my-opencode-slim.20261031T003521-3556.log)
[ OK ] mcp:webpage - MCP server 'webpage' - cmd /c npx | cmd /c npx
[ OK ] env:bashrc - bash -lc must export OPENCODE_SERVER_PASSWORD (the launcher runs through it) | OPENCODE_SERVER_PASSWORD length: 20 (the value is never printed)
[ OK ] auth:login - opencode.db (table credential) - the active integrations of the machine | 2 active: opencode-go, minimax-coding-plan (opencode.db (table credential))
```

Расхождение версии — `[WARN]` с обоими числами (и код возврата 1), а не `[ OK ]`.

## 4. Что установщик принципиально не делает

* не трогает `~/.config/opencode` и `~/.local/share/opencode` существующие файлы
  (пишет только отсутствующие или **сломанные**; перезапись — только с `-Force`);
  сломанный конфиг перед перезаписью копируется в `<имя>.bak-<yyyyMMdd-HHmmss>`;
* **не трогает `~/.bashrc`** — ни строки, ни бэкап: файл держит секрет, правка
  делается вручную и точечно, с бэкапом (п. 1.7);
* не удаляет и не переустанавливает opencode «на живую» (уже установленную версию
  не понижает; расхождение версий — предупреждение, а не действие);
* **не создаёт ничего в `%USERPROFILE%`** — ни `node_modules`, ни `package.json`,
  ни `bun.lock`: зависимости плагина ставятся в `~/.config/opencode`, а всё, что
  всё-таки появилось в домашнем каталоге, удаляется (проверка `home:hygiene`);
* не меняет системные переменные окружения (`setx` не используется);
* не хранит и не копирует секреты: `auth.json`, `service.json`, `opencode.db`,
  ключи провайдеров; из `opencode.db` читается только колонка `integration_id`,
  значение секрета не выводится никогда;
* не останавливает и не перезапускает сервер opencode.
