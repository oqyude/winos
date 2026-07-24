# Project Rules

Правила, которым агент обязан следовать во всех фазах.
Добавляйте сюда условия, которые должны соблюдаться всегда — они будут прочитаны
перед началом каждой фазы и учтены при декомпозиции и реализации.

## Обязательные правила

- Всегда использовать английский язык для имён переменных, функций, классов и комментариев в коде
- Всегда запускать тесты (`.\scripts\test.ps1`) перед завершением задачи
- Следовать существующим конвенциям кода в проекте
- Все модули принимают `[string]$action` с `[ValidateSet(...)]`

## Запреты

- Не изменять CI/CD конфигурацию без явного разрешения
- Не удалять существующие файлы (только в рамках явной задачи)
- Не коммитить в main/master без PR
- Не добавлять проверку администратора (проект работает без elevation)

## Конвенции проекта

- Имена функций: approved verbs (`Set-`, `Remove-`, `Update-`, `Get-`, `Invoke-`, `Read-`, `Show-`)
- Имена переменных: PascalCase для модулей/scope, lowerCamelCase для JSON-полей
- Точка входа: `main.ps1` (CLI + интерактив)
- Скрипты: `scripts/lint.ps1`, `scripts/test.ps1`
- Тесты: `tests/`, smoke-тесты с Pester 5.x
- Конфиг: `data/data.json` (version 2, схема symlinks[])
- Линтер-конфиг: `.pspsscriptanalyzer.psd1`

## Структура проекта

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
        isolate.ps1              # per-app скрипты из data/isolate/
  scripts/
    lint.ps1                     # Invoke-ScriptAnalyzer
    test.ps1                     # Invoke-Pester
  tests/
    {module}.Tests.ps1
    modules/
      {module}.Tests.ps1
  data/
    data.json                    # version 2, symlinks[]
    isolate/                     # per-app скрипты
    autorun/                     # .lnk для автозапуска
  bucket/                        # Scoop-манифесты
  .pspsscriptanalyzer.psd1       # конфиг линтинга
```

## Команды

- Запуск приложения: `.\main.ps1` (интерактив) или `.\main.ps1 "Module" action` (CLI)
- Запуск тестов: `.\scripts\test.ps1`
- Запуск линтера: `.\scripts\lint.ps1`
