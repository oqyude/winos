# Project State

**Last updated:** 2026-10-17
**MetaAgent version:** 3.0.0

---

## Overview

| Field | Value |
|---|---|
| Project | winos-powerlinks (слияние завершено) |
| Type | existing |
| Language | PowerShell 7 |
| Entry point | `main.ps1` (CLI + интерактив) |
| Branch | `dev` (5 ahead of `master`; `merge-powerlinks` сохранён как marker-ветка для ревью) |
| Last commits | `783b79f` docs(merge): meta-state refresh; `36a744a` test: plugin suite + menu tests; `748ac17` feat(plugins): merge powerlinks; `f8ac12b` ci: gate lint/test; `6664dda` chore(metaagent): v3.0.0 |
| Current session | Слияние powerlinks в winos (`e41df406-4a8b-45b2-a38d-efd3c78f1859`) |

## Architecture

```
winos/
  main.ps1                       # CLI + интерактив; Show-Menu / Read-Choice / Read-Confirm
  winos.cmd                      # shim: pwsh -File main.ps1 %*
  src/
    init.ps1                     # bootstrap: Set-Location + dot-source vars.ps1
    vars.ps1                     # $modules реестр (Alias/Actions/Destructive), пути
    modules/
      symlink-manager.ps1        # Config Persistence: plan, apply, snapshot
      essentials.ps1             # install, uninstall
      opencode-serve.ps1         # setup, remove, status, start, stop
      common/State.ps1           # движок симлинков КОНФИГОВ (468 строк, 8 функций)
      methods/{symlink,isolate}.ps1
      opencode-serve/runner.ps1
      plugins/                   # изолированный корень модуля плагинов (см. ниже)
        plugin-manager.ps1       # Plugin Deployment: 7 глаголов
        vars.ps1                 # локальные пути: $pluginRoot, $stateFile, $manifestDir...
        common/                  # свой State.ps1 (571 строка, 9 функций)
        methods/                 # registry-import, copy-tree, process-kill
  manifests/                     # 28 штук, по одной на папку плагина в S:\Plugins
  state/powerlinks.json          # allowlist плагинов
  data/data.json                 # version 2: конфиги winos
  scripts/{lint,test}.ps1        # оба гейтят код возврата
  tests/
    plugins/                     # 139 перенесённых тестов powerlinks (8 файлов)
    modules/                     # тесты существующих модулей winos
```

### Почему `plugins/` вложен, а не рядом с `symlink-manager.ps1`

**Историческая справка.** Модуль был вложен, потому что у него была своя копия
`common/State.ps1`, а обе копии определяли 8 одинаковых имён и грузились через
dot-source — кто загрузился последним, тот и выигрывал, молча ломая другой модуль.

