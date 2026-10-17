# Протокол 04: Декомпозиция задач (DECOMPOSITION)

## Цель

Разбить цель пользователя (и архитектурный план, если есть) на атомарные, независимо выполнимые задачи. Записать в `manifest.json` + `manifest.md`.

## Вход

- `.agent/context/analysis-report.md`
- `.agent/context/design-report.md` (опционально — для greenfield)
- `.agent/roadmap/sources.md` (опционально)
- `.agent/decisions/*.md` (опционально)
- Цель пользователя (goal из `checkpoints.json`)
- `.agent/rules/project-rules.md` — прочитать первым
- `.agent/checkpoints.json` (фаза decomposition: pending)

## Принципы

1. **Атомарность** — одна задача = одна логическая единица, выполнимая и проверяемая за один подход.
2. **Независимость (макс.)** — минимизировать зависимости между задачами.
3. **Тестируемость** — каждая задача имеет измеримые acceptance criteria.
4. **Границы** — задача не выходит за пределы `BOUNDARIES.md`.
5. **Порядок** — задачи с зависимостями выполняются строго последовательно.

## Шаги

### 4.1. Прочитать правила проекта

Прочитать `.agent/rules/project-rules.md`, применить.

### 4.2. Размер задачи

Задача должна укладываться в **1-2 часа работы агента**. Если крупнее — разбить.

Признак слишком крупной задачи:
- Нельзя сформулировать acceptance criteria одной строкой.
- Затрагивает 5+ файлов.
- Содержит союзы «и», «а также», «после чего».

### 4.3. Сверить с roadmap

Если существует `.agent/roadmap/sources.md`:

- Задачи из roadmap получают приоритет P0-P3 в соответствии с `sources.md`.
- Задачи без явного источника получают `origin: "decomposition"`.

### 4.4. Структура задачи

| Поле | Описание | Пример |
|---|---|---|
| `id` | Уникальный идентификатор | `T1`, `T2` |
| `title` | Что сделать | "Добавить модель User" |
| `description` | Как и зачем | "Создать SQLAlchemy модель..." |
| `type` | Тип | `feature`, `refactor`, `test`, `fix`, `config`, `design`, `docs`, `invariant` |
| `status` | Статус | `pending`, `in_progress`, `completed`, `failed`, `archived` |
| `origin` | Источник | `roadmap:file`, `adr:NNN`, `user:direct`, `agent:analysis`, `decomposition` |
| `files` | Файлы | `["app/models/user.py"]` |
| `depends_on` | Зависимости | `[]` или `["T0"]` |
| `acceptance_criteria` | 3-5 измеримых пунктов | `["Модель проходит миграцию"]` |
| `context` | Доп. информация | `"Смотри app/models/base.py"` |

**Типы origin:**

- `roadmap:{filename}` — из FUTURE/ или roadmap
- `adr:{NNN}` — из Architecture Decision Record
- `user:direct` — от пользователя
- `agent:analysis` — выявлено агентом
- `decomposition` — создано при декомпозиции
- `invariant:{adr_id}` — инвариант для ADR (создаётся командой `/invariant-tests`)
- `risk:{R-NNN}` — из Risk Register

### 4.5. Зелёная декомпозиция (greenfield/scaffold)

Если есть `design-report.md` — задачи на основе группировки из дизайна:

1. **T1: init** — инициализация, зависимости, scaffold.
2. **T2..Tn: features** — модули по одному.
3. **Tn+1: tests** — тесты (можно в составе feature).
4. **Tn+2: polish** — документация, форматирование.

### 4.6. Сортировка

Задачи в манифесте в порядке выполнения:

1. Без зависимостей.
2. Чьи зависимости уже выполнены.
3. С наибольшим числом зависимостей.

### 4.7. Записать manifest

Создать `.agent/tasks/manifest.json` по шаблону `TEMPLATES/task-manifest.json`.
Создать `.agent/tasks/manifest.md` по шаблону `TEMPLATES/task-manifest.md`.

### 4.8. Обновить checkpoints

```json
{
  "phases": { "decomposition": "completed" },
  "tasks": [...],
  "last_updated": "<timestamp>"
}
```

## Выход

- `.agent/tasks/manifest.json`
- `.agent/tasks/manifest.md`
- Обновлённый `checkpoints.json`

## Критерии завершения

- [ ] Цель разбита на атомарные задачи
- [ ] У каждой задачи — acceptance criteria, origin, files
- [ ] Зависимости корректны (нет циклов)
- [ ] Задачи сверены с roadmap (если `sources.md` существует)
- [ ] `manifest.json` и `manifest.md` созданы
- [ ] `checkpoints.json` обновлён
