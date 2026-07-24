. (Join-Path $PSScriptRoot "./src/init.ps1")

$moduleNames = $modules.Keys | Sort-Object
$selectedModule = $null

if ($args.Count -ge 1) {
    $selectedModule = if ($args[0] -as [int]) { $moduleNames[$args[0] - 1] } else { $args[0] }
    if (-not $modules.ContainsKey($selectedModule)) {
        Write-Host "Module '$($args[0])' not found. Available:" -ForegroundColor Red
        $moduleNames | ForEach-Object { Write-Host "  $_" }
        exit 1
    }
}

if (-not $selectedModule) {
    Write-Host "`n winos — select a module:`n" -ForegroundColor Yellow
    for ($i = 0; $i -lt $moduleNames.Count; $i++) {
        $actions = $modules[$moduleNames[$i]].Actions -join " / "
        Write-Host "  $($i+1)  $($moduleNames[$i])" -NoNewline
        Write-Host "       $actions" -ForegroundColor DarkGray
    }
    Write-Host ""
    do {
        $input = Read-Host " Enter number or name"
        $selectedModule = if ($input -as [int]) { $moduleNames[$input - 1] } else { $input }
        if (-not $modules.ContainsKey($selectedModule)) { Write-Host " Not found, try again" -ForegroundColor Yellow }
    } until ($modules.ContainsKey($selectedModule))
}

$actions = $modules[$selectedModule].Actions
$selectedAction = $null

if ($args.Count -ge 2) {
    $selectedAction = if ($args[1] -as [int]) { $actions[$args[1] - 1] } else { $args[1] }
    if ($actions -notcontains $selectedAction) {
        Write-Host "Invalid action. Available: $($actions -join ', ')" -ForegroundColor Red
        exit 1
    }
}

if (-not $selectedAction) {
    Write-Host "`n $selectedModule" -ForegroundColor Cyan
    for ($i = 0; $i -lt $actions.Count; $i++) {
        Write-Host "  $($i+1)  $($actions[$i])"
    }
    do {
        $input = Read-Host " Select action"
        $selectedAction = if ($input -as [int]) { $actions[$input - 1] } else { $input }
        if ($actions -notcontains $selectedAction) { Write-Host " Invalid action, try again" -ForegroundColor Yellow }
    } until ($actions -contains $selectedAction)
}

Write-Host "`n Running: $selectedModule → $selectedAction`n" -ForegroundColor Green
& $modules[$selectedModule].Path $selectedAction