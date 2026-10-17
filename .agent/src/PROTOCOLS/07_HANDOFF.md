# Протокол 07: Завершение сессии (HANDOFF)

## Цель

Финализация сессии: валидация структуры `.agent/`, финальный `session-summary.md`, отметка `phases.handoff = "completed"`.

> Если перед HANDOFF был METASTATE — архивация, project-state, handoff-summary уже готовы. HANDOFF только валидирует и финализирует.

## Вход

- `.agent/checkpoints.json` (все фазы кроме handoff: completed или skipped)
- Все артефакты `.agent/`

## Шаги

### 7.1. Проверить: был ли METASTATE?

Если существуют `.agent/handoff-summary.md` и `.agent/context/project-state.md` (обновлён) — METASTATE выполнен. Перейти к шагу 7.3.

Если нет — выполнить лёгкую архивацию (шаг 7.2).

### 7.2. Лёгкая архивация (если METASTATE не было)

Если есть `completed` задачи в `manifest.json`:

- Архивировать в `.agent/archive/tasks/{id}.json`.
- Заменить в `manifest.json` на one-liner.
- Создать `.agent/archive/index.json`.

### 7.3. Валидация

Проверить:

- [ ] Все фазы в `checkpoints.json` отмечены `completed` или `skipped`.
- [ ] `.agent/` содержит обязательные файлы:
  - `checkpoints.json`
  - `context/analysis-report.md`
  - `context/project-state.md`
  - `tasks/manifest.json` + `manifest.md`
  - `rules/project-rules.md`
  - `src/GUIDE.md`
  - `src/BOUNDARIES.md`
  - `src/VERSION`
  - `src/PROTOCOLS/`
  - `src/COMMANDS/`
  - `src/TEMPLATES/`
- [ ] В `manifest.json` нет циклических зависимостей.
- [ ] У каждой задачи — measurable acceptance criteria и origin.
- [ ] `AGENTS.md` присутствует в корне репозитория.

### 7.4. Создать session-summary

Создать `.agent/session-summary.md`:

```markdown
# Session Summary

**Session:** <id>
**MetaAgent version:** 3.0.0
**Date:** <timestamp>
**Goal:** <goal>

## Phases Executed
- [x] INIT
- [x] ANALYSE
- [x] ROADMAP
- [x] DESIGN (или skipped)
- [x] DECOMPOSITION
- [x] EXECUTION (N tasks)
- [x] METASTATE (или skipped)
- [x] HANDOFF

## Results
- Tasks completed: N
- Requests approved: N
- Files changed: [list]

## Next
Следующий агент: читай `.agent/handoff-summary.md`.
```

### 7.5. Финализировать checkpoints

```json
{ "phases": { "handoff": "completed" }, "last_updated": "<timestamp>" }
```

### 7.6. Сигнал

```
HANDOFF COMPLETE

Session: <session_id>
Target: <target_repo>
Type: <existing | greenfield | scaffold>
Tasks: <N> total, <M> completed, <K> pending

Следующий агент начинает с .agent/handoff-summary.md
```

## Выход

- `.agent/session-summary.md`
- Финальный `.agent/checkpoints.json`
- (если METASTATE не было) `.agent/archive/index.json`

## Критерии завершения

- [ ] Все артефакты на месте
- [ ] (если METASTATE не было) `completed` задачи архивированы
- [ ] `session-summary.md` создан
- [ ] `checkpoints.json` финализирован
- [ ] Сигнал отправлен пользователю
