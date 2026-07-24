# META_AGENT_GUIDE — Главная инструкция

## Жизненный цикл сессии

```
.agent/metaagent-request.md
        │
        ▼
INIT → ANALYSE → [DESIGN] → [RED_TEAM] → DECOMPOSITION → SETUP → (CHECKPOINT)* → HANDOFF → EXIT
                       │                        │
                       ▼                        ▼
                  ADR (опц.)            Invariant Tasks (опц.)
                  Alt.Arch (опц.)
                  Risk Register (опц.)
```

Фазы выполняются **строго последовательно**. Фаза DESIGN — только если project_type = greenfield/scaffold.
Фаза RED_TEAM — только если config.red_team = yes.

Все артефакты размещаются в `.agent/` целевого репозитория (с layer-структурой или плоские, в зависимости от config).

---

## Конфигурация сессии (.agent/metaagent-request.md)

Перед запуском сессии пользователь заполняет `.agent/metaagent-request.md` (см. `TEMPLATES/metaagent-request.md`). Файл должен находиться в директории `.agent/` целевого репозитория.

Ключевые параметры:

### Шкала глубины (depth 1-10)

| Уровень | Название | Что выполняется |
|---|---|---|
| 1-2 | Scaffold | INIT → ANALYSIS → SETUP (только структура, без реализации) |
| 3-4 | Light | + DESIGN (без ADR/альтернатив), DECOMPOSITION (без инвариантов), HANDOFF — **(default)** |
| 5-6 | Standard | полный цикл с базовым DESIGN и DECOMPOSITION |
| 7-8 | Deep | + ADR, Alternative Architecture, Risk Register, Invariant Tests |
| 9-10 | Maximum | + Red Team Review, Executable Invariants для всех ADR |

### Функции (таблица вкл/выкл)

| Функция | Фаза | Глубина | Описание |
|---|---|---|---|
| adr | DESIGN | >=7 | Создание ADR для каждого ключевого решения |
| alternative_arch | DESIGN | >=7 | Обязательное описание альтернативной архитектуры |
| red_team | DESIGN (после) | >=9 | Red Team Review — попытка разрушить архитектуру |
| risk_register | DESIGN | >=7 | Явный реестр допущений |
| invariant_tests | DECOMPOSITION | >=7 | Задачи-инварианты для каждого ADR |
| layer_structure | HANDOFF | любая | Организация .agent/ по слоям (layer-0..3) |

---

## Фаза 0: INIT

**Вход:** целевой репозиторий + опционально `.agent/metaagent-request.md`.

**Протокол:** `PROTOCOLS/00_CONFIG.md`

**Действия:**
- Прочитать `VERSION` — текущая версия MetaAgent
- Склонировать/открыть целевой репозиторий
- Создать директорию `.agent/` в корне целевого репозитория (если нет)
- **Создать `.temp/` в корне целевого репозитория** (если нет) — для временных файлов агента
- **Добавить `.temp/` в `.gitignore`** целевого репозитория (если нет записи)
- **Установить исходники MetaAgent в `.agent/src/`:**
  - Скопировать `META_AGENT_GUIDE.md`, `BOUNDARIES.md`, `WORKFLOW.md`, `VERSION` в `.agent/src/`
  - Скопировать `PROTOCOLS/` и `TEMPLATES/` в `.agent/src/`
  - Скопировать `install.sh` и `install.ps1` в `.agent/src/` (для возможности обновления)
  - Если файлы уже существуют — пропустить (не перезаписывать)
- **Создать `.agent/rules/`** — директорию для пользовательских правил
  - Если `.agent/rules/project-rules.md` не существует — создать из шаблона `.agent/src/TEMPLATES/project-rules.md`
- **Создать/обновить `AGENTS.md` в корне целевого репозитория** (если нет — создать, если есть — не трогать)
- Прочитать `PROTOCOLS/00_CONFIG.md`
- Выполнить 00_CONFIG:
  - Если `.agent/metaagent-request.md` существует — прочитать config из него
  - Если нет — провести интервью с пользователем (или принять `default`)
  - Валидировать config относительно depth
  - Если не было файла — создать `.agent/metaagent-request.md` с пометкой Auto-generated
- **Проверить версию:** если `.agent/checkpoints.json` существует → выполнить `PROTOCOLS/00_MIGRATE.md` (сравнить metaagent_version, применить миграцию при необходимости)
- Прочитать `PROTOCOLS/01_ANALYSIS.md`
- Инициализировать `.agent/checkpoints.json` с `metaagent_version` (если не существовал)

```json
{
  "metaagent_version": "1.1.0",
  "session_id": "<uuid>",
  "target_repo": "<path>",
  "goal": "<цель от пользователя>",
  "project_type": "pending",
  "config": {
    "depth": 4,
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
  "last_updated": "<timestamp>"
}
```

