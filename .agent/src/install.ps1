#!/usr/bin/env pwsh
# MetaAgent — установка исходников в целевой проект
# Usage: .\install.ps1 [[-Path] target_path] [-Check] [-Update]

param(
    [string]$Path = "",
    [switch]$Check,
    [switch]$Update,
    [switch]$Help
)

$MetaAgentSrc = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- helpers ---
function Write-Info  { Write-Host "  →" -NoNewline -ForegroundColor Blue; Write-Host " $args" }
function Write-Ok    { Write-Host "  ✓" -NoNewline -ForegroundColor Green; Write-Host " $args" }
function Write-Skip  { Write-Host "  −" -NoNewline -ForegroundColor Yellow; Write-Host " $args" }
function Write-Warn  { Write-Host "  ⚠" -NoNewline -ForegroundColor Yellow; Write-Host " $args" }
function Write-Fail  { Write-Host "  ✗" -NoNewline -ForegroundColor Red; Write-Host " $args" }
function Write-Header { param([string]$Label)
    Write-Host ""
    Write-Host ("─" * 40)
    Write-Host " $Label"
    Write-Host ("─" * 40)
}

function Show-Usage {
    @"
Usage: install.ps1 [[-Path] target_path] [-Check] [-Update] [-Help]

Install MetaAgent sources into <target>/.agent/src/

Options:
  -Path      Path to target project (default: interactive prompt)
  -Check     Dry-run: only check target readiness, no install
  -Update    Overwrite existing files in .agent/src/
  -Help      Show this help

Examples:
  .\install.ps1
  .\install.ps1 -Path C:\Projects\MyApp
  .\install.ps1 -Path C:\Projects\MyApp -Check
  .\install.ps1 -Path C:\Projects\MyApp -Update
"@
    exit 0
}

if ($Help) { Show-Usage }

# --- resolve target ---
$TargetPath = $Path
if (-not $TargetPath) {
    $TargetPath = Read-Host "Enter path to target project"
}
$TargetPath = $TargetPath.Trim()

# --- pre-flight -----------------------------------------------------------
Write-Header "Pre-flight"

# 1. target exists?
if (-not (Test-Path $TargetPath -PathType Container)) {
    Write-Fail "Target directory '$TargetPath' does not exist."
    exit 1
}
$TargetPath = (Resolve-Path $TargetPath).Path
Write-Ok "Target: $TargetPath"

# 2. write permission? (try to create a temp file as probe)
$probe = [System.IO.Path]::Combine($TargetPath, ".metaagent_probe.tmp")
try {
    [System.IO.File]::WriteAllBytes($probe, [byte[]]@())
    Remove-Item $probe -Force
    Write-Ok "Write permission: yes"
} catch {
    Write-Fail "No write permission on '$TargetPath'."
    exit 1
}

# 3. already installed? compare versions
$AgentDir = Join-Path $TargetPath ".agent"
$SrcDir   = Join-Path $AgentDir "src"
$VersionFile = Join-Path $MetaAgentSrc "VERSION"

$Version = if (Test-Path $VersionFile -PathType Leaf) {
    (Get-Content $VersionFile -Raw -Encoding UTF8).Trim()
} else { "?" }

$oldVerPath = Join-Path $SrcDir "VERSION"
if (Test-Path $oldVerPath -PathType Leaf) {
    $oldVer = (Get-Content $oldVerPath -Raw -Encoding UTF8).Trim()
    if ($oldVer -ne $Version) {
        Write-Info "Existing MetaAgent v$oldVer found → upgrading to v$Version"
    } else {
        Write-Skip "MetaAgent v${Version} already installed (use -Update to reinstall)"
        if (-not $Check) {
            Write-Warn "No changes applied. Run with -Update to overwrite existing files."
        }
    }
} else {
    Write-Info "Fresh install: MetaAgent v$Version"
}

# 4. summary
$AgentsMd  = Join-Path $TargetPath "AGENTS.md"
$RulesDir   = Join-Path $AgentDir "rules"
$DecisionsDir = Join-Path $AgentDir "decisions"
$TasksDir     = Join-Path $AgentDir "tasks"
$ContextDir   = Join-Path $AgentDir "context"
$ArchiveDir   = Join-Path $AgentDir "archive"
$RequestsDir    = Join-Path $AgentDir "requests"
$RoadmapDir     = Join-Path $AgentDir "roadmap"
$TempDir    = Join-Path $TargetPath ".temp"

