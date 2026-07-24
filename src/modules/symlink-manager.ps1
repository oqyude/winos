[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("deploy", "clean", "redeploy")]
    [string]$action = "deploy"
)

# Self-bootstrap: if vars.ps1 hasn't been sourced (run directly), source it.
if (-not $jsonConfig) {
    . (Join-Path $PSScriptRoot "..\init.ps1")
}

$symlinkMethod = Join-Path $PSScriptRoot "methods\symlink.ps1"
$isolateMethod = Join-Path $PSScriptRoot "methods\isolate.ps1"

function Resolve-Entry {
    param($entry)

    # Default `from` to $persist\$name (canonical source-of-truth).
    $rawFrom = if ($entry.from) { $entry.from } else { '$persist\$name' }
    $rawFrom = $rawFrom -replace '\$name', $entry.name

    $rawTo = $entry.to -replace '\$name', $entry.name

    return @{
        name     = $entry.name
        enabled  = $entry.enabled
        from     = $ExecutionContext.InvokeCommand.ExpandString($rawFrom)
        to       = $ExecutionContext.InvokeCommand.ExpandString($rawTo)
        method   = if ($entry.method -eq "isolate") { $isolateMethod } else { $symlinkMethod }
        mappings = $entry.mappings
    }
}

function Deploy-Entry {
    param($e)
    Write-Host "[DEPLOY] $($e.name)" -ForegroundColor Cyan
    if ($e.method -eq $isolateMethod) {
        & $e.method -action deploy -name $e.name -from $e.from -to $e.to -appsDir $apps
    } else {
        & $e.method -action deploy -from $e.from -to $e.to -mappings $e.mappings
    }
}

function Remove-Entry {
    param($e)
    Write-Host "[CLEAN] $($e.name)" -ForegroundColor Cyan
    if ($e.method -eq $isolateMethod) {
        & $e.method -action clean -name $e.name -from $e.from -to $e.to -appsDir $apps
    } else {
        & $e.method -action clean -from $e.from -to $e.to -mappings $e.mappings
    }
}

$config = Get-Content -Raw -Path $jsonConfig | ConvertFrom-Json
$entries = $config.symlinks | Where-Object { -not $_.archived }
$resolved = $entries | ForEach-Object { Resolve-Entry $_ }

switch ($action) {
    "deploy" {
        foreach ($e in $resolved) {
            if ($e.enabled) { Deploy-Entry $e } else { Remove-Entry $e }
        }
    }
    "clean" {
        foreach ($e in $resolved) { Remove-Entry $e }
    }
    "redeploy" {
        foreach ($e in $resolved) { Remove-Entry $e; if ($e.enabled) { Deploy-Entry $e } }
    }
}
