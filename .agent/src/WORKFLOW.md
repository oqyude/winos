# WORKFLOW — Сквозной пример сессии

---

## Сценарий A: Existing проект

**Цель:** Добавить в существующий FastAPI-проект ручку GET /health с тестами.

**Целевой репозиторий:** `github.com/example/fastapi-app`

**Пользователь:** "Добавь health-check endpoint и тесты к нему"

---

### Фаза INIT

Мета-агент читает `.agent/metaagent-request.md`, клонирует репозиторий, создаёт `.agent/`, пишет начальный чекпоинт:

```json
{
  "metaagent_version": "1.1.0",
  "session_id": "ses_abc123",
  "target_repo": "/tmp/fastapi-app",
  "goal": "Добавить GET /health с тестами",
  "project_type": "existing",
  "config": {
    "depth": 6,
    "design": { "adr": false, "alternative_arch": false },
    "red_team": false,
    "risk_register": false,
    "decomposition": { "invariant_tests": false },
    "handoff": { "layer_structure": false }
  },
  "phases": {
    "analysis": "pending",
    "design": "pending",
    "red_team": "pending",
    "decomposition": "pending",
    "environment": "pending",
    "handoff": "pending"
  },
  "tasks": [],
  "last_updated": "2026-07-12T15:00:00Z"
}
```

---

### Фаза ANALYSE

Мета-агент выполняет `PROTOCOLS/01_ANALYSIS.md`. Определяет тип проекта: `existing`.

Результат `.agent/analysis-report.md`:

```markdown
## 2. Стек технологий
| Язык | Python 3.12 |
| Фреймворк | FastAPI |
| Тестовый раннер | pytest + httpx |
| Пакетный менеджер | pip + requirements.txt |

## 3. Архитектура
├── app/
│   ├── main.py
│   ├── routers/
│   │   └── users.py
│   ├── models/
│   │   └── user.py
│   └── schemas/
│       └── user.py
├── tests/
│   └── test_users.py
```

Тесты запущены: **12 passed, 0 failed**.

Чекпоинт обновлён: `analysis = "completed"`, `project_type = "existing"`.
Фаза DESIGN пропускается.

---

### Фаза DECOMPOSITION

Мета-агент выполняет `PROTOCOLS/03_DECOMPOSITION.md`.

Декомпозиция цели "Добавить GET /health с тестами":

| ID | Задача | Тип | Зависит от | AC |
|---|---|---|---|---|
| T1 | Создать health-check router | feature | — | Ручка возвращает 200 + {"status":"ok"} |
| T2 | Подключить router в main.py | config | T1 | Ручка доступна по /health |
| T3 | Написать тесты для /health | test | T2 | Тесты проверяют 200 и структуру ответа |

Создан `.agent/task-manifest.json` и `.agent/task-manifest.md`.

Чекпоинт обновлён: `decomposition = "completed"`. Tasks: T1-T3 со статусом `pending`.

---

### Фаза SETUP

Мета-агент выполняет `PROTOCOLS/04_ENVIRONMENT_SETUP.md` (ветка A: existing).

- `pip install -r requirements.txt` — OK
- Запуск pytest — OK, 12 passed (базовый тест)
- Результат в `.agent/baseline-test-report.log`

Чекпоинт обновлён: `environment = "completed"`.

---

### Фаза HANDOFF

Мета-агент выполняет `PROTOCOLS/05_HANDOFF.md`.

Создан `.agent/handoff-summary.md`:

```markdown
## Next Steps
Исполнительный агент начинает с задачи T1: "Создать health-check router".

## Caveats
- Придерживаться стиля существующего роутера users.py
- Не менять существующие тесты
- Убедиться, что response model соответствует JSON: {"status": "ok"}
```

Чекпоинт финализирован:

```json
{
  "metaagent_version": "1.1.0",
  "session_id": "ses_abc123",
  "goal": "Добавить GET /health с тестами",
  "project_type": "existing",
  "config": {
    "depth": 6,
    "design": { "adr": false, "alternative_arch": false },
    "red_team": false,
    "risk_register": false,
    "decomposition": { "invariant_tests": false },
    "handoff": { "layer_structure": false }
  },
  "phases": {
    "analysis": "completed",
    "design": "skipped",
    "red_team": "skipped",
    "decomposition": "completed",
    "environment": "completed",
    "handoff": "completed"
  },
  "tasks": [
    { "id": "T1", "title": "Создать health-check router", "status": "pending" },
    { "id": "T2", "title": "Подключить router в main.py", "status": "pending" },
    { "id": "T3", "title": "Написать тесты для /health", "status": "pending" }
  ],
  "last_updated": "2026-07-12T15:15:00Z"
}
```

Сигнал пользователю:

```
HANDOFF COMPLETE
Session: ses_abc123
Target: /tmp/fastapi-app
Type: existing
Tasks: 3 tasks ready

Исполнительный агент может начинать с задачи T1.
```

---

## Сценарий B: Greenfield проект (Cashflow Forecasting)

**Цель:** Спроектировать и реализовать MVP сервиса прогнозирования денежных потоков.

**Целевой репозиторий:** `github.com/example/cashflow-app`

