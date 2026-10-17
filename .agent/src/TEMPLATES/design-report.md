# Design Report

## Session

- **Session ID:** `{{ session_id }}`
- **Target repo:** `{{ target_repo }}`
- **Date:** {{ date }}

## 1. Технологический стек

| Компонент | Выбор | Обоснование |
|---|---|---|
| Язык | {{ language }} | {{ language_rationale }} |
| Фреймворк | {{ framework }} | {{ framework_rationale }} |
| База данных | {{ database }} | {{ database_rationale }} |
| Инфраструктура | {{ infrastructure }} | {{ infrastructure_rationale }} |

## 2. High-Level архитектура

**Паттерн:** {{ architecture_pattern }}

```
{{ architecture_diagram }}
```

**Поток данных:**
1. {{ data_flow_step_1 }}
2. {{ data_flow_step_2 }}
3. {{ data_flow_step_3 }}

## 3. Модули

| Модуль | Ответственность | Ключевые компоненты | Зависит от |
|---|---|---|---|
| `{{ module_path }}` | {{ responsibility }} | {{ components }} | {{ dependencies }} |

## 4. Модели данных

### Сущности

{{ entity_descriptions }}

## 5. API / Интерфейсы

{{ api_endpoints_table }}

## 6. Обработка ошибок

- **Стратегия:** {{ error_strategy }}
- **Формат ошибок:** {{ error_format }}
- **Логирование:** {{ logging_strategy }}

## 7. Тестирование

- **Unit-тесты:** {{ unit_test_strategy }}
- **Integration-тесты:** {{ integration_test_strategy }}
- **Mock-стратегия:** {{ mock_strategy }}
- **Команда запуска:** `{{ test_command }}`

## 8. Дополнительные артефакты (по команде пользователя)

Если пользователь вызвал соответствующие команды, добавить ссылки:

- ADR: `.agent/decisions/` (команда `/adr`)
- Alternative Architecture: `.agent/context/alt-architecture.md` (команда `/alt-arch`)
- Risk Register: `.agent/context/risk-register.md` (команда `/risk-register`)
- Red Team Review: `.agent/context/red-team-report.md` (команда `/red-team`)

## 9. Предварительная группировка задач

| Задача | Описание | Тип |
|---|---|---|
| T1 | {{ task_1 }} | config |
| T2 | {{ task_2 }} | feature |
| T3 | {{ task_3 }} | feature |
| T4 | {{ task_4 }} | test |

## 10. Примечания

{{ notes }}
