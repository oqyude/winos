# Modules
$symlinkManagerModule = "$PSScriptRoot\modules\symlink-manager.ps1"
$essentialsModule = "$PSScriptRoot\modules\essentials.ps1"

$modules = @{
    "Symlink Manager" = @{
        Path        = $symlinkManagerModule
        Actions     = @("deploy", "clean", "redeploy")
        Description = "Symlinks & isolate"
    }
    "Essentials" = @{
        Path        = $essentialsModule
        Actions     = @("install", "uninstall")
        Description = "Cursor themes"
    }
}

# GLOBAL
$tempFolder = "$env:TEMP\winos"
$storage = "$env:USERPROFILE\Storage"
$data = if (Test-Path "$storage\winos\data") { "$storage\winos\data" } else { "$root\data" }
$apps = "$data\isolate"
$jsonConfig = "$data\data.json"