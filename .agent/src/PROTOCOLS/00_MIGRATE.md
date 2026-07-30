# Протокол 00b: Миграция артефактов (MIGRATE)

## Цель

Обеспечить совместимость артефактов `.agent/` при изменении версии MetaAgent.
Позволяет обновлять проекты, созданные старой версией, без потери данных.

## Вход

- `VERSION` — текущая версия MetaAgent
- `.agent/checkpoints.json` — артефакты целевого проекта
- `.agent/` — остальные артефакты

## Шаги

### M1. Определить версию артефактов

Прочитать `.agent/checkpoints.json`:

```python
stored_version = checkpoints.get("metaagent_version", None)
current_version = read("VERSION").strip()
```

- Если `metaagent_version` отсутствует → артефакт создан **v0.x** (доверсионный)
- Если `metaagent_version` == `current_version` → пропустить миграцию
- Если `metaagent_version` < `current_version` → требуется миграция

### M2. Сравнение версий (SemVer)

Версии сравниваются по семантическому версионированию (`MAJOR.MINOR.PATCH`).

```python
def needs_migration(stored, current):
    if stored is None:
        return True
    return parse_semver(stored) < parse_semver(current)
```

### M3. Матрица миграций

Каждая строка — набор шагов для перехода с одной версии на следующую.

| Из версии | В версию | Шаги миграции |
|---|---|---|
| v0.x (нет поля) | v1.0.0 | M3.1 — M3.4 |
| v1.0.0 | v1.1.0 | M3.5 — M3.6 (см. ниже) |
| v1.1.x | v2.0.0 | M6.1 — M6.17 (см. ниже) |

### M4. Шаги миграции v0.x → v1.0.0

... (шаги миграции остаются без изменений)

### M5. Шаги миграции v1.0.0 → v1.1.0

M3.5: Создать `.agent/rules/` с шаблоном `project-rules.md` (если не существует).
M3.6: Создать `.agent/archive/` (если не существует).

#### M3.1. Добавить metaagent_version

Записать в checkpoints.json:

```json
"metaagent_version": "1.1.0"
```

#### M3.2. Добавить config (default)

Если поля `config` нет в checkpoints.json — добавить config по умолчанию:

```json
"config": {
  "depth": 4,
  "design": { "adr": false, "alternative_arch": false },
  "red_team": false,
  "risk_register": false,
  "decomposition": { "invariant_tests": false },
  "handoff": { "layer_structure": false }
}
```

#### M3.3. Добавить фазу red_team

Если в `phases` нет ключа `red_team`:

```json
"red_team": "skipped"
```

#### M3.4. Создать layer-1/ (опционально, только если config.handoff.layer_structure)

Если включена layer_structure:

```bash
mkdir -p .agent/layer-1/adr
touch .agent/layer-1/adr/.gitkeep
```

Если `risk-register.md` уже существует на верхнем уровне — переместить в `.agent/layer-1/risk-register.md`.

### M6. Шаги миграции v1.1.x → v2.0.0

Цель: перейти от layer-0..3 структуры к семантической (decisions/tasks/context/rules).

#### M6.1. Удалить `handoff.layer_structure` из config

Если в `checkpoints.json` присутствует `config.handoff.layer_structure` — удалить поле:

```python
checkpoints["config"].pop("handoff", None)
# или если handoff пуст — удалить целиком
if "handoff" in checkpoints["config"] and not checkpoints["config"]["handoff"]:
    del checkpoints["config"]["handoff"]
```

#### M6.2. Создать новые директории

```bash
mkdir -p .agent/decisions
mkdir -p .agent/tasks/backlog
mkdir -p .agent/context
mkdir -p .agent/archive/decisions
```

#### M6.3. Перенести ADR (.agent/layer-1/adr/ → .agent/decisions/)

```bash
if [ -d ".agent/layer-1/adr" ]; then
  cp -n .agent/layer-1/adr/*.md .agent/decisions/ 2>/dev/null || true
fi
```

#### M6.4. Создать decisions/index.json

Если в `.agent/decisions/` есть .md файлы — создать индекс:

```json
{
  "version": "2.0.0",
  "decisions": [
    { "id": "001", "title": "<извлечь из первого заголовка>", "file": "001-....md" }
  ],
  "created_at": "<timestamp>"
}
```