$DirList = @(
    $SrcDir, $RulesDir, $DecisionsDir, $TasksDir,
    (Join-Path $TasksDir "backlog"), $ContextDir,
    $ArchiveDir,
    (Join-Path $ArchiveDir "tasks"),
    (Join-Path $ArchiveDir "decisions"),
    (Join-Path $ArchiveDir "checkpoints"),
    (Join-Path $RequestsDir "active"),
    (Join-Path $RequestsDir "archive"),
    $RoadmapDir,
    (Join-Path $RoadmapDir "archive"),
    $TempDir
)

if ($Check) {
    Write-Host ""
    Write-Info "--check mode: all checks passed, no changes applied."
    exit 0
}

# --- phase 1: directories ------------------------------------------------
Write-Header "Directories"

foreach ($d in $DirList) {
    $null = New-Item -ItemType Directory -Path $d -Force
    $short = $d.Replace("$TargetPath\", "")
    if (Test-Path $d -PathType Container) {
        Write-Ok $short
    } else {
        Write-Fail "$short (creation failed)"
    }
}

# --- phase 2: files ------------------------------------------------------
Write-Header "Files"

$copyCount = 0
$skipCount = 0
$failCount = 0

function Copy-File {
    param([string]$Src, [string]$DstDir)
    $name = Split-Path $Src -Leaf
    $dst = Join-Path $DstDir $name
    if (-not (Test-Path $Src -PathType Leaf)) {
        Write-Skip "$name (source not found)"
        $script:skipCount++
        return
    }
    if ($Update -or -not (Test-Path $dst)) {
        try {
            Copy-Item $Src $dst -Force -ErrorAction Stop
            Write-Ok $name
            $script:copyCount++
        } catch {
            Write-Fail $name
            $script:failCount++
        }
    } else {
        Write-Skip "$name (exists, use -Update to overwrite)"
        $script:skipCount++
    }
}

function Copy-Dir {
    param([string]$Src, [string]$DstDir)
    $name = Split-Path $Src -Leaf
    $dst = Join-Path $DstDir $name
    if (-not (Test-Path $Src -PathType Container)) {
        Write-Skip "$name/ (source not found)"
        $script:skipCount++
        return
    }
    $null = New-Item -ItemType Directory -Path $dst -Force
    try {
        if ($Update) {
            Get-ChildItem $Src | ForEach-Object {
                Copy-Item $_.FullName $dst -Recurse -Force -ErrorAction Stop
            }
        } else {
            Get-ChildItem $Src | ForEach-Object {
                $targetPath = Join-Path $dst $_.Name
                if (-not (Test-Path $targetPath)) {
                    Copy-Item $_.FullName $dst -Recurse -ErrorAction Stop
                }
            }
        }
        Write-Ok "$name/"
        $script:copyCount++
    } catch {
        Write-Fail "$name/ (partial copy)"
        $script:failCount++
    }
}

Copy-File (Join-Path $MetaAgentSrc "META_AGENT_GUIDE.md") $SrcDir
Copy-File (Join-Path $MetaAgentSrc "BOUNDARIES.md") $SrcDir
Copy-File (Join-Path $MetaAgentSrc "WORKFLOW.md") $SrcDir
Copy-File (Join-Path $MetaAgentSrc "VERSION") $SrcDir
Copy-Dir  (Join-Path $MetaAgentSrc "PROTOCOLS") $SrcDir
Copy-Dir  (Join-Path $MetaAgentSrc "TEMPLATES") $SrcDir
Copy-File (Join-Path $MetaAgentSrc "install.sh") $SrcDir
Copy-File (Join-Path $MetaAgentSrc "install.ps1") $SrcDir

# --- phase 3: AGENTS.md --------------------------------------------------
Write-Header "AGENTS.md"

if (-not (Test-Path $AgentsMd -PathType Leaf)) {
    $content = @"
# MetaAgent

Этот проект использует [MetaAgent](.agent/src/META_AGENT_GUIDE.md) v$Version —
набор инструкций для AI-агента.

## Контекст MetaAgent

| Ресурс | Путь |
|--------|------|
| Главная инструкция | `.agent/src/META_AGENT_GUIDE.md` |
| Протоколы фаз | `.agent/src/PROTOCOLS/` |
| Шаблоны артефактов | `.agent/src/TEMPLATES/` |
| Границы (что разрешено/запрещено) | `.agent/src/BOUNDARIES.md` |
| Правила проекта | `.agent/rules/project-rules.md` |
| Примеры работы | `.agent/src/WORKFLOW.md` |
| Версия | `.agent/src/VERSION` |

## Состояние сессии (если инициализировано)

| Артефакт | Путь |
|----------|------|
| Чекпоинты сессии | `.agent/checkpoints.json` |
| Манифест задач | `.agent/task-manifest.json` |
| Сводка для exec-агента | `.agent/handoff-summary.md` |
| Анализ репозитория | `.agent/analysis-report.md` |

## Для исполнительного агента

1. **Прочитай** `.agent/src/META_AGENT_GUIDE.md` — пойми жизненный цикл MetaAgent.
2. **Прочитай** `.agent/src/BOUNDARIES.md` — соблюдай границы.
3. **Прочитай** `.agent/rules/project-rules.md` — выполни пользовательские правила.
4. **Проверь** `.agent/checkpoints.json` — если существует, используй как состояние сессии.
5. **Проверь** `.agent/task-manifest.json` — если существует, выполняй задачи по порядку.
6. Если `.agent/` не инициализирован или устарел — запусти `install.sh --update` для
   обновления исходников MetaAgent до актуальной версии.
"@
    $utf8 = [System.Text.Encoding]::UTF8
    [System.IO.File]::WriteAllBytes($AgentsMd, $utf8.GetBytes($content))
    Write-Ok "AGENTS.md created"
} elseif ($Update) {
    $content = @"
# MetaAgent

Этот проект использует [MetaAgent](.agent/src/META_AGENT_GUIDE.md) v$Version —
набор инструкций для AI-агента.

## Контекст MetaAgent

| Ресурс | Путь |
|--------|------|
| Главная инструкция | `.agent/src/META_AGENT_GUIDE.md` |
| Протоколы фаз | `.agent/src/PROTOCOLS/` |
| Шаблоны артефактов | `.agent/src/TEMPLATES/` |
| Границы (что разрешено/запрещено) | `.agent/src/BOUNDARIES.md` |
| Правила проекта | `.agent/rules/project-rules.md` |
| Примеры работы | `.agent/src/WORKFLOW.md` |
| Версия | `.agent/src/VERSION` |

## Состояние сессии (если инициализировано)

| Артефакт | Путь |
|----------|------|
| Чекпоинты сессии | `.agent/checkpoints.json` |
| Манифест задач | `.agent/task-manifest.json` |
| Сводка для exec-агента | `.agent/handoff-summary.md` |
| Анализ репозитория | `.agent/analysis-report.md` |

## Для исполнительного агента

1. **Прочитай** `.agent/src/META_AGENT_GUIDE.md` — пойми жизненный цикл MetaAgent.
2. **Прочитай** `.agent/src/BOUNDARIES.md` — соблюдай границы.
3. **Прочитай** `.agent/rules/project-rules.md` — выполни пользовательские правила.
4. **Проверь** `.agent/checkpoints.json` — если существует, используй как состояние сессии.
5. **Проверь** `.agent/task-manifest.json` — если существует, выполняй задачи по порядку.
6. Если `.agent/` не инициализирован или устарел — запусти `install.sh --update` для
   обновления исходников MetaAgent до актуальной версии.
"@
    $utf8 = [System.Text.Encoding]::UTF8
    [System.IO.File]::WriteAllBytes($AgentsMd, $utf8.GetBytes($content))
    Write-Ok "AGENTS.md updated"
} else {
    Write-Skip "AGENTS.md (exists, use -Update to overwrite)"
    $script:skipCount++
}

# --- summary -------------------------------------------------------------
Write-Header "Summary"
Write-Host "  MetaAgent v$Version → $SrcDir"
Write-Host ""
if ($copyCount -gt 0) { Write-Ok "$copyCount file(s) copied" }
if ($skipCount -gt 0) { Write-Skip "$skipCount file(s) skipped" }
if ($failCount -gt 0) { Write-Fail "$failCount file(s) failed" }
Write-Host ""
if ($failCount -eq 0) {
    Write-Ok "Installation completed successfully."
} else {
    Write-Fail "Installation completed with $failCount error(s)."
    exit 1
}
