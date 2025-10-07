param(
    [string]$Action = "reconnect",
    [string]$AppName = "EqualizerAPO",
    [string]$From,
    [string]$To
)

# Валидация входа (fallback для кривых путей)
if (-not $From) {
    Write-Error "No From path – aborting"
    Exit 1
}
if (-not [System.IO.Path]::IsPathRooted($To)) {
    $To = Join-Path $env:ProgramFiles $AppName
    Write-Host "Fixed To: $To"
}

# Константы (уютно в одном месте)
$configDir = Join-Path $To "config"
$regPath = "HKLM:\SOFTWARE\EqualizerAPO"
$regKey = "ConfigPath"
$vstDir = Join-Path $To "VSTPlugins"
$FabFilterLink = Join-Path $vstDir "FabFilter Pro-Q 3.dll"
$globalDLL = "$env:ProgramFiles\VSTPlugins\FabFilter\FabFilter Pro-Q 3.dll"

Write-Host "Isolate: $AppName ($Action) | From: $From | To: $To"

# Функции для чистоты (disconnect/connect как модули)
function Disconnect-App {
    Write-Host "  Disconnecting..."
    
    # Чисти config (как в BAT)
    if (Test-Path $configDir) {
        Remove-Item $configDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "    Config wiped"
    }
    
    # Удаляй линк (не оригинал)
    if (Test-Path $FabFilterLink) {
        Remove-Item $FabFilterLink -Force -ErrorAction SilentlyContinue
        Write-Host "    VST link removed"
    }
    
    # Чисти реестр
    if (Test-Path $regPath) {
        Remove-ItemProperty -Path $regPath -Name $regKey -ErrorAction SilentlyContinue
        Write-Host "    Registry cleaned"
    }
}

function Connect-App {
    Write-Host "  Connecting..."
    
    # Реестр на storage
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    Set-ItemProperty -Path $regPath -Name $regKey -Value $From -Type String -Force
    Write-Host "    ConfigPath -> $From"
    
    # Линк VST: в APO на системный (как в BAT)
    if (-not (Test-Path $vstDir)) {
        New-Item -ItemType Directory -Path $vstDir -Force | Out-Null
    }
    if (Test-Path $FabFilterLink) {
        Remove-Item $FabFilterLink -Force
    }
    if (Test-Path $globalDLL) {
        New-Item -ItemType SymbolicLink -Path $FabFilterLink -Value $globalDLL -Force | Out-Null
        Write-Host "    VST linked: $FabFilterLink -> $globalDLL"
    } else {
        Write-Warning "  No system VST: $globalDLL (install it?)"
    }
}

# Основная логика
switch ($Action.ToLower()) {
    "disconnect" { Disconnect-App }
    "connect" { Connect-App }
    "reconnect" { 
        Disconnect-App 
        Connect-App 
    }
    default { Write-Warning "Unknown action: $Action" }
}

Write-Host "Done with $AppName"