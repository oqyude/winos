# Протокол 05: Исполнение задач (EXECUTION)

## Цель

Выполнить задачи из `manifest.json`: реализовать код, написать тесты, закоммитить, создать request — артефакт результата.

EXECUTION — **циклическая** фаза. Работает, пока есть задачи со статусом `pending` и выполненными `depends_on`.

## Вход

- `.agent/tasks/manifest.json`
- `.agent/context/analysis-report.md`
- `.agent/context/design-report.md` (опционально)
- `.agent/decisions/*.md` (опционально)
- `.agent/rules/project-rules.md` — прочитать первым
- `.agent/checkpoints.json` (фаза execution: pending)

## Шаги (цикл)

### 5.1. Прочитать правила проекта

Прочитать `.agent/rules/project-rules.md`, применить.

### 5.2. Setup окружения (первый запуск)

Если это первый запуск EXECUTION в сессии:

- Установить зависимости через штатный пакетный менеджер.
- Запустить сборку / базовые тесты.
- Записать baseline в `.agent/context/baseline-test-report.log`.

### 5.3. Выбрать задачу

Найти в `manifest.json` задачу, удовлетворяющую:

- `status: "pending"`
- Все `depends_on` имеют `status: "completed"` или `"archived"`.

Если таких нет — EXECUTION завершён, перейти к ожиданию команды пользователя.

### 5.4. Заблокировать задачу

В `manifest.json`:

```json
{ "id": "T1", "status": "in_progress" }
```

### 5.5. Исполнить

- Следовать конвенциям проекта (из ANALYSE).
- Соблюдать `BOUNDARIES.md`.
- Если задача ссылается на ADR — следовать архитектурному решению.
- Писать код + тесты.

### 5.6. Верифицировать

- Запустить тесты (все или релевантные).
- Проверить LSP diagnostics на изменённых файлах.
- Убедиться, что acceptance criteria выполнены.

### 5.7. Закоммитить

Сделать git-коммит. Сообщение — суть задачи.

### 5.8. Создать request

Создать `.agent/requests/active/req-{task_id}.json` по шаблону `TEMPLATES/request.json`:

```json
{
  "request_id": "req-T1",
  "task_id": "T1",
  "title": "GET /health endpoint",
  "status": "ready_for_review",
  "goal": "Добавить ручку GET /health с тестами",
  "changes": {
    "summary": "Создан health router, подключён в main.py, написаны тесты",
    "commits": ["abc1234"],
    "files_changed": ["app/routers/health.py", "app/main.py", "tests/test_health.py"]
  },
  "verification": {
    "tests_passed": "24/24",
    "lsp_clean": true
  },
  "fulfills_ac": ["Ручка возвращает 200 + {\"status\":\"ok\"}"]
}
```

Request фиксирует:
- **summary** — суть изменений (не diff).
- **commits** — ссылки на коммиты.
- **files_changed** — какие файлы.
- **verification** — тесты + LSP.
- **fulfills_ac** — какие acceptance criteria закрыты.

### 5.9. Завершить задачу

```json
{ "id": "T1", "status": "completed" }
```

### 5.10. Цикл

Перейти к шагу 5.3. Если задач больше нет — сообщить пользователю и ожидать команду (METASTATE, новая задача, или завершение).

## Request как единица результата

Не просто «задача сделана», а документированный результат. Request проходит ревью в фазе METASTATE:

- `ready_for_review` → после проверки → `approved` или `rejected`.

## Команды во время EXECUTION

В любой момент цикла пользователь может вызвать:

- **/adr** — зафиксировать архитектурное решение, появившееся в процессе.
- **/red-team** — попытаться сломать текущий подход.
- **/risk-register** — зафиксировать новый риск.

Команды не прерывают EXECUTION, но могут добавить задачи в manifest.

## Выход

- Выполненные задачи в `manifest.json` (status: completed)
- `.agent/requests/active/req-{task_id}.json` для каждой выполненной задачи
- Обновлённый `checkpoints.json`

## Критерии завершения (одна итерация)

- [ ] Acceptance criteria выполнены
- [ ] Тесты проходят
- [ ] LSP diagnostics чист
- [ ] Коммит создан
- [ ] Request создан в `.agent/requests/active/`
- [ ] Задача в `manifest.json` отмечена completed
