# Undone
param(
    [string]$configPath = $jsonConfig
)

$config = Get-Content -Raw -Path $configPath | ConvertFrom-Json

foreach ($app in $config.'user-appdata') {
    if (-not $app.enabled) { continue }

    $AppName = $app.name

    $rawFrom = $app.From -replace '\$AppName', $AppName
    $rawTo   = $app.To   -replace '\$AppName', $AppName

    $from = $ExecutionContext.InvokeCommand.ExpandString($rawFrom)
    $to   = $ExecutionContext.InvokeCommand.ExpandString($rawTo)

    if (-not [System.IO.Path]::IsPathRooted($to)) {
        $to = Join-Path $env:USERPROFILE $to
    }

    Write-Host "=============================="
    Write-Host "Checking $AppName"
    Write-Host "  Expected From: $from"
    Write-Host "  Expected To  : $to"

    if (Test-Path $to) {
        $item = Get-Item $to -ErrorAction SilentlyContinue
        if ($item -and $item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $target = (Get-Item $to -Force).Target
            Write-Host "  Symlink exists -> points to: $target"
        } else {
            Write-Host "  Exists but is NOT a symlink."
        }
    } else {
        Write-Host "  Missing"
    }
}
