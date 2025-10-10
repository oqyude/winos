# LOCAL

# Modules
$appsDataManager = "$PSScriptRoot\modules\apps-data-manager.ps1"
$autostartManager = "$PSScriptRoot\modules\autostart-manager.ps1"

# Package Manager Installers
$winget = "$PSScriptRoot\winget.ps1"

# Data folder
$data = "$root\data"

# Setup Data Folder
$apps = "$data\isolate"
$appsAll = "$data\apps.csv"
# $appsUser = "$apps\$env:COMPUTERNAME"
# $appsLegacy = "$apps\legacy"

# Mounts
# $mounts = "$data\mounts"

# GLOBAL
$storage = "$env:USERPROFILE\Storage"
$autostartDir = "C:\Winos\Scenaries\Autorun"

# $userName = "oqyude"
# $diskLabel = "S:"
# $games = "$diskLabel\Games"
# $storageGames = "N:\Games\.storage"
