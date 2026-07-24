# Analysis Report

## Session

- **Session ID:** `{{ session_id }}`
- **Target repo:** `{{ target_repo }}`
- **Date:** {{ date }}
- **Project type:** `{{ project_type }}` (existing / greenfield / scaffold)

## 1. Общая информация

- **README:** {{ readme_summary }}
- **Лицензия:** {{ license }}
- **CI/CD:** {{ ci_cd }}
- **Точка входа:** {{ entry_point }}
- **Система сборки:** {{ build_system }}

{% if project_type == "existing" or project_type == "scaffold" %}
## 2. Стек технологий

| Компонент | Значение |
|---|---|
| Язык | {{ language }} |
| Фреймворк | {{ framework }} |
| База данных | {{ database }} |
| Тестовый раннер | {{ test_runner }} |
| Пакетный менеджер | {{ package_manager }} |
| Линтер/форматтер | {{ linter }} |

## 3. Архитектура

```
{{ directory_tree }}
```

**Паттерн:** {{ architecture_pattern }}

**Ключевые модули:**

| Модуль | Описание |
|---|---|
| {{ module }} | {{ description }} |

## 4. Конвенции

- **Стиль:** {{ code_style }}
- **Импорты:** {{ import_style }}
- **Типизация:** {{ typing_usage }}
- **Обработка ошибок:** {{ error_handling }}
- **Логирование:** {{ logging }}

## 5. Тесты

- **Команда запуска:** `{{ test_command }}`
- **Всего тестов:** {{ total_tests }}
- **Пройдено:** {{ passed }}
- **Упало:** {{ failed }}
- **Пропущено:** {{ skipped }}
- **Упавшие тесты:**
  {% for test in failed_tests %}
  - `{{ test }}`
  {% endfor %}

## 6. Базовая проверка

- **Сборка:** {{ build_status }}
- **Запуск:** {{ run_status }}
- **Git status:** {{ git_status }}
{% endif %}

{% if project_type == "greenfield" or project_type == "scaffold" %}
## 7. Требования (из README)

### Функциональные требования

{% for req in functional_requirements %}
- {{ req }}
{% endfor %}

### Нефункциональные требования

{% for req in non_functional_requirements %}
- {{ req }}
{% endfor %}

### Бизнес-контекст

{% for item in business_context %}
- {{ item }}
{% endfor %}

### Неясные моменты / Вопросы

{% for question in open_questions %}
- {{ question }}
{% endfor %}
{% endif %}

## 8. Примечания

{{ notes }}
