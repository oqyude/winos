#!/usr/bin/env bash
# MetaAgent — установка исходников в целевой проект
# Usage: ./install.sh [--check|--update] [target_path]
set -euo pipefail

METAAGENT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- helpers ---
red=; grn=; ylw=; blu=; rst=
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    red=$(tput setaf 1); grn=$(tput setaf 2)
    ylw=$(tput setaf 3); blu=$(tput setaf 4)
    rst=$(tput sgr0)
fi
info()  { echo "  ${blu}→${rst} $*"; }
ok()    { echo "  ${grn}✓${rst} $*"; }
skip()  { echo "  ${ylw}−${rst} $*"; }
warn()  { echo "  ${ylw}⚠${rst} $*"; }
fail()  { echo "  ${red}✗${rst} $*"; }
header(){ echo; echo "────────────────────────────────────────"; echo " $*"; echo "────────────────────────────────────────"; }

usage() {
    cat <<EOF
Usage: $0 [--check|--update] [target_path]

Install MetaAgent sources into <target>/.agent/src/

Options:
  --check, -c     Dry-run: only check target readiness, no install
  --update, -u    Overwrite existing files in .agent/src/
  --help, -h      Show this help

Examples:
  $0
  $0 /path/to/project
  $0 --check /path/to/project
  $0 --update /path/to/project
EOF
    exit 0
}

# --- arg parsing ---
CHECK=false
UPDATE=false
TARGET_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check|-c)    CHECK=true; shift ;;
        --update|-u)   UPDATE=true; shift ;;
        --help|-h)     usage ;;
        --*) echo "${red}Unknown option:${rst} $1"; usage ;;
        *) TARGET_PATH="$1"; shift ;;
    esac
done

# --- resolve target ---
if [[ -z "$TARGET_PATH" ]]; then
    read -r -p "Enter path to target project: " TARGET_PATH
fi
TARGET_PATH="${TARGET_PATH/#\~/$HOME}"

# --- pre-flight -----------------------------------------------------------
header "Pre-flight"

# 1. target exists?
if [[ ! -d "$TARGET_PATH" ]]; then
    fail "Target directory '$TARGET_PATH' does not exist."
    exit 1
fi

# resolve to absolute path
TARGET_PATH="$(cd "$TARGET_PATH" 2>/dev/null && pwd)" || {
    fail "Cannot access '$TARGET_PATH'."
    exit 1
}
ok "Target: $TARGET_PATH"

# 2. write permission?
if [[ ! -w "$TARGET_PATH" ]]; then
    fail "No write permission on '$TARGET_PATH'."
    exit 1
fi
ok "Write permission: yes"

# 3. already installed? compare versions
AGENT_DIR="$TARGET_PATH/.agent"
SRC_DIR="$AGENT_DIR/src"
VERSION="$(cat "$METAAGENT_SRC/VERSION" 2>/dev/null || echo '?')"

if [[ -f "$SRC_DIR/VERSION" ]]; then
    OLD_VER="$(cat "$SRC_DIR/VERSION" 2>/dev/null || echo '?')"
    if [[ "$OLD_VER" != "$VERSION" ]]; then
        info "Existing MetaAgent v${OLD_VER} found → upgrading to v${VERSION}"
    else
        skip "MetaAgent v${VERSION} already installed (use --update to reinstall)"
        if [[ "$CHECK" == false ]]; then
            warn "No changes applied. Run with --update to overwrite existing files."
        fi
    fi
else
    info "Fresh install: MetaAgent v$VERSION"
fi

# 4. summary
AGENTS_MD="$TARGET_PATH/AGENTS.md"
RULES_DIR="$AGENT_DIR/rules"
DECISIONS_DIR="$AGENT_DIR/decisions"
TASKS_DIR="$AGENT_DIR/tasks"
CONTEXT_DIR="$AGENT_DIR/context"
ARCHIVE_DIR="$AGENT_DIR/archive"
ARCHIVE_TASKS_DIR="$ARCHIVE_DIR/tasks"
ARCHIVE_DECISIONS_DIR="$ARCHIVE_DIR/decisions"
ARCHIVE_CHECKPOINTS_DIR="$ARCHIVE_DIR/checkpoints"
REQUESTS_DIR="$AGENT_DIR/requests"
REQUESTS_ACTIVE_DIR="$REQUESTS_DIR/active"
REQUESTS_ARCHIVE_DIR="$REQUESTS_DIR/archive"
ROADMAP_DIR="$AGENT_DIR/roadmap"
ROADMAP_ARCHIVE_DIR="$ROADMAP_DIR/archive"
TEMP_DIR="$TARGET_PATH/.temp"

if [[ "$CHECK" == true ]]; then
    echo ""
    info "${ylw}--check mode:${rst} all checks passed, no changes applied."
    exit 0
fi

