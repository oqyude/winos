<#
.SYNOPSIS
    Runner script for the HerdrServe scheduled task.
    Reads data/herdr-serve/config.json, launches `herdr server`.
#>
$configPath = Join-Path $PSScriptRoot "..\..\..\data\herdr-serve\config.json"

$herdrCmd        = "herdr"
$allowUnelevated = $true

if (Test-Path $configPath) {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json

    if ($config.herdr) { $herdrCmd = $config.herdr }

    if ($null -ne $config.allowUnelevatedClients) {
        $allowUnelevated = [bool]$config.allowUnelevatedClients
    }
}

# A non-elevated herdr server blocks ordinary same-account clients (other
# terminals, IDE plugins) from attaching. --allow-unelevated-clients opens the
# socket to those clients, at the cost of closing every pane on the server's
# elevated side. Configurable in config.json so the operator can flip it
# without editing this script.
if ($allowUnelevated) {
    & $herdrCmd server --allow-unelevated-clients
} else {
    & $herdrCmd server
}
