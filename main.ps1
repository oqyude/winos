<#
.SYNOPSIS
    winos — Symlink orchestrator and Windows configuration manager.
.DESCRIPTION
    Manages application config persistence via symlinks, cursor themes,
    and background services.
.PARAMETER Module
    Module: symlink-manager, essentials, service.
.PARAMETER Name
    For modules: the action (plan, apply, snapshot, install, uninstall).
    For service: the service name (e.g. opencode-serve).
.PARAMETER SubAction
    For service: the action (setup, remove, status, start, stop).
.PARAMETER Help
    Show this help message.
.PARAMETER Version
    Show version.
.EXAMPLE
    winos symlink-manager plan
    winos service opencode-serve status
    winos --help
#>
param(
    [Parameter(Position = 0)]
    [string]$Module,

    [Parameter(Position = 1)]
    [string]$Name,

    [Parameter(Position = 2)]
    [string]$SubAction,

    [switch]$Help,
    [switch]$Version,
    [switch]$Force
)

. (Join-Path $PSScriptRoot "./src/init.ps1")

# Help / Version (handle both -File and -Command invocation modes)
if ($Help -or $Module -eq '--help' -or $Module -eq '-?') { Get-Help $PSCommandPath -Detailed; exit 0 }
if ($Version -or $Module -eq '--version') { Write-Output "winos v0.1.2"; exit 0 }

# CLI mode
if ($Module) {
    # --- Service routing: winos service <name> <action> ---
    if ($Module -eq "service") {
        $serviceAliases = @{
            "opencode-serve" = "Service Manager"
        }
        $validServiceActions = @{
            "Service Manager" = @("setup", "remove", "status", "start", "stop")
        }

        $serviceKey = $serviceAliases[$Name]
        if (-not $serviceKey) {
            Write-Error "Unknown service '$Name'. Valid: $($serviceAliases.Keys -join ', ')"
            exit 1
        }
        if (-not $SubAction) {
            Write-Error "Service '$Name' requires an action: $($validServiceActions[$serviceKey] -join ', ')"
            exit 1
        }
        if ($validServiceActions[$serviceKey] -notcontains $SubAction) {
            Write-Error "Invalid action '$SubAction' for service '$Name'. Valid: $($validServiceActions[$serviceKey] -join ', ')"
            exit 1
        }
        & $modules[$serviceKey].Path $SubAction -Force:$Force
        exit 0
    }

    # --- Direct module routing: winos <module> <action> ---
    $moduleAliases = @{
        "symlink-manager" = "Symlink Manager"
        "essentials"      = "Essentials"
    }
    $validActions = @{
        "Symlink Manager" = @("plan", "apply", "snapshot")
        "Essentials"      = @("install", "uninstall")
    }

    $moduleKey = $moduleAliases[$Module]
    if (-not $moduleKey) {
        Write-Error "Unknown module '$Module'. Valid: $($moduleAliases.Keys -join ', ') or 'service'"
        exit 1
    }
    if (-not $Name) {
        Write-Error "Module '$Module' requires an action: $($validActions[$moduleKey] -join ', ')"
        exit 1
    }
    if ($validActions[$moduleKey] -notcontains $Name) {
        Write-Error "Invalid action '$Name' for '$Module'. Valid: $($validActions[$moduleKey] -join ', ')"
        exit 1
    }
    & $modules[$moduleKey].Path $Name -Force:$Force
    exit 0
}

# No args → interactive menu (existing code follows)

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
        # Empty/null input → no console (pipied stdin) → bail out
        if ([string]::IsNullOrEmpty($raw)) { exit 0 }
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
        & $modules[$selectedModule].Path $selectedAction -Force:$Force
        break actions
    }
}
