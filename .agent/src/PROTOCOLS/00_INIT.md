# Протокол 00: Инициализация (INIT)

## Цель

Подготовить `.agent/` в целевом репозитории: установить исходники MetaAgent, создать структуру директорий, инициализировать `checkpoints.json`, создать/обновить `AGENTS.md`.

INIT выполняется **один раз** в начале работы с проектом. Если `.agent/` уже существует и инициализирован — пропускается.

## Вход

- Целевой репозиторий (путь или текущая директория)
- `VERSION` — текущая версия MetaAgent
- Опционально: существующий `.agent/` (если обновление)

## Шаги

### 0.1. Определить целевой репозиторий

Если не указан явно — текущая рабочая директория. Если указан как URL — клонировать во временную директорию, дальше работать с копией.

### 0.2. Проверить существующий `.agent/`

Если `.agent/` существует:

- Прочитать `.agent/checkpoints.json` → `metaagent_version`
- Если `metaagent_version == VERSION` → INIT уже выполнен, выйти
- Если версия старше → запустить `install.sh --update` (Unix) или `install.ps1 -Update` (Windows) для переустановки исходников, затем выйти
- Если `.agent/` есть, но `checkpoints.json` отсутствует → продолжить INIT (создать checkpoints)

Если `.agent/` не существует → продолжить INIT.

### 0.3. Создать структуру `.agent/`

Создать директории:

```
.agent/
  src/                 # исходники MetaAgent (копируются из METAAGENT_SRC)
  rules/
  decisions/
  tasks/
    backlog/
  context/
  requests/
    active/
    archive/
  roadmap/
    archive/
  archive/
    tasks/
    decisions/
    requests/
    checkpoints/
```

### 0.4. Создать `.temp/` в корне проекта

Если не существует — создать `.temp/` в корне целевого репозитория. Добавить в `.gitignore` (если его нет — создать с одной строкой `.temp/`).

### 0.5. Скопировать исходники MetaAgent

Скопировать в `.agent/src/`:

- `GUIDE.md`
- `BOUNDARIES.md`
- `CHANGELOG.md`
- `VERSION`
- `PROTOCOLS/`
- `COMMANDS/`
- `TEMPLATES/`
- `install.sh`, `install.ps1`

Существующие файлы в `.agent/src/` не перезаписывать (только с явным `--update`).

### 0.6. Создать `.agent/rules/project-rules.md`

Если файла нет — создать по шаблону `TEMPLATES/project-rules.md`.

### 0.7. Создать/обновить `AGENTS.md` в корне

Если `AGENTS.md` в корне проекта отсутствует — создать по `AGENTS.template.md` с подставленной версией.

Если существует и не относится к MetaAgent — не трогать (попросить пользователя переименовать или подтвердить перезапись).

### 0.8. Инициализировать `checkpoints.json`

Создать `.agent/checkpoints.json`:

```json
{
  "metaagent_version": "3.0.0",
  "session_id": "<uuid>",
  "target_repo": "<путь>",
  "goal": null,
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
  "last_updated": "<timestamp>"
}
```

Поля `goal` и `project_type` остаются `null` до фазы ANALYSE (goal может быть задан пользователем заранее — тогда заполнить сразу).

## Выход

- `.agent/` с полной структурой
- `.agent/src/` с актуальными исходниками MetaAgent
- `.agent/rules/project-rules.md`
- `.agent/checkpoints.json` со `session_id` и `phases.init = "completed"`
- `AGENTS.md` в корне проекта
- `.temp/` в корне + `.gitignore` обновлён

## Критерии завершения

- [ ] `.agent/` содержит все обязательные директории
- [ ] `.agent/src/` содержит GUIDE.md, PROTOCOLS/, COMMANDS/, TEMPLATES/, VERSION
- [ ] `.agent/checkpoints.json` валиден (JSON parse)
- [ ] `AGENTS.md` присутствует в корне
- [ ] `.temp/` существует и в `.gitignore`
