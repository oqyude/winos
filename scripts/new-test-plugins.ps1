<#
.SYNOPSIS
    Populate S:\Plugins\Test for sandboxed runs.

.DESCRIPTION
    The sandbox reads sources from S:\Plugins\Test and writes targets to C:\Test,
    so the plugins being exercised need to exist there.

    -Skeleton is the mode to reach for when validating the whole library. A
    junction only needs its source directory to exist; nothing reads the file
    contents. So the directory tree is reproduced and the handful of small files
    that manifests actually reference (.reg imports, .cmd kill scripts) are
    copied. That turns a 300 GB library into a few MB of directories, which is
    the difference between auditing everything and auditing four plugins.

    Without -Skeleton the plugin is copied whole, which is what you want when
    you intend to actually load the plugin through the sandboxed link.

.PARAMETER Include
    Plugin folder names. Defaults to a curated set of small plugins.

.PARAMETER All
    Every folder in the plugin library, not just the default set.

.PARAMETER Skeleton
    Recreate directories only, plus manifest-referenced small files.

.PARAMETER MaxSizeMB
    Refuse a whole-copy of any plugin larger than this. Ignored for skeletons.
    Default 150.

.PARAMETER Force
    Re-copy plugins that are already present.

.EXAMPLE
    .\scripts\new-test-plugins.ps1 -WhatIf
    .\scripts\new-test-plugins.ps1
    .\scripts\new-test-plugins.ps1 -All -Skeleton
    .\scripts\new-test-plugins.ps1 -Include 'Waves' -MaxSizeMB 200
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$Include = @(
        'Daichi Laboratory - Synth1',
        'Stone Voices - DVerb',
        'BOBOC - Just a Sample',
        'Joey Sturgis Tones - Toneforge DI Match'
    ),
    [switch]$All,
    [switch]$Skeleton,
    [int]$MaxSizeMB = 150,
    [switch]$Force
)

$ErrorActionPreference = 'Continue'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'src\init.ps1')
# Plugin library paths ($pluginRoot, $manifestDir, ...) live with the plugin
# module; the shared src\vars.ps1 defines only the host's own variables.
. (Join-Path $repoRoot 'src\modules\plugins\vars.ps1')
. (Join-Path $repoRoot 'src\modules\plugins\common\Sandbox.ps1')
. (Join-Path $repoRoot 'src\modules\plugins\common\Discovery.ps1')
. (Join-Path $repoRoot 'src\modules\plugins\common\Manifest.ps1')

$dest = 'S:\Plugins\Test'
$manifestDir = Join-Path $repoRoot 'manifests'

if (-not (Test-Path -LiteralPath $dest)) {
    if ($PSCmdlet.ShouldProcess($dest, 'Create directory')) {
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
    }
}

$targets = if ($All) {
    Get-PluginFolders -PluginRoot $pluginRoot | ForEach-Object { $_.FullName }
} else {
    $Include | ForEach-Object { Join-Path $pluginRoot $_ }
}

# Files small enough to matter to a manifest step: registry imports and the
# vendor scripts a revert would run.
$manifestFileExtensions = @('.reg', '.cmd', '.bat', '.ps1', '.vbs')

