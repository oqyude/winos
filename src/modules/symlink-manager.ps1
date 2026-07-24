param(
    [ValidateSet("deploy", "clean", "redeploy")]
    [string]$action = "deploy"
)

$symlinkMethod = Join-Path $PSScriptRoot "methods\symlink.ps1"
$isolateMethod = Join-Path $PSScriptRoot "methods\isolate.ps1"

$config = Get-Content -Raw -Path $jsonConfig | ConvertFrom-Json

foreach ($entry in $config.symlinks) {
    if ($entry.archived) {
        Write-Host "[SKIP] $($entry.name) — archived" -ForegroundColor DarkGray
        continue
    }

    $Name = $entry.name

    $rawFrom = $entry.from -replace '\$name', $Name
    $rawTo   = $entry.to   -replace '\$name', $Name

    $from = $ExecutionContext.InvokeCommand.ExpandString($rawFrom)
    $to   = $ExecutionContext.InvokeCommand.ExpandString($rawTo)

    $methodScript = if ($entry.method -eq "isolate") { $isolateMethod } else { $symlinkMethod }

    if ($action -eq "redeploy") {
        Write-Host "[CLEAN] $Name" -ForegroundColor Cyan
        if ($entry.method -eq "isolate") {
            & $methodScript -action "clean" -name $Name -from $from -to $to -appsDir $apps
        } else {
            & $methodScript -action "clean" -from $from -to $to -mappings $entry.mappings
        }
    }

    if (-not $entry.enabled) {
        Write-Host "[CLEAN] $Name — disabled" -ForegroundColor Cyan
        if ($entry.method -eq "isolate") {
            & $methodScript -action "clean" -name $Name -from $from -to $to -appsDir $apps
        } else {
            & $methodScript -action "clean" -from $from -to $to -mappings $entry.mappings
        }
        continue
    }

    Write-Host "[DEPLOY] $Name" -ForegroundColor Cyan
    if ($entry.method -eq "isolate") {
        & $methodScript -action "deploy" -name $Name -from $from -to $to -appsDir $apps
    } else {
        & $methodScript -action "deploy" -from $from -to $to -mappings $entry.mappings
    }
}
