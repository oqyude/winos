[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$action = "reconnect",
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

Write-Host "Isolate: $AppName ($action) | From: $From | To: $To" -ForegroundColor Yellow

function Disconnect-App {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Write-Host "  Disconnecting..." -ForegroundColor Yellow

    if (Test-Path $configDir) {
        if ($PSCmdlet.ShouldProcess($configDir, "Remove config directory")) {
            Remove-Item $configDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "    Config wiped" -ForegroundColor Red
        }
    }

    if (Test-Path $FabFilterLink) {
        if ($PSCmdlet.ShouldProcess($FabFilterLink, "Remove VST link")) {
            Remove-Item $FabFilterLink -Force -ErrorAction SilentlyContinue
            Write-Host "    VST link removed" -ForegroundColor Red
        }
    }

    if (Test-Path $regPath) {
        if ($PSCmdlet.ShouldProcess("$regPath\$regKey", "Remove registry key")) {
            Remove-ItemProperty -Path $regPath -Name $regKey -ErrorAction SilentlyContinue
            Write-Host "    Registry cleaned" -ForegroundColor Red
        }
    }
}

function Connect-App {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Write-Host "  Connecting..." -ForegroundColor Yellow

    if (-not (Test-Path $regPath)) {
        if ($PSCmdlet.ShouldProcess($regPath, "Create registry key")) {
            New-Item -Path $regPath -Force | Out-Null
        }
    }
    if ($PSCmdlet.ShouldProcess("$regPath\$regKey", "Set ConfigPath to $From")) {
        Set-ItemProperty -Path $regPath -Name $regKey -Value $From -Type String -Force
        Write-Host "    ConfigPath -> $From" -ForegroundColor Blue
    }

    if (-not (Test-Path $vstDir)) {
        if ($PSCmdlet.ShouldProcess($vstDir, "Create VST dir")) {
            New-Item -ItemType Directory -Path $vstDir -Force | Out-Null
        }
    }
    if (Test-Path $FabFilterLink) {
        if ($PSCmdlet.ShouldProcess($FabFilterLink, "Remove existing VST link")) {
            Remove-Item $FabFilterLink -Force
        }
    }
    if (Test-Path $globalDLL) {
        if ($PSCmdlet.ShouldProcess($FabFilterLink, "Link to $globalDLL")) {
            New-Item -SymbolicLink -Path $FabFilterLink -Value $globalDLL -Force | Out-Null
            Write-Host "    VST linked: $FabFilterLink -> $globalDLL" -ForegroundColor Blue
        }
    } else {
        Write-Warning "  No system VST: $globalDLL (install it?)"
    }
}

switch ($action) {
    "disconnect" { Disconnect-App }
    "connect" { Connect-App }
    "reconnect" {
        Disconnect-App
        Connect-App
    }
    default { Write-Warning "Unknown action: $action" }
}

Write-Host "Done with $AppName" -ForegroundColor Green
