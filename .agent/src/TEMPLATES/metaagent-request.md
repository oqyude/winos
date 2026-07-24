# MetaAgent Request
# Для ручного заполнения перед запуском MetaAgent.
# Поместите этот файл в .agent/metaagent-request.md целевого репозитория.
# Если файл отсутствует — MetaAgent проведёт интервью (PROTOCOLS/00_CONFIG.md).
# Ответьте "default" на любой вопрос — будет использовано значение по умолчанию.

## Параметры сессии

| Функция | Вкл | Аргументы |
|---|---|---|
| ANALYSIS | ✓ | — |
| DESIGN | ✓ | adr=yes, alternative_arch=yes |
| RED_TEAM | ✗ | — |
| RISK_REGISTER | ✗ | — |
| DECOMPOSITION | ✓ | invariant_tests=yes |
| SETUP | ✓ | — |
| HANDOFF | ✓ | layer_structure=yes |

## Глубина проработки

**Значение:** 6 (1-10)

| Уровень | Название | Описание |
|---|---|---|
| 1-2 | Scaffold | Только структура проекта + пустые модули |
| 3-4 | Light | (default) Быстрый дизайн + задачи без расширений |
| 5-6 | Standard | Полный ANALYSIS→DESIGN→DECOMP→SETUP→HANDOFF |
| 7-8 | Deep | Standard + ADR, Risk Register, Alternative Architecture |
| 9-10 | Maximum | Deep + Red Team Review, Executable Invariants |

## Цель

Сформулируйте задачу для MetaAgent.

## Дополнительно

- **Boundaries:** (опционально) ограничения, которые нельзя нарушать
- **Target:** путь к репозиторию или URL