#### M6.5. Перенести risk-register.md (.agent/layer-1/ → .agent/context/)

```bash
if [ -f ".agent/layer-1/risk-register.md" ]; then
  mv .agent/layer-1/risk-register.md .agent/context/risk-register.md
fi
```

#### M6.6. Перенести red-team-report.md (.agent/layer-1/ → .agent/context/)

```bash
if [ -f ".agent/layer-1/red-team-report.md" ]; then
  mv .agent/layer-1/red-team-report.md .agent/context/red-team-report.md
fi
```

#### M6.7. Перенести analysis-report.md (.agent/layer-2/ → .agent/context/)

```bash
if [ -f ".agent/layer-2/analysis-report.md" ]; then
  mv .agent/layer-2/analysis-report.md .agent/context/analysis-report.md
fi
```

#### M6.8. Перенести design-report.md (.agent/layer-2/ → .agent/context/)

```bash
if [ -f ".agent/layer-2/design-report.md" ]; then
  mv .agent/layer-2/design-report.md .agent/context/design-report.md
fi
```

#### M6.9. Перенести task-manifest (.agent/task-manifest.json → .agent/tasks/manifest.json)

```bash
if [ -f ".agent/task-manifest.json" ]; then
  mv .agent/task-manifest.json .agent/tasks/manifest.json
fi
if [ -f ".agent/task-manifest.md" ]; then
  mv .agent/task-manifest.md .agent/tasks/manifest.md
fi
```

#### M6.10. Перенести handoff-summary.md (.agent/layer-3/ → .agent/)

```bash
if [ -f ".agent/layer-3/handoff-summary.md" ]; then
  mv .agent/layer-3/handoff-summary.md .agent/handoff-summary.md
fi
```

#### M6.11. Перенести baseline-test-report.log (.agent/layer-3/ → .agent/context/)

```bash
if [ -f ".agent/layer-3/baseline-test-report.log" ]; then
  mv .agent/layer-3/baseline-test-report.log .agent/context/baseline-test-report.log
fi
```

#### M6.12. Перенести setup-report.log (.agent/layer-3/ → .agent/context/)

```bash
if [ -f ".agent/layer-3/setup-report.log" ]; then
  mv .agent/layer-3/setup-report.log .agent/context/setup-report.log
fi
```

#### M6.13. Перенести session-summary.md (.agent/layer-0/ → .agent/)

```bash
if [ -f ".agent/layer-0/session-summary.md" ]; then
  mv .agent/layer-0/session-summary.md .agent/session-summary.md
fi
```

#### M6.14. Перенести checkpoints.json (.agent/layer-0/ → .agent/)

```bash
if [ -f ".agent/layer-0/checkpoints.json" ]; then
  cp .agent/layer-0/checkpoints.json .agent/checkpoints.json
  echo "[backup] layer-0/checkpoints.json сохранён на случай отката"
fi
```

#### M6.15. Перенести archive/adr/ → archive/decisions/

```bash
if [ -d ".agent/archive/adr" ]; then
  cp -n .agent/archive/adr/* .agent/archive/decisions/ 2>/dev/null || true
  rm -rf .agent/archive/adr
fi
```

#### M6.16. Удалить пустые layer-директории

```bash
rm -rf .agent/layer-0 .agent/layer-1 .agent/layer-2 .agent/layer-3
rm -rf .agent/archive/reports 2>/dev/null || true
```

#### M6.17. Обновить metaagent_version в checkpoints.json

```json
"metaagent_version": "2.0.0"
```

### M4. После миграции — резюме

Записать в `.agent/migration-report.log`:

```
[MIGRATE] {{ timestamp }}
  From: {{ from_version }}
  To: {{ to_version }}
  Steps applied: {{ step_list }}
  Status: OK
```

## Выход

- Обновлённый `.agent/checkpoints.json` (metaagent_version + config)
- Обновлённая структура `.agent/` (decisions/tasks/context вместо layer-0..3)
- `.agent/migration-report.log`

## Критерии завершения

- [ ] metaagent_version в checkpoints.json == текущей версии из VERSION
- [ ] config присутствует в checkpoints.json
- [ ] phases.red_team присутствует (skipped, если не нужен)
- [ ] migration-report.log создан
- [ ] Все старые данные сохранены (ничего не удалено)
