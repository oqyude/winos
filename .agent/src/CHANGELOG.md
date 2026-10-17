# Changelog

## 3.0.0 — Упрощение модели

**Дата:** 2026-10-08

### Что изменилось

Принята модель «жизненный цикл + команды на вызов» вместо «жизненный цикл с уровнями глубины».

**Удалено:**
- Шкала глубины (depth 1-10) и все её варианты (Scaffold/Light/Standard/Deep/Maximum).
- Условные фичи в фазах: `adr`, `alternative_arch`, `red_team`, `risk_register`, `invariant_tests`.
- Интервью с пользователем на старте (5 вопросов про depth и фичи).
- `.agent/metaagent-request.md` — конфиг-файл, который сейчас не нужен.
- `TEMPLATES/metaagent-request.md`.

**Добавлено:**
- Директория `COMMANDS/` с пятью on-demand инструкциями: `adr.md`, `red-team.md`, `risk-register.md`, `alt-arch.md`, `invariant-tests.md`.
- `GUIDE.md` — заменяет `META_AGENT_GUIDE.md`, описание цикла + список команд.
- `CHANGELOG.md` — этот файл.

**Переименовано / перенумеровано:**
- `META_AGENT_GUIDE.md` → `GUIDE.md`.
- `PROTOCOLS/01_ANALYSIS.md` → `01_ANALYSE.md`.
- `PROTOCOLS/02_DESIGN.md` → `03_DESIGN.md`.
- `PROTOCOLS/03_DECOMPOSITION.md` → `04_DECOMPOSITION.md`.
- `PROTOCOLS/04_EXECUTION.md` → `05_EXECUTION.md`.
- `PROTOCOLS/05_HANDOFF.md` → `07_HANDOFF.md`.
- `PROTOCOLS/06_METASTATE.md` остался под тем же именем (теперь фаза 6).

**Удалены протоколы:**
- `PROTOCOLS/00_CONFIG.md` — конфигурация больше не нужна.
- `PROTOCOLS/00_MIGRATE.md` — миграция теперь документируется в этом CHANGELOG.
- `PROTOCOLS/04_ENVIRONMENT_SETUP.md` — поглощён фазой `00_INIT.md`.
- `PROTOCOLS/02b_REDTEAM.md` — теперь команда `COMMANDS/red-team.md`.

**Структура `.agent/checkpoints.json`** упрощена: убраны `config.depth`, `config.design.adr`, `config.red_team`, `config.risk_register`, `config.decomposition.invariant_tests`.

### Миграция с v2.1 → v3.0

Для проектов, созданных с MetaAgent v2.1:

1. **Удалить** из `.agent/checkpoints.json` секцию `config` целиком (она больше не читается).
2. **Удалить** `.agent/metaagent-request.md` (не используется).
3. **Удалить** `.agent/decisions/config.json`, если есть (аналог config для решений).
4. **Запустить** `install.sh --update` (или `install.ps1 -Update` / `install.bat --update`) — перезапишет исходники MetaAgent.
5. **Переименовать** пути в существующих артефактах: `layer-1/adr/` → `decisions/` (если остались с v1.x), `layer-2/analysis-report.md` → `context/analysis-report.md` и т.п. — это касается только проектов, оставшихся на v1.x.
6. **Записать** в `.agent/checkpoints.json` новое значение `metaagent_version: "3.0.0"`.

`request.json`, `manifest.json`, `decisions/index.json` остаются в том же формате, что в v2.1.

### Экономия

| | v2.1 | v3.0 |
|---|---|---|
| Markdown строк всего | ~3 820 | ~1 800 (целевой) |
| Протоколов | 10 | 8 |
| Уровней конфигурации | 5 (depth) | 0 |

---

## 2.1.0 — Project Loop + Work Loop + Requests

**Дата:** 2025-08 (предыдущая версия)

- Введён двухконтурный жизненный цикл: Project Loop (однократно) + Work Loop (циклически).
- Добавлены фазы: ROADMAP, METASTATE, RED_TEAM.
- Введены `requests/` как единица результата выполненной задачи.
- Введён `metaagent-request.md` с конфигом сессии (depth scale, фичи).
- Введена структура `.agent/` с семантическими директориями: `decisions/`, `tasks/`, `context/`, `rules/`, `requests/`, `roadmap/`, `archive/`.
- Шкала глубины 1-10 с условными фичами (adr, alternative_arch, red_team, risk_register, invariant_tests).

## 2.0.0 — Реструктуризация `.agent/`

- Переход от слоистой структуры `layer-0..3` к семантическим директориям.
- Полный MIGRATE-протокол для апгрейда с v1.x.

## 1.1.0 — Добавлены rules, archive

- `PROTOCOLS/01_ANALYSIS.md` обзавёлся правилами из `.agent/rules/`.
- Добавлена директория `archive/`.

## 1.0.0 — Первый релиз

- Односессионный pipeline: INIT → ANALYSE → DECOMP → SETUP → HANDOFF.
- Структура `layer-0..3`.
