#!/usr/bin/env bash
# MetaAgent — установка исходников в целевой проект
# Usage: ./install.sh [--update] [target_path]
set -euo pipefail

METAAGENT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<EOF
Usage: $0 [--update] [target_path]

Install MetaAgent sources into <target>/.agent/src/

Options:
  --update, -u    Overwrite existing files in .agent/src/
  --help, -h      Show this help

Examples:
  $0
  $0 /path/to/project
  $0 --update /path/to/project
EOF
    exit 0
}

UPDATE=false
TARGET_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --update|-u) UPDATE=true; shift ;;
        --help|-h) usage ;;
        --*) echo "Unknown option: $1"; usage ;;
        *) TARGET_PATH="$1"; shift ;;
    esac
done

if [[ -z "$TARGET_PATH" ]]; then
    read -r -p "Enter path to target project: " TARGET_PATH
fi

TARGET_PATH="${TARGET_PATH/#\~/$HOME}"
TARGET_PATH="$(cd "$TARGET_PATH" 2>/dev/null && pwd)" || {
    echo "Error: Directory '$TARGET_PATH' does not exist."
    exit 1
}

AGENT_DIR="$TARGET_PATH/.agent"
SRC_DIR="$AGENT_DIR/src"
VERSION="$(cat "$METAAGENT_SRC/VERSION" 2>/dev/null || echo '?')"

RULES_DIR="$AGENT_DIR/rules"
ARCHIVE_DIR="$AGENT_DIR/archive"
TEMP_DIR="$TARGET_PATH/.temp"
mkdir -p "$SRC_DIR" "$RULES_DIR" "$ARCHIVE_DIR" "$TEMP_DIR"
echo "Installing MetaAgent v$VERSION → $SRC_DIR"

# --- create .temp/ and ensure .gitignore ---
if [[ ! -f "$TARGET_PATH/.gitignore" ]]; then
    echo ".temp/" > "$TARGET_PATH/.gitignore"
    echo "  [create] .gitignore (.temp/)"
else
    if ! grep -q '^\.temp/$' "$TARGET_PATH/.gitignore"; then
        echo ".temp/" >> "$TARGET_PATH/.gitignore"
        echo "  [update] .gitignore (added .temp/)"
    else
        echo "  [skip] .gitignore (.temp/ already present)"
    fi
fi

# --- copy files ---
copy_file() {
    local src="$1" dst_dir="$2"
    local name; name="$(basename "$src")"
    if [[ ! -f "$src" ]]; then
        echo "  [skip] $name (not found)"
        return
    fi
    if [[ "$UPDATE" == true ]] || [[ ! -f "$dst_dir/$name" ]]; then
        cp "$src" "$dst_dir/$name"
        echo "  [copy] $name"
    else
        echo "  [skip] $name (exists, use --update to overwrite)"
    fi
}

copy_dir() {
    local src="$1" dst_dir="$2"
    local name; name="$(basename "$src")"
    if [[ ! -d "$src" ]]; then
        echo "  [skip] $name/ (not found)"
        return
    fi
    mkdir -p "$dst_dir/$name"
    if [[ "$UPDATE" == true ]]; then
        cp -rf "$src"/* "$dst_dir/$name/" 2>/dev/null || true
    else
        cp -rn "$src"/* "$dst_dir/$name/" 2>/dev/null || true
    fi
    echo "  [copy] $name/"
}

copy_file "$METAAGENT_SRC/META_AGENT_GUIDE.md" "$SRC_DIR"
copy_file "$METAAGENT_SRC/BOUNDARIES.md" "$SRC_DIR"
copy_file "$METAAGENT_SRC/WORKFLOW.md" "$SRC_DIR"
copy_file "$METAAGENT_SRC/VERSION" "$SRC_DIR"
copy_dir  "$METAAGENT_SRC/PROTOCOLS" "$SRC_DIR"
copy_dir  "$METAAGENT_SRC/TEMPLATES" "$SRC_DIR"
copy_file "$METAAGENT_SRC/install.sh" "$SRC_DIR"
copy_file "$METAAGENT_SRC/install.ps1" "$SRC_DIR"

# --- create / update AGENTS.md in root of target ---
AGENTS_MD="$TARGET_PATH/AGENTS.md"

create_agents_md() {
    cat > "$1" << AGENTS_EOF
# MetaAgent

Этот проект использует [MetaAgent](.agent/src/META_AGENT_GUIDE.md) v$VERSION —
набор инструкций для AI-агента.

## Контекст MetaAgent

| Ресурс | Путь |
|--------|------|
| Главная инструкция | \`.agent/src/META_AGENT_GUIDE.md\` |
| Протоколы фаз | \`.agent/src/PROTOCOLS/\` |
| Шаблоны артефактов | \`.agent/src/TEMPLATES/\` |
| Границы (что разрешено/запрещено) | \`.agent/src/BOUNDARIES.md\` |
| Правила проекта | \`.agent/rules/project-rules.md\` |
| Примеры работы | \`.agent/src/WORKFLOW.md\` |
| Версия | \`.agent/src/VERSION\` |

## Состояние сессии (если инициализировано)

| Артефакт | Путь |
|----------|------|
| Чекпоинты сессии | \`.agent/checkpoints.json\` |
| Манифест задач | \`.agent/task-manifest.json\` |
| Сводка для exec-агента | \`.agent/handoff-summary.md\` |
| Анализ репозитория | \`.agent/analysis-report.md\` |

## Для исполнительного агента

1. **Прочитай** \`.agent/src/META_AGENT_GUIDE.md\` — пойми жизненный цикл MetaAgent.
2. **Прочитай** \`.agent/src/BOUNDARIES.md\` — соблюдай границы.
3. **Прочитай** \`.agent/rules/project-rules.md\` — выполни пользовательские правила.
4. **Проверь** \`.agent/checkpoints.json\` — если существует, используй как состояние сессии.
5. **Проверь** \`.agent/task-manifest.json\` — если существует, выполняй задачи по порядку.
6. Если \`.agent/\` не инициализирован или устарел — запусти \`install.sh --update\` для
   обновления исходников MetaAgent до актуальной версии.
AGENTS_EOF
}

if [[ ! -f "$AGENTS_MD" ]]; then
    create_agents_md "$AGENTS_MD"
    echo "  [create] AGENTS.md"
elif [[ "$UPDATE" == true ]]; then
    create_agents_md "$AGENTS_MD"
    echo "  [update] AGENTS.md"
else
    echo "  [skip] AGENTS.md (exists, use --update to overwrite)"
fi

echo ""
echo "Done! MetaAgent v$VERSION installed at $SRC_DIR"
