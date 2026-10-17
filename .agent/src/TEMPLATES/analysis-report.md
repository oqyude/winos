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

## 2. Стек технологий (existing / scaffold)

| Компонент | Значение |
|---|---|
| Язык | {{ language }} |
| Фреймворк | {{ framework }} |
| База данных | {{ database }} |
| Тестовый раннер | {{ test_runner }} |
| Пакетный менеджер | {{ package_manager }} |
| Линтер/форматтер | {{ linter }} |

## 3. Архитектура (existing / scaffold)

```
{{ directory_tree }}
```

**Паттерн:** {{ architecture_pattern }}

**Ключевые модули:**

| Модуль | Описание |
|---|---|
| {{ module }} | {{ description }} |

## 4. Конвенции (existing / scaffold)

- **Стиль:** {{ code_style }}
- **Импорты:** {{ import_style }}
- **Типизация:** {{ typing_usage }}
- **Обработка ошибок:** {{ error_handling }}
- **Логирование:** {{ logging }}

## 5. Тесты (existing / scaffold)

- **Команда запуска:** `{{ test_command }}`
- **Всего тестов:** {{ total_tests }}
- **Пройдено:** {{ passed }}
- **Упало:** {{ failed }}
- **Пропущено:** {{ skipped }}
- **Упавшие тесты:** {{ failed_tests_list }}

## 6. Базовая проверка (existing / scaffold)

- **Сборка:** {{ build_status }}
- **Запуск:** {{ run_status }}
- **Git status:** {{ git_status }}

## 7. Требования (greenfield / scaffold)

### Функциональные требования

{{ functional_requirements_list }}

### Нефункциональные требования

{{ non_functional_requirements_list }}

### Бизнес-контекст

{{ business_context_list }}

### Неясные моменты / Вопросы

{{ open_questions_list }}

## 8. Примечания

{{ notes }}
