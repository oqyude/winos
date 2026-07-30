# META_AGENT_GUIDE — Главная инструкция v2.1

## Жизненный цикл сессии

```
                    .agent/metaagent-request.md
                             │
                             ▼
┌─────────────────────────────────────────────────────┐
│                 PROJECT LOOP (однократно)             │
│                                                     │
│  INIT → ANALYSE → ROADMAP → DESIGN → DECOMPOSITION  │
│                                                     │
│  Выход: .agent/tasks/manifest.json                  │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│                 WORK LOOP (циклически)                │
│                                                     │
│  EXECUTION → (request) → METASTATE (по команде)     │
│                                                     │
│  Цикл повторяется: беру задачу → делаю →            │
│  создаю request → накопилось → METASTATE            │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│                 HANDOFF (завершение)                  │
└─────────────────────────────────────────────────────┘
```

Фазы выполняются **строго последовательно** внутри PROJECT LOOP.
WORK LOOP может повторяться многократно.
HANDOFF — легковесное завершение.

Все артефакты размещаются в `.agent/` целевого репозитория.

---

## Конфигурация сессии (.agent/metaagent-request.md)

Перед запуском сессии пользователь заполняет `.agent/metaagent-request.md` (см. `TEMPLATES/metaagent-request.md`). Файл должен находиться в директории `.agent/` целевого репозитория.

Ключевые параметры:

### Шкала глубины (depth 1-10)

| Уровень | Название | Что выполняется |
|---|---|---|
| 1-2 | Scaffold | INIT → ANALYSIS → SETUP (только структура, без реализации) |
| 3-4 | Light | + ROADMAP, DESIGN (без ADR/альтернатив), DECOMPOSITION — **(default)** |
| 5-6 | Standard | полный цикл с базовым DESIGN и DECOMPOSITION |
| 7-8 | Deep | + ADR, Alternative Architecture, Risk Register, Invariant Tests |
| 9-10 | Maximum | + Red Team Review, Executable Invariants для всех ADR |

### Функции

| Функция | Фаза | Глубина | Описание |
|---|---|---|---|
| adr | DESIGN | >=7 | Создание ADR для каждого ключевого решения |
| alternative_arch | DESIGN | >=7 | Обязательное описание альтернативной архитектуры |
| red_team | DESIGN (после) | >=9 | Red Team Review — попытка разрушить архитектуру |
| risk_register | DESIGN | >=7 | Явный реестр допущений |
| invariant_tests | DECOMPOSITION | >=7 | Задачи-инварианты для каждого ADR |

---

## Фаза 0: INIT

**Протокол:** `PROTOCOLS/00_CONFIG.md`

**Действия:**
- Прочитать `VERSION` — текущая версия MetaAgent
- Склонировать/открыть целевой репозиторий
- Создать директорию `.agent/` в корне целевого репозитория (если нет)
- Создать `.temp/` в корне целевого репозитория (если нет), добавить в `.gitignore`
- Установить исходники MetaAgent в `.agent/src/`
- Создать структуру `.agent/`: `rules/`, `decisions/`, `tasks/` (с `backlog/`), `context/`, `requests/` (с `active/`, `archive/`), `roadmap/` (с `archive/`), `archive/` (с `tasks/`, `decisions/`, `checkpoints/`)
- Создать/обновить `AGENTS.md` в корне
- Прочитать/создать `.agent/metaagent-request.md` (интервью или default)
- Проверить версию, инициализировать `checkpoints.json`

**Выход:** готовая `.agent/` + checkpoints.json.

---

## Фаза 1: ANALYSIS

**Протокол:** `PROTOCOLS/01_ANALYSIS.md`

**Действия:**
- Прочитать `.agent/rules/project-rules.md`
- Прочитать config из checkpoints.json
- Выполнить анализ репозитория:
  - Определить тип проекта (existing / greenfield / scaffold)
  - Зафиксировать стек, архитектуру, конвенции, тесты
  - Для greenfield — извлечь требования из README
- Создать начальный `.agent/context/project-state.md` — слепок проекта
- Записать `.agent/context/analysis-report.md`
- Обновить checkpoints.json

**Ветвление:**
- `project_type = "greenfield"` или `"scaffold"` → далее ROADMAP → DESIGN
- `project_type = "existing"` → далее ROADMAP (DESIGN пропускается)

