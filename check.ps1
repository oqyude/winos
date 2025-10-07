param(
    [string]$csvPath = $appsAll
)

# Импорт CSV
$apps = Import-Csv -Path $csvPath

foreach ($app in $apps) {
    if ($app.Enabled -ne "1") { continue }

    $AppName = $app.App

    # Разворачиваем пути
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
