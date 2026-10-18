# Project State

**Last updated:** 2026-10-18
**MetaAgent version:** 3.0.0

---

## Overview

| Field | Value |
|---|---|
| Project | winos (post-mergepowerlinks) |
| Type | existing |
| Language | PowerShell 7 |
| Entry point | `main.ps1` (CLI + интерактив) |
| Branch | `dev` (active). `merge-powerlinks` сохранён локально как исторический marker; в `github/dev` уже история после rebase `bee5588 → e7acfab` |
| Last commits | `6235565` chore(meta): add W16; `0727b67` fix(opencode-serve): honour -WhatIf; `a9d7888` chore(meta): add W15; `f596232` chore(review): apply post-merge findings; `e7acfab` (был `bee5588`) chore(tasks): close W10 with reference commit 7374f7e |
| Previous session | `e41df406-4a8b-45b2-a38d-efd3c78f1859` закрыта 2026-10-17, HANDOFF phase |
| Powerlinks source | `S:\Git\powerlinks` УДАЛЁН 2026-10-18 владельцем. Зеркало в gitea сохранено как архив |

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
      opencode-serve.ps1         # setup, remove, status, start, stop — все гейтят -WhatIf (W16)
      herdr-serve.ps1            # setup, remove, status, start, stop — гейтят -WhatIf с W10
      opencode-serve/runner.ps1
      herdr-serve/runner.ps1
      common/State.ps1           # движок симлинков КОНФИГОВ
      methods/{symlink,isolate}.ps1
      plugins/                   # изолированный корень модуля плагинов
        plugin-manager.ps1       # Plugin Deployment: 7 глаголов; баннер 'Plugin Deployment ::' (был 'powerlinks ::' до 57276a1)
        vars.ps1                 # локальные пути: $pluginRoot, $stateFile, $manifestDir...
        common/                  # свой State.ps1, StateFile, Discovery, Sandbox, Verify
        methods/                 # registry-import, copy-tree, process-kill
  manifests/                     # 28 штук, по одной на папку плагина в S:\Plugins
  state/powerlinks.json          # allowlist плагинов (имя историческое, не путать с удалённым репо)
  data/data.json                 # version 2: конфиги winos
  scripts/{lint,test,audit-plugins,build-mappings,generate-manifests,new-test-plugins,snapshot,update-kvrt}.ps1
  tests/
    plugins/                     # перенесённые из powerlinks (8 файлов)
    modules/                     # тесты существующих модулей winos (включая herdr-serve.Tests, opencode-serve.Tests)
    {main,vars,state,build-mappings,standalone}.Tests.ps1