**README:** README содержит описание:
> Сервис для прогнозирования движения денежных средств (cashflow forecasting).
> Пользователь загружает CSV с транзакциями, сервис строит прогноз на N дней вперёд.
> Стек: Python, FastAPI, SQLite, matplotlib для графиков.

---

### Фаза INIT

```json
{
  "metaagent_version": "1.1.0",
  "session_id": "ses_def456",
  "target_repo": "/tmp/cashflow-app",
  "goal": "Спроектировать и реализовать MVP сервиса прогнозирования денежных потоков",
  "project_type": "greenfield",
  "config": {
    "depth": 7,
    "design": { "adr": true, "alternative_arch": true },
    "red_team": false,
    "risk_register": true,
    "decomposition": { "invariant_tests": true },
    "handoff": { "layer_structure": true }
  },
  "phases": {
    "analysis": "pending",
    "design": "pending",
    "red_team": "pending",
    "decomposition": "pending",
    "environment": "pending",
    "handoff": "pending"
  },
  "tasks": [],
  "last_updated": "2026-07-12T16:00:00Z"
}
```

---

### Фаза ANALYSE

Мета-агент выполняет `PROTOCOLS/01_ANALYSIS.md`. Определяет тип проекта: `greenfield`.

Сканирование корня: пусто (кроме README.md, LICENSE, .gitignore).

Извлечение требований из README:

| Тип | Требование |
|---|---|
| Функциональное | Загрузка CSV с транзакциями |
| Функциональное | Прогноз на N дней вперёд |
| Нефункциональное | Python, FastAPI |
| Нефункциональное | SQLite |
| Нефункциональное | matplotlib для графиков |

Чекпоинт: `analysis = "completed"`, `project_type = "greenfield"`.

Так как проект greenfield — мета-агент переходит к фазе DESIGN.

---

### Фаза DESIGN

Мета-агент выполняет `PROTOCOLS/02_DESIGN.md`.

Результат `.agent/design-report.md`:

```markdown
## 1. Технологический стек
| Язык | Python 3.12 |
| Фреймворк | FastAPI + Pydantic |
| БД | SQLite + SQLAlchemy |
| Визуализация | matplotlib |
| Тесты | pytest |

## 2. Архитектура
[Client] → HTTP → [FastAPI] → [CashflowService] → [SQLite]
                                     ↓
                              [ForecastEngine] → [matplotlib]

## 3. Модули
| Модуль | Ответственность |
|---|---|
| app/main.py | Точка входа, роуты |
| app/models/transaction.py | Модель транзакции |
| app/services/cashflow.py | Бизнес-логика |
| app/services/forecast.py | Алгоритм прогноза |
| app/services/upload.py | Парсинг CSV |
| app/schemas/ | Pydantic схемы |

## 4. Модели
Transaction: id, date, amount, category, description

## 5. API
POST /upload — загрузить CSV
GET /forecast?days=30 — прогноз + график

## 6. Задачи (pre-grouped)
T1: init — проект, зависимости, scaffold
T2: models — модели + миграции
T3: upload — загрузка CSV
T4: forecast — алгоритм прогноза
T5: API — endpoints
T6: tests — тесты
```

Чекпоинт: `design = "completed"`.

---

### Фаза DECOMPOSITION

Мета-агент выполняет `PROTOCOLS/03_DECOMPOSITION.md`, используя design-report.

Итоговые задачи:

| ID | Задача | Тип | Зависит от |
|---|---|---|---|
| T1 | Инициализация проекта + зависимости | config | — |
| T2 | Модель Transaction + SQLAlchemy + SQLite | feature | T1 |
| T3 | Сервис загрузки и парсинга CSV | feature | T2 |
| T4 | ForecastEngine — алгоритм прогноза | feature | T2 |
| T5 | API endpoints + документация | feature | T3, T4 |
| T6 | Тесты (unit + integration) | test | T5 |

---

### Фаза SETUP

Мета-агент выполняет `PROTOCOLS/04_ENVIRONMENT_SETUP.md` (ветка B: greenfield).

- `poetry init` + создание pyproject.toml
- Установка fastapi, uvicorn, sqlalchemy, matplotlib, pytest
- Создание scaffold-структуры: `app/models/`, `app/services/`, `app/schemas/`, `tests/`
- Пустые заглушки модулей
- `.agent/baseline-test-report.log`: "0 tests — greenfield, scaffold готов"

---

### Фаза HANDOFF

```markdown
HANDOFF COMPLETE
Session: ses_def456
Target: /tmp/cashflow-app
Type: greenfield
Config: depth=7, adr=yes, risk_register=yes, invariant_tests=yes
Tasks: 6 tasks ready

Исполнительный агент может начинать с задачи T1 (init).
Архитектурный план: .agent/design-report.md
ADR: .agent/layer-1/adr/
```

---

## После HANDOFF: работа исполнительного агента

Исполнительный агент читает `.agent/handoff-summary.md`, `.agent/task-manifest.json`, выполняет задачи по порядку, обновляя checkpoints.json после каждой.

После завершения всех задач:

```
ALL TASKS COMPLETE
Session: ses_def456
Tasks: 6/6 completed

T1: Инициализация проекта ✓
T2: Модель Transaction ✓
T3: Сервис загрузки CSV ✓
T4: ForecastEngine ✓
T5: API endpoints ✓
T6: Тесты ✓

Все тесты проходят: 24/24 passed.
```
