# Modules
$appsDataManagerModule = "$PSScriptRoot\modules\appdata-manager.ps1"
$autostartManagerModule = "$PSScriptRoot\modules\autostart-manager.ps1"
$mountsManagerModule = "$PSScriptRoot\modules\mounts-manager.ps1"
$deployModule = "$PSScriptRoot\modules\deploy.ps1"
$wingetInstallerModule = "$PSScriptRoot\modules\winget-installer.ps1"
$packageManagerModule = "$PSScriptRoot\modules\package-manager.ps1"
$windowsCursorModule = "$PSScriptRoot\modules\windows-cursor.ps1"

# Define available modules with their respective actions - need to ref
$modules = @{
    "AppData Manager" = @{
        Path    = $appsDataManagerModule
        Actions = @("reconnect", "connect", "disconnect")
    }
    "Autostart Manager" = @{
        Path    = $autostartManagerModule
        Actions = @("update", "remove")
    }
    "Deploy Manager" = @{
        Path    = $deployModule
        Actions = @("apply", "clean")
    }
    "Mounts Manager" = @{
        Path    = $mountsManagerModule
        Actions = @("reconnect", "connect", "disconnect")
    }
    "Package Manager" = @{
        Path    = $packageManagerModule
        Actions = @("install", "uninstall")
    }
    "Winget Installer" = @{
        Path    = $wingetInstallerModule
        Actions = @("check", "install")
    }
    "Windows Cursor" = @{
        Path    = $windowsCursorModule
        Actions = @("install", "uninstall")
    }
}


# Functions
function checkWingetStatus {
    try {
        $null = winget --version 2>$null
        Write-Host "Winget is installed." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Winget is not installed." -ForegroundColor Yellow
        return $false
    }
}

# Data folder
$data = "$root\data"

# Setup Data Folder
$apps = "$data\isolate"
$appsAll = "$data\apps.csv"
$mountsAll = "$data\mounts.csv"

# GLOBAL
$tempFolder = "$env:TEMP\winos";
$storage = "$env:USERPROFILE\Storage"
$autostartDir = "$data\autorun"