$initFile = Join-Path $PSScriptRoot ".\src\init.ps1"
. $initFile

# Check for administrator privileges
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "The script requires administrator privileges. Restarting..."
    
    # Restart the script with admin rights
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "Administrator privileges confirmed."

# Define available actions
$actions = @("reconnect", "connect", "disconnect")

# Determine action: from argument or interactive menu
if ($args.Count -ge 1) {
    $action = $args[0]
} else {
    Write-Host "Select an action:"
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

Write-Host "Selected action: $action"

# Call with the chosen action
. $appsDataManager $action
