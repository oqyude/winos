# WORKFLOW — Сквозной пример сессии v3.0

---

## Сценарий: рефакторинг auth-модуля

**Цель:** Вынести логику из `auth/login.py` (450 строк, монолит) в отдельные модули `auth/router.py`, `auth/schemas.py`, `auth/deps.py`.

**Целевой репозиторий:** `github.com/example/fastapi-app`

**Пользователь:** «Вынеси авторизацию в отдельные модули».

**MetaAgent:** v3.0.0

---

### PROJECT LOOP

#### INIT

Агент читает `AGENTS.md`, переходит в `.agent/src/GUIDE.md`. Понимает цикл. Создаёт `.agent/`, копирует исходники, инициализирует `checkpoints.json`:

```json
{
  "metaagent_version": "3.0.0",
  "session_id": "ses_v30_001",
  "target_repo": "/tmp/fastapi-app",
  "goal": "Вынести авторизацию в auth/{router,schemas,deps}.py",
  "project_type": null,
  "phases": {
    "init": "completed",
    "analyse": "pending",
    "roadmap": "pending",
    "design": "pending",
    "decomposition": "pending",
    "execution": "pending",
    "metastate": "pending",
    "handoff": "pending"
  },
  "tasks": [],
  "last_updated": "2026-10-08T15:00:00Z"
}
```

#### ANALYSE

Агент сканирует проект:

- Стек: Python 3.12, FastAPI, SQLAlchemy, pytest.
- `auth/login.py` — 450 строк, монолит (цель рефакторинга).
- Тесты: 48 passed (baseline).

Создаёт:

- `.agent/context/analysis-report.md`
- `.agent/context/project-state.md` (начальный)

`checkpoints.json`: `project_type = "existing"`, `phases.analyse = "completed"`.

#### ROADMAP

- `FUTURE/` — пусто.
- `.agent/decisions/` — пусто.
- Единственный источник — пользовательский запрос.

Создаёт `.agent/roadmap/sources.md`:

```markdown
## User Requests
| Вынести авторизацию | P0 | user:direct |

## Consolidated Priority Queue
1. Вынести auth/ (user:direct) — P0
```

`phases.roadmap = "completed"`.

#### DESIGN

**Пропускается** (existing-проект). `phases.design = "skipped"`.

#### DECOMPOSITION

Задачи:

```json
{
  "tasks": [
    {
      "id": "T1",
      "title": "Создать auth/router.py",
      "origin": "user:direct",
      "files": ["app/auth/router.py"],
      "depends_on": [],
      "acceptance_criteria": [
        "Роуты авторизации вынесены из auth/login.py",
        "auth/router.py экспортирует router",
        "Существующие тесты проходят"
      ],
      "status": "pending"
    },
    {
      "id": "T2",
      "title": "Создать auth/schemas.py",
      "origin": "user:direct",
      "files": ["app/auth/schemas.py"],
      "depends_on": ["T1"],
      "acceptance_criteria": [
        "Pydantic схемы вынесены в auth/schemas.py",
        "Существующие тесты проходят"
      ],
      "status": "pending"
    },
    {
      "id": "T3",
      "title": "Создать auth/deps.py",
      "origin": "user:direct",
      "files": ["app/auth/deps.py"],
      "depends_on": ["T1"],
      "acceptance_criteria": [
        "Dependency injection функции вынесены в auth/deps.py",
        "Существующие тесты проходят"
      ],
      "status": "pending"
    }
  ]
}
```

`phases.decomposition = "completed"`.

---

### WORK LOOP (первая итерация)

#### EXECUTION — задача T1

1. Берёт T1 (`pending`, нет зависимостей).
2. `status = "in_progress"`.
3. Создаёт `app/auth/router.py` — переносит роуты.
4. Тесты: 48/48.
5. Коммит: `abc1234 — refactor: extract auth router`.
6. Создаёт request:

```json
{
  "request_id": "req-T1",
  "task_id": "T1",
  "title": "Создать auth/router.py",
  "status": "ready_for_review",
  "goal": "Вынести роуты авторизации",
  "changes": {
    "summary": "Роуты авторизации вынесены из auth/login.py в auth/router.py",
    "commits": ["abc1234"],
    "files_changed": ["app/auth/router.py", "app/auth/__init__.py", "tests/test_auth_router.py"]
  },
  "verification": { "tests_passed": "48/48", "lsp_clean": true },
  "fulfills_ac": ["Роуты вынесены", "Тесты проходят"]
}
```

7. `T1 → completed`.

#### EXECUTION — задача T2

Создаёт `auth/schemas.py`, request `req-T2`. T2 → completed.

#### EXECUTION — задача T3

Создаёт `auth/deps.py`, request `req-T3`. T3 → completed.

Задачи закончились. Агент ждёт команду.

---

### METASTATE (по команде пользователя)

**Пользователь:** «обнови метасостояние».

1. **Ревью requests:** три request-а, все approved.
   - `req-T1`, `req-T2`, `req-T3` → `.agent/requests/archive/`.

2. **Архивация задач:**
   - T1, T2, T3 → `.agent/archive/tasks/`.
   - В `manifest.json` — one-liner: `status: "archived"`.

3. **Обновление project-state.md:**

   ```markdown
   ## Key Modules
   | Module | Status | Description |
   |--------|--------|-------------|
   | app/auth/router.py | new | Вынесенные роуты |
   | app/auth/schemas.py | new | Pydantic схемы |
   | app/auth/deps.py | new | Dependency injection |
   ```

4. **Создание handoff-summary.md:**

   ```markdown
   ## Session Summary
   **Goal:** Рефакторинг авторизации
   **Completed:** 3/3 tasks
   **Approved requests:** req-T1, req-T2, req-T3

   ## Project State
   auth разбит на router + schemas + deps.
   Исходный auth/login.py: 450 → 120 строк.

   ## Next Steps
   - Проверить, не осталось ли прямых импортов из старого login.py
   - Обновить main.py если нужно
   ```

---

### HANDOFF

```
HANDOFF COMPLETE

Session: ses_v30_001
Target: /tmp/fastapi-app
Type: existing
Tasks: 3/3 completed

Следующий агент начинает с .agent/handoff-summary.md
```

---

## Использование команд в процессе

В любой момент сессии пользователь мог вызвать:

- **«запиши это как ADR»** → `COMMANDS/adr.md` создал бы `.agent/decisions/001-modular-auth.md`.
- **«red team»** → `COMMANDS/red-team.md` создал бы `.agent/context/red-team-report.md` с попыткой сломать новую структуру.
- **«risk register»** → `COMMANDS/risk-register.md` зафиксировал бы допущения (например, «считаем, что порядок middleware не важен»).

Команды **не обязательны**. Если не вызваны — `.agent/decisions/`, `risk-register.md`, `red-team-report.md` не создаются.
