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

{% for entity in entities %}
### {{ entity.name }}

| Поле | Тип | Ограничения | Описание |
|---|---|---|---|
{% for field in entity.fields %}
| {{ field.name }} | {{ field.type }} | {{ field.constraints }} | {{ field.description }} |
{% endfor %}

**Связи:** {{ entity.relationships }}

{% endfor %}

## 5. API / Интерфейсы

{% if has_api %}
| Метод | Путь | Описание | Request | Response |
|---|---|---|---|---|
{% for endpoint in api_endpoints %}
| {{ endpoint.method }} | {{ endpoint.path }} | {{ endpoint.description }} | {{ endpoint.request }} | {{ endpoint.response }} |
{% endfor %}
{% endif %}

{% if has_gui %}
**Экраны:** {{ gui_screens }}
{% endif %}

{% if has_cli %}
**Команды:** {{ cli_commands }}
{% endif %}

## 6. Обработка ошибок

- **Стратегия:** {{ error_strategy }}
- **Формат ошибок:** {{ error_format }}
- **Логирование:** {{ logging_strategy }}

## 7. Тестирование

- **Unit-тесты:** {{ unit_test_strategy }}
- **Integration-тесты:** {{ integration_test_strategy }}
- **Mock-стратегия:** {{ mock_strategy }}
- **Команда запуска:** `{{ test_command }}`

## 8. Alternative Architecture (если применимо)

| Критерий | Выбранная архитектура | Альтернатива |
|---|---|---|
| Название | {{ chosen_arch }} | {{ alt_arch }} |
| Сложность | {{ chosen_complexity }} | {{ alt_complexity }} |
| Почему не выбрана | — | {{ alt_rejection_reason }} |

## 9. ADR Reference (если применимо)

| ID | Решение | Файл |
|---|---|---|
{% for adr in adr_list %}
| {{ adr.id }} | {{ adr.title }} | `{{ adr.path }}` |
{% endfor %}

## 10. Risk Register (если применимо)

| # | Assumption | Impact | Mitigation |
|---|---|---|---|
{% for risk in risk_list %}
| {{ risk.id }} | {{ risk.assumption }} | {{ risk.impact }} | {{ risk.mitigation }} |
{% endfor %}

## 11. Предварительная группировка задач

| Задача | Описание | Тип |
|---|---|---|
| T1 | {{ task_1 }} | config |
| T2 | {{ task_2 }} | feature |
| T3 | {{ task_3 }} | feature |
| T4 | {{ task_4 }} | test |

## 12. Примечания

{{ notes }}
