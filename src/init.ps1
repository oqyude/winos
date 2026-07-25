Set-Location -Path $PSScriptRoot

# $root is the parent of src/ (e.g. S:\Git\winos).
# Use Split-Path -Parent to get a normalized path — without this, paths
# would have a literal ".." suffix and break state-probe string comparison.
$root = Split-Path -Parent $PSScriptRoot
$varsFile = Join-Path $root "src\vars.ps1"
if (Test-Path $varsFile) {
    . $varsFile
} else {
    Write-Warning "Vars file not found: $varsFile"
}