**Выход:** `.agent/context/analysis-report.md`, `.agent/context/project-state.md`

---

## Фаза 2: ROADMAP

**Протокол:** `PROTOCOLS/02_ROADMAP.md`

**Действия:**
- Прочитать `.agent/rules/project-rules.md`
- Сканировать FUTURE/ — долгосрочные планы
- Сканировать `.agent/decisions/index.json` — ADR, требующие реализации
- Учесть пользовательские запросы и выявленные улучшения
- Приоритизировать все источники (P0-P3)
- Создать `.agent/roadmap/sources.md`

**Выход:** `.agent/roadmap/sources.md`

---

## Фаза 3: DESIGN (условная)

**Протокол:** `PROTOCOLS/02_DESIGN.md`

Выполняется только для greenfield/scaffold.

**Действия:**
- Спроектировать архитектуру, модули, данные, интерфейсы
- Если config.design.adr: создать ADR → `.agent/decisions/`
- Если config.risk_register: создать `.agent/context/risk-register.md`
- Записать `.agent/context/design-report.md`

**Выход:** `.agent/context/design-report.md`, опционально ADR, risk-register

---

## Фаза 3b: RED_TEAM (опциональная)

**Протокол:** `PROTOCOLS/02b_REDTEAM.md`

Только если config.red_team = yes (depth >= 9).

**Выход:** `.agent/context/red-team-report.md`

---

## Фаза 4: DECOMPOSITION

**Протокол:** `PROTOCOLS/03_DECOMPOSITION.md`

**Действия:**
- Прочитать `.agent/rules/project-rules.md`
- Разбить цель (и дизайн) на атомарные задачи
- Каждой задаче присвоить `origin` (источник: roadmap, ADR, user, agent)
- Если есть `.agent/roadmap/sources.md` — сверить приоритеты
- Если config.invariant_tests: создать задачи-инварианты для ADR
- Записать `.agent/tasks/manifest.json` и `.agent/tasks/manifest.md`

**Выход:** `.agent/tasks/manifest.json` + `.agent/tasks/manifest.md`

---

## Фаза 5: EXECUTION (циклическая)

**Протокол:** `PROTOCOLS/04_EXECUTION.md`

**Действия:**
1. Выбрать следующую задачу из manifest.json (pending, все depends_on выполнены)
2. Отметить `in_progress`
3. Реализовать (код, тесты, конфиги)
4. Верифицировать (тесты, LSP diagnostics)
5. Закоммитить
6. Создать request в `.agent/requests/active/req-{id}.json`
7. Отметить `completed` в manifest.json
8. Повторить, пока есть задачи
9. Если задач нет — ожидать команду пользователя

**Request — единица результата:**
```json
{
  "request_id": "req-T1",
  "task_id": "T1",
  "title": "Human-readable title",
  "status": "ready_for_review",
  "changes": {
    "summary": "Суть изменений",
    "commits": ["abc1234"],
    "files_changed": ["path/to/file.py"]
  },
  "verification": {
    "tests_passed": "24/24",
    "lsp_clean": true
  },
  "fulfills_ac": ["AC1"]
}
```

**Выход:** выполненные задачи в manifest + request-ы в `.agent/requests/active/`

---

## Фаза 6: METASTATE (по команде пользователя)

**Протокол:** `PROTOCOLS/06_METASTATE.md`

Запускается по команде: «обнови метасостояние», «update metastate», «подведи итог».

**Действия:**
1. **Ревью requests** — проверить каждый `ready_for_review`:
   - ✅ approved → в `.agent/requests/archive/`, задача confirmed
   - ❌ rejected → задача reopened, комментарий
2. **Архивация** — completed задачи → one-liner в manifest, детали в `.agent/archive/tasks/`
3. **Обновление project-state.md** — актуальный слепок проекта
4. **Обновление roadmap** — отметить выполненное, пересчитать приоритеты
5. **Создание handoff-summary.md** — полная сводка для следующего агента
6. **Индекс архива** — `.agent/archive/index.json`

**Выход:** обновлённый `.agent/` — полный слепок проекта. Следующий агент читает только `.agent/`.

---

## Фаза 7: HANDOFF

**Протокол:** `PROTOCOLS/05_HANDOFF.md`

