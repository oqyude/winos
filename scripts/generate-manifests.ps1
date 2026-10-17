<#
.SYNOPSIS
    Generate link manifests from the junctions the live system actually has.

.DESCRIPTION
    The C-mirror layout heuristic cannot tell an install location from a content
    tree: Acon Digital alone yields 170 candidate mappings of which 2 are real,
    and no depth threshold separates them. So C-layout plugins get their links
    written down explicitly instead.

    The live junctions are the ground truth here. This script reads them, groups
    them by the plugin folder they point into, and writes a manifest per plugin.
    Existing manifests are left alone unless -Force is given.

    Path rewriting is the inverse of the sandbox map: a real system path is
    turned back into %VAR% tokens so the manifest stays machine independent.

.PARAMETER Force
    Overwrite manifests that already exist.

.PARAMETER Include
    Only generate for these plugin names.

.PARAMETER WhatIfOutput
    Print the JSON instead of writing files.

.EXAMPLE
    .\scripts\generate-manifests.ps1 -WhatIfOutput
    .\scripts\generate-manifests.ps1
    .\scripts\generate-manifests.ps1 -Include 'Waves' -Force
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$Include,
    [switch]$Force,
    [switch]$WhatIfOutput
)

$ErrorActionPreference = 'Continue'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'src\init.ps1')
# Plugin library paths ($pluginRoot, $manifestDir, ...) live with the plugin
# module; the shared src\vars.ps1 defines only the host's own variables.
. (Join-Path $repoRoot 'src\modules\plugins\vars.ps1')
. (Join-Path $repoRoot 'src\modules\plugins\common\Sandbox.ps1')
. (Join-Path $repoRoot 'src\modules\plugins\common\Manifest.ps1')

$manifestDir = Join-Path $repoRoot 'manifests'

# Longest prefixes first so C:\Program Files\Common Files is not shortened to
# C:\Program Files before the more specific rule gets a chance.
$tokenRules = @(
    @{ Real = [Environment]::GetEnvironmentVariable('CommonProgramFiles'); Token = '%CommonProgramFiles%' }
    @{ Real = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)');  Token = '%ProgramFiles(x86)%' }
    @{ Real = [Environment]::GetEnvironmentVariable('ProgramFiles');       Token = '%ProgramFiles%' }
    @{ Real = [Environment]::GetEnvironmentVariable('ProgramData');        Token = '%ProgramData%' }
    @{ Real = [Environment]::GetEnvironmentVariable('AppData');            Token = '%AppData%' }
    @{ Real = [Environment]::GetEnvironmentVariable('LocalAppData');       Token = '%LocalAppData%' }
    @{ Real = [Environment]::GetEnvironmentVariable('Public');             Token = '%Public%' }
    @{ Real = [Environment]::GetEnvironmentVariable('UserProfile');        Token = '%UserProfile%' }
) | Where-Object { $_.Real } | Sort-Object { $_.Real.Length } -Descending