```

### `state/powerlinks.json` — почему такое имя

Исторически: файл пришёл из powerlinks. После удаления репо-источника (2026-10-18) переименование **не делалось** — это churn (нужна миграция state-файла, правка тестов и доки), и не блокирует. Зафиксировано в `manifest.json` W13 context как осознанный отказ.

## Реестр модулей `$modules` (`src/vars.ps1`)

| Модуль | Alias | Actions | Destructive |
|---|---|---|---|
| `Config Persistence` | `symlink-manager` | plan, apply, snapshot | — |
| `Plugin Deployment` | `plugin-manager` | plan, apply, revert, snapshot, status, adopt, verify | revert, adopt |
| `Essentials` | `essentials` | install, uninstall | uninstall |
| `opencode-serve` | `opencode-serve` | setup, remove, status, start, stop | remove |
| `herdr-serve` | `herdr-serve` | setup, remove, status, start, stop | remove |

С W2 + W10: legacy `Service Manager` (menu-only, без Alias) УДАЛЁН. Каждый сервис — самостоятельная запись с собственным Alias. CLI-карты в `main.ps1` **выводятся** из реестра (`$moduleAliases`/`$serviceAliases` derivation от `$modules`, см. f596232), а не дублируются.

## Tests

- Runner: `.\scripts\test.ps1` (Pester 6, гейт по `FailedCount` и `HadErrors`)
- **241 passed / 0 failed.** Из них 139 перенесены из powerlinks, остальные — winos-native. +8 herdr-serve (W10), +1 opencode-serve -WhatIf (W16)
- Lint: `.\scripts\lint.ps1` — src + tests + scripts, **0 замечаний, exit 0**
- Audit: `.\scripts\audit-plugins.ps1` — 28 plugins, 166 live links, **orphans 0, blocking 0, warnings 4** (ожидаемые: 2× NO_LINKS, 2× TARGET_DIFFERS по Dear Reality)

## Состояние задач

| ID | Что | Статус |
|---|---|---|
| W0–W8 | Миграция v2→v3, перенос артефактов, общий набор тестов, лёрнер, объединение движков | ✅ |
| W9 | Потеряна работа в `.temp/new-features` (4 файла) | ⏸ **ждёт решения владельца** |
| W10 | Автозапуск `herdr-serve` по образцу `opencode-serve` | ✅ 2026-10-17 (`7374f7e`) |
| W11 | Перенос оставшихся скриптов powerlinks | ✅ |
| W12 | Документация powerlinks + ADR | ✅ |
| W13 | Архивирование powerlinks | ✅ 2026-10-18 (владелец удалил локальный клон; gitea-зеркало как архив) |
| W14 | NeuralNote: portable manifest | ⏸ ждёт owner-side решений (загрузка файлов, лицензия CC BY-NC) |
| W15 | Post-merge review findings (`merge-powerlinks..dev`) | ✅ 2026-10-17 (`f596232`) |
| W16 | opencode-serve -WhatIf alignment с herdr-serve | ✅ 2026-10-17 (`0727b67`) |

## Сделано после HANDOFF 2026-10-17

1. **W15** (4 фикса из отчёта `.temp/report.md`): `$serviceAliases` derivation от `$modules`, сужение Alias-ассерта до сервис-entries, `$ConfirmPreference='None'` в herdr-serve.Tests BeforeAll, исправление cross-reference в `bee5588` (commit 57276a1 → 7374f7e в сообщении и в W10 context) — rebase + force-push.
2. **W16** (пункт #5 отчёта): `$PSCmdlet.ShouldProcess` в opencode-serve setup/remove/start/stop по образцу herdr-serve, новый тест `setup -WhatIf writes nothing and registers nothing`, `$ConfirmPreference='None'` в opencode-serve.Tests BeforeAll. `herdr-serve.md` перестал врать про оба модуля.
3. **W13** (этот коммит): физическое удаление `S:\Git\powerlinks` владельцем, правило в `project-rules.md` убрано, W13 → `completed`.

## Требует внимания

1. **W9 открыта.** 4 потерянных файла в `.temp/new-features` (см. W9 context). Из них `oc-serve.{sh,ps1}` дублируют работу `opencode-serve.ps1` (не потеряны по существу); `herdr-{run.sh,task.ps1}` потеряны безвозвратно, но `herdr-serve.ps1` уже реализует их задачу.
2. **W14 открыта.** NeuralNote: манифест + adopt — это owner-work (загрузка файлов в `S:\Plugins\NeuralNote`, лицензионное решение по CC BY-NC для коммерческого использования).
3. **`state/powerlinks.json` в репозитории.** Машинное состояние пользователя, но коммитится сознательно (см. `src/modules/plugins/vars.ps1`). При появлении второго пользователя — решить, оставлять или перенести в `.gitignore`.
4. **Heritage-имена** в коде (после удаления powerlinks-репо): `state/powerlinks.json`, `Read/Write-PowerLinksState`, `$PowerLinksSandbox`, баннер `Plugin Deployment ::` (уже переименован с `powerlinks ::` в 57276a1), комментарии в `docs/roadmap.md` и `docs/symlink-manager.md`. Не блокирует, не правил в этом проходе.
5. **`src/init.ps1` делает `Set-Location` глобально.** Уводит CWD в `src/`. Безвредно для одноразового CLI, рискованно для интерактивного сеанса и тестовой параллельности. Не правил.
6. **Ctrl+C не проверен** в меню. Остальные выходные пути проверены вживую.
7. **Нет README.md.** `AGENTS.md` — bootstrap MetaAgent, не пользовательская документация.

## Ближайшие шаги

- **W9** — owner decision по потерянным файлам.
- **W14** — owner work (NeuralNote adopt + загрузка).
- **Heritage-rename pass** — отдельной задачей: `state/powerlinks.json` → `state/plugin-deployment.json` + переименование функций + миграция. Бэклог, не блокер.
- **PR** — ветка `dev` не открыта в PR (правило: `master` только через PR). Сейчас активная работа идёт в `dev`, PR пока не нужен.
