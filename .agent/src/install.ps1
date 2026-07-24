#!/usr/bin/env pwsh
# MetaAgent — установка исходников в целевой проект
# Usage: .\install.ps1 [[-Path] target_path] [-Update]

param(
    [string]$Path = "",
    [switch]$Update,
    [switch]$Help
)

$MetaAgentSrc = Split-Path -Parent $MyInvocation.MyCommand.Path

function Show-Usage {
    @"
Usage: install.ps1 [[-Path] target_path] [-Update] [-Help]

Install MetaAgent sources into <target>/.agent/src/

Options:
  -Path      Path to target project (default: interactive prompt)
  -Update    Overwrite existing files in .agent/src/
  -Help      Show this help

Examples:
  .\install.ps1
  .\install.ps1 -Path C:\Projects\MyApp
  .\install.ps1 -Path C:\Projects\MyApp -Update
"@
    exit 0
}

if ($Help) { Show-Usage }

$TargetPath = $Path
if (-not $TargetPath) {
    $TargetPath = Read-Host "Enter path to target project"
}

$TargetPath = $TargetPath.Trim()
if (-not (Test-Path $TargetPath -PathType Container)) {
    Write-Error "Directory '$TargetPath' does not exist."
    exit 1
}
$TargetPath = (Resolve-Path $TargetPath).Path

$AgentDir = Join-Path $TargetPath ".agent"
$SrcDir   = Join-Path $AgentDir "src"
$RulesDir   = Join-Path $AgentDir "rules"
$ArchiveDir = Join-Path $AgentDir "archive"
$TempDir    = Join-Path $TargetPath ".temp"
$VersionFile = Join-Path $MetaAgentSrc "VERSION"
$Version = if (Test-Path $VersionFile) { Get-Content $VersionFile -Raw | ForEach-Object { $_.Trim() } } else { "?" }

New-Item -ItemType Directory -Path $SrcDir -Force | Out-Null
New-Item -ItemType Directory -Path $RulesDir -Force | Out-Null
New-Item -ItemType Directory -Path $ArchiveDir -Force | Out-Null
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
Write-Host "Installing MetaAgent v$Version → $SrcDir"

# --- create .temp/ and ensure .gitignore ---
$GitIgnore = Join-Path $TargetPath ".gitignore"
if (-not (Test-Path $GitIgnore -PathType Leaf)) {
    ".temp/" | Out-File -FilePath $GitIgnore -Encoding utf8
    Write-Host "  [create] .gitignore (.temp/)"
} else {
    $content = Get-Content $GitIgnore -Raw
    if ($content -notmatch '^\.temp/$') {
        ".temp/" | Out-File -FilePath $GitIgnore -Encoding utf8 -Append
        Write-Host "  [update] .gitignore (added .temp/)"
    } else {
        Write-Host "  [skip] .gitignore (.temp/ already present)"
    }
}

# --- copy files ---
function Copy-File {
    param([string]$Src, [string]$DstDir)
    $name = Split-Path $Src -Leaf
    if (-not (Test-Path $Src -PathType Leaf)) {
        Write-Host "  [skip] $name (not found)"
        return
    }
    $dst = Join-Path $DstDir $name
    if ($Update -or -not (Test-Path $dst)) {
        Copy-Item $Src $dst -Force
        Write-Host "  [copy] $name"
    } else {
        Write-Host "  [skip] $name (exists, use -Update to overwrite)"
    }
}

function Copy-Dir {
    param([string]$Src, [string]$DstDir)
    $name = Split-Path $Src -Leaf
    if (-not (Test-Path $Src -PathType Container)) {
        Write-Host "  [skip] $name/ (not found)"
        return
    }
    $dst = Join-Path $DstDir $name
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    if ($Update) {
        Get-ChildItem $Src | ForEach-Object {
            Copy-Item $_.FullName $dst -Recurse -Force
        }
    } else {
        Get-ChildItem $Src | ForEach-Object {
            $targetPath = Join-Path $dst $_.Name
            if (-not (Test-Path $targetPath)) {
                Copy-Item $_.FullName $dst -Recurse
            }
        }
    }
    Write-Host "  [copy] $name/"
}

Copy-File (Join-Path $MetaAgentSrc "META_AGENT_GUIDE.md") $SrcDir
Copy-File (Join-Path $MetaAgentSrc "BOUNDARIES.md") $SrcDir
Copy-File (Join-Path $MetaAgentSrc "WORKFLOW.md") $SrcDir
Copy-File (Join-Path $MetaAgentSrc "VERSION") $SrcDir
Copy-Dir  (Join-Path $MetaAgentSrc "PROTOCOLS") $SrcDir
Copy-Dir  (Join-Path $MetaAgentSrc "TEMPLATES") $SrcDir
Copy-File (Join-Path $MetaAgentSrc "install.sh") $SrcDir
Copy-File (Join-Path $MetaAgentSrc "install.ps1") $SrcDir

# --- create / update AGENTS.md in root of target ---
$AgentsMd = Join-Path $TargetPath "AGENTS.md"

function New-AgentsMd {
    param([string]$Path)
@"
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
6. Если `.agent/` не инициализирован или устарел — запусти `install.ps1 -Update` для
   обновления исходников MetaAgent до актуальной версии.
"@
}

if (-not (Test-Path $AgentsMd -PathType Leaf)) {
    New-AgentsMd $AgentsMd | Out-File -FilePath $AgentsMd -Encoding utf8
    Write-Host "  [create] AGENTS.md"
} elseif ($Update) {
    New-AgentsMd $AgentsMd | Out-File -FilePath $AgentsMd -Encoding utf8
    Write-Host "  [update] AGENTS.md"
} else {
    Write-Host "  [skip] AGENTS.md (exists, use -Update to overwrite)"
}

Write-Host ""
Write-Host "Done! MetaAgent v$Version installed at $SrcDir"
