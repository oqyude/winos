# Init
Set-Location -Path $PSScriptRoot

$root = Join-Path $PSScriptRoot ".."

$varsFile = Join-Path $root "src\vars.ps1"
if (Test-Path $varsFile) {
    . $varsFile 
} else {
    Write-Warning "Vars file not found: $varsFile"
}

# Define variables for administrator check and restart
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
$restartArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""