# --- phase 1: directories ------------------------------------------------
header "Directories"

mkdir -p "$SRC_DIR" "$RULES_DIR" "$DECISIONS_DIR" "$TASKS_DIR" "$TASKS_DIR/backlog" \
         "$CONTEXT_DIR" "$ARCHIVE_DIR" "$ARCHIVE_TASKS_DIR" "$ARCHIVE_DECISIONS_DIR" \
         "$ARCHIVE_CHECKPOINTS_DIR" \
         "$REQUESTS_ACTIVE_DIR" "$REQUESTS_ARCHIVE_DIR" \
         "$ROADMAP_DIR" "$ROADMAP_ARCHIVE_DIR" \
         "$TEMP_DIR"

for d in "$SRC_DIR" "$RULES_DIR" "$DECISIONS_DIR" "$TASKS_DIR" "$TASKS_DIR/backlog" \
         "$CONTEXT_DIR" "$ARCHIVE_DIR" "$ARCHIVE_TASKS_DIR" "$ARCHIVE_DECISIONS_DIR" \
         "$ARCHIVE_CHECKPOINTS_DIR" \
         "$REQUESTS_ACTIVE_DIR" "$REQUESTS_ARCHIVE_DIR" \
         "$ROADMAP_DIR" "$ROADMAP_ARCHIVE_DIR" \
         "$TEMP_DIR"; do
    short="${d#$TARGET_PATH/}"
    if [[ -d "$d" ]]; then
        ok "$short"
    else
        fail "$short (creation failed)"
    fi
done

# --- phase 2: files ------------------------------------------------------
header "Files"

COPY_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0

copy_file() {
    local src="$1" dst_dir="$2"
    local name; name="$(basename "$src")"
    local dst="$dst_dir/$name"
    if [[ ! -f "$src" ]]; then
        skip "$name (source not found)"
        ((SKIP_COUNT += 1))
        return
    fi
    if [[ "$UPDATE" == true ]] || [[ ! -f "$dst" ]]; then
        if cp "$src" "$dst"; then
            ok "$name"
            ((COPY_COUNT++))
        else
            fail "$name"
            ((FAIL_COUNT++))
        fi
    else
        skip "$name (exists, use --update to overwrite)"
        ((SKIP_COUNT += 1))
    fi
}

copy_dir() {
    local src="$1" dst_dir="$2"
    local name; name="$(basename "$src")"
    local dst="$dst_dir/$name"
    if [[ ! -d "$src" ]]; then
        skip "$name/ (source not found)"
        ((SKIP_COUNT += 1))
        return
    fi
    mkdir -p "$dst"
    if [[ "$UPDATE" == true ]]; then
        if cp -rf "$src"/* "$dst/" 2>/dev/null; then
            ok "$name/"
            ((COPY_COUNT++))
        else
            fail "$name/ (partial copy)"
            ((FAIL_COUNT++))
        fi
    else
        cp -rn "$src"/* "$dst/" 2>/dev/null || true
        ok "$name/"
        ((COPY_COUNT++))
    fi
}

copy_file "$METAAGENT_SRC/META_AGENT_GUIDE.md" "$SRC_DIR"
copy_file "$METAAGENT_SRC/BOUNDARIES.md" "$SRC_DIR"
copy_file "$METAAGENT_SRC/WORKFLOW.md" "$SRC_DIR"
copy_file "$METAAGENT_SRC/VERSION" "$SRC_DIR"
copy_dir  "$METAAGENT_SRC/PROTOCOLS" "$SRC_DIR"
copy_dir  "$METAAGENT_SRC/TEMPLATES" "$SRC_DIR"
copy_file "$METAAGENT_SRC/install.sh" "$SRC_DIR"
copy_file "$METAAGENT_SRC/install.ps1" "$SRC_DIR"

# --- phase 3: AGENTS.md --------------------------------------------------
header "AGENTS.md"

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
    ok "AGENTS.md created"
elif [[ "$UPDATE" == true ]]; then
    create_agents_md "$AGENTS_MD"
    ok "AGENTS.md updated"
else
    skip "AGENTS.md (exists, use --update to overwrite)"
    ((SKIP_COUNT += 1))
fi

# --- summary -------------------------------------------------------------
header "Summary"
echo "  MetaAgent v$VERSION → $SRC_DIR"
echo ""
if (( COPY_COUNT > 0 )); then
    ok "${COPY_COUNT} file(s) copied"
fi
if (( SKIP_COUNT > 0 )); then
    skip "${SKIP_COUNT} file(s) skipped"
fi
if (( FAIL_COUNT > 0 )); then
    fail "${FAIL_COUNT} file(s) failed"
fi
echo ""
if (( FAIL_COUNT == 0 )); then
    ok "Installation completed successfully."
else
    fail "Installation completed with ${FAIL_COUNT} error(s)."
    exit 1
fi
