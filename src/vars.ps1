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
$herdrServeModule     = "$PSScriptRoot\modules\herdr-serve.ps1"

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
        Description = "Deploy audio plugins from the declared plugin library"
    }
    "Essentials" = @{
        Alias       = "essentials"
        Path        = $essentialsModule
        Actions     = @("install", "uninstall")
        Destructive = @("uninstall")
        Description = "Cursor themes"
    }
    "opencode-serve" = @{
        Alias       = "opencode-serve"
        Path        = $opencodeServeModule
        Actions     = @("setup", "remove", "status", "start", "stop")
        Destructive = @("remove")
        Description = "Scheduled-task lifecycle for `opencode serve` on logon"
    }
    "herdr-serve" = @{
        Alias       = "herdr-serve"
        Path        = $herdrServeModule
        Actions     = @("setup", "remove", "status", "start", "stop")
        Destructive = @("remove")
        Description = "Scheduled-task lifecycle for `herdr server` on logon"
    }
}

# GLOBAL
$tempFolder = "$env:TEMP\winos"
$storage = "$env:USERPROFILE\Storage"
$persist = "$storage\persist"

# --- Per-host paths -----------------------------------------------------------
# Two questions this file used to answer silently:
#
#   1. WHERE does the machine state live -- the synced store
#      (%USERPROFILE%\Storage\winos\data) or the repository's own data\ dir?
#      The precedence is UNCHANGED (store first, repository second); what
#      changed is that the choice is returned and printed instead of being a
#      silent `if`. Task T24 in .agent/tasks/manifest.md.
#   2. WHICH absolute paths does THIS host use -- S:\Git, C:\Tools, S:\Plugins?
#      They used to be hardcoded at their use sites and rotted there. They are
#      declared per host now, in <data dir>\hosts\<COMPUTERNAME>.json.
#
# src/host-paths.ps1 owns both rules and the built-in defaults. A host without
# a declaration still works, and says so out loud.
. (Join-Path $PSScriptRoot "host-paths.ps1")
$hostPathState = @{}
$hostPaths = Resolve-WinosHostPaths -RepoRoot $root -State $hostPathState

$data             = $hostPaths.dataDir
$dataSource       = $hostPaths.dataSource
$projectsDir      = $hostPaths.projectsDir
$toolsDir         = $hostPaths.toolsDir
$pluginRoot       = $hostPaths.pluginRoot
$taskWorkingDirectory = $hostPaths.taskWorkingDirectory
$hostDeclarationFile  = $hostPaths.declarationFile
$hostDeclarationFound = $hostPaths.declarationFound

$apps = "$data\isolate"
$jsonConfig = "$data\data.json"
$statePath = "$data\state\symlink-snapshot.json"
