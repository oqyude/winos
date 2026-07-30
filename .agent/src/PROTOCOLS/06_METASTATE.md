# Протокол 06: Обновление метасостояния (METASTATE)

## Цель

По команде пользователя «обнови метасостояние проекта» — провести ревью накопленных requests, синхронизировать манифест, обновить слепок проекта и подготовить `.agent/` как полную картину для следующей сессии.

## Вход

- `.agent/requests/active/` — все request-ы со статусом `ready_for_review`
- `.agent/tasks/manifest.json` — текущее состояние задач
- `.agent/context/project-state.md` — текущий слепок проекта (создан в ANALYSIS)
- `.agent/roadmap/sources.md` — дорожная карта (создана в ROADMAP)
- `.agent/checkpoints.json`

## Шаги

### 6.1. Сбор requests

Прочитать все файлы из `.agent/requests/active/` со статусом `ready_for_review`.
Каждый request — это выполненная задача, ожидающая подтверждения.

### 6.2. Ревью каждого request

Для каждого request:

1. **Верифицировать** — проверить, что verification корректен:
   - Тесты действительно проходят (перезапустить, если нужно)
   - LSP diagnostics чист
   - Acceptance criteria выполнены
   - При необходимости — проверить коммиты (git show)

2. **Принять или отклонить:**
   - ✅ **approved** — всё ОК:
     - Переместить request: `.agent/requests/active/` → `.agent/requests/archive/`
     - Убедиться, что задача в manifest.json имеет `status: "completed"`
   - ❌ **rejected** — есть проблемы:
     - Оставить request в active/ с комментарием о причинах отказа
     - В manifest.json: `status: "reopened"`, снять `claimed_by`
     - Добавить `rejection_reason` в request

### 6.3. Архивация завершённых задач

Для каждой задачи в manifest.json со статусом `completed`:
1. Создать `.agent/archive/tasks/{id}.json` — полное описание задачи (все поля)
2. В manifest.json заменить на one-liner:
   ```json
   { "id": "T1", "title": "GET /health endpoint", "status": "archived", "origin": "user:direct" }
   ```

### 6.4. Обновление project-state.md

Переписать `.agent/context/project-state.md` с учётом выполненных задач:
- Обновить список модулей (какие добавлены/изменены)
- Обновить архитектурную схему (кратко)
- Обновить статус тестов
- Добавить новые ADR, если появились
- Убрать закрытые concerns

Цель: следующий агент читает project-state.md и понимает проект, не открывая исходники.

### 6.5. Обновление roadmap

В `.agent/roadmap/sources.md`:
- Отметить выполненные пункты
- Пересчитать приоритеты
- Если появились новые источники — добавить

### 6.6. Индекс архива

Создать/обновить `.agent/archive/index.json`:
```json
{
  "version": "2.1.0",
  "archived_at": "<timestamp>",
  "tasks": [
    { "id": "T1", "title": "GET /health", "archived_at": "<timestamp>" }
  ],
  "requests": [
    { "id": "req-T1", "task_id": "T1", "archived_at": "<timestamp>" }
  ],
  "checkpoints": [
    { "file": "checkpoints/<timestamp>.json", "archived_at": "<timestamp>" }
  ]
}
```

### 6.7. Создание handoff-summary.md

Создать `.agent/handoff-summary.md` — полную сводку для следующего агента:

```markdown
## Session Summary
**Session:** <id>
**Goal:** <goal>
**Completed:** N tasks
**Pending:** M tasks
**Approved requests:** req-T1, req-T2

## Project State
(краткая выжимка из project-state.md)

## Next Steps
(с чего начать следующую сессию)

## Key Artifacts
- Project state: `.agent/context/project-state.md`
- Tasks: `.agent/tasks/manifest.json`
- Roadmap: `.agent/roadmap/sources.md`
- Pending reviews: `.agent/requests/active/`
- Archive: `.agent/archive/index.json`
```

### 6.8. Финализация чекпоинта

Обновить checkpoints.json:
- `phases.metastate = "completed"`
- Актуальный список задач
- `last_updated`

## Выход

- Подтверждённые requests: `.agent/requests/archive/`
- Архив задач: `.agent/archive/tasks/{id}.json`
- Обновлённый project-state.md
- Обновлённый roadmap/sources.md
- `.agent/handoff-summary.md` — полная сводка
- `.agent/archive/index.json`
- Финальный checkpoints.json

## Критерии завершения

- [ ] Все ready_for_review requests проверены (approved/rejected)
- [ ] Approved requests перемещены в archive
- [ ] Completed задачи архивированы (one-liner в manifest)
- [ ] project-state.md отражает актуальное состояние проекта
- [ ] roadmap/sources.md обновлён
- [ ] archive/index.json создан
- [ ] handoff-summary.md готов
- [ ] checkpoints.json финализирован

## Когда запускать

По команде пользователя:
- «обнови метасостояние»
- «update metastate»
- «подведи итог»
- «заверши сессию»

Может запускаться многократно в течение жизни проекта — после каждой группы выполненных задач.
