# registry-import.ps1 -- Import a .reg file via reg.exe import.
#
# Used by plugin manifests' Registry array: each entry has OnEnable and/or OnDisable
# paths (relative to the plugin folder under S:\Plugins). The user supplies an
# uninstall .reg that reverses the install one -- we don't auto-snapshot keys.
#
# Requires reg.exe (built into Windows). HKLM keys require admin; HKCU does not.
# Tests use HKCU for non-admin verification.

function Import-RegistryFile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warning "Registry file not found: $Path"
        return [PSCustomObject]@{ Status = 'skipped'; Note = 'file not found' }
    }

    if (-not $PSCmdlet.ShouldProcess($Path, "Import registry file")) {
        return [PSCustomObject]@{ Status = 'skipped'; Note = 'WhatIf' }
    }

    try {
        # reg import is silent on success; capture stderr for diagnostics.
        $stderr = reg.exe import $Path 2>&1
        $code = $LASTEXITCODE
        if ($code -eq 0) {
            return [PSCustomObject]@{ Status = 'imported'; Note = $null }
        } else {
            return [PSCustomObject]@{ Status = 'failed'; Note = "reg exit ${code}: ${stderr}" }
        }
    } catch {
        return [PSCustomObject]@{ Status = 'failed'; Note = $_.Exception.Message }
    }
}