**Выход:** готовая `.agent/` + checkpoints.json с metaagent_version и config.

---

## Фаза 1: ANALYSE

**Вход:** целевой репозиторий, `.agent/metaagent-request.md` (или auto-generated), checkpoints.json (analysis: pending, config: from INIT).

**Протокол:** `PROTOCOLS/01_ANALYSIS.md`

**Действия:**
- **Прочитать `.agent/rules/project-rules.md`** — учесть пользовательские правила
- Прочитать config из checkpoints.json (уже получен на INIT через 00_CONFIG)
- Если config отсутствует — применить default config (depth=4) как fallback
- Выполнить анализ репозитория по протоколу (определяет тип проекта)
- Записать результат в `.agent/analysis-report.md`
- Обновить checkpoints.json: `phases.analysis = "completed"`, `project_type = "existing" | "greenfield" | "scaffold"`

**Выход:** `.agent/analysis-report.md`

**Ветвление:**
- `project_type = "greenfield"` или `"scaffold"` → далее фаза DESIGN
- `project_type = "existing"` → DESIGN пропускается, сразу DECOMPOSITION

---

## Фаза 2: DESIGN (условная)

**Вход:** analysis-report.md, checkpoints.json (analysis: completed, project_type: greenfield/scaffold).

**Протокол:** `PROTOCOLS/02_DESIGN.md`

**Действия:**
- **Прочитать `.agent/rules/project-rules.md`** — учесть пользовательские правила
- Спроектировать архитектуру, модули, данные, интерфейсы
- Если config.design.alternative_arch: описать альтернативную архитектуру
- Если config.design.adr: создать ADR для каждого ключевого решения → `.agent/layer-1/adr/`
- Если config.risk_register: создать `.agent/layer-1/risk-register.md`
- Записать результат в `.agent/design-report.md`
- Обновить checkpoints.json: `phases.design = "completed"`

**Ветвление:**
- Если config.red_team = yes → следующая фаза RED_TEAM
- Иначе → сразу DECOMPOSITION

**Выход:** `.agent/design-report.md`, опционально `.agent/layer-1/adr/*.md`, `.agent/layer-1/risk-register.md`

---

## Фаза 2b: RED_TEAM (опциональная)

**Вход:** design-report.md, ADR (опционально), checkpoints.json (design: completed).

**Протокол:** `PROTOCOLS/02b_REDTEAM.md`

**Действия:**
- **Прочитать `.agent/rules/project-rules.md`** — учесть пользовательские правила
- Выполнить Red Team Review по протоколу
- Записать результат в `.agent/layer-1/red-team-report.md`
- Дополнить risk-register.md (если существует)
- Если найдены критические проблемы — исправить design-report
- Обновить checkpoints.json: `phases.red_team = "completed"`

**Выход:** `.agent/layer-1/red-team-report.md`

---

## Фаза 3: DECOMPOSITION

**Вход:** analysis-report.md + design-report.md (опционально) + ADR (опционально) + checkpoints.json.

**Протокол:** `PROTOCOLS/03_DECOMPOSITION.md`

**Действия:**
- **Прочитать `.agent/rules/project-rules.md`** — учесть пользовательские правила
- Разбить цель (и дизайн) на атомарные задачи
- Если config.decomposition.invariant_tests: создать задачи-инварианты для каждого ADR
- Записать манифест в `.agent/task-manifest.json` и `.agent/task-manifest.md`
- Обновить checkpoints.json: `phases.decomposition = "completed"`, заполнить `tasks`

**Выход:** `.agent/task-manifest.json`, `.agent/task-manifest.md`

---

## Фаза 4: SETUP

**Вход:** analysis-report.md, design-report.md (опционально), task-manifest.json, checkpoints.json (decomposition: completed).

**Протокол:** `PROTOCOLS/04_ENVIRONMENT_SETUP.md`

**Действия:**
- **Прочитать `.agent/rules/project-rules.md`** — учесть пользовательские правила
- Выполнить настройку окружения по протоколу (ветка A для existing, ветка B для greenfield)
- Записать результат проверки в `.agent/baseline-test-report.log` и `.agent/setup-report.log`
- Обновить checkpoints.json: `phases.environment = "completed"`

**Выход:** рабочее окружение + `.agent/baseline-test-report.log`

---

## Фаза 5: CHECKPOINT (сквозная)

**Вход:** любая фаза.

**Протокол:** обновлять checkpoints.json после каждого значимого шага.

**Архивирование перед сохранением чекпоинта:**
- Если checkpoints.json уже существует — сохранить предыдущую версию в `.agent/archive/checkpoints/<last_updated>.json`

**Формат:**

