param(
    [string]$action = "reconnect"
)

Write-Host "Mounts Manager started with action: $action" -ForegroundColor Yellow

$csv = Import-Csv -Path $mountsAll
foreach ($entry in $csv) {
    if ($entry.Enabled -ne "1") { continue }

    $Name = $entry.Name

    # Expand From and To strings
    $rawFrom = $entry.From -replace '\$Name', $Name
    $rawTo   = $entry.To   -replace '\$Name', $Name

    # Expand environment variables
    $from = $ExecutionContext.InvokeCommand.ExpandString($rawFrom)
    $to   = $ExecutionContext.InvokeCommand.ExpandString($rawTo)

    # If To path is relative, make it absolute relative to the user
    if (-not [System.IO.Path]::IsPathRooted($to)) {
        $to = Join-Path $env:USERPROFILE $to
    }

    Write-Host "===============================" -ForegroundColor Gray
    Write-Host "Processing $Name with action $action" -ForegroundColor White
    Write-Host "  From: $from" -ForegroundColor White
    Write-Host "  To  : $to" -ForegroundColor White

    switch ($action.ToLower()) {
        "disconnect" {
            Write-Host "    Removing $to" -ForegroundColor Red
            if (Test-Path $to) { Remove-Item $to -Recurse -Force }
        }
        "connect" {
            Write-Host "    Creating symlink $to -> $from" -ForegroundColor Blue
            if (-not (Test-Path $to)) {
                New-Item -Path $to -ItemType SymbolicLink -Value $from | Out-Null
            }
        }
        "reconnect" {
            Write-Host "    Removing $to" -ForegroundColor Red
            if (Test-Path $to) { Remove-Item $to -Recurse -Force }
            Write-Host "    Creating symlink $to -> $from" -ForegroundColor Blue
            if (-not (Test-Path $to)) {
                New-Item -Path $to -ItemType SymbolicLink -Value $from | Out-Null
            }
        }
        default {
            Write-Warning "Unknown action: $action"
        }
    }
}
