# Project State

**Last updated:** 2026-07-30
**MetaAgent version:** 2.1.0

---

## Overview

| Field | Value |
|---|---|
| Project | winos |
| Type | existing |
| Language | PowerShell 7.6.3 |
| Entry point | `main.ps1` |
| Branch | `dev` |
| Last session | Cleanup-сессия: привести артефакты MetaAgent в консистентное состояние после рефакторинга winos (M1-M7) |

## Architecture

```
winos/
  main.ps1                       # CLI + интерактив (Back/Exit)
  src/
    init.ps1                     # bootstrap
    vars.ps1                     # модули, пути
    modules/
      symlink-manager.ps1        # dispatcher: deploy/clean/redeploy
      essentials.ps1             # install/uninstall (cursor themes)
      methods/
        symlink.ps1              # Set-Symlink, Remove-ItemLogged
        isolate.ps1              # per-app скрипты
  scripts/
    lint.ps1                     # Invoke-ScriptAnalyzer
    test.ps1                     # Invoke-Pester
  tests/
    vars.Tests.ps1               # smoke: загрузка модулей
    modules/
      symlink-manager.Tests.ps1  # smoke: парсинг
      essentials.Tests.ps1       # smoke: парсинг
  data/
    data.json                    # version 2, symlinks[]
    isolate/                     # per-app скрипты
    autorun/                     # .lnk для автозапуска
  bucket/                        # Scoop-манифесты
  .pspsscriptanalyzer.psd1       # конфиг линтинга
```

## Completed Work (9 tasks)

| ID | Title | Status |
|---|---|---|
| C1 | Миграция CSV → JSON (data/data.json v2) | archived |
| C2 | Symlink Manager с method-архитектурой | archived |
| C3 | Unified $action во всех модулях | archived |
| C4 | Новый main.ps1 (CLI + интерактив) | archived |
| C5 | Essentials module (ex Windows Cursor) | archived |
| C6 | Удалить админ-проверку и старые модули | archived |
| P3 | PSScriptAnalyzer + approved verbs | archived |
| P4 | Pester smoke-тесты | archived |
| P5 | Структура проекта + интерактив | archived |

## Conventions

- PascalCase для модулей/scope, lowerCamelCase для JSON-полей
- Все модули принимают `[string]$action` с `[ValidateSet()]`
- Approved verbs: `Set-`, `Remove-`, `Update-`, `Get-`, `Invoke-`, `Read-`, `Show-`
- Dot-sourcing для vars, прямые вызовы для модулей
- Source-of-truth root: `~/Storage/persist/`

## Tests

- Runner: `.\scripts\test.ps1` (Pester 5.x+)
- Total: 11 smoke tests (all passed)
- Lint: PSScriptAnalyzer (0 warnings)

## Next Steps

See `docs/roadmap.md` for forward-looking tasks.