```json
{
  "metaagent_version": "1.1.0",
  "session_id": "<uuid>",
  "target_repo": "<path>",
  "goal": "<цель>",
  "project_type": "existing | greenfield | scaffold",
  "config": {
    "depth": 6,
    "design": { "adr": true, "alternative_arch": true },
    "red_team": false,
    "risk_register": false,
    "decomposition": { "invariant_tests": true },
    "handoff": { "layer_structure": true }
  },
  "phases": {
    "analysis": "completed",
    "design": "completed",
    "red_team": "skipped",
    "decomposition": "in_progress",
    "environment": "pending",
    "handoff": "pending"
  },
  "tasks": [
    { "id": "T1", "title": "...", "status": "completed",
      "depends_on": [], "acceptance_criteria": ["..."] },
    { "id": "T2", "title": "...", "status": "pending",
      "depends_on": ["T1"], "acceptance_criteria": ["..."] }
  ],
  "last_updated": "<timestamp>"
}
```

`status` может быть: `pending`, `in_progress`, `completed`, `failed`, `skipped`.
Фаза `red_team` может быть `skipped` если config.red_team = false.

---

## Фаза 6: HANDOFF

**Вход:** все предыдущие фазы completed.

**Протокол:** `PROTOCOLS/05_HANDOFF.md`

**Действия:**
- **Прочитать `.agent/rules/project-rules.md`** — учесть пользовательские правила
- **Архивировать завершённые задачи:**
  - Для каждой задачи со статусом `completed` в `task-manifest.json`:
    - Перенести полное описание в `.agent/archive/tasks/<id>.json`
    - Заменить в манифесте на one-liner: `{ "id": "<id>", "title": "<title>", "status": "archived" }`
  - Создать `.agent/archive/index.json` со списком архивированных задач
  - Заархивировать предыдущий `checkpoints.json` в `.agent/archive/checkpoints/`
- Выполнить валидацию всех артефактов
- Если config.handoff.layer_structure: организовать `.agent/` по слоям
- Записать `.agent/handoff-summary.md` (в layer-3 при layer_structure=yes)
- Создать `.agent/session-summary.md` (в layer-0 при layer_structure=yes)
- Обновить checkpoints.json: `phases.handoff = "completed"`
- Сообщить пользователю/оркестратору

**Выход:** `.agent/handoff-summary.md` — итоговый документ для исполнительного агента.

---

## Фаза 7: EXIT

Мета-агент завершает работу. Управление переходит к исполнительному агенту.

---

## Структура .agent/

.agent/ всегда содержит служебную директорию `src/` с исходниками MetaAgent (см. фазу INIT).
`.temp/` в корне проекта — временные файлы агента (всегда, на одном уровне с `.agent/`).
При layer_structure=yes артефакты сессии раскладываются по слоям layer-0..3.

```
.agent/
  src/                          # исходники MetaAgent (всегда)
    META_AGENT_GUIDE.md         #   главная инструкция
    PROTOCOLS/                  #   протоколы фаз
    TEMPLATES/                  #   шаблоны артефактов
    BOUNDARIES.md               #   границы
    WORKFLOW.md                 #   примеры работы
    VERSION                     #   версия MetaAgent
    install.sh                  #   скрипт установки/обновления (Unix)
    install.ps1                 #   скрипт установки/обновления (Windows)
  rules/                        # пользовательские правила (всегда)
    project-rules.md            #   правила проекта — читать перед каждой фазой
  archive/                      # архив завершённых артефактов (создаётся при HANDOFF)
    index.json                  #   мета-индекс архива
    tasks/                      #   детали завершённых задач
    checkpoints/                #   исторические чекпоинты
    adr/                        #   заменённые ADR
    reports/                    #   устаревшие отчёты
  layer-0/                      # ядро сессии (только при layer_structure=yes)
    checkpoints.json            # всегда (ядро)
    session-summary.md          # краткая сводка сессии
  layer-1/                      # архитектурные решения (справочно)
    adr/
      001-технологический-стек.md
      002-архитектурный-паттерн.md
      ...
    risk-register.md
    red-team-report.md
  layer-2/                      # дизайн и анализ (справочно)
    analysis-report.md
    design-report.md
  layer-3/                      # состояние исполнения
    handoff-summary.md
    task-manifest.json
    task-manifest.md
    baseline-test-report.log
    setup-report.log
```

`.temp/` структура:

```
.temp/
  downloads/            # временно скачанные файлы
  patches/              # временные патчи и diff
  cache/                # кеш анализа, промежуточные результаты
  agent-session-xxx/    # временные файлы конкретной сессии
```

Исполнительный агент всегда начинает с layer-0 (checkpoints + session-summary),
затем при необходимости обращается к layer-1 (ADR для понимания "почему"),
layer-2 (детали дизайна), layer-3 (что было сделано).
