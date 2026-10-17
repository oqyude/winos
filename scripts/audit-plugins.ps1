<#
.SYNOPSIS
    Audit the plugin library: what each plugin resolves to, and where that does
    not match what the live system actually has linked.

.DESCRIPTION
    Reads only. Never creates, moves, or deletes anything.

    Two questions drive the exit code:

      1. For every plugin, do the resolved mappings make sense? A mapping whose
         source does not exist would create a junction pointing nowhere. A
         target already occupied by something else is a conflict the operator
         needs to decide about, not something apply should silently overwrite.

      2. Does the live system contain junctions that no mapping accounts for?
         Those are orphans: revert would leave them behind and apply would never
         notice them, so they are exactly the surprise this audit exists to
         catch before leaving the sandbox.

.PARAMETER LibraryRoot
    Plugin library to inspect. Defaults to $pluginRoot. Deliberately not named
    $Root: init.ps1 assigns $root to the repo root and PowerShell variable
    names are case-insensitive, so sourcing init.ps1 would overwrite a $Root
    parameter and silently audit the wrong directory.

.PARAMETER ManifestDir
    Manifest directory. Defaults to the repo's manifests folder.

.PARAMETER PruneDangling
    Remove dangling orphans: junctions whose source directory no longer exists.

    Without this flag the script only reports. Only 'dangling' orphans are
    touched -- 'undeclared' ones point at a source that still exists, so they
    may be a manifest gap or a wanted link from a different installer variant,
    and removing them would be a guess. Junctions outside the plugin library
    are never considered in the first place.

    Run it after reviewing a report, not as routine maintenance.

.EXAMPLE
    .\scripts\audit-plugins.ps1
    .\scripts\audit-plugins.ps1 -PruneDangling -WhatIf
    .\scripts\audit-plugins.ps1 -PruneDangling
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$LibraryRoot,
    [string]$ManifestDir,
    [switch]$PruneDangling
)

$ErrorActionPreference = 'Continue'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'src\init.ps1')
# Plugin library paths ($pluginRoot, $manifestDir, ...) live with the plugin
# module; the shared src\vars.ps1 defines only the host's own variables.
. (Join-Path $repoRoot 'src\modules\plugins\vars.ps1')
# Order matters: Sandbox before Discovery/Manifest, which call into it.
. (Join-Path $repoRoot 'src\modules\plugins\common\Sandbox.ps1')
. (Join-Path $repoRoot 'src\modules\plugins\common\State.ps1')
. (Join-Path $repoRoot 'src\modules\plugins\common\Discovery.ps1')
. (Join-Path $repoRoot 'src\modules\plugins\common\Manifest.ps1')

if (-not $LibraryRoot) { $LibraryRoot = $pluginRoot }
if (-not $ManifestDir) { $ManifestDir = Join-Path $repoRoot 'manifests' }

