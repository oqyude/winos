# MetaAgent GUIDE v3.0

MetaAgent — набор инструкций для AI-агента. Задача: превратить хаотичное общение с агентом в структурированный процесс, в котором состояние проекта переживает любую сессию.

## Два слоя

- **Цикл** (всегда, по необходимости) — последовательность фаз, которую агент проходит при работе с проектом.
- **Команды** (по запросу пользователя) — on-demand инструкции, которые не привязаны к фазе.

Состояние проекта живёт в `.agent/` целевого репозитория. Следующий агент читает `.agent/` и не лезет в исходники.

---

## Цикл

```
                    .agent/checkpoints.json
                              │
                              ▼
        ┌─────────────────────────────────────┐
        │          PROJECT LOOP (разово)        │
        │                                     │
        │  INIT → ANALYSE → ROADMAP →         │
        │  → [DESIGN] → DECOMPOSITION         │
        │                                     │
        │  Выход: .agent/tasks/manifest.json  │
        └──────────────────┬──────────────────┘
                           │
                           ▼
        ┌─────────────────────────────────────┐
        │          WORK LOOP (циклически)      │
        │                                     │
        │  EXECUTION → (request) →            │
        │  → METASTATE (по команде)           │
        │                                     │
        │  Беру задачу → делаю → request →    │
        │  накопилось → METASTATE             │
        └──────────────────┬──────────────────┘
                           │
                           ▼
                  HANDOFF (завершение)
```

Фазы выполняются **строго последовательно** внутри PROJECT LOOP. WORK LOOP повторяется многократно.

### Ветвление

| Тип проекта | Цикл |
|---|---|
| **existing** | INIT → ANALYSE → ROADMAP → DECOMPOSITION → EXECUTION → METASTATE → HANDOFF |
| **greenfield / scaffold** | + фаза DESIGN между ROADMAP и DECOMPOSITION |

Тип проекта определяется автоматически в фазе ANALYSE. Никакого интервью с пользователем, никакой шкалы глубины.

---

## Фазы

| # | Фаза | Протокол | Что делает |
|---|---|---|---|
| 0 | INIT | `PROTOCOLS/00_INIT.md` | Создаёт `.agent/`, ставит исходники, инициализирует checkpoints |
| 1 | ANALYSE | `PROTOCOLS/01_ANALYSE.md` | Сканирует проект, создаёт `analysis-report.md` + начальный `project-state.md` |
| 2 | ROADMAP | `PROTOCOLS/02_ROADMAP.md` | Собирает источники задач (FUTURE, ADR, user-запросы) → `roadmap/sources.md` |
| 3 | DESIGN | `PROTOCOLS/03_DESIGN.md` | Только greenfield. Архитектура, модули, API, модели |
| 4 | DECOMPOSITION | `PROTOCOLS/04_DECOMPOSITION.md` | Разбивает цель на атомарные задачи → `tasks/manifest.json` |
| 5 | EXECUTION | `PROTOCOLS/05_EXECUTION.md` | Цикл: берёт задачу → код → тесты → коммит → request |
| 6 | METASTATE | `PROTOCOLS/06_METASTATE.md` | По команде. Ревью requests, обновление project-state, handoff-summary |
| 7 | HANDOFF | `PROTOCOLS/07_HANDOFF.md` | Валидация `.agent/`, финализация checkpoints, session-summary |

---

## Команды

Эти инструкции выполняются **по явной просьбе пользователя** в любой момент сессии. Они не привязаны к фазе.

| Команда | Файл | Что делает |
|---|---|---|
| «запиши ADR» / «/adr» | `COMMANDS/adr.md` | Создаёт `.agent/decisions/NNN-slug.md` |
| «red team» / «/red-team» | `COMMANDS/red-team.md` | Создаёт `.agent/context/red-team-report.md` — попытка сломать дизайн |
| «risk register» / «/risk-register» | `COMMANDS/risk-register.md` | Создаёт `.agent/context/risk-register.md` |
| «альтернативная архитектура» / «/alt-arch» | `COMMANDS/alt-arch.md` | Описывает альтернативу текущему дизайну |
| «invariant-тесты» / «/invariant-tests» | `COMMANDS/invariant-tests.md` | Создаёт задачи-инварианты для ADR |

