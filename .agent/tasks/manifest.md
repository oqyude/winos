# Task Manifest — winos-powerlinks

**Session:** `e41df406-4a8b-45b2-a38d-efd3c78f1859`
**Schema:** v3.0 (`metaagent-task-manifest`)
**Goal:** слияние powerlinks в winos — winos становится контейнером, powerlinks четвёртым модулем.

Машиночитаемая версия: [manifest.json](manifest.json)

---

## Задачи слияния

| ID | Задача | Статус |
|---|---|---|
| **W0** | Миграция метасостояния v2 → v3 | ✅ completed (`6664dda`) |
| **W1** | Перенести артефакты powerlinks в дерево winos | ✅ completed (`748ac17`) |
| **W2** | Зарегистрировать 4-й модуль + переименовать | ✅ completed (`748ac17`) |
| **W3** | Общий прогон тестов + линт | ✅ completed (`f8ac12b`) |
| **W4** | Заменить `lint.ps1`/`test.ps1` на версии с гейтом | ✅ completed (`f8ac12b`) |
| **W5** | Доработать меню (подтверждения, `-WhatIf`, exit code) | ✅ completed (`748ac17`) |
| **W6** | Тесты меню | ✅ completed (`36a744a`) |
| **W7** | Объединение двух `State.ps1` | ✅ completed (`748ac17`) |
| **W8** | Линтерная политика объединённого репо | ✅ completed (`f8ac12b`) |
| **W9** | Потеря `.temp/new-features` | ✅ completed (резолюция: утрата; восстановление не нужно) |
| **W10** | Модуль `herdr-serve` | ✅ completed (`57276a1`) |
| **W11** | Перенос оставшихся скриптов `powerlinks` | ✅ completed (`748ac17`) |
| **W12** | Перенос документации + ADR | ✅ completed (`783b79f`) |
| **W13** | Архивирование `S:\Git\powerlinks` | ⏳ pending (владелец удалит руками после ревью) |
| **W14** | NeuralNote: portable manifest по анализу из `S:\Git\work` | ⏳ pending (создать `manifests/NeuralNote.json`; отчёты в `docs/` временные) |

## Зависимости

W-серия слияния идёт линейно по фазам 0 → 1 → 2 → 3 (W0 → W1..W2..W7..W8..W6 → W11 → W12). W9/W10/W13 — независимые хвосты, обрабатываются по решению владельца.

## Задачи аудита техдолга (сессия 2026-10-23)

**Session:** `e41df406-4a8b-45b2-a38d-efd3c78f1859` (продолжение)
**Происхождение:** read-only аудит техдолга + план реструктуризации, утверждённый владельцем.
**Базовая линия на `dev` @ `4e0192d`:** тесты `230 passed / 25 failed / 1 skipped` (все 25 падений — **среда**, не код: `UnauthorizedAccessException` на создании symlink/junction + расхождение формата stderr между pwsh 7 и Windows PowerShell 5.1); линт `exit 1`, 20 findings, все — `PSAvoidOverwritingBuiltInCmdlets` в стабах `tests/modules/*.Tests.ps1`.

Каждая задача — отдельный коммит, независимо откатываемый. «Страховка» = тест, который пишется **до** правки кода.

