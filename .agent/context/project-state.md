# Project State

**Last updated:** 2026-10-20
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
| Last commits | `49d3e9e` ci(gitea): log which secrets the runner injected; `fee78c1` ci(gitea): use the repository secrets that actually exist; `91a1272` fix(bucket): keep the 4-space indentation; `ec5d9a1` fix(bucket): tasks-org; `ebbb19d` ci(gitea): take jq and pwsh from the `ci` devshell; `c161b12` ci(gitea): check the repository out explicitly (W18) |
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

## CI/CD (Gitea Actions)

Раннер: `act_runner v3.1.0` на сапфире, host-режим, метка `native:host`
(`modules/server/gitea-runner.nix` в репозитории nixos, `S:\Git\nixos`).

| Что | Значение |
|---|---|
| Workflow | `.gitea/workflows/auto-update.yml` (каждые 6 ч + вручную), `.gitea/workflows/update-kvrt.yml` (05:40/17:40) |
| Воркспейс job'а | `/tmp/gitea-runner-work/<hash>/hostexecutor` (tmpfs, чистится раннером) |
| PATH job'а | ровно `hostPackages` раннера, зашит в systemd-юнит при активации → изменить можно только `nixos-rebuild switch` |
| jq и pwsh | в PATH раннера **нет**; берутся из devshell `ci` репозитория nixos: `nix develop path:/etc/nixos#ci` (общий список — `lib/ci-tools.nix`) |
| Секреты репозитория | `GH_API_TOKEN` (GitHub, снимает лимит 60/час), `OAUTH_TOKEN` (Gitea, checkout + push), `JOB_TOKEN` — авто-инжектящийся job-токен, запасной вариант |
| Логи прогонов | `/mnt/services/gitea/data/actions_log/oqyude/winos/…log.zst` на сапфире (zstd) |

**Правила, которые стоит помнить** (найдены на живом раннере, W18):

- Gitea **не чекаутит репозиторий сам** — без шага checkout workspace пустой.
- `GITEA_WORKSPACE` act_runner не выставляет (только `GITHUB_WORKSPACE`), корень репозитория лучше определять по содержимому (`bucket/` + `scripts/`).
- `nix-shell -p` на сапфире не работает: реестр nix пустой, каналов нет.
- `nix develop` к чужому git-репозиторию не идёт (libgit2, ownership) — только `path:`.
- Имена env-переменных в workflow не могут начинаться с `GITEA_`/`GITHUB_` (сервер режет), имена секретов — могут.
- `actions/checkout@v4` на act_runner v3.x тянется с инстанса или GitHub и требует node — на этом раннере проще свой git-шаг.

**Что ещё не проверено вживую:** пуш с настоящим токеном. Шаг commit+push отработал в репетишне против локального origin, но ни одного коммита от CI в истории репозитория пока нет — все прогоны на момент фиксации находили «всё up to date».

## Состояние задач

| ID | Что | Статус |
|---|---|---|
| W0–W8 | Миграция v2→v3, перенос артефактов, общий набор тестов, лёрнер, объединение движков | ✅ |
| W9 | Потеряна работа в `.temp/new-features` (4 файла) | ✅ 2026-10-17 (закрыто как утрата; oc-serve перереализован в W11, herdr — в W10) |
| W10 | Автозапуск `herdr-serve` по образцу `opencode-serve` | ✅ 2026-10-17 (`7374f7e`) |
| W11 | Перенос оставшихся скриптов powerlinks | ✅ |
| W12 | Документация powerlinks + ADR | ✅ |
| W13 | Архивирование powerlinks | ✅ 2026-10-18 (владелец удалил локальный клон; gitea-зеркало как архив) |
| W14 | NeuralNote: portable manifest | ⏸ ждёт owner-side решений (загрузка файлов, лицензия CC BY-NC) |
| W15 | Post-merge review findings (`merge-powerlinks..dev`) | ✅ 2026-10-17 (`f596232`) |
| W16 | opencode-serve -WhatIf alignment с herdr-serve | ✅ 2026-10-17 (`0727b67`) |
| W18 | CI/CD на Gitea: auto-update и update-kvrt | ✅ 2026-10-20 (`c161b12`…`49d3e9e`) |

