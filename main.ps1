param(
    [ValidateSet("plan","apply","snapshot","install","uninstall")]
    [string]$action
)

. (Join-Path $PSScriptRoot "./src/init.ps1")

if ($action) {
    $moduleMap = @{
        "plan"     = "Symlink Manager"
        "apply"    = "Symlink Manager"
        "snapshot" = "Symlink Manager"
        "install"  = "Essentials"
        "uninstall" = "Essentials"
    }
    $moduleName = $moduleMap[$action]
    & $modules[$moduleName].Path $action
    exit
}

function Show-Menu {
    param(
        [string]$Title,
        [string[]]$Items,
        [string[]]$Descriptions,
        [string]$BackLabel = $null
    )
    $width = 40
    Write-Host ""
    Write-Host "  $($Title)" -ForegroundColor Cyan
    Write-Host "  $('─' * $width)" -ForegroundColor DarkGray
    if ($BackLabel) {
        Write-Host "  [0]" -NoNewline -ForegroundColor Yellow
        Write-Host " $BackLabel" -ForegroundColor DarkGray
    }
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $num = "  [$($i + 1)]"
        $name = " $($Items[$i])"
        $desc = if ($Descriptions -and $Descriptions[$i]) { " — $($Descriptions[$i])" } else { "" }
        Write-Host $num -NoNewline -ForegroundColor Yellow
        Write-Host $name -NoNewline -ForegroundColor White
        Write-Host $desc -ForegroundColor DarkGray
    }
    Write-Host "  $('─' * $width)" -ForegroundColor DarkGray
    Write-Host ""
}

function Read-Choice {
    param([string]$Prompt, [int]$MaxChoice, [switch]$AllowZero)
    do {
        $raw = Read-Host "  $Prompt"
        if ($AllowZero -and $raw -eq "0") { return 0 }
        $num = $raw -as [int]
        if ($null -ne $num -and $num -ge 1 -and $num -le $MaxChoice) { return $num }
        Write-Host "  Invalid, try again" -ForegroundColor Yellow
    } while ($true)
}

$moduleNames = $modules.Keys | Sort-Object

:menu while ($true) {
    $descs = $moduleNames | ForEach-Object { $modules[$_].Description }
    Show-Menu -Title "winos" -Items $moduleNames -Descriptions $descs
    $modIdx = Read-Choice -Prompt "Select module" -MaxChoice $moduleNames.Count -AllowZero
    if ($modIdx -eq 0) { exit 0 }
    $selectedModule = $moduleNames[$modIdx - 1]

    :actions while ($true) {
        $actions = $modules[$selectedModule].Actions
        Show-Menu -Title $selectedModule -Items $actions -BackLabel "Back"
        $actIdx = Read-Choice -Prompt "Select action" -MaxChoice $actions.Count -AllowZero
        if ($actIdx -eq 0) { continue menu }
        $selectedAction = $actions[$actIdx - 1]

        Write-Host ""
        Write-Host "  ▸ $selectedModule → $selectedAction" -ForegroundColor Green
        Write-Host ""
        & $modules[$selectedModule].Path $selectedAction
        break actions
    }
}