function Copy-Skeleton {
    param([string]$Source, [string]$Target, [string]$ManifestDir)

    $dirs = @(Get-ChildItem -LiteralPath $Source -Recurse -Directory -Force -ErrorAction SilentlyContinue)
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
    foreach ($d in $dirs) {
        $rel = $d.FullName.Substring($Source.Length).TrimStart('\', '/')
        New-Item -ItemType Directory -Path (Join-Path $Target $rel) -Force -ErrorAction SilentlyContinue | Out-Null
    }

    # Copy only what the plugin's own manifest points at. Link sources that are
    # files (u-he ships .xml presets, XLN ships .dll stubs) are not copied --
    # they are recreated empty, since a symlink only needs the path to exist and
    # copying whole DLLs would defeat the point of a skeleton.
    $name = Split-Path -Leaf $Source
    $wantedFiles = @()
    $wantedEmpty = @()
    $manifest = Get-PluginManifest -Name $name -ManifestDir $ManifestDir
    if ($null -ne $manifest) {
        $pluginDir = $Source
        foreach ($s in (Get-ManifestRegistrySteps -Manifest $manifest -Action 'enable'  -BaseDir $pluginDir)) { $wantedFiles += $s.RegFile }
        foreach ($s in (Get-ManifestRegistrySteps -Manifest $manifest -Action 'disable' -BaseDir $pluginDir)) { $wantedFiles += $s.RegFile }
        foreach ($s in (Get-ManifestProcessSteps  -Manifest $manifest -Trigger 'beforeRevert' -BaseDir $pluginDir)) { $wantedFiles += $s.Script }
        foreach ($l in (Get-ManifestLinks -Manifest $manifest -BaseDir $pluginDir)) {
            if (Test-Path -LiteralPath $l.From -PathType Leaf) { $wantedEmpty += $l.From }
        }
    }

    $copiedFiles = 0
    foreach ($w in ($wantedFiles | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $w)) { continue }
        if ([System.IO.Path]::GetExtension($w).ToLower() -notin $manifestFileExtensions) { continue }
        $rel = $w.Substring($Source.Length).TrimStart('\', '/')
        $dst = Join-Path $Target $rel
        $parent = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Copy-Item -LiteralPath $w -Destination $dst -Force -ErrorAction SilentlyContinue
        $copiedFiles++
    }

    # Recreate file link targets as empty files so the sandbox can exercise
    # file symlinks too.
    $createdEmpty = 0
    foreach ($w in ($wantedEmpty | Select-Object -Unique)) {
        $rel = $w.Substring($Source.Length).TrimStart('\', '/')
        $dst = Join-Path $Target $rel
        $parent = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        if (-not (Test-Path -LiteralPath $dst)) {
            New-Item -ItemType File -Path $dst -Force -ErrorAction SilentlyContinue | Out-Null
            $createdEmpty++
        }
    }

    [PSCustomObject]@{ Directories = $dirs.Count + 1; Files = $copiedFiles; EmptyFiles = $createdEmpty }
}

$copied = 0; $skipped = 0; $failed = 0; $totalDirs = 0; $totalFiles = 0; $totalEmpty = 0

foreach ($src in $targets) {
    if (-not (Test-Path -LiteralPath $src -PathType Container)) {
        Write-Warning "Not found in plugin library: $src"
        $skipped++
        continue
    }
    $name = Split-Path -Leaf $src
    $target = Join-Path $dest $name

    if ($Skeleton) {
        if (-not $PSCmdlet.ShouldProcess($target, 'Recreate directory tree')) { continue }
        try {
            $r = Copy-Skeleton -Source $src -Target $target -ManifestDir $manifestDir
            $totalDirs += $r.Directories
            $totalFiles += $r.Files
            $totalEmpty += $r.EmptyFiles
            Write-Host ("  ~ {0,-45} {1,6} dirs, {2} file(s), {3} stub(s)" -f $name, $r.Directories, $r.Files, $r.EmptyFiles) -ForegroundColor DarkCyan
            $copied++
        } catch {
            Write-Warning ("Skeleton failed for '{0}': {1}" -f $name, $_.Exception.Message)
            $failed++
        }
        continue
    }

    $sizeMB = [math]::Round((Get-ChildItem -LiteralPath $src -Recurse -File -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum / 1MB, 1)
    if ($sizeMB -gt $MaxSizeMB) {
        Write-Warning ("Skipping '{0}': {1} MB exceeds the {2} MB limit (use -Skeleton)" -f $name, $sizeMB, $MaxSizeMB)
        $skipped++
        continue
    }

    if (Test-Path -LiteralPath $target) {
        if (-not $Force) {
            Write-Host ("  = {0,-42} {1,7} MB  (already present)" -f $name, $sizeMB) -ForegroundColor DarkGray
            $skipped++
            continue
        }
        if ($PSCmdlet.ShouldProcess($target, 'Remove and re-copy')) {
            Remove-Item -LiteralPath $target -Recurse -Force
        }
    }

    if (-not $PSCmdlet.ShouldProcess($src, "Copy to $target ($sizeMB MB)")) { continue }

    try {
        Write-Host ("  + {0,-42} {1,7} MB" -f $name, $sizeMB) -ForegroundColor Cyan
        & robocopy.exe $src $target /E /NFL /NDL /NJH /NJS /NP /R:1 /W:1 | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "robocopy exited with $LASTEXITCODE" }
        $copied++
    } catch {
        Write-Warning ("Failed to copy '{0}': {1}" -f $name, $_.Exception.Message)
        $failed++
    }
}

Write-Host ''
if ($Skeleton) {
    Write-Host ("skeletons: {0}  ({1} directories, {2} manifest files, {3} stub files)  skipped: {4}  failed: {5}" -f $copied, $totalDirs, $totalFiles, $totalEmpty, $skipped, $failed) -ForegroundColor Cyan
} else {
    Write-Host ("copied: {0}  skipped: {1}  failed: {2}" -f $copied, $skipped, $failed) -ForegroundColor Cyan
}
Write-Host ("Sandbox source tree: {0}" -f $dest) -ForegroundColor DarkGray

if ($failed -gt 0) { exit 1 }