# StateFile.ps1 -- Read and write state/plugin-deployment.json.
#
# Schema (Phase 1):
# {
#   "version": 1,
#   "tool_version": "0.0.1",
#   "plugins": [
#     {
#       "name": "Vendor - Product",         # matches a folder under $pluginRoot
#       "link": true,                        # desired state: true=create junction, false=drop
#       "ignore": false,                     # skip entry entirely if true (default for unlisted folders: true)
#       "from": "S:\\Plugins\\Vendor - Product",  # source path (optional in Phase 2 when autodeploy lands)
#       "to":   "C:\\Program Files\\...",         # target path
#       "mappings": [ { "from": "VST2", "to": "VST2" } ]  # optional sub-mappings
#     }
#   ]
# }
#
# Notes:
# - Phantoms: PowerShell ConvertFrom-Json sometimes returns $null entries for missing
#   trailing items. Read-PluginDeploymentState strips these.
# - Defaults: if a plugin folder is not in the list, treat as ignore=true (handled
#   in plugin-manager.ps1, not here).
# - Backward compatibility: if a field is missing on a plugin entry, downstream code
#   uses $entry.PSObject.Properties['field']?.Value, which returns $null for missing.

# Read-PluginDeploymentState -- Load state file or return empty default.
function Read-PluginDeploymentState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path
    )

    $default = [PSCustomObject]@{
        version     = $stateVersion
        tool_version = $toolVersion
        plugins     = @()
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        return $default
    }

    $raw = Get-Content -Raw -LiteralPath $Path
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $default
    }

    try {
        $data = $raw | ConvertFrom-Json
    } catch {
        Write-Warning "Failed to parse $Path -- returning empty default. Error: $_"
        return $default
    }

    # Strip phantom nulls from PowerShell bug (empty trailing items in arrays).
    $plugins = @()
    if ($data.plugins) {
        foreach ($p in $data.plugins) {
            if ($null -ne $p) { $plugins += $p }
        }
    }

    [PSCustomObject]@{
        version      = if ($data.version) { $data.version } else { $stateVersion }
        tool_version = if ($data.tool_version) { $data.tool_version } else { $toolVersion }
        plugins      = $plugins
    }
}

# Write-PluginDeploymentState -- Persist state to JSON. Creates parent dir if missing.
function Write-PluginDeploymentState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] $Data
    )

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $Data | ConvertTo-Json -Depth 10 | Out-File -FilePath $Path -Encoding utf8
}

# Get-EnabledPlugins -- Return only the plugins where ignore=false (after default fill).
#
# Default rules per spec:
#   - If a plugin is NOT in the list, treat as ignore=true (skipped).
#   - If a plugin IS in the list, use its explicit ignore (default false if missing).
#   - If a plugin IS in the list and link is missing, treat as link=false.
function Get-EnabledPlugins {
    param(
        [Parameter(Mandatory)] $State
    )

    $enabled = @()
    foreach ($p in $State.plugins) {
        $ignore = $false
        if ($p.PSObject.Properties['ignore']) { $ignore = [bool]$p.ignore }
        if ($ignore) { continue }

        # Apply defaults for missing fields
        $link = $false
        if ($p.PSObject.Properties['link']) { $link = [bool]$p.link }

        # Clone with defaults applied
        $clone = [PSCustomObject]@{
            name     = $p.name
            link     = $link
            ignore   = $ignore
            from     = if ($p.PSObject.Properties['from'])     { $p.from }     else { $null }
            to       = if ($p.PSObject.Properties['to'])       { $p.to }       else { $null }
            mappings = if ($p.PSObject.Properties['mappings']) { $p.mappings } else { $null }
            method   = if ($p.PSObject.Properties['method'])   { $p.method }   else { 'symlink' }
        }
        $enabled += $clone
    }
    # Use unary comma to prevent PowerShell from unwrapping an empty array to $null
    # when the function result is captured by a downstream caller.
    , $enabled
}
