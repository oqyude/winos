# Task Manifest

**Session:** 00000000-0000-0000-0000-000000000001
**Goal:** Инициализация проекта winos: рефакторинг, миграция CSV→JSON, Symlink Manager, унификация.
**Date:** 2026-07-24

---

## Completed

| ID | Title | Type | Status |
|---|---|---|---|
| C1 | Миграция CSV → JSON (data/data.json v2) | refactor | completed |
| C2 | Symlink Manager с method-архитектурой | feature | completed |
| C3 | Unified $action во всех модулях | refactor | completed |
| C4 | Новый run.ps1 (CLI + интерактив) | refactor | completed |
| C5 | Essentials module (ex Windows Cursor) | fix | completed |
| C6 | Удалить админ-проверку и старые модули | refactor | completed |

## Pending

| ID | Title | Type | Depends On | Status |
|---|---|---|---|---|---|
| P3 | PSScriptAnalyzer + линтинг | config | — | pending |
| P4 | Pester тесты + CI | config | P3 | pending |
