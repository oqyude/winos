# vars.ps1 -- paths for the plugin-deployment module.
#
# Sourced by plugin-manager.ps1 AFTER src/init.ps1 has set $root. It is
# deliberately NOT merged into src/vars.ps1: that file belongs to the winos
# symlink-manager and declares the module registry for the whole project. Adding
# plugin-specific paths there would couple two modules that are meant to stay
# independent (see W1 in .agent/tasks/manifest.json).
#
# $root is already bound by init.ps1 at this point. Everything below derives from
# it, so this file works from any working directory.

# --- Plugin library -----------------------------------------------------------
# Where the plugin library lives. DECLARED per host: src/vars.ps1 resolves it
# from <data dir>\hosts\<COMPUTERNAME>.json (see src/host-paths.ps1) and falls
# back to the built-in default when the host has not been declared.
#
# Treated as read-only: the tool never writes into it.
#
# The fallback below exists for the one case where src/vars.ps1 has not run --
# this file dot-sourced on its own. Then the resolver is loaded here and asked
# for the same value, so the answer comes from one place either way.
if (-not $pluginRoot) {
    . (Join-Path $PSScriptRoot "..\..\host-paths.ps1")
    $hostPaths = Resolve-WinosHostPaths -RepoRoot $root
    $pluginRoot = $hostPaths.pluginRoot
}

# --- State files --------------------------------------------------------------
# state/plugin-deployment.json is the committed allowlist.
# plugin-deployment-snapshot.json is a machine-local baseline regenerated on
# every run and is gitignored.
$stateDir     = Join-Path $root "state"
$stateFile    = Join-Path $stateDir "plugin-deployment.json"
$snapshotFile = Join-Path $stateDir "plugin-deployment-snapshot.json"

# --- Manifests ----------------------------------------------------------------
# One JSON file per plugin folder, named after the folder, declaring what the
# vendor installer does beyond symlinking: registry imports, tree copies, and
# scripts to run before revert. %VAR% tokens expand to environment variables.
$manifestDir = Join-Path $root "manifests"

# --- Versions -----------------------------------------------------------------
$stateVersion = 1
$toolVersion  = "0.0.1"