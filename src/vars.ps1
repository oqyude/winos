# Modules
$symlinkManagerModule = "$PSScriptRoot\modules\symlink-manager.ps1"
$essentialsModule = "$PSScriptRoot\modules\essentials.ps1"
$opencodeServeModule = "$PSScriptRoot\modules\opencode-serve.ps1"

$modules = @{
    "Symlink Manager" = @{
        Path        = $symlinkManagerModule
        Actions     = @("plan", "apply", "snapshot")
        Description = "Symlinks & isolate"
    }
    "Essentials" = @{
        Path        = $essentialsModule
        Actions     = @("install", "uninstall")
        Description = "Cursor themes"
    }
    "OpenCode Serve" = @{
        Path        = $opencodeServeModule
        Actions     = @("setup", "remove", "status", "start", "stop")
        Description = "opencode serve service manager"
    }
}

# GLOBAL
$tempFolder = "$env:TEMP\winos"
$storage = "$env:USERPROFILE\Storage"
$persist = "$storage\persist"
$data = if (Test-Path "$storage\winos\data") { "$storage\winos\data" } else { "$root\data" }
$apps = "$data\isolate"
$jsonConfig = "$data\data.json"
$statePath = "$data\state\symlink-snapshot.json"
