# $root is the parent of src/ (e.g. S:\Git\winos).
# Use Split-Path -Parent to get a normalized path -- without this, paths
# would have a literal ".." suffix and break state-probe string comparison.
#
# No Set-Location here. Callers from arbitrary CWDs (CI runners, parallel
# test harnesses, an interactive shell that started elsewhere) must not
# have their CWD silently rewritten. All paths in the project derive from
# $root (absolute) or $PSScriptRoot, so CWD never matters at any level.
$root = Split-Path -Parent $PSScriptRoot
$varsFile = Join-Path $root "src\vars.ps1"
if (Test-Path $varsFile) {
    . $varsFile
} else {
    Write-Warning "Vars file not found: $varsFile"
}