**Действия:**
- Если METASTATE был — просто валидировать и финализировать
- Если METASTATE не было — лёгкая архивация completed задач
- Валидация структуры `.agent/`
- Создание `.agent/session-summary.md`
- Финализация checkpoints.json

**Выход:** `.agent/session-summary.md`, финальный checkpoints.json

---

## Checkpoint (сквозная)

checkpoints.json обновляется после каждой фазы:

```json
{
  "metaagent_version": "2.1.0",
  "session_id": "<uuid>",
  "target_repo": "<path>",
  "goal": "<цель>",
  "project_type": "existing | greenfield | scaffold",
  "config": {
    "depth": 6,
    "design": { "adr": true, "alternative_arch": true },
    "red_team": false,
    "risk_register": false,
    "decomposition": { "invariant_tests": true }
  },
  "phases": {
    "analysis": "completed",
    "roadmap": "completed",
    "design": "completed",
    "red_team": "skipped",
    "decomposition": "completed",
    "execution": "completed",
    "metastate": "completed",
    "handoff": "completed"
  },
  "tasks": [
    { "id": "T1", "title": "...", "status": "archived", "origin": "user:direct" },
    { "id": "T2", "title": "...", "status": "pending", "origin": "roadmap:010" }
  ],
  "last_updated": "<timestamp>"
}
```

---

## Структура .agent/

```
.agent/
  checkpoints.json                  # состояние сессии (ядро)
  session-summary.md                # краткая сводка сессии
  handoff-summary.md                # сводка для следующего агента (создаётся METASTATE)

  src/                              # исходники MetaAgent (всегда)
    META_AGENT_GUIDE.md
    PROTOCOLS/
    TEMPLATES/
    BOUNDARIES.md
    WORKFLOW.md
    VERSION
    install.sh / install.ps1

  rules/
    project-rules.md

  roadmap/                          # ИСТОЧНИКИ ЗАДАЧ (новое в v2.1)
    sources.md                      #   консолидированный список с приоритетами
    archive/                        #   устаревшие roadmap-планы

  decisions/                        # архитектурные решения (ADR)
    index.json
    001-*.md

  tasks/                            # задачи
    manifest.json                   #   + поле origin
    manifest.md
    backlog/

  requests/                         # ЕДИНИЦЫ РЕЗУЛЬТАТА (новое в v2.1)
    active/                         #   req-T1.json (ready_for_review)
    archive/                        #   req-T1.json (approved/rejected)

  context/
    analysis-report.md              # замороженный анализ на старте
    project-state.md                # динамический слепок проекта (обновляется METASTATE)
    design-report.md
    risk-register.md
    red-team-report.md
    baseline-test-report.log

  archive/
    index.json
    tasks/
    decisions/
    requests/
    checkpoints/
```

`.temp/` в корне проекта:

```
.temp/
  downloads/
  patches/
  cache/
  agent-session-xxx/
```

---

## Принципы работы

### Два контура

**Project Loop** (однократно): INIT → ANALYSIS → ROADMAP → DESIGN → DECOMPOSITION.
Настраивает проект, определяет задачи.

**Work Loop** (циклически): EXECUTION → (request) → METASTATE (по команде).
Агент работает, создаёт requests, по команде пользователя подводит итог.

### Request — единица результата

Каждая выполненная задача завершается созданием request. Не просто «сделано», а документированный результат:
- суть изменений (не diff, а именно суть)
- ссылки на коммиты
- верификация (тесты, LSP)
- какие acceptance criteria закрыты

Request проходит ревью в METASTATE.

### .agent/ как слепок проекта

После METASTATE `.agent/` содержит полную картину. Следующий агент читает `.agent/` и не лезет в исходники проекта.

### Depth scale

Определяет глубину проработки:

| Depth | PROJECT LOOP | WORK LOOP |
|-------|-------------|-----------|
| 1-2 | INIT → ANALYSIS → DECOMP | EXECUTION (scaffold only) |
| 3-4 | + ROADMAP, DESIGN (light) | EXECUTION → METASTATE |
| 5-6 | + DESIGN (full), invariants | EXECUTION → METASTATE |
| 7-8 | + ADR, risk_register | EXECUTION → METASTATE |
| 9-10 | + Red Team | EXECUTION → METASTATE |