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
# Where the plugin library lives. Treated as read-only: the tool never writes
# into it. Falls back to %USERPROFILE%\Plugins if the S: drive is absent, so the
# module still resolves on a machine without the library.
if (Test-Path "S:\Plugins") {
    $pluginRoot = "S:\Plugins"
} elseif (Test-Path (Join-Path $env:USERPROFILE "Plugins")) {
    $pluginRoot = Join-Path $env:USERPROFILE "Plugins"
} else {
    # Neither exists -- keep the convention and let the probe report it.
    $pluginRoot = "S:\Plugins"
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