| ID | Суть | Где (путь:строка) | Тип | Риск | Польза | Когда |
|---|---|---|---|---|---|---|
| **T01** | Нет `README.md`; единственный корневой док — `AGENTS.md` (указатель на MetaAgent, не README проекта) | корень; `docs/roadmap.md:28` | дрейф | нет | высокая | **сейчас** |
| **T02** | `docs/plugin-manager.md` указывает 20 несуществующих путей (модуль уехал в `src/modules/plugins/`, тесты — в `tests/plugins/`) | `docs/plugin-manager.md:312-316,326-332,337,339,347-352` | дрейф | нет | высокая | **сейчас** |
| **T03** | Help-блок `main.ps1` перечисляет 2 модуля из 5 (`plugin-manager`, `opencode-serve`, `herdr-serve` не упомянуты) | `main.ps1:8,10`; реестр `src/vars.ps1:24-60` | дрейф | низкий | средняя | **сейчас** |
| **T04** | Комментарий движка winos упоминает `$pluginRoot` — переменную чужого движка, в его scope не существующую | `src/modules/common/State.ps1:88` | дрейф | нет | низкая | **сейчас** |
| **T05** | `.gitignore` — шаблон Python/JS на 280 строк в PowerShell-проекте; релевантны 5 строк | `.gitignore:1-222` | мусор | нет | низкая-средняя | **сейчас** |
| **T06** | `tests/plugins/state.Tests.ps1` (702 LOC) тестирует **чужой** модуль `src/modules/common/State.ps1` — остаток двудвижковой раскладки | `tests/plugins/state.Tests.ps1:3,246` | мусор/дрейф | низкий | средняя | **сейчас** |
| **T07** | Линтер глотает ошибки анализатора и не обходит `main.ps1` / `data/isolate/` | `scripts/lint.ps1:31,52` | хрупкость | низкий | средняя | **сейчас** |
| **T08** | `$toolVersion` вне scope движка winos → снимки пишут `tool_version: null` | `src/modules/common/State.ps1:565`; `src/modules/plugins/vars.ps1:41` | хрупкость | низкий | **высокая** | страховка: тест формата снимка |
| **T09** | Нет тестов: `methods/symlink.ps1`, `methods/isolate.ps1`, оба `runner.ps1` | `src/modules/methods/`, `src/modules/*-serve/runner.ps1` | хрупкость (покрытие) | нет | средняя | **сейчас** |
| **T10** | Опечатка в имени файла линтера: `.pspsscriptanalyzer.psd1` → `.psscriptanalyzer.psd1` | корень; `scripts/lint.ps1:29` | дрейф | низкий | низкая | **сейчас** |
| **T11** | Ссылка на несуществующий `manifests/NeuralNote.json` | `docs/neural-note-portable-symlinks-report.md:76` | дрейф | нет | низкая | **сейчас** |
| **T12** | `docs/roadmap.md` от 2026-07-25 подан как актуальный план; часть пунктов уже выполнена иначе | `docs/roadmap.md:3,73-75,112,134,142` | дрейф | нет | средняя | **сейчас** |
| **T13** | Структурная схема в правилах устарела; политика «W7 не сливать два `State.ps1`» мотивировочно мертва (слияние — `748ac17`) | `.agent/rules/project-rules.md:16,18,57-90` | дрейф | нет | средняя | **заблокировано** — файл под `.agent/` вне разрешённого списка |
| **T14** | `analysis-report.md` устарел: «11 тестов», старая схема дерева, неполный список ExcludeRules | `.agent/context/analysis-report.md:40-58,71,78-80` | дрейф | нет | низкая | **заблокировано** — файл под `.agent/` вне разрешённого списка |
| **T15** | Два `*-serve` — ~66% дословного дубля (remove/start/stop посимвольно) | `src/modules/herdr-serve.ps1:73-84,123-135`; `src/modules/opencode-serve.ps1:82-93,134-146` | **реструктуризация** | средний | средняя-высокая | страховка: `tests/modules/{herdr,opencode}-serve.Tests.ps1` |
| **T16** | `State.ps1` — 571 LOC, одна функция на ~190 строк | `src/modules/common/State.ps1:208-399` | **реструктуризация** | средний-высокий | средняя | страховка: T08-тест + `tests/state.Tests.ps1` |
| **T17** | `plugin-manager.ps1` — 516 LOC, логика смешана с presentation | `src/modules/plugins/plugin-manager.ps1:131` (+ `:67`,`:84`) | **реструктуризация** | средний | средняя | страховка: `tests/plugins/*` |
| **T18** | Исполняемый код лежит в каталоге данных | `data/isolate/EqualizerAPO.ps1`; `src/modules/methods/isolate.ps1:11-13` | **реструктуризация** | средний | низкая-средняя | страховка: `bucket/winos.json:9-12` (публикуется) |
| **T19** | `scripts/` — 4 разные роли в одной папке (dev-точки / дубли модулей / CI / генераторы) | `scripts/` | **реструктуризация** | средний | низкая-средняя | страховка: после решения по T22 |
| **T20** | Два синтаксиса токенов на одно понятие: `$persist`/`$env:USERPROFILE` и `%VAR%` | `src/modules/common/State.ps1:88-91`; `src/modules/plugins/common/Manifest.ps1:208-214` | хрупкость | высокий | средняя | **решение владельца** |
| **T21** | Ни один CI не запускает `test.ps1`/`lint.ps1` | `.gitea/workflows/` (только `auto-update.yml`, `update-kvrt.yml`) | хрупкость | средний | **высокая** | **решение владельца** — `project-rules.md:40` |
| **T22** | `update-manifest.sh:85` требует `jq`, которого нет на раннере → **тихий скип всех обновлений** | `scripts/update-manifest.sh:85-87`; `.gitea/workflows/auto-update.yml:143-148,215-218` | хрупкость | средний-высокий | **высокая** | **решение владельца** (какой JSON-инструментарий канонический) |
| **T23** | Три источника версии, расходятся: `0.1.2` / `0.1.2` / `0.0.1` | `main.ps1:42`; `bucket/winos.json:2`; `src/modules/plugins/vars.ps1:41` | дрейф | низкий | средняя | после T08 |
| **T24** | `$data` молча переключается на машинный `~/Storage/winos/data` вместо репозиторного | `src/vars.ps1:66`; обход в тестах `tests/vars.Tests.ps1:137-138` | хрупкость | средний | средняя | **решение владельца** (меняет поведение) |
| **T25** | `opencode-serve` слушает `0.0.0.0` (все интерфейсы) без предупреждения; порт `4096` продублирован 4 раза | `src/modules/opencode-serve.ps1:45-46`; `src/modules/opencode-serve/runner.ps1:24-28` | хрупкость | средний | средняя-высокая | **решение владельца** (меняет поведение) |
| **T26** | `exit` внутри библиотечных модулей убивает интерактивный хост | `src/modules/herdr-serve.ps1:33,90`; `src/modules/opencode-serve.ps1:35,98`; `src/modules/plugins/plugin-manager.ps1:59` | хрупкость | средний | средняя | **решение владельца** (меняет поведение) |
| **T27** | `icacls` без проверки кода возврата → «тихий» успех при отказе в защите `.env` | `src/modules/opencode-serve.ps1:58` | хрупкость | низкий | средняя | **решение владельца** (меняет поведение) |
| **T28** | Закоммиченные логи и одноразовый scratch (в т.ч. хардкод `S:\Git\winos` + UAC-эскалация) | `.agent/context/{baseline-test-report,setup-report}.log`; `.agent/migration-report.log`; `.agent/archive/scratch-2026-10-18/apply-neuralnote-elevated.ps1:12-19,37` | мусор | нет | средняя | **заблокировано** — под `.agent/` |
| **T29** | Три разных дозорных переменных на один вопрос «я уже загружен?» | `essentials.ps1:8`; `symlink-manager.ps1:9`; `plugin-manager.ps1:18` | хрупкость | низкий | низкая-средняя | после T16/T17 |

