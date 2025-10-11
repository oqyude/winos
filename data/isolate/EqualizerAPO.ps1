param(
    [string]$Action = "reconnect",
    [string]$AppName = "EqualizerAPO",
    [string]$From,
    [string]$To
)

Write-Host "==============================" -ForegroundColor Gray

if (-not $From) {
    Write-Error "No From path - aborting"
    Exit 1
}
if (-not [System.IO.Path]::IsPathRooted($To)) {
    $To = Join-Path $env:ProgramFiles $AppName
    Write-Host "Fixed To: $To" -ForegroundColor Yellow
}

$configDir = Join-Path $To "config"
$regPath = "HKLM:\SOFTWARE\EqualizerAPO"
$regKey = "ConfigPath"
$vstDir = Join-Path $To "VSTPlugins"
$FabFilterLink = Join-Path $vstDir "FabFilter Pro-Q 3.dll"
$globalDLL = "$env:ProgramFiles\VSTPlugins\FabFilter\FabFilter Pro-Q 3.dll"

Write-Host "Isolate: $AppName ($Action) | From: $From | To: $To" -ForegroundColor Yellow

function Disconnect-App {
    Write-Host "  Disconnecting..." -ForegroundColor Yellow
    
    if (Test-Path $configDir) {
        Remove-Item $configDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "    Config wiped" -ForegroundColor Red
    }
    
    if (Test-Path $FabFilterLink) {
        Remove-Item $FabFilterLink -Force -ErrorAction SilentlyContinue
        Write-Host "    VST link removed" -ForegroundColor Red
    }
    
    if (Test-Path $regPath) {
        Remove-ItemProperty -Path $regPath -Name $regKey -ErrorAction SilentlyContinue
        Write-Host "    Registry cleaned" -ForegroundColor Red
    }
}

function Connect-App {
    Write-Host "  Connecting..." -ForegroundColor Yellow
    
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    Set-ItemProperty -Path $regPath -Name $regKey -Value $From -Type String -Force
    Write-Host "    ConfigPath -> $From" -ForegroundColor Blue
    
    if (-not (Test-Path $vstDir)) {
        New-Item -ItemType Directory -Path $vstDir -Force | Out-Null
    }
    if (Test-Path $FabFilterLink) {
        Remove-Item $FabFilterLink -Force
    }
    if (Test-Path $globalDLL) {
        New-Item -ItemType SymbolicLink -Path $FabFilterLink -Value $globalDLL -Force | Out-Null
        Write-Host "    VST linked: $FabFilterLink -> $globalDLL" -ForegroundColor Blue
    } else {
        Write-Warning "  No system VST: $globalDLL (install it?)"
    }
}

switch ($Action.ToLower()) {
    "disconnect" { Disconnect-App }
    "connect" { Connect-App }
    "reconnect" { 
        Disconnect-App 
        Connect-App 
    }
    default { Write-Warning "Unknown action: $Action" }
}

Write-Host "Done with $AppName" -ForegroundColor Green