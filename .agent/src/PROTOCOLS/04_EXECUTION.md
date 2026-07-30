# Протокол 04: Исполнение задач (EXECUTION)

## Цель

Выполнить задачи из manifest.json: реализовать код, написать тесты, закоммитить, создать request — артефакт результата.

## Вход

- `.agent/tasks/manifest.json` — манифест с задачами
- `.agent/context/analysis-report.md` — контекст проекта
- `.agent/context/design-report.md` — архитектурный план (опционально)
- `.agent/decisions/*.md` — ADR (опционально)
- `.agent/rules/project-rules.md` — правила проекта
- `.agent/checkpoints.json` (фаза execution: pending)

## Шаги

### 4.0. Setup окружения (первый запуск)

Если это первый запуск EXECUTION в сессии:
- Установить зависимости (через штатный пакетный менеджер)
- Запустить сборку/базовые тесты для верификации окружения
- Записать baseline в `.agent/context/baseline-test-report.log`

### 4.1. Выбор задачи

Найти в `.agent/tasks/manifest.json` задачу, удовлетворяющую всем условиям:
- `status: "pending"`
- Все `depends_on` имеют статус `completed` или `archived`

Если таких задач нет — EXECUTION завершён, перейти к ожиданию команды пользователя.

### 4.2. Блокировка задачи

Отметить задачу в манифесте:
```json
{
  "id": "T1",
  "status": "in_progress"
}
```

### 4.3. Исполнение

Реализовать задачу в соответствии с acceptance criteria:
- Следовать конвенциям проекта (выявленным в ANALYSIS)
- Соблюдать BOUNDARIES.md
- Если задача ссылается на ADR — следовать архитектурному решению
- Писать код + тесты

### 4.4. Верификация

- Запустить тесты (все или релевантные)
- Проверить LSP diagnostics на изменённых файлах
- Убедиться, что acceptance criteria выполнены

### 4.5. Коммит

Сделать git-коммит с результатами задачи. Сообщение коммита должно отражать суть выполненной задачи.

### 4.6. Создание request

Создать `.agent/requests/active/req-{task_id}.json`:

```json
{
  "request_id": "req-T1",
  "task_id": "T1",
  "title": "GET /health endpoint",
  "status": "ready_for_review",
  "goal": "Добавить ручку GET /health с тестами",
  "changes": {
    "summary": "Создан health router, подключён в main.py, написаны тесты",
    "commits": ["abc1234", "abc1235"],
    "files_changed": [
      "app/routers/health.py",
      "app/main.py",
      "tests/test_health.py"
    ]
  },
  "verification": {
    "tests_passed": "24/24",
    "lsp_clean": true
  },
  "fulfills_ac": [
    "Ручка возвращает 200 + {\"status\":\"ok\"}"
  ]
}
```

Request фиксирует:
- **changes.summary** — краткая суть изменений (не полный diff, а именно суть)
- **changes.commits** — ссылки на коммиты (чтобы можно было проанализировать при ревью)
- **changes.files_changed** — какие файлы затронуты
- **verification** — результаты проверки
- **fulfills_ac** — какие acceptance criteria закрыты

### 4.7. Завершение задачи

В манифесте:
```json
{
  "id": "T1",
  "status": "completed"
}
```

### 4.8. Цикл

Перейти к шагу 4.1 — выбрать следующую задачу.
Если задач больше нет — сообщить пользователю и ожидать команду (METASTATE или новую задачу).

## Request как единица результата

Request — ключевой артефакт v2.1. Не просто «задача сделана», а документированный результат:
- Что сделано (суть, не diff)
- Как проверить (коммиты, тесты)
- Что закрыто (acceptance criteria)

Request проходит ревью в фазе METASTATE:
- `ready_for_review` → после проверки → `approved` или `rejected`

## Выход

- Выполненные задачи в manifest.json (status: completed)
- `.agent/requests/active/req-{task_id}.json` для каждой выполненной задачи
- Обновлённый checkpoints.json (`phases.execution = "in_progress"` или `"completed"`)

## Критерии завершения

Фаза EXECUTION не имеет единого момента завершения — она циклична. Критерии для одной итерации:

- [ ] Acceptance criteria задачи выполнены
- [ ] Тесты проходят
- [ ] LSP diagnostics чист
- [ ] Коммит создан
- [ ] Request создан в `.agent/requests/active/`
- [ ] Задача в manifest.json отмечена completed