### Что помечено blocked и почему

- **T13, T14, T28** — лежат под `.agent/`, а владелец разрешил трогать в `.agent/` только `tasks/manifest.md`, `context/project-state.md`, `handoff-summary.md`. Требуют отдельного разрешения.
- **T20, T21, T22, T24, T25, T26, T27** — требуют явного решения владельца: правка меняет публичное поведение CLI, формат конфигурации/состояния либо CI-конфигурацию (`project-rules.md:40`).

## Ключевые решения, зафиксированные в задачах

**Контейнер — winos.** Мультидоменный (после W10 — 5 модулей), есть меню, реестр `$modules`, CLI, документация, CI-гейт.

**Движок симлинков один (`src/modules/common/State.ps1`)**, обслуживает и Config Persistence, и Plugin Deployment. Junction для каталогов — без повышения прав.

**Политика линтинга принята от powerlinks.** 29 → 0 замечаний; все исключения документированы inline.

**W9 закрыта без восстановления.** `oc-serve.*` дублируют `opencode-serve.ps1` (W4), `herdr-*` пишутся заново в W10 с тестами, не по памяти.

**W13 — ручная операция владельца.** Критерии зелёные; физическое удаление/архивирование `S:\Git\powerlinks` делается владельцем после ревью изменений с `merge-powerlinks` на `dev`.

## Архив

| ID | Задача | Статус |
|---|---|---|
| C1–C6, P3–P5 | Рефакторинг winos (M1–M7), июль 2026 | archived |

Состояние этих задач перенесено из манифеста формата v2.1.0, который не соответствовал установленной схеме v3.