# Modules
$appsDataManagerModule = "$PSScriptRoot\modules\appdata-manager.ps1"
$autostartManagerModule = "$PSScriptRoot\modules\autostart-manager.ps1"
$mountsManagerModule = "$PSScriptRoot\modules\mounts-manager.ps1"
$deployModule = "$PSScriptRoot\modules\deploy.ps1"

# Define available modules with their respective actions
$modules = @{
    "appsDataManagerModule" = @("reconnect", "connect", "disconnect")
    "autostartManagerModule" = @("update", "remove")
    "deployModule" = @("apply", "clean")
    "mountsManagerModule" = @("reconnect", "connect", "disconnect")
}

# Package Manager Installers
$winget = "$PSScriptRoot\winget.ps1"

# Data folder
$data = "$root\data"

# Setup Data Folder
$apps = "$data\isolate"
$appsAll = "$data\apps.csv"
$mountsAll = "$data\mounts.csv"

# GLOBAL
$storage = "$env:USERPROFILE\Storage"
$autostartDir = "$data\autorun"