### Когда вызывать

- **ADR** — после архитектурного решения, которое нужно зафиксировать. Типично во время DESIGN или при появлении неочевидного выбора в EXECUTION.
- **Red Team** — после готового дизайна, чтобы найти слабые места до реализации.
- **Risk Register** — в начале проекта или при появлении новых допущений.
- **Alt Arch** — если сомневаетесь в выбранном подходе, хотите сравнить варианты.
- **Invariant Tests** — после ADR, чтобы зафиксировать «что не должно сломаться».

Команды **не обязательны**. Если не вызваны — не выполняются. Состояние проекта от них не зависит.

---

## Структура `.agent/`

```
.agent/
  checkpoints.json                  # состояние сессии (ядро)
  session-summary.md                # краткая сводка сессии
  handoff-summary.md                # сводка для следующего агента (создаётся METASTATE)

  src/                              # исходники MetaAgent (всегда)
    GUIDE.md
    BOUNDARIES.md
    CHANGELOG.md
    PROTOCOLS/
    COMMANDS/
    TEMPLATES/
    VERSION
    install.sh / install.ps1

  rules/
    project-rules.md                # ваши правила — читать перед каждой фазой

  roadmap/                          # источники задач
    sources.md
    archive/

  decisions/                        # ADR
    index.json
    001-*.md

  tasks/                            # задачи
    manifest.json + manifest.md
    backlog/

  requests/                         # результаты выполненных задач
    active/                         #   ready_for_review
    archive/                        #   approved / rejected

  context/
    analysis-report.md
    project-state.md                # обновляется в METASTATE
    design-report.md                # только greenfield
    red-team-report.md              # если вызывали /red-team
    risk-register.md                # если вызывали /risk-register
    baseline-test-report.log

  archive/
    index.json
    tasks/
    decisions/
    requests/
    checkpoints/
```

`.temp/` в корне проекта — для временных файлов агента. Всегда в `.gitignore`.

---

## Checkpoints

`checkpoints.json` обновляется после каждой фазы:

```json
{
  "metaagent_version": "3.0.0",
  "session_id": "<uuid>",
  "target_repo": "<path>",
  "goal": "<цель>",
  "project_type": "existing | greenfield | scaffold",
  "phases": {
    "init": "completed",
    "analyse": "completed",
    "roadmap": "completed",
    "design": "skipped",
    "decomposition": "completed",
    "execution": "in_progress",
    "metastate": "pending",
    "handoff": "pending"
  },
  "tasks": [
    { "id": "T1", "title": "...", "status": "in_progress", "origin": "user:direct" }
  ],
  "last_updated": "<timestamp>"
}
```

Секции `config` больше нет. Параметры, которые раньше были в `config` (depth, adr, red_team и т.п.), теперь либо не существуют, либо живут в отдельных командах.

---

## Принципы

### Цикл vs команды

Цикл — это «что агент делает по умолчанию». Команды — «что агент делает по явной просьбе». Не путать: ADR не запускается автоматически в DESIGN, а только когда пользователь скажет «запиши это как решение».

### `.agent/` как слепок проекта

После METASTATE `.agent/` содержит всю картину. Следующий агент читает только `.agent/`, не исходники.

### Request — единица результата

Каждая выполненная задача в EXECUTION завершается созданием `request` (`.agent/requests/active/req-{id}.json`). Request содержит суть изменений, коммиты, верификацию, закрытые acceptance criteria. Ревью request-ов происходит в METASTATE.

### Правила выше протоколов

Перед каждой фазой читать `.agent/rules/project-rules.md`. Если правило пользователя противоречит протоколу — следовать правилу.

### Контекст бесконечно не растёт

Завершённые задачи архивируются в `.agent/archive/tasks/`, request-ы — в `.agent/requests/archive/`. Текущий manifest остаётся lean.
