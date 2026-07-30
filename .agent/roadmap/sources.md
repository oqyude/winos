# Roadmap Sources

**Last updated:** 2026-07-30
**Session:** MetaAgent Migration v1.1.1 → v2.1.0

---

## Source Inventory

### 1. Existing Documentation

| Source | Priority | Status | Notes |
|---|---|---|---|
| `docs/roadmap.md` | P1 | backlog | Forward-looking tasks from previous session |
| `docs/symlink-manager.md` | P2 | done | State model, action matrix, path resolution |

### 2. Archived Tasks (from previous session)

| ID | Title | Priority | Status |
|---|---|---|---|
| C1 | Миграция CSV → JSON | P0 | archived |
| C2 | Symlink Manager с method-архитектурой | P0 | archived |
| C3 | Unified $action | P0 | archived |
| C4 | Новый main.ps1 | P0 | archived |
| C5 | Essentials module | P0 | archived |
| C6 | Удалить админ-проверку и старые модули | P0 | archived |
| P3 | PSScriptAnalyzer + approved verbs | P1 | archived |
| P4 | Pester smoke-тесты | P1 | archived |
| P5 | Структура проекта + интерактив | P1 | archived |

### 3. Project Rules

- Source-of-truth root: `~/Storage/persist/`
- All modules use `[string]$action` with `[ValidateSet(...)]`
- Approved verbs for all functions
- Pester 5.x+ smoke tests required

---

## Priority Legend

| Priority | Definition |
|---|---|
| P0 | Critical — must be done |
| P1 | High — should be done |
| P2 | Medium — nice to have |
| P3 | Low — future |
