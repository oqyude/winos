param(
    [ValidateSet("deploy", "clean")]
    [string]$action,
    [string]$name,
    [string]$from,
    [string]$to,
    [string]$appsDir
)

$safeName = $name -replace ' ', '_'
$scriptPath = Join-Path $appsDir "$safeName.ps1"

if (Test-Path $scriptPath) {
    Write-Host "    Running isolate script: $scriptPath" -ForegroundColor Yellow
    & $scriptPath -Action $action -AppName $name -From $from -To $to
} else {
    Write-Warning "Isolate script not found: $scriptPath"
}
