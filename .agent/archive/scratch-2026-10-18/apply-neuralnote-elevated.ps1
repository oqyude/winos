# Helper: run winos plugin-manager apply in an elevated pwsh.
# Invoked via `Start-Process -FilePath pwsh -ArgumentList @("-NoProfile", "-File", $PSCommandPath) -Verb RunAs -Wait`
# from the parent (non-elevated) pwsh. The user has to click Yes at the UAC prompt.
# Result goes to .temp/apply-result.json so the parent can read it.

$ErrorActionPreference = 'Continue'

$timestamp = Get-Date -Format 'o'
$cwdBefore = (Get-Location).Path
$cwdAfter = $null
$applyOutput = ''
$applyExit = $null
$mainPs1Exists = Test-Path -LiteralPath 'S:\Git\winos\main.ps1'
$varsExists = Test-Path -LiteralPath 'S:\Git\winos\src\vars.ps1'
$stateFileExists = Test-Path -LiteralPath 'S:\Git\winos\state\plugin-deployment.json'

Set-Location 'S:\Git\winos'
$cwdAfter = (Get-Location).Path

try {
    $applyOutput = & ./main.ps1 plugin-manager apply *>&1 | Out-String
    $applyExit = $LASTEXITCODE
} catch {
    $applyOutput = "EXCEPTION: $($_.Exception.Message)`n$($_.ScriptStackTrace)"
    $applyExit = -1
}

$report = [PSCustomObject]@{
    Timestamp       = $timestamp
    MainPs1Exists   = $mainPs1Exists
    VarsExists      = $varsExists
    StateFileExists = $stateFileExists
    CwdBefore       = $cwdBefore
    CwdAfter        = $cwdAfter
    ApplyExit       = $applyExit
    ApplyOutput     = $applyOutput
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath 'S:\Git\winos\.temp\apply-result.json' -Encoding utf8

