$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
$restartArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""

. (Join-Path $PSScriptRoot "./src/init.ps1")
if (-not $isAdmin) {
    Write-Host "The script requires administrator privileges. Restarting..."
    Start-Process -FilePath "powershell.exe" -ArgumentList $restartArgs -Verb RunAs
    exit
}
Write-Host "Administrator privileges confirmed."

Clear-Host
Write-Host "Select a module:"
$moduleNames = $modules.Keys | Sort-Object
for ($i = 0; $i -lt $moduleNames.Count; $i++) {
    Write-Host "[$($i+1)] $($moduleNames[$i])"
}
do {
    $moduleSelection = Read-Host "Enter the number of your choice"
    $validModule = ($moduleSelection -as [int]) -and ($moduleSelection -ge 1) -and ($moduleSelection -le $moduleNames.Count)
    if (-not $validModule) { Write-Host "Invalid module selection. Try again." }
} until ($validModule)

Clear-Host
$selectedModule = $moduleNames[$moduleSelection - 1]
$actions = $modules[$selectedModule]
Write-Host "Selected module: $selectedModule"

if ($args.Count -ge 1) {
    $action = $args[0]
} else {
    Write-Host "Select an action for $selectedModule :"
    for ($i = 0; $i -lt $actions.Count; $i++) {
        Write-Host "[$($i+1)] $($actions[$i])"
    }
    do {
        $selection = Read-Host "Enter the number of your choice"
        $valid = ($selection -as [int]) -and ($selection -ge 1) -and ($selection -le $actions.Count)
        if (-not $valid) { Write-Host "Invalid selection. Try again." }
    } until ($valid)

    $action = $actions[$selection - 1]
}

Clear-Host
Write-Host "Selected action: $action"

& (Get-Variable $selectedModule).Value $action