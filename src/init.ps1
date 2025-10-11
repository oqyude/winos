# Init
Set-Location -Path $PSScriptRoot

$root = Join-Path $PSScriptRoot ".."

$varsFile = Join-Path $root "src\vars.ps1"
if (Test-Path $varsFile) {
    . $varsFile 
} else {
    Write-Warning "Vars file not found: $varsFile"
}