# MetaAgent

Этот проект использует [MetaAgent](.agent/src/META_AGENT_GUIDE.md) v2.1.0 —
набор инструкций для AI-агента.

## Контекст MetaAgent

| Ресурс | Путь |
|--------|------|
| Главная инструкция | .agent/src/META_AGENT_GUIDE.md |
| Протоколы фаз | .agent/src/PROTOCOLS/ |
| Шаблоны артефактов | .agent/src/TEMPLATES/ |
| Границы (что разрешено/запрещено) | .agent/src/BOUNDARIES.md |
| Правила проекта | .agent/rules/project-rules.md |
| Примеры работы | .agent/src/WORKFLOW.md |
| Версия | .agent/src/VERSION |

## Состояние сессии (если инициализировано)

| Артефакт | Путь |
|----------|------|
| Чекпоинты сессии | .agent/checkpoints.json |
| Манифест задач | .agent/task-manifest.json |
| Сводка для exec-агента | .agent/handoff-summary.md |
| Анализ репозитория | .agent/analysis-report.md |

## Для исполнительного агента

1. **Прочитай** .agent/src/META_AGENT_GUIDE.md — пойми жизненный цикл MetaAgent.
2. **Прочитай** .agent/src/BOUNDARIES.md — соблюдай границы.
3. **Прочитай** .agent/rules/project-rules.md — выполни пользовательские правила.
4. **Проверь** .agent/checkpoints.json — если существует, используй как состояние сессии.
5. **Проверь** .agent/task-manifest.json — если существует, выполняй задачи по порядку.
6. Если .agent/ не инициализирован или устарел — запусти install.sh --update для
   обновления исходников MetaAgent до актуальной версии.