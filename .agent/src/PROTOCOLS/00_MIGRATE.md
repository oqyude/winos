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
- Опционально: `.agent/layer-1/` структура
- `.agent/migration-report.log`

## Критерии завершения

- [ ] metaagent_version в checkpoints.json == текущей версии из VERSION
- [ ] config присутствует в checkpoints.json
- [ ] phases.red_team присутствует (skipped, если не нужен)
- [ ] migration-report.log создан
- [ ] Все старые данные сохранены (ничего не удалено)
