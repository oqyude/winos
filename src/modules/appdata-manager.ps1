param(
    [string]$action = "reconnect"
)

Write-Host "AppData Manager started with action: $action" -ForegroundColor Yellow

$csv = Import-Csv -Path $appsAll

foreach ($app in $csv) {
    if ($app.Enabled -ne "1") { continue }

    $AppName = $app.App

    # Expand From and To strings with $AppName substitution
    $rawFrom = $app.From -replace '\$AppName', $AppName
    $rawTo   = $app.To   -replace '\$AppName', $AppName

    # Expand environment variables
    $from = $ExecutionContext.InvokeCommand.ExpandString($rawFrom)
    $to   = $ExecutionContext.InvokeCommand.ExpandString($rawTo)

    # If To path is relative, make it absolute relative to the user
    if (-not [System.IO.Path]::IsPathRooted($to)) {
        $to = Join-Path $env:USERPROFILE $to
    }

    Write-Host "==============================" -ForegroundColor Gray
    Write-Host "Processing $AppName with action $action (Type=$($app.Type))" -ForegroundColor White
    Write-Host "  Raw From: $rawFrom" -ForegroundColor White
    Write-Host "  Raw To  : $rawTo" -ForegroundColor White
    Write-Host "  Expanded From: $from" -ForegroundColor White
    Write-Host "  Expanded To  : $to" -ForegroundColor White

    # Handle isolate type: execute a script instead of symlinks
    if ($app.Type -eq "isolate") {
        if ($app.Script) {
            # Step 1: replace $AppName
            $scriptRaw = $app.Script -replace '\$AppName', $AppName
            # Step 2: replace $Apps with $apps path (in case of typo in CSV)
            $scriptRaw = $scriptRaw -replace '\$apps', $apps
            # Step 3: expand remaining variables (env etc.)
            $scriptPath = $ExecutionContext.InvokeCommand.ExpandString($scriptRaw)
        } else {
            # Fallback if Script is not defined
            $safeName = $AppName -replace ' ', '_'
            $scriptPath = Join-Path $apps "$safeName.ps1"
        }
        
        Write-Host "    Isolate mode: Executing script $scriptPath" -ForegroundColor Yellow
        if (Test-Path $scriptPath) {
            try {
                # Pass action and app context to the script
                & $scriptPath -Action $action -AppName $AppName -From $from -To $to
            } catch {
                Write-Error "Script failed for $AppName`: $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Warning "Isolate script not found: $scriptPath" -ForegroundColor Red
        }
        continue
    }

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
            Write-Warning "Unknown action: $action" -ForegroundColor DarkYellow
        }
    }
}
