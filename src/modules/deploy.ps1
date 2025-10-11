param(
    [ValidateSet('apply','clean')]
    [string]$Action = 'apply'
)

Write-Host "Deployment Manager started with action: $Action"

# Define modules with their respective actions
$Modules = @(
    @{ Name = 'autostartManagerModule'; Apply = 'update';   Clean = 'remove' },
    @{ Name = 'appsDataManagerModule';  Apply = 'reconnect'; Clean = 'disconnect' },
    @{ Name = 'mountsManagerModule';    Apply = 'reconnect'; Clean = 'disconnect' }
    @{ Name = 'wingetInstallerModule';    Apply = 'install'; Clean = 'check' }
    @{ Name = 'packageManagerModule';    Apply = 'install'; Clean = 'uninstall' }
)

foreach ($module in $Modules) {
    $currentAction = if ($Action -eq 'apply') { $module.Apply } else { $module.Clean }
    Write-Host "`n=== $($module.Name) : $currentAction"
    try {
        # Resolve the script path stored in a variable with the same name
        $scriptPath = (Get-Variable -Name $module.Name -ErrorAction Stop).Value

        if (Test-Path -LiteralPath $scriptPath) {
            & $scriptPath $currentAction
        }
        else {
            Write-Warning "Module script not found: $scriptPath"
        }
    }
    catch {
        Write-Warning "Could not resolve path for module '$($module.Name)': $_"
    }
}

Write-Host "`nDeployment finished."