Сейчас это **не актуально**: движок один, `src/modules/common/State.ps1`, функций
в нём 9. Пересечение имён с плагинными `common/`+`methods/` (30 функций) — пустое,
проверено. Вложенность сохранена только как организация: плагинные
Discovery/Manifest/Sandbox/StateFile/Verify не конфликтуют ни с чем и остались
локальными, а `plugin-manager.ps1` тянет общий движок через `..\common\`.

## Реестр модулей `$modules` (`src/vars.ps1`)

| Модуль | Alias | Actions | Destructive |
|---|---|---|---|
| `Config Persistence` | `symlink-manager` | plan, apply, snapshot | — |
| `Plugin Deployment` | `plugin-manager` | plan, apply, revert, snapshot, status, adopt, verify | revert, adopt |
| `Essentials` | `essentials` | install, uninstall | uninstall |
| `Service Manager` | *(нет — menu-only)* | setup, remove, status, start, stop | remove |

`Service Manager` намеренно без Alias: он доступен только через двухуровневую
грамматику `service <name> <action>`. CLI-карты в `main.ps1` **выводятся** из
этого реестра, а не дублируются — иначе список глаголов жил бы в двух местах.

## Tests

- Runner: `.\scripts\test.ps1` (Pester 6, гейт по `FailedCount` и `HadErrors`)
- **232 passed / 0 failed.** Из них 139 перенесены из powerlinks, 23 в
  `main.Tests.ps1` (8 из них — меню)
- Lint: `.\scripts\lint.ps1` — src + tests + scripts, **0 замечаний, exit 0**

## Состояние задач

| Задача | Что | Статус |
|---|---|---|
| W0 | Миграция метасостояния v2 → v3 | ✅ |
| W1 | Перенос артефактов powerlinks (47 файлов) | ✅ |
| W2 | Регистрация 4-го модуля + переименование | ✅ |
| W3 | Общий тестовый набор + починка ассерта версии | ✅ |
| W4 | `test.ps1` / `lint.ps1` с гейтом кода возврата | ✅ |
| W5 | Подтверждения, `-WhatIf`, показ кода возврата в меню | ✅ |
| W6 | Тесты меню | ✅ |
| **W7** | Объединение двух `State.ps1` | ✅ движок один, 232/232, коллизий нет |
| **W8** | Линтерная политика powerlinks | ✅ 29 → 0 замечаний, exit 0 |
| **W9** | Потеряна работа в `.temp/new-features` | ⏸ **ждёт решения владельца** |
| W10 | Автозапуск `herdr-serve` по образцу `opencode-serve` | ⏸ ожидает W9 |
| W11 | Перенос оставшихся скриптов `powerlinks` | ✅ |
| W12 | Перенос документации + ADR | ✅ |
| W13 | Архивирование `powerlinks` | ⏸ критерии зелёные, ждёт владельца |

## Сделано в этой сессии (после коммитов 6664dda..36a744a)

W0–W12 оформлены в `merge-powerlinks` четырьмя атомарными коммитами.
PR в `master` не открывался; `master` не тронут.

## Требует внимания

1. **PR не открыт.** Ветка `merge-powerlinks` локально, 4 коммита ahead `master`.
   Правило проекта: коммит в `master` только через PR. Решение владельца —
   как мержить (squash / merge / rebase).
2. **W9 открыта.** Переписывать ли потерянные `.temp/new-features`. Из 4 файлов:
   `oc-serve.{sh,ps1}` дублируют то, что сейчас делает `opencode-serve.ps1`, —
   не потеряны по существу; `herdr-{run.sh,task.ps1}` потеряны безвозвратно
   и не восстановимы из материалов репозитория.
3. **W10/W13 ждут владельца.** W10 (herdr-serve модуль) не зависит от W9;
   W13 (архивация `S:\Git\powerlinks`) технически готов, все 4 критерия зелёные.
4. **`src/init.ps1` делает `Set-Location` глобально.** Уводит CWD в `src/`.
   Безвредно для одноразового CLI, рискованно для интерактивного сеанса и
   тестовой параллельности.
5. **Ctrl+C не проверен.** Остальные выходные пути меню (пустой ввод, `0`,
   `n` на destructive) проверены вживую.
6. **Баннер модуля протекает.** `plugin-manager.ps1` печатает `powerlinks :: <verb>`
   внутри winos. Косметика, не трогал.
7. **Нет README.md.** `AGENTS.md` — bootstrap MetaAgent, не документация
   для пользователя.
8. **`state/powerlinks.json` в репозитории.** Это машинное состояние
   пользователя, но коммитится сознательно (см. `vars.ps1` плагин-модуля).
   При наличии второго пользователя стоит решить — оставить как есть или
   перенести в `.gitignore`.

## Ближайшие шаги

W7 и W8 закрыты в рамках этой сессии. Открыто:

- **W9** — решение по потерянным файлам `.temp/new-features`.
- **W10** — модуль `herdr-serve` (зависит от W9, но может стартовать без
  восстановления W9).
- **W13** — архивирование `S:\Git\powerlinks`.
- **PR из `merge-powerlinks` в `master`.**