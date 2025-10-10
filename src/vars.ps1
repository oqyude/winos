# LOCAL

# Modules
$appsDataManagerModule = "$PSScriptRoot\modules\appdata-manager.ps1"
$autostartManagerModule = "$PSScriptRoot\modules\autostart-manager.ps1"
$mountsManagerModule = "$PSScriptRoot\modules\mounts-manager.ps1"
$deployModule = "$PSScriptRoot\modules\deploy.ps1"

# Package Manager Installers
$winget = "$PSScriptRoot\winget.ps1"

# Data folder
$data = "$root\data"

# Setup Data Folder
$apps = "$data\isolate"
$appsAll = "$data\apps.csv"
$mountsAll = "$data\mounts.csv"
# $appsUser = "$apps\$env:COMPUTERNAME"

# GLOBAL
$storage = "$env:USERPROFILE\Storage"
$autostartDir = "$data\autorun"
# $autostartDir = "C:\Winos\Scenaries\Autorun"

# $userName = "oqyude"
# $diskLabel = "S:"
# $games = "$diskLabel\Games"
# $storageGames = "N:\Games\.storage"
