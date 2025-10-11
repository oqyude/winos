param(
    [ValidateSet("apply", "clean")]
    [string]$action = "apply"
)

# Start deployment process
Write-Host "Deployment Manager started with action: $action"

# Define deployment modules and their corresponding actions
$deployModules = @(
    @{ Module = "autostartManagerModule"; Apply = "update"; Clean = "remove" },
    @{ Module = "appsDataManagerModule"; Apply = "reconnect"; Clean = "disconnect" },
    @{ Module = "mountsManagerModule"; Apply = "reconnect"; Clean = "disconnect" }
)

foreach ($mod in $deployModules) {





















    @{ Module = "autostartManagerModule"; Apply =
