param(
    [ValidateSet("apply","clean")]
    [string]$action = "apply"
)

Write-Host "Deployment Manager started with action: $action"

# Список модулей с аргументами для apply и clean
$deployModules = @(
    @{ Module = "autostartManager"; Apply = "update"; Clean = "remove" },
    @{ Module = "appsDataManager"; Apply = "reconnect"; Clean = "disconnect" },
    @{ Module = "mountsManagerModule"; Apply = "reconnect"; Clean = "disconnect" }
)

foreach ($item in $deployModules) {
    $moduleName = $item.Module
    $moduleAction = if ($action -eq "apply") { $item.Apply } else { $item.Clean }

    Write-Host "=============================="
    Write-Host "Executing module '$moduleName' with action '$moduleAction'"

    $modulePath = Join-Path $PSScriptRoot "$moduleName.ps1"

    if (Test-Path $modulePath) {
        try {
            # Передаём аргумент точно так же, как $action передавался бы напрямую модулю
            & $modulePath $moduleAction
        } catch {
            Write-Warning "Module '$moduleName' failed: $($_.Exception.Message)"
        }
    } else {
        Write-Warning "Module script not found: $modulePath"
    }
}

Write-Host "Deployment finished."
