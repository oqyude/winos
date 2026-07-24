# Task Manifest

**Session:** 00000000-0000-0000-0000-000000000001
**Goal:** Базовая инициализация проекта winos. Подготовка к работе и планированию.
**Date:** 2026-07-24T00:00:00.000Z

---

## Task Overview

| ID | Title | Type | Depends On | Status |
|---|---|---|---|---|
| T1 | Добавить PSScriptAnalyzer и конфигурацию линтинга | config | — | pending |
| T2 | Создать тестовую инфраструктуру Pester | config | — | pending |
| T3 | Добавить CI через GitHub Actions | config | T1, T2 | pending |
| T4 | Стандартизировать обработку ошибок в модулях | refactor | — | pending |
| T5 | Добавить валидацию CSV-конфигов перед использованием | feature | — | pending |
| T6 | Создать документацию модулей и архитектуры | docs | T4, T5 | pending |

**Total tasks:** 6

---

## Task Details

### T1: Добавить PSScriptAnalyzer и конфигурацию линтинга

**Type:** config

**Description:** Установить и настроить PSScriptAnalyzer — официальный линтер для PowerShell. Создать .psd1 конфиг с правилами, проверить существующие скрипты.

**Files:**
- `.pspsscriptanalyzer.psd1`
- `.vscode/settings.json`

**Depends on:** —

**Acceptance Criteria:**
- [ ] PSScriptAnalyzer установлен и запускается без ошибок
- [ ] Создан конфигурационный файл с базовыми правилами
- [ ] Все существующие .ps1 файлы проходят линтинг (или есть список игнорируемых правил)
- [ ] В корне проекта есть инструкция по запуску линтера

**Context:** Анализ показал отсутствие линтера. PowerShell Best Practices: именование (PascalCase для функций, команд), наличие help-блоков, обработка ошибок.

---

### T2: Создать тестовую инфраструктуру Pester

**Type:** config

**Description:** Установить Pester (фреймворк для тестирования PowerShell), создать базовую структуру tests/, написать smoke-тесты для проверки подгрузки модулей.

**Files:**
- `tests/`
- `tests/smoke.Tests.ps1`

**Depends on:** —

**Acceptance Criteria:**
- [ ] Pester установлен и доступен
- [ ] Создана директория tests/
- [ ] Smoke-тест проверяет, что vars.ps1 загружается без ошибок
- [ ] Smoke-тест проверяет, что все модули из списка существуют
- [ ] Команда Invoke-Pester завершается успешно (хотя бы 1 тест пройден)

**Context:** Сейчас тестов нет. Pester — стандартный фреймворк для PowerShell.

---

### T3: Добавить CI через GitHub Actions

**Type:** config

**Description:** Создать .github/workflows/ci.yml с запуском PSScriptAnalyzer и Pester-тестов на каждый push/PR.

**Files:**
- `.github/workflows/ci.yml`

**Depends on:** T1, T2

**Acceptance Criteria:**
- [ ] Workflow запускается на push в dev/main
- [ ] Workflow запускает PSScriptAnalyzer
- [ ] Workflow запускает Pester-тесты
- [ ] Workflow не падает при отсутствии изменений в коде

**Context:** CI/CD отсутствует. Базовый GitHub Actions для Windows (runs-on: windows-latest).

---

### T4: Стандартизировать обработку ошибок в модулях

**Type:** refactor

**Description:** Добавить единый шаблон try/catch во все модули, централизованные функции Write-Error и Write-Warning. Унифицировать параметры (все модули должны иметь param-блок с action).

**Files:**
- `src/modules/appdata-manager.ps1`
- `src/modules/autostart-manager.ps1`
- `src/modules/mounts-manager.ps1`
- `src/modules/package-manager.ps1`
- `src/modules/winget-installer.ps1`
- `src/modules/windows-cursor.ps1`
- `src/modules/deploy.ps1`

**Depends on:** —

**Acceptance Criteria:**
- [ ] Все модули имеют единый param-блок с [string]$Action
- [ ] Критические операции обёрнуты в try/catch с человекочитаемым сообщением
- [ ] Ошибки не приводят к падению всего скрипта без сообщения

**Context:** Сейчас appdata-manager.ps1 имеет try/catch, deploy.ps1 частично. Остальные модули не имеют обработки ошибок в критических участках.

---

### T5: Добавить валидацию CSV-конфигов перед использованием

**Type:** feature

**Description:** Создать функцию Validate-CsvConfig, которая проверяет структуру apps.csv и mounts.csv перед их использованием модулями. Добавить проверку обязательных колонок и типов.

**Files:**
- `src/modules/csv-validator.ps1`
- `data/apps.csv`
- `data/mounts.csv`

**Depends on:** —

**Acceptance Criteria:**
- [ ] Функция проверяет наличие обязательных колонок в CSV
- [ ] Функция сообщает о проблемах до начала операций с файловой системой
- [ ] Функция интегрирована в appdata-manager.ps1 и mounts-manager.ps1

**Context:** CSV-файлы — единственный источник конфигурации. Сейчас нет проверки их корректности, ошибка в CSV приводит к неявным сбоям.

---

### T6: Создать документацию модулей и архитектуры

**Type:** docs

**Description:** Написать MODULES.md с описанием каждого модуля, его действий (actions), формата CSV-конфигов и примерами использования.

**Files:**
- `MODULES.md`

**Depends on:** T4, T5

**Acceptance Criteria:**
- [ ] Описаны все 8 модулей с их actions
- [ ] Описаны форматы apps.csv и mounts.csv
- [ ] Описана архитектура запуска (run.ps1 → init → vars → modules)
- [ ] Добавлены примеры использования

**Context:** README.md даёт только общее описание. Нет документации по модулям и форматам конфигов.
