# Протокол 00: Конфигурация сессии (CONFIG)

## Цель

Определить параметры сессии MetaAgent: глубину проработки, набор функций, тип проекта. Выполняется на фазе INIT.

## Вход

- `VERSION` — текущая версия MetaAgent
- Запрос пользователя (цель)
- Опционально: `.agent/metaagent-request.md` (в директории `.agent/` целевого репозитория)

## Шаги

### 0.1. Проверить наличие .agent/metaagent-request.md

Если файл существует — распарсить, провалидировать и использовать.
Если нет — перейти к интервью (шаг 0.2).

### 0.2. Интервью с пользователем

Задать пользователю серию вопросов для сбора конфигурации.

**Сценарий интервью:**

```
MetaAgent: .agent/metaagent-request.md не найден. Давайте настроим сессию.
           (или ответьте "default" — я выберу depth=4, light)

Q1: Это новый проект (greenfield) или работа с существующим кодом (existing)?
    Варианты: new / existing / scaffold / default

Q2: Глубина проработки?
    1-2: Scaffold — только структура, пустые модули
    3-4: Light — быстрый дизайн + задачи, без расширений (рекомендуется default)
    5-6: Standard — полный цикл с acceptance criteria
    7-8: Deep — + ADR, risk register, alternative architecture
    9-10: Maximum — + Red Team review, executable invariants
    Варианты: число 1-10 / default

Q3 (если глубина >= 7): Нужны ADR (Architecture Decision Records)?
    Варианты: yes / no / default

Q4 (если глубина >= 7): Нужен Risk Register?
    Варианты: yes / no / default

Q5 (если глубина >= 9): Нужен Red Team Review?
    Варианты: yes / no / default
```

**Правила обработки ответов:**
- Если пользователь ответил `default` или не ответил — применить значение по умолчанию для этого поля
- Если пользователь ответил `new` — `project_type = greenfield`
- Если `existing` — `project_type = existing`

### 0.3. Default config

```json
{
  "depth": 4,
  "design": {
    "adr": false,
    "alternative_arch": false
  },
  "red_team": false,
  "risk_register": false,
  "decomposition": {
    "invariant_tests": false
  },
  "handoff": {
    "layer_structure": false
  }
}
```

Depth=4 (Light) означает:
- ANALYSIS — полный (определение типа проекта, извлечение требований)
- DESIGN — выполняется (если greenfield), но **без** ADR, Alternative Architecture, Risk Register
- DECOMPOSITION — задачи с acceptance criteria, **без** invariant-тестов
- SETUP — полный
- HANDOFF — плоский `.agent/` (без layer-структуры)

### 0.4. Запись .agent/metaagent-request.md

Если файла не было, создать его по результатам интервью с пометкой `Auto-generated`:

```markdown
# MetaAgent Request
# Auto-generated from user interview on {{ date }}

## Параметры сессии

| Функция | Вкл | Аргументы |
|---|---|---|
| ANALYSIS | ✓ | — |
| DESIGN | ✓ | adr={{ adr }}, alternative_arch={{ alt_arch }} |
| RED_TEAM | {{ red_team }} | — |
| RISK_REGISTER | {{ risk_register }} | — |
| DECOMPOSITION | ✓ | invariant_tests={{ invariant_tests }} |
| SETUP | ✓ | — |
| HANDOFF | ✓ | layer_structure={{ layer_structure }} |

## Глубина проработки

**Значение:** {{ depth }}

## Цель

{{ goal }}
```

### 0.5. Создание .agent/rules/

Создать директорию `.agent/rules/` в корне целевого проекта (если не существует).
Если `.agent/rules/project-rules.md` не существует — создать из шаблона `.agent/src/TEMPLATES/project-rules.md`:

```markdown
# Project Rules

Добавляйте сюда правила, которым агент обязан следовать во всех фазах.
```

### 0.6. Валидация config

Проверить совместимость параметров с depth:

```
depth < 3 → DESIGN пропускается (даже для greenfield)
depth < 7 → adr=false, alternative_arch=false, risk_register=false, invariant_tests=false
depth < 9 → red_team=false
```

Если depth несовместим с включёнными функциями — понизить функции до максимума, разрешённого depth.

## Выход

- `.agent/metaagent-request.md` (создан или подтверждён)
- config — словарь параметров для записи в checkpoints.json

## Критерии завершения

- [ ] `.agent/metaagent-request.md` существует (создан или найден)
- [ ] Config содержит depth, design.*, red_team, risk_register, decomposition.*, handoff.*
- [ ] Config совместим с depth (доп. функции отключены для малых depth)
- [ ] При отсутствии файла — проведено интервью, файл создан