# --- inventory of what the live system has linked ------------------------------
# Deliberately recursive and broad. A first pass that only looked at the
# immediate children of the four plugin roots reported iZotope as having no
# links at all, because its junction sits at ...\VST3\iZotope\Ozone 11. The
# ProgramData / AppData / Public roots are included too, since Waves-style
# installers link there rather than under Program Files.
#
# Everything is filtered to junctions whose target is inside the plugin library,
# so unrelated links elsewhere on the machine are ignored.
$scanRoots = @(
    (Join-Path $env:PROGRAMFILES 'VSTPlugins')
    (Join-Path $env:COMMONPROGRAMFILES 'VST3')
    (Join-Path $env:COMMONPROGRAMFILES 'Avid\Audio\Plug-Ins')
    (Join-Path $env:PROGRAMFILES 'Steinberg\VSTPlugins')
    $env:COMMONPROGRAMFILES
    [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    $env:PROGRAMDATA
    $env:APPDATA
    $env:LOCALAPPDATA
    $env:PUBLIC
    (Join-Path ([Environment]::GetEnvironmentVariable('UserProfile')) 'Documents')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique

$pluginRootFull = [System.IO.Path]::GetFullPath($LibraryRoot).TrimEnd('\', '/')

$live = @{}
$liveInLibrary = @{}
foreach ($r in $scanRoots) {
    Get-ChildItem -LiteralPath $r -Recurse -Depth 3 -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } |
        ForEach-Object {
            $t = $_.Target
            if (-not $t) { return }
            $live[$_.FullName] = $t
            $tFull = [System.IO.Path]::GetFullPath($t).TrimEnd('\', '/')
            if ($tFull.StartsWith($pluginRootFull, [StringComparison]::OrdinalIgnoreCase)) {
                $liveInLibrary[$_.FullName] = $t
            }
        }
}

# --- per-plugin resolution ----------------------------------------------------
$rows = @()
$claimed = @{}
$problems = @()

foreach ($folder in (Get-PluginFolders -PluginRoot $LibraryRoot)) {
    $name = $folder.Name
    $dir = $folder.FullName

    $layout = @()
    foreach ($probe in @('VST2', 'VST3', 'vst', 'C')) {
        if (Test-Path -LiteralPath (Join-Path $dir $probe)) { $layout += $probe }
    }

    $manifest = Get-PluginManifest -Name $name -ManifestDir $ManifestDir
    $links = @()
    if ($null -ne $manifest) {
        $links = Get-ManifestLinks -Manifest $manifest -BaseDir $dir
    }
    if (@($links).Count -eq 0) {
        $links = (Discover-Plugin -PluginDir $dir).Mappings
    }
    $links = @($links)

    $regOn = 0; $regOff = 0; $copyN = 0; $procN = 0
    if ($null -ne $manifest) {
        $regOn  = (Get-ManifestRegistrySteps -Manifest $manifest -Action 'enable'  -BaseDir $dir).Count
        $regOff = (Get-ManifestRegistrySteps -Manifest $manifest -Action 'disable' -BaseDir $dir).Count
        $copyN  = (Get-ManifestCopySteps    -Manifest $manifest -BaseDir $dir).Count
        $procN  = (Get-ManifestProcessSteps -Manifest $manifest -Trigger 'beforeRevert' -BaseDir $dir).Count

        # Manifest-referenced files must exist; a missing .reg or .cmd only shows
        # up at run time otherwise, which is the surprise we are trying to avoid.
        foreach ($s in (Get-ManifestRegistrySteps -Manifest $manifest -Action 'enable'  -BaseDir $dir)) {
            if (-not (Test-Path -LiteralPath $s.RegFile)) {
                $problems += [PSCustomObject]@{ Kind='MISSING_REG'; Plugin=$name; Detail=$s.RegFile }
            }
        }
        foreach ($s in (Get-ManifestRegistrySteps -Manifest $manifest -Action 'disable' -BaseDir $dir)) {
            if (-not (Test-Path -LiteralPath $s.RegFile)) {
                $problems += [PSCustomObject]@{ Kind='MISSING_REG'; Plugin=$name; Detail=$s.RegFile }
            }
        }
        foreach ($s in (Get-ManifestProcessSteps -Manifest $manifest -Trigger 'beforeRevert' -BaseDir $dir)) {
            if (-not (Test-Path -LiteralPath $s.Script)) {
                $problems += [PSCustomObject]@{ Kind='MISSING_SCRIPT'; Plugin=$name; Detail=$s.Script }
            }
        }
        foreach ($s in (Get-ManifestCopySteps -Manifest $manifest -BaseDir $dir)) {
            if (-not (Test-Path -LiteralPath $s.From -PathType Container)) {
                $problems += [PSCustomObject]@{ Kind='MISSING_COPY_SRC'; Plugin=$name; Detail=$s.From }
            }
        }
    }

    $srcMissing = 0; $tgtEmpty = 0; $tgtOk = 0; $tgtOther = 0
    foreach ($l in $links) {
        $claimed[$l.To] = $l.From

        if (-not (Test-Path -LiteralPath $l.From)) {
            $srcMissing++
            $problems += [PSCustomObject]@{ Kind='MISSING_SRC'; Plugin=$name; Detail=$l.From }
            continue
        }
        if (-not (Test-Path -LiteralPath $l.To)) { $tgtEmpty++; continue }

        $item = Get-Item -LiteralPath $l.To -Force -ErrorAction SilentlyContinue
        if (-not ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint))) {
            $tgtOther++
            $problems += [PSCustomObject]@{ Kind='TARGET_OCCUPIED'; Plugin=$name; Detail=$l.To }
            continue
        }
        if ([string]::Equals([string]$item.Target, [string]$l.From, [StringComparison]::OrdinalIgnoreCase)) {
            $tgtOk++
        } else {
            $tgtOther++
            $problems += [PSCustomObject]@{ Kind='TARGET_DIFFERS'; Plugin=$name; Detail=("{0}  ->  {1}" -f $l.To, $item.Target) }
        }
    }

    if (@($links).Count -eq 0) {
        $problems += [PSCustomObject]@{ Kind='NO_LINKS'; Plugin=$name; Detail=($layout -join '+') }
    }

    $rows += [PSCustomObject]@{
        Plugin    = $name
        Manifest  = [bool]$manifest
        Layout    = $(if ($layout.Count) { $layout -join '+' } else { '-' })
        Links     = $links.Count
        SrcMiss   = $srcMissing
        TgtEmpty  = $tgtEmpty
        TgtOk     = $tgtOk
        TgtOther  = $tgtOther
        Reg       = "$regOn/$regOff"
        Copy      = $copyN
        Proc      = $procN
    }
}

# --- orphans: live links no mapping claims -------------------------------------
# The two kinds need different decisions, so they are reported separately:
#
#   dangling -- the link points at a path that is not in the library any more.
#               The link itself is broken; removing it loses nothing.
#   undeclared -- the source exists, but no manifest asks for this target. Either
#               the manifest is missing a link, or the link is a leftover from an
#               installer variant that should not have run on this machine.
$orphans = @()
foreach ($k in $liveInLibrary.Keys) {
    if ($claimed.ContainsKey($k)) { continue }
    $orphans += [PSCustomObject]@{
        Target   = $k
        PointsAt = $liveInLibrary[$k]
        Kind     = if (Test-Path -LiteralPath $liveInLibrary[$k]) { 'undeclared' } else { 'dangling' }
    }
}

# --- prune dangling orphans --------------------------------------------------
# Only ever touches 'dangling' ones: their source is already gone, so the link
# is broken and removing it cannot lose data. 'undeclared' orphans keep their
# source, so dropping them would be a guess about intent.
$pruned = 0
$prunedTargets = @()
if ($PruneDangling) {
    foreach ($o in @($orphans | Where-Object { $_.Kind -eq 'dangling' })) {
        if (-not $PSCmdlet.ShouldProcess($o.Target, 'Remove dangling junction')) { continue }
        try {
            # rmdir rather than Remove-Item: on a junction whose target does not
            # exist, Remove-Item can fail or reach somewhere unintended. rmdir
            # removes the link itself and nothing else.
            cmd /c rmdir "$($o.Target)" 2>&1 | Out-Null
            if (Test-Path -LiteralPath $o.Target) {
                Write-Warning ("Still present after rmdir: {0}" -f $o.Target)
                continue
            }
            Write-Host ("    pruned: {0}" -f $o.Target) -ForegroundColor Green
            $pruned++
            $prunedTargets += $o.Target
        } catch {
            Write-Warning ("Could not prune {0}: {1}" -f $o.Target, $_.Exception.Message)
        }
    }
    if ($prunedTargets.Count -gt 0) {
        $orphans = @($orphans | Where-Object { $_.Target -notin $prunedTargets })
    }
}

# --- report -------------------------------------------------------------------
$rows | Sort-Object Plugin | Format-Table -AutoSize

Write-Host ''
Write-Host ("plugins scanned      : {0}" -f $rows.Count) -ForegroundColor Cyan
Write-Host ("live links in library: {0}" -f $liveInLibrary.Count) -ForegroundColor Cyan
Write-Host ("links claimed by maps: {0}" -f $claimed.Count) -ForegroundColor Cyan
Write-Host ("orphans (unclaimed)  : {0}" -f $orphans.Count) -ForegroundColor $(if ($orphans.Count) { 'Red' } else { 'Green' })

if ($orphans.Count) {
    Write-Host ''
    Write-Host '  Live junctions nothing accounts for:' -ForegroundColor Red
    $orphans | Sort-Object Kind, Target | ForEach-Object {
        $color = if ($_.Kind -eq 'dangling') { 'DarkYellow' } else { 'Red' }
        Write-Host ("    [{0}] {1}" -f $_.Kind, $_.Target) -ForegroundColor $color
        Write-Host ("      -> {0}" -f $_.PointsAt) -ForegroundColor DarkGray
    }
    $dangling   = @($orphans | Where-Object { $_.Kind -eq 'dangling' }).Count
    $undeclared = @($orphans | Where-Object { $_.Kind -eq 'undeclared' }).Count
    Write-Host ("    {0} dangling (link broken, safe to remove), {1} undeclared (needs a decision)" -f $dangling, $undeclared) -ForegroundColor Cyan
}

if ($problems.Count) {
    Write-Host ''
    Write-Host '  Mapping problems:' -ForegroundColor Yellow
    $problems | Sort-Object Kind, Plugin | ForEach-Object {
        Write-Host ("    [{0}] {1}" -f $_.Kind, $_.Plugin) -ForegroundColor Yellow
        Write-Host ("      {0}" -f $_.Detail) -ForegroundColor DarkGray
    }
}

Write-Host ''
$blocking = @($problems | Where-Object { $_.Kind -in @('MISSING_SRC', 'MISSING_REG', 'MISSING_SCRIPT', 'MISSING_COPY_SRC') }).Count
$warn     = @($problems | Where-Object { $_.Kind -notin @('MISSING_SRC', 'MISSING_REG', 'MISSING_SCRIPT', 'MISSING_COPY_SRC') }).Count
Write-Host ("blocking: {0}   warnings: {1}   orphans: {2}" -f $blocking, $warn, $orphans.Count) -ForegroundColor $(if ($blocking -or $orphans.Count) { 'Red' } else { 'Green' })

if ($blocking -gt 0 -or $orphans.Count -gt 0) { exit 1 }
exit 0