function ConvertTo-TokenPath {
    param([string]$Path)
    foreach ($r in $tokenRules) {
        $pattern = '^' + [regex]::Escape($r.Real.TrimEnd('\')) + '(?=\\|$)'
        if ($Path -match $pattern) {
            return $r.Token + $Path.Substring($r.Real.TrimEnd('\').Length)
        }
    }
    return $Path
}

# --- collect live junctions ---------------------------------------------------
# Recursive and broad, same reasoning as audit-plugins.ps1: a plugin may nest its
# junction one level under a vendor folder (iZotope lives at ...\VST3\iZotope\
# Ozone 11), and some installers link under ProgramData or AppData instead of
# Program Files. Everything is filtered to targets inside the plugin library.
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

$libraryFull = [System.IO.Path]::GetFullPath($pluginRoot).TrimEnd('\', '/')
$byPlugin = [ordered]@{}

foreach ($r in $scanRoots) {
    Get-ChildItem -LiteralPath $r -Recurse -Depth 3 -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } |
        ForEach-Object {
            $src = $_.Target
            if (-not $src) { return }
            $srcFull = [System.IO.Path]::GetFullPath($src).TrimEnd('\', '/')
            if (-not $srcFull.StartsWith($libraryFull, [StringComparison]::OrdinalIgnoreCase)) { return }

            $pluginName = $srcFull.Substring($libraryFull.Length).TrimStart('\').Split('\')[0]
            if (-not $byPlugin.Contains($pluginName)) { $byPlugin[$pluginName] = @() }
            $byPlugin[$pluginName] += [PSCustomObject]@{
                From = $src
                To   = $_.FullName
            }
        }
}

# --- emit --------------------------------------------------------------------
$written = 0; $merged = 0; $skipped = 0

foreach ($pluginName in ($byPlugin.Keys | Sort-Object)) {
    if ($Include -and ($Include -notcontains $pluginName)) { continue }

    $existing = Join-Path $manifestDir "$pluginName.json"

    # Candidate links from the live system, with dangling ones reported and dropped.
    $candidates = @()
    $skippedBroken = 0
    foreach ($l in $byPlugin[$pluginName]) {
        # A live junction can point at a path the vendor never shipped. Recording
        # it would make apply recreate the breakage, so it is reported instead.
        if (-not (Test-Path -LiteralPath $l.From)) {
            Write-Host ("      ! dangling junction, source absent: {0}" -f $l.From) -ForegroundColor Yellow
            $skippedBroken++
            continue
        }
        $rel = $l.From.Substring($libraryFull.Length).TrimStart('\')
        $rel = $rel.Substring($pluginName.Length).TrimStart('\')
        $candidates += [PSCustomObject]@{
            From = $rel
            To   = ConvertTo-TokenPath -Path $l.To
            Kind = 'Junction'
        }
    }

    # Merge into an existing manifest rather than replacing it: hand-written
    # Registry / Copy / Process sections must survive a regeneration, and links
    # already declared should not be duplicated.
    if (Test-Path -LiteralPath $existing) {
        if (-not $Force) {
            Write-Host ("  = {0,-45} {1} link(s)  (manifest exists, use -Force)" -f $pluginName, $candidates.Count) -ForegroundColor DarkGray
            $skipped++
            continue
        }

        $current = Get-Content -Raw -LiteralPath $existing | ConvertFrom-Json
        $have = @{}
        foreach ($l in @($current.Links)) {
            if ($null -eq $l) { continue }
            $have[("{0}|{1}" -f $l.From, $l.To).ToLowerInvariant()] = $true
        }

        $added = @()
        foreach ($c in $candidates) {
            if ($have.ContainsKey(("{0}|{1}" -f $c.From, $c.To).ToLowerInvariant())) { continue }
            $added += $c
        }

        if ($added.Count -eq 0) {
            Write-Host ("  = {0,-45} nothing new" -f $pluginName) -ForegroundColor DarkGray
            $skipped++
            continue
        }

        $current.Links = @($current.Links) + $added
        $json = $current | ConvertTo-Json -Depth 10
        if ($PSCmdlet.ShouldProcess($existing, "Add $($added.Count) link(s)")) {
            [System.IO.File]::WriteAllText($existing, $json, [System.Text.UTF8Encoding]::new($false))
            Write-Host ("  ~ {0,-45} +{1} link(s) merged" -f $pluginName, $added.Count) -ForegroundColor Yellow
            $merged++
        }
        continue
    }

    if ($candidates.Count -eq 0) {
        Write-Host ("  ! {0,-45} no usable links, skipping" -f $pluginName) -ForegroundColor DarkYellow
        $skipped++
        continue
    }

    $obj = [PSCustomObject]@{
        Name        = $pluginName
        Description = 'Generated from the junctions present on this system.'
        Links       = $candidates
    }
    $json = $obj | ConvertTo-Json -Depth 10

    if ($WhatIfOutput) {
        Write-Host "--- $pluginName ---"
        Write-Host $json
        continue
    }

    if ($PSCmdlet.ShouldProcess($existing, "Write manifest with $($candidates.Count) link(s)")) {
        [System.IO.File]::WriteAllText($existing, $json, [System.Text.UTF8Encoding]::new($false))
        Write-Host ("  + {0,-45} {1} link(s)" -f $pluginName, $candidates.Count) -ForegroundColor Green
        $written++
    }
}

Write-Host ''
Write-Host ("written: {0}   merged: {1}   left alone: {2}" -f $written, $merged, $skipped) -ForegroundColor Cyan