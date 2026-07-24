[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("deploy", "clean", "redeploy")]
    [string]$action = "deploy",
    [string]$AppName = "EqualizerAPO",
    [string]$From,
    [string]$To
)

# === Validate inputs ===
if (-not $From) {
    Write-Error "No From path - aborting"
    exit 1
}
if (-not (Test-Path $From -PathType Container)) {
    Write-Error "From path not found or not a directory: $From"
    exit 1
}
if (-not $To) {
    Write-Error "No To path - aborting"
    exit 1
}

# === Paths ===
$regPath = "HKLM:\SOFTWARE\EqualizerAPO"
$regKey  = "ConfigPath"
$vstDir  = Join-Path $To "VSTPlugins"
$FabFilterLink = Join-Path $vstDir "FabFilter Pro-Q 3.dll"
$globalDLL = "$env:ProgramFiles\VSTPlugins\FabFilter\FabFilter Pro-Q 3.dll"

Write-Host "Isolate: $AppName ($action) | From: $From | To: $To" -ForegroundColor Yellow

# === Registry: point EqualizerAPO at user-managed config dir ===
function Set-RegistryConfigPath {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if (-not (Test-Path $regPath)) {
        if ($PSCmdlet.ShouldProcess($regPath, "Create registry key")) {
            New-Item -Path $regPath -Force | Out-Null
        }
    }
    if ($PSCmdlet.ShouldProcess("$regPath\$regKey", "Set ConfigPath to $From")) {
        Set-ItemProperty -Path $regPath -Name $regKey -Value $From -Type String -Force
        Write-Host "    ConfigPath -> $From" -ForegroundColor Blue
    }
}

function Remove-RegistryConfigPath {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if (Test-Path $regPath) {
        if ($PSCmdlet.ShouldProcess("$regPath\$regKey", "Remove ConfigPath")) {
            Remove-ItemProperty -Path $regPath -Name $regKey -ErrorAction SilentlyContinue
            Write-Host "    Registry cleaned" -ForegroundColor Red
        }
    }
}

# === VST plugin symlink (program directory side) ===
function Set-VSTLink {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if (-not (Test-Path $vstDir)) {
        if ($PSCmdlet.ShouldProcess($vstDir, "Create VST dir")) {
            New-Item -ItemType Directory -Path $vstDir -Force | Out-Null
        }
    }
    if (Test-Path $FabFilterLink) {
        if ($PSCmdlet.ShouldProcess($FabFilterLink, "Remove existing VST link")) {
            Remove-Item $FabFilterLink -Force
        }
    }
    if (Test-Path $globalDLL) {
        if ($PSCmdlet.ShouldProcess($FabFilterLink, "Link to $globalDLL")) {
            New-Item -SymbolicLink -Path $FabFilterLink -Value $globalDLL -Force | Out-Null
            Write-Host "    VST linked: $FabFilterLink -> $globalDLL" -ForegroundColor Blue
        }
    } else {
        Write-Warning "  No system VST: $globalDLL (install it?)"
    }
}

function Remove-VSTLink {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if (Test-Path $FabFilterLink) {
        if ($PSCmdlet.ShouldProcess($FabFilterLink, "Remove VST link")) {
            Remove-Item $FabFilterLink -Force
            Write-Host "    VST link removed" -ForegroundColor Red
        }
    }
}

# === Action dispatch ===
function Invoke-Deploy {
    Set-RegistryConfigPath
    Set-VSTLink
}

function Invoke-Clean {
    Remove-RegistryConfigPath
    Remove-VSTLink
}

function Invoke-Redeploy {
    Invoke-Clean
    Invoke-Deploy
}

switch ($action) {
    "deploy"   { Invoke-Deploy }
    "clean"    { Invoke-Clean }
    "redeploy" { Invoke-Redeploy }
}

Write-Host "Done with $AppName" -ForegroundColor Green
