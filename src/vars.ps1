# Modules
#
# Each entry carries:
#   Alias       -- short lower-case token the CLI accepts. An entry with NO Alias
#                  is menu-only; Service Manager is reached through the
#                  two-level `service <name> <action>` grammar instead, so giving
#                  it a flat alias would add a second, undocumented way in.
#   Actions     -- verbs the module accepts.
#   Destructive -- verbs the interactive menu must gate behind an explicit
#                  confirmation. Declared here rather than hardcoded in main.ps1
#                  for the same reason Actions live here: one list, one place.
#                  A verb listed here is NOT run on a single keypress, and the
#                  menu offers a -WhatIf preview instead of a bare yes/no.
#
# Display names describe the JOB, not the mechanism. The first two entries both
# create symlinks, so naming them after symlinks would have left two entries in
# the menu a user could not tell apart.
$symlinkManagerModule = "$PSScriptRoot\modules\symlink-manager.ps1"
$essentialsModule     = "$PSScriptRoot\modules\essentials.ps1"
$opencodeServeModule  = "$PSScriptRoot\modules\opencode-serve.ps1"
$pluginManagerModule  = "$PSScriptRoot\modules\plugins\plugin-manager.ps1"

$modules = @{
    "Config Persistence" = @{
        Alias       = "symlink-manager"
        Path        = $symlinkManagerModule
        Actions     = @("plan", "apply", "snapshot")
        Destructive = @()
        Description = "Symlink app config into place (plan/apply)"
    }
    "Plugin Deployment" = @{
        Alias       = "plugin-manager"
        Path        = $pluginManagerModule
        Actions     = @("plan", "apply", "revert", "snapshot", "status", "adopt", "verify")
        Destructive = @("revert", "adopt")
        Description = "Deploy audio plugins from S:\Plugins"
    }
    "Essentials" = @{
        Alias       = "essentials"
        Path        = $essentialsModule
        Actions     = @("install", "uninstall")
        Destructive = @("uninstall")
        Description = "Cursor themes"
    }
    "Service Manager" = @{
        Path        = $opencodeServeModule
        Actions     = @("setup", "remove", "status", "start", "stop")
        Destructive = @("remove")
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
