# Протокол 06: Обновление метасостояния (METASTATE)

## Цель

По команде пользователя провести ревью накопленных requests, синхронизировать манифест, обновить слепок проекта и подготовить `.agent/` как полную картину для следующей сессии.

## Когда запускать

По команде пользователя:

- «обнови метасостояние»
- «update metastate»
- «подведи итог»
- «заверши сессию»

Может запускаться многократно — после каждой группы выполненных задач.

## Вход

- `.agent/requests/active/` — все request-ы со статусом `ready_for_review`
- `.agent/tasks/manifest.json`
- `.agent/context/project-state.md` (создан в ANALYSE, обновляется здесь)
- `.agent/roadmap/sources.md`
- `.agent/decisions/index.json`
- `.agent/checkpoints.json`

## Шаги

### 6.1. Собрать requests

Прочитать все файлы из `.agent/requests/active/` со статусом `ready_for_review`.

### 6.2. Ревью каждого request

Для каждого:

1. **Верифицировать** — тесты проходят, LSP чист, AC выполнены, коммиты на месте.
2. **Принять или отклонить:**

   - ✅ **approved**:
     - Переместить в `.agent/requests/archive/`.
     - В `manifest.json` убедиться: `status: "completed"`.

   - ❌ **rejected**:
     - Оставить в `active/` с комментарием.
     - В `manifest.json`: `status: "reopened"`, добавить `rejection_reason`.
     - В request добавить `rejection_reason`.

### 6.3. Архивация завершённых задач

Для каждой `completed` задачи:

1. Создать `.agent/archive/tasks/{id}.json` — полное описание.
2. В `manifest.json` заменить на one-liner:

   ```json
   { "id": "T1", "title": "GET /health endpoint", "status": "archived", "origin": "user:direct" }
   ```

### 6.4. Обновить project-state

Переписать `.agent/context/project-state.md` с учётом выполненных задач:

- Обновить список модулей (добавлены / изменены).
- Обновить архитектурную схему (кратко).
- Обновить статус тестов.
- Добавить новые ADR.
- Убрать закрытые concerns.

**Цель:** следующий агент читает `project-state.md` и понимает проект, не открывая исходники.

### 6.5. Обновить roadmap

В `.agent/roadmap/sources.md`:

- Отметить выполненные пункты.
- Пересчитать приоритеты.
- Добавить новые источники (если появились).

### 6.6. Индекс архива

Создать/обновить `.agent/archive/index.json`:

```json
{
  "version": "3.0.0",
  "archived_at": "<timestamp>",
  "tasks": [{ "id": "T1", "title": "...", "archived_at": "<timestamp>" }],
  "requests": [{ "id": "req-T1", "task_id": "T1", "archived_at": "<timestamp>" }],
  "checkpoints": [{ "file": "checkpoints/<ts>.json", "archived_at": "<timestamp>" }]
}
```

### 6.7. Создать handoff-summary

Создать `.agent/handoff-summary.md` — полная сводка для следующего агента:

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

### 6.8. Обновить checkpoints

```json
{ "phases": { "metastate": "completed" }, "last_updated": "<timestamp>" }
```

## Выход

- `.agent/requests/archive/` — подтверждённые request-ы
- `.agent/archive/tasks/{id}.json` — архив задач
- Обновлённый `.agent/context/project-state.md`
- Обновлённый `.agent/roadmap/sources.md`
- `.agent/handoff-summary.md`
- `.agent/archive/index.json`
- Финальный `checkpoints.json`

## Критерии завершения

- [ ] Все `ready_for_review` requests проверены (approved / rejected)
- [ ] Approved перемещены в archive
- [ ] Completed задачи архивированы (one-liner в manifest)
- [ ] `project-state.md` отражает актуальное состояние
- [ ] `roadmap/sources.md` обновлён
- [ ] `archive/index.json` создан
- [ ] `handoff-summary.md` готов
- [ ] `checkpoints.json` финализирован
