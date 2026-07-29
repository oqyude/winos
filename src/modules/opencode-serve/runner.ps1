<#
.SYNOPSIS
    Runner script for OpenCode Serve Scheduled Task.
    Reads config.json + .env, launches opencode serve.
#>
$configPath = Join-Path $PSScriptRoot "..\..\..\data\opencode-serve\config.json"
$envPath = Join-Path $PSScriptRoot "..\..\..\data\opencode-serve\.env"

# Priority: env var > .env file > config.json > defaults
if (-not $env:OPENCODE_SERVER_PASSWORD -and (Test-Path $envPath)) {
    $envLine = (Get-Content $envPath -Raw).Trim()
    if ($envLine -match '^OPENCODE_SERVER_PASSWORD=(.+)') {
        $env:OPENCODE_SERVER_PASSWORD = $matches[1]
    }
}

if (Test-Path $configPath) {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json

    if (-not $env:OPENCODE_SERVER_USERNAME -and $config.username) {
        $env:OPENCODE_SERVER_USERNAME = $config.username
    }

    $hostname = if ($config.hostname) { $config.hostname } else { "0.0.0.0" }
    $port = if ($config.port) { $config.port } else { 4096 }
} else {
    $hostname = "0.0.0.0"
    $port = 4096
}

$opencodeCmd = if ($config.opencode) { $config.opencode } else { "opencode" }

& $opencodeCmd serve --hostname $hostname --port $port
