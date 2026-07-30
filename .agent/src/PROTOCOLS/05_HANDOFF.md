# Протокол 07: Завершение сессии (HANDOFF)

## Цель

Легковесное завершение сессии: валидация структуры `.agent/`, финализация чекпоинтов, формирование сводки. Архивация и обновление project-state выполняются фазой METASTATE.

> **Важно:** если перед HANDOFF была выполнена фаза METASTATE (06) — архивация, project-state и handoff-summary уже готовы.
> HANDOFF в этом случае только валидирует и финализирует.

## Вход

- `.agent/checkpoints.json` (все предыдущие фазы: completed)
- `.agent/context/project-state.md` (опционально, создан в ANALYSIS, обновлён в METASTATE)
- `.agent/handoff-summary.md` (опционально, создан в METASTATE)
- `.agent/tasks/manifest.json`
- `.agent/roadmap/sources.md` (опционально)
- Все артефакты `.agent/`

## Шаги

### 5.1. Проверка: была ли METASTATE?

Если существует `.agent/handoff-summary.md` и `.agent/context/project-state.md`:
- METASTATE уже выполнен
- Перейти к шагу 5.3 (Валидация)

Если нет:
- METASTATE не выполнялся (например, сессия завершается до execution)
- Перейти к шагу 5.2 (Лёгкая архивация)

### 5.2. Лёгкая архивация (если METASTATE не было)

Если есть completed задачи в manifest.json:
- Архивировать их в `.agent/archive/tasks/{id}.json`
- Заменить в manifest.json на one-liner
- Создать `.agent/archive/index.json`

Если нет completed задач — пропустить.

### 5.3. Валидация

Проверить:

- [ ] Все фазы отмечены как `completed` или `skipped` в checkpoints.json
- [ ] `.agent/` содержит обязательные файлы:
  - `checkpoints.json`
  - `context/analysis-report.md`
  - `context/project-state.md`
  - `tasks/manifest.json` + `tasks/manifest.md`
  - `src/META_AGENT_GUIDE.md`
  - `src/BOUNDARIES.md`
  - `src/VERSION`
  - `src/PROTOCOLS/`
  - `src/TEMPLATES/`
  - `rules/project-rules.md`
- [ ] В `.agent/tasks/manifest.json` нет циклических зависимостей
- [ ] Все acceptance criteria сформулированы измеримо
- [ ] Для каждой задачи указаны affected files и origin
- [ ] `.agent/src/` содержит актуальные исходники
- [ ] `AGENTS.md` присутствует в корне репозитория

### 5.4. Создание session-summary.md

Создать `.agent/session-summary.md` — краткая сводка сессии:

```markdown
# Session Summary

**Session:** <id>
**MetaAgent version:** 2.1.0
**Date:** <timestamp>
**Goal:** <goal>

## Phases Executed
- [x] INIT
- [x] ANALYSIS
- [x] ROADMAP
- [x] DESIGN
- [x] DECOMPOSITION
- [x] EXECUTION (N tasks)
- [x] METASTATE
- [x] HANDOFF

## Results
- Tasks completed: N
- Requests approved: N
- Files changed: [list]

## Next
Следующий агент: читай .agent/handoff-summary.md
```

### 5.5. Финализация checkpoints

- Отметить `phases.handoff = "completed"`
- Записать финальный `last_updated`

### 5.6. Сигнал

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
- `.agent/checkpoints.json` (финальный)
- Если METASTATE не было: `.agent/archive/index.json`

## Критерии завершения

- [ ] Все артефакты на месте (согласно структуре .agent/)
- [ ] Если METASTATE не было — completed задачи архивированы
- [ ] session-summary.md создан
- [ ] checkpoints.json финализирован
- [ ] Сигнал отправлен пользователю
