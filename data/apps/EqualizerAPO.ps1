param(
    [string]$Action = "reconnect",
    [string]$AppName = "EqualizerAPO",
    [string]$From,
    [string]$To
)

Write-Host "Isolate script for $AppName : $Action | From: $From | To: $To"  # Дебаг входа

$FabFilterTarget = "$env:ProgramFiles\VSTPlugins\FabFilter\FabFilter Pro-Q 3.dll"
$FabFilterLink = Join-Path $To "VSTPlugins\FabFilter Pro-Q 3.dll"
$configDir = Join-Path $To "config"
$regPath = "HKLM:\SOFTWARE\EqualizerAPO"
$regKey = "ConfigPath"

if (-not $From) {
    Write-Warning "Missing From path: $From – skipping, idiot"
    return
}
if (-not $To -or -not [System.IO.Path]::IsPathRooted($To)) {
    Write-Warning "Invalid To path: $To – fixing to default ProgramFiles"
    $To = Join-Path $env:ProgramFiles $AppName  # Fallback, если apps-manager всё равно сломан
}

switch ($Action.ToLower()) {
    "disconnect" {
        Write-Host "  Disconnecting $AppName – cleaning up"
        
        # Чисти config (как в BAT)
        $configDir = Join-Path $To "config"
        if (Test-Path $configDir) {
            Write-Host "    Wiping config: $configDir"
            Remove-Item $configDir\* -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # Удаляй только линк в APO, не системный DLL
        $FabFilterLink = Join-Path $To "VSTPlugins\FabFilter Pro-Q 3.dll"
        if (Test-Path $FabFilterLink) {
            Write-Host "    Removing link: $FabFilterLink"
            Remove-Item $FabFilterLink -Force -ErrorAction SilentlyContinue
        }
        
        # Чисти реестр (BAT этого не делает, но логично для disconnect)
        $regPath = "HKLM:\SOFTWARE\EqualizerAPO"
        $regKey = "ConfigPath"
        if (Test-Path $regPath) {
            Remove-ItemProperty -Path $regPath -Name $regKey -ErrorAction SilentlyContinue
            Write-Host "    Registry cleaned"
        }
    }
    
    "connect" {
        Write-Host "  Connecting $AppName – linking system VST to APO"
        
        # Реестр: ConfigPath на storage (как в BAT)
        $regPath = "HKLM:\SOFTWARE\EqualizerAPO"
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        Set-ItemProperty -Path $regPath -Name "ConfigPath" -Value $From -Type String -Force
        Write-Host "    Registry set: ConfigPath -> $From"
        
        # Линк: в APO на системный VST (как в BAT)
        $globalDLL = $FabFilterTarget
        $FabFilterLink = Join-Path $To "VSTPlugins\FabFilter Pro-Q 3.dll"
        $vstDir = Split-Path $FabFilterLink -Parent
        if (-not (Test-Path $vstDir)) {
            New-Item -ItemType Directory -Path $vstDir -Force | Out-Null
            Write-Host "    Created VST dir in APO: $vstDir"
        }
        if (Test-Path $FabFilterLink) {
            Remove-Item $FabFilterLink -Force
        }
        if (Test-Path $globalDLL) {
            New-Item -ItemType SymbolicLink -Path $FabFilterLink -Value $globalDLL -Force | Out-Null
            Write-Host "    Link created: $FabFilterLink -> $globalDLL (system VST)"
        } else {
            Write-Warning "  System DLL missing: $globalDLL – no link (install FabFilter?)"
        }
    }
    
    "reconnect" {
        Write-Host "  Reconnecting: disconnect then connect"
        & $MyInvocation.MyCommand.Path -Action "disconnect" -AppName $AppName -From $From -To $To
        & $MyInvocation.MyCommand.Path -Action "connect" -AppName $AppName -From $From -To $To
    }
    
    default {
        Write-Warning "Unknown: $Action – nothing happens"
    }
}

Write-Host "Isolate script for $AppName finished"  # Дебаг выхода