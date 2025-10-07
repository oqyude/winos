# LOCAL

# Package Managers
$winget = "$PSScriptRoot\winget.ps1"

# Local Root
$data = "$root\data"

# Packages
$packages = "$data\packages"
$packagesInstaller = "$packages\install.bat"
$packagesAllLists = "$packages\[all]"
$packagesUserLists = "$packages\$env:COMPUTERNAME"
$packagesUserListsOther = "$packagesUserLists\other.bat"

# Apps
$apps = "$data\apps"
$appsAll = "$apps\all.csv"
$appsLegacy = "$apps\legacy"
$appsUser = "$apps\$env:COMPUTERNAME"

# Mounts
$mounts = "$data\mounts"

# GLOBAL
$diskLabel = "S:"
$userName = "oqyude"

# Main Folder
$games = "$diskLabel\Games"
$storage = "$env:USERPROFILE\Storage"
$storageGames = "N:\Games\.storage"
