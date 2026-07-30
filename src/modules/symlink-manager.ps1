[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("plan", "apply", "snapshot")]
    [string]$action = "plan",
    [switch]$Force
)

# Self-bootstrap: if vars.ps1 hasn't been sourced (run directly), source it.
if (-not $jsonConfig) {
    . (Join-Path $PSScriptRoot "..\init.ps1")
}

# Source State.ps1 for probe/compare/format functions
. (Join-Path $PSScriptRoot "common\State.ps1")

$symlinkMethod = Join-Path $PSScriptRoot "methods\symlink.ps1"
$isolateMethod = Join-Path $PSScriptRoot "methods\isolate.ps1"

# Load config; strip phantom nulls from PowerShell bug
$rawConfig = Get-Content -Raw -Path $jsonConfig | ConvertFrom-Json
$entries = @()
foreach ($e in $rawConfig.symlinks) {
    if ($null -ne $e -and -not $e.archived) {
        $entries += $e
    }
}

# Probe state for each entry.
# enabled=true  -> desired = 'symlink' (manage/create)
# enabled=false -> desired = 'missing' (break connection / drop)
$delta = @()
foreach ($entry in $entries) {
    $entryState = Get-SymlinkEntryState -Entry $entry
    $desired = if ($entry.enabled) { 'symlink' } else { 'missing' }
    $categorized = Compare-State -EntryState $entryState -Desired $desired
    $delta += $categorized
}

switch ($action) {
    "plan" {
        Write-Host "=== Plan ===" -ForegroundColor Cyan
        Format-Plan -Delta $delta | Out-Null
    }
    "apply" {
        Write-Host "=== Apply ===" -ForegroundColor Cyan
        $results = @()
        foreach ($entry in $delta) {
            if ($entry.method -ne 'symlink') { continue }
            $entryResults = Invoke-SafeAction -EntryState $entry -Force:$Force
            foreach ($r in $entryResults) {
$icon = switch ($r.action) {
    'noop'     { '~' }
    'create'   { '+' }
    'replace'  { '*' }
    'drop'     { '-' }
    'conflict' { '!' }
}
                $color = switch ($r.action) {
                    'noop'     { 'DarkGray' }
                    'create'   { 'Green' }
                    'replace'  { 'Yellow' }
                    'drop'     { 'DarkCyan' }
                    'conflict' { 'Red' }
                }
                $line = "  {0} {1,-10} {2}" -f $icon, $r.status, $r.to
                if ($r.note) { $line += "  ($($r.note))" }
                Write-Host $line -ForegroundColor $color
            }
            $results += $entryResults
        }

        $created  = ($results | Where-Object { $_.status -eq 'created' }).Count
        $replaced = ($results | Where-Object { $_.status -eq 'replaced' }).Count
        $resolved = ($results | Where-Object { $_.status -eq 'resolved' }).Count
        $skipped  = ($results | Where-Object { $_.status -eq 'skipped' }).Count
        $failed   = ($results | Where-Object { $_.status -eq 'failed' }).Count

        Write-Host ""
        Write-Host ("Created: {0}  Replaced: {1}  Resolved: {2}  Skipped: {3}  Failed: {4}" -f $created, $replaced, $resolved, $skipped, $failed) -ForegroundColor Cyan
    }
    "snapshot" {
        Write-Host "=== Snapshot ===" -ForegroundColor Cyan
        $delta | Select-Object name, method, @{n='sub_count';e={$_.subentries.Count}} | Format-Table
    }
}

# Save snapshot (side effect of all actions)
Save-Snapshot -Path $statePath -Delta $delta | Out-Null
Write-Host ""
Write-Host ("Saved: {0}" -f $statePath) -ForegroundColor DarkGray
