#Requires -Version 5.1
<#
.SYNOPSIS
    Snapshot, plan, or apply symlink-manager state.
.DESCRIPTION
    Three modes:
      -Plan     : probe state, show delta, save snapshot to data/state/.
      -Apply    : probe state, apply safe actions (create, noop skip), save snapshot.
      -Snapshot : probe state, save snapshot only (no plan output).

    Drift (replace) and conflicts are SKIPPED by default. They require
    --Force, which is not yet implemented.

    Reads vars from src/vars.ps1 (data.json, $statePath, $persist, etc.).
#>
[CmdletBinding()]
param(
    [switch]$Plan,
    [switch]$Apply,
    [switch]$Snapshot,
    [switch]$Force,
    [string]$JsonConfig,
    [string]$StatePath
)

# Bootstrap: load vars from src/init.ps1 if not already loaded
if (-not $jsonConfig) {
    . (Join-Path $PSScriptRoot "..\src\init.ps1")
}

# Source state functions
. (Join-Path $PSScriptRoot "..\src\modules\common\State.ps1")

# Default to Plan if no switch specified
if (-not $Plan -and -not $Apply -and -not $Snapshot) {
    $Plan = $true
}

if (-not $JsonConfig)  { $JsonConfig  = $jsonConfig }
if (-not $StatePath)   { $StatePath   = $statePath }

Write-Host "=== Symlink Manager ===" -ForegroundColor Cyan
Write-Host ("Config: {0}" -f $JsonConfig)
Write-Host ("State:  {0}" -f $StatePath)
Write-Host ""

# Load config
$config = Get-Content -Raw -Path $JsonConfig | ConvertFrom-Json

# Strip phantom nulls from PowerShell ConvertFrom-Json bug
$entries = @()
foreach ($e in $config.symlinks) {
    if ($null -ne $e -and -not $e.archived) { $entries += $e }
}

# Probe state for each entry.
# enabled=true  → desired = 'symlink' (manage/create)
# enabled=false → desired = 'missing' (break connection / drop)
$delta = @()
foreach ($entry in $entries) {
    $entryState = Get-SymlinkEntryState -Entry $entry
    $desired = if ($entry.enabled) { 'symlink' } else { 'missing' }
    $categorized = Compare-State -EntryState $entryState -Desired $desired
    $delta += $categorized
}

# Output
if ($Plan -or $Snapshot) {
    Write-Host "=== Plan ===" -ForegroundColor Cyan
    Format-Plan -Delta $delta | Out-Null
}

# Execute
if ($Apply) {
    Write-Host ""
    Write-Host "=== Apply ===" -ForegroundColor Cyan
    $results = @()
    foreach ($entry in $delta) {
        if ($entry.method -ne 'symlink') { continue }
        $entryResults = Invoke-SafeAction -EntryState $entry
        $results += $entryResults
    }

    $created = ($results | Where-Object { $_.status -eq 'created' }).Count
    $removed = ($results | Where-Object { $_.status -eq 'removed' }).Count
    $skipped = ($results | Where-Object { $_.status -eq 'skipped' }).Count
    $failed  = ($results | Where-Object { $_.status -eq 'failed' }).Count

    Write-Host ""
    Write-Host "=== Result ===" -ForegroundColor Cyan
    Write-Host ("Created: {0}" -f $created) -ForegroundColor Green
    Write-Host ("Removed: {0}" -f $removed) -ForegroundColor DarkCyan
    Write-Host ("Skipped: {0}" -f $skipped) -ForegroundColor DarkGray
    Write-Host ("Failed:  {0}" -f $failed)  -ForegroundColor Red
}

# Save snapshot (always, as side effect)
Save-Snapshot -Path $StatePath -Delta $delta | Out-Null
Write-Host ""
Write-Host ("Saved snapshot: {0}" -f $StatePath) -ForegroundColor DarkGray
