# Протокол 05: Передача исполнительному агенту (HANDOFF)

## Цель

Подготовить и передать исполнительному агенту полный контекст для работы: задачи, окружение, правила.

## Вход

- `.agent/analysis-report.md`
- `.agent/design-report.md` (опционально, для greenfield)
- `.agent/layer-1/adr/*.md` (опционально)
- `.agent/layer-1/risk-register.md` (опционально)
- `.agent/layer-1/red-team-report.md` (опционально)
- `.agent/task-manifest.json`
- `.agent/task-manifest.md`
- `.agent/baseline-test-report.log`
- `.agent/checkpoints.json` (все предыдущие фазы: completed)

## Шаги

### 5.1. Архивация завершённых артефактов

Перед валидацией и передачей выполнить архивирование.

**Архивировать завершённые задачи:**

Для каждой задачи в `task-manifest.json` со статусом `completed`:
1. Создать `.agent/archive/tasks/<id>.json` — перенести полное описание задачи (все поля)
2. В `task-manifest.json` заменить задачу на one-liner:
   ```json
   { "id": "<id>", "title": "<title>", "status": "archived" }
   ```

**Архивировать чекпоинты:**

Если `checkpoints.json` уже существует — сохранить предыдущую версию в `.agent/archive/checkpoints/<last_updated>.json`.

**Создать индекс архива:**

```json
{
  "version": "1.1.0",
  "archived_at": "<timestamp>",
  "tasks": [
    { "id": "T1", "title": "...", "archived_at": "<timestamp>" }
  ],
  "checkpoints": [
    { "file": "checkpoints/2026-07-15T10-00-00.json", "archived_at": "<timestamp>" }
  ]
}
```

### 5.2. Валидация

Перед передачей проверить:

- [ ] Все фазы отмечены как `completed` в checkpoints.json
- [ ] `.agent/` содержит все обязательные файлы:
  - `checkpoints.json`
  - `analysis-report.md`
  - `task-manifest.json` + `task-manifest.md`
  - `baseline-test-report.log`
  - `setup-report.log`
  - `src/META_AGENT_GUIDE.md`
  - `src/BOUNDARIES.md`
  - `src/VERSION`
  - `src/PROTOCOLS/`
  - `src/TEMPLATES/`
  - `rules/project-rules.md`
  - `archive/index.json`
- [ ] Для greenfield: `design-report.md` присутствует
- [ ] В task-manifest.json нет циклических зависимостей
- [ ] Все acceptance criteria сформулированы измеримо
- [ ] Для каждой задачи указаны affected files
- [ ] В репозитории нет незакоммиченных изменений (кроме `.agent/`)
- [ ] `.agent/src/` содержит актуальные исходники MetaAgent (META_AGENT_GUIDE.md, PROTOCOLS/, TEMPLATES/, BOUNDARIES.md, VERSION)
- [ ] `AGENTS.md` присутствует в корне репозитория
- [ ] `.agent/rules/` содержит `project-rules.md`

**Дополнительные проверки (если config включает):**
- [ ] ADR присутствуют (если adr=yes)
- [ ] Risk Register заполнен (если risk_register=yes)
- [ ] Red Team Report есть (если red_team=yes)
- [ ] Invariant-задачи в манифесте (если invariant_tests=yes)

### 5.3. Layer-структура .agent/

Если `config.layer_structure = yes`, организовать артефакты по слоям:

```
.agent/
  layer-0/
    checkpoints.json          # всегда (ядро)
    session-summary.md        # краткая сводка сессии (создаётся здесь)
  layer-1/
    adr/                      # ADR (опционально)
    risk-register.md          # (опционально)
    red-team-report.md        # (опционально)
  layer-2/
    analysis-report.md
    design-report.md
    design-report.md
  layer-3/
    handoff-summary.md
    task-manifest.json
    task-manifest.md
    baseline-test-report.log
    setup-report.log
```

Если `layer_structure = no` — артефакты остаются плоскими в `.agent/`, как раньше.

### 5.4. Создать handoff-summary.md

Заполнить по шаблону `TEMPLATES/handoff-summary.md`:

- **Session Info** — ID, цель, дата
- **Configuration** — какие функции были включены, глубина
- **Repo Summary** — краткая выжимка из analysis-report
- **Environment Status** — результат сборки и тестов
- **Design Summary** (если есть design-report) — ключевые архитектурные решения
- **ADR Summary** (если adr=yes) — какие решения задокументированы
- **Risk Register** (если risk_register=yes) — основные допущения
- **Task Overview** — количество задач, типы, список
- **Next Steps** — с какой задачи начинать исполнительному агенту
- **Project Rules** — ссылка на `.agent/rules/project-rules.md` (передаётся exec-агенту)
- **Archive** — ссылка на `.agent/archive/index.json` (история завершённых задач)
- **Caveats** — известные проблемы, ограничения, неясные моменты
- **Checkpoints** — актуальное состояние чекпоинтов

### 5.5. Финализировать checkpoints

- Отметить `phases.handoff = "completed"`
- Записать финальный `last_updated`

### 5.6. Сигнал

Сообщить пользователю/оркестратору:

```
HANDOFF COMPLETE

Session: <session_id>
Target: <target_repo>
Type: <existing | greenfield | scaffold>
Config: depth=<N>, adr=<yes|no>, red_team=<yes|no>, ...
Tasks: <count> tasks ready

Исполнительный агент может начинать с задачи <T1>.
Контекст: .agent/handoff-summary.md
Манифест: .agent/task-manifest.json
```

## Что получает исполнительный агент

1. **Целевой репозиторий** — полностью настроенный, с установленными зависимостями
2. **`.agent/`** — директория со всеми артефактами (layer-структура или плоская)
3. **`task-manifest.json`** — машиночитаемый список задач
4. **`task-manifest.md`** — человекочитаемый список задач
5. **`handoff-summary.md`** — итоговая сводка
6. **`checkpoints.json`** — актуальное состояние (исполнительный агент будет его обновлять)
7. **`layer-1/adr/*.md`** (опционально) — ключевые решения
8. **`layer-1/risk-register.md`** (опционально) — допущения
9. **`layer-2/analysis-report.md`** — полный анализ репозитория (справочно)
10. **`layer-2/design-report.md`** (только для greenfield) — архитектурный план
11. **`layer-3/baseline-test-report.log`** — baseline тестов (чтобы не сломать существующее)
12. **`.agent/src/`** — полные исходники MetaAgent (справочно, всегда присутствуют)
13. **`.agent/rules/`** — пользовательские правила проекта
14. **`AGENTS.md`** — инструкция для AI-агента в корне проекта (всегда присутствует)
15. **`.agent/archive/`** — архив завершённых задач, чекпоинтов и устаревших артефактов

## Выход

- `.agent/layer-0/session-summary.md` (если layer_structure=yes)
- `.agent/layer-3/handoff-summary.md`
- `.agent/layer-0/checkpoints.json` (финальный)
- `.agent/archive/index.json` (создаётся при архивации)

## Критерии завершения

- [ ] Все артефакты на месте (с учётом layer-структуры)
- [ ] `.agent/src/` содержит актуальные исходники MetaAgent
- [ ] `.agent/rules/` содержит `project-rules.md`
- [ ] `AGENTS.md` присутствует в корне репозитория
- [ ] `.agent/archive/index.json` создан, завершённые задачи архивированы
- [ ] handoff-summary.md заполнен (включая config, design summary, ADR summary, archive)
- [ ] checkpoints.json финализирован
- [ ] Сигнал отправлен пользователю/оркестратору