## Сделано после HANDOFF 2026-10-17

1. **W15** (4 фикса из отчёта `.temp/report.md`): `$serviceAliases` derivation от `$modules`, сужение Alias-ассерта до сервис-entries, `$ConfirmPreference='None'` в herdr-serve.Tests BeforeAll, исправление cross-reference в `bee5588` (commit 57276a1 → 7374f7e в сообщении и в W10 context) — rebase + force-push.
2. **W16** (пункт #5 отчёта): `$PSCmdlet.ShouldProcess` в opencode-serve setup/remove/start/stop по образцу herdr-serve, новый тест `setup -WhatIf writes nothing and registers nothing`, `$ConfirmPreference='None'` в opencode-serve.Tests BeforeAll. `herdr-serve.md` перестал врать про оба модуля.
3. **W13** (этот коммит): физическое удаление `S:\Git\powerlinks` владельцем, правило в `project-rules.md` убрано, W13 → `completed`.

## Требует внимания

1. **W14 открыта.** NeuralNote: манифест + adopt — это owner-work (загрузка файлов в `S:\Plugins\NeuralNote`, лицензионное решение по CC BY-NC для коммерческого использования).
2. **`master` не смержен с `dev`.** Расписание Gitea берёт workflow из дефолтной ветки — на `master` лежит старая версия `auto-update.yml` (до W18), т.е. расписание продолжит падать. Правило проекта: в `master` только через PR.
3. **Пуш от CI не проверен вживую.** Ни одного коммита `chore(bucket): auto-update` в истории нет: на момент фиксации все прогоны находили «всё up to date». Проверяется прогоном `Update KVRT` из `dev` — там манифест отстаёт (`20.0.14.0-202610170555` против текущей сборки `20.0.14.0-202610200320`).
4. **`checkver` для `bucket/winos.json` не работает** — у `oqyude/winos` на GitHub нет релизов, только теги. Автообновлением этот манифест не пойдёт. Чинить через API тегов опасно: порядок не гарантирован, манифест может откатиться на старый тег. Оставлено как есть, warning в логе.
5. **`state/powerlinks.json` в репозитории.** Машинное состояние пользователя, но коммитится сознательно (см. `src/modules/plugins/vars.ps1`). При появлении второго пользователя — решить, оставлять или перенести в `.gitignore`.
6. **Heritage-имена** в коде (после удаления powerlinks-репо): `state/powerlinks.json`, `Read/Write-PowerLinksState`, `$PowerLinksSandbox`, баннер `Plugin Deployment ::` (уже переименован с `powerlinks ::` в 57276a1), комментарии в `docs/roadmap.md` и `docs/symlink-manager.md`. Не блокирует, не правил в этом проходе.
7. **`src/init.ps1` делает `Set-Location` глобально.** Уводит CWD в `src/`. Безвредно для одноразового CLI, рискованно для интерактивного сеанса и тестовой параллельности. Не правил.
8. **Ctrl+C не проверен** в меню. Остальные выходные пути проверены вживую.
9. **Нет README.md.** `AGENTS.md` — bootstrap MetaAgent, не пользовательская документация.

## Ближайшие шаги

- **merge `dev` → `master`** — без него расписание auto-update продолжит использовать старую версию workflow.
- **Прогон `Update KVRT` из `dev`** — закрывает последний непроверенный участок цепочки (коммит + пуш с настоящим токеном).
- **W14** — owner work (NeuralNote adopt + загрузка).
- **Heritage-rename pass** — отдельной задачей: `state/powerlinks.json` → `state/plugin-deployment.json` + переименование функций + миграция. Бэклог, не блокер.
- **PR** — ветка `dev` не открыта в PR (правило: `master` только через PR). Сейчас активная работа идёт в `dev`, PR пока